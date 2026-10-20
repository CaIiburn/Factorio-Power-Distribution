-- Pylon Transformers - runtime script.
--
-- Design: every transformer is a visible "shell" entity plus two hidden electric-energy-interface
-- halves (input = left, output = right). The engine handles idle drain, the output power cap and
-- the buffers natively. This script only (1) creates/destroys the halves, (2) computes a loss
-- factor once per transformer, and (3) moves energy from the input buffer to the output buffer
-- every N ticks.
--
-- Shared constants (tiers, offsets, loss limits) come from config.lua, which is also used by the
-- data stage so both stages always agree.
local C = require("__pylon-transformers__.config")

-- Update interval in ticks (startup setting). Each transformer is serviced once every N ticks.
local N = settings.startup["pt-update-interval"].value

---------------------------------------------------------------------------
-- Static lookups (derived from config only; safe to rebuild on every load)
---------------------------------------------------------------------------
-- Lookup tables built from config on every load (no state, so nothing is saved in storage).
-- shell_info maps a shell entity name to its kind ("up"/"down"), tier, half prototype names and
-- output buffer capacity. half_names is used to recognise hidden halves; shell_names feeds the
-- event filters.
local shell_info = {}   -- shell entity name -> {kind, tier, in_name, out_name, cap}
local half_names = {}   -- set of hidden half names
local shell_names = {}
for _, kind in ipairs(C.kinds) do
  for tier, t in ipairs(C.tiers) do
    local name = C.shell_name(kind, tier)
    shell_info[name] = {
      kind = kind, tier = tier,
      in_name = C.in_name(kind, tier), out_name = C.out_name(kind, tier),
      -- output buffer capacity in J (same formula as the prototype)
      cap = math.floor(t.rated_w * (N / 60) * C.buffer_safety + 0.5),
    }
    shell_names[#shell_names + 1] = name
    half_names[C.in_name(kind, tier)] = true
    half_names[C.out_name(kind, tier)] = true
  end
end

---------------------------------------------------------------------------
-- Storage
--   records[reg]  = rec          (reg = registration number of the shell)
--   ups[reg]/downs[reg] = rec    (kind indexes, for network queries)
--   buckets[1..N] = arrays of rec (hot loop; rec.bucket / rec.idx for O(1) removal)
---------------------------------------------------------------------------
-- Per-save state lives in `storage`. `buckets` is a local alias of storage.buckets so the hot
-- loop avoids a table lookup (re-bound in on_init / on_load / on_configuration_changed).
local buckets -- upvalue cache of storage.buckets for the hot loop

-- Create any missing storage tables. Safe to call repeatedly (also on config change).
local function init_storage()
  storage.records = storage.records or {}
  storage.ups = storage.ups or {}
  storage.downs = storage.downs or {}
  storage.half_owner = storage.half_owner or {} -- half registration number -> shell registration number
  storage.buckets = storage.buckets or {}
  for i = 1, N do storage.buckets[i] = storage.buckets[i] or {} end
  storage.dirty = storage.dirty or false
end

-- Re-point the local `buckets` alias at storage.buckets. Must run after every load.
local function bind() buckets = storage.buckets end

-- Put a record into the emptiest bucket so the work stays evenly spread over the N ticks.
-- The record remembers its bucket and index for O(1) removal.
local function bucket_insert(rec)
  local best, best_n = 1, #buckets[1]
  for i = 2, N do
    local n = #buckets[i]
    if n < best_n then best, best_n = i, n end
  end
  local b = buckets[best]
  b[#b + 1] = rec
  rec.bucket, rec.idx = best, #b
end

-- Swap-remove a record from its bucket: move the last entry into the freed slot and fix its idx.
local function bucket_remove(rec)
  local b = buckets[rec.bucket]
  if not b then return end
  local last = #b
  if rec.idx ~= last then
    local moved = b[last]
    b[rec.idx] = moved
    moved.idx = rec.idx
  end
  b[last] = nil
end

---------------------------------------------------------------------------
-- Geometry / pole queries (event-driven only)
---------------------------------------------------------------------------
-- Largest supply-area distance of any electric pole at any quality. Used as the search radius
-- when looking for poles near a hidden half. Cached because prototypes never change at runtime.
local max_supply -- lazily computed, depends only on prototypes
local function get_max_supply()
  if not max_supply then
    max_supply = 0
    for _, proto in pairs(prototypes.entity) do
      if proto.type == "electric-pole" then
        for _, q in pairs(prototypes.quality) do
          local d = proto.get_supply_area_distance(q)
          if d and d > max_supply then max_supply = d end
        end
      end
    end
  end
  return max_supply
end

-- (Poles only connect to an entity if their supply area overlaps its collision box, so a
-- tiny half box means each half joins exactly one network.)
-- Poles whose supply area overlaps the tiny collision box of a half at (x, y).
local function poles_covering(surface, x, y)
  local R = get_max_supply() + C.half_box
  local found = surface.find_entities_filtered{
    type = "electric-pole",
    area = { { x - R, y - R }, { x + R, y + R } },
  }
  local res = {}
  for _, p in pairs(found) do
    local d = p.prototype.get_supply_area_distance(p.quality) + C.half_box
    local pp = p.position
    if math.abs(pp.x - x) < d and math.abs(pp.y - y) < d then res[#res + 1] = p end
  end
  return res
end

-- Set of unit_numbers of poles that touch any step-up output half on a surface.
-- `cache` is per query/pass, so the pole searches happen once even when many step-downs are
-- recomputed together.
local function get_targets(cache, surface)
  local t = cache[surface.index]
  if t then return t end
  t = {}
  for _, rec in pairs(storage.ups) do
    if rec.surface_index == surface.index then
      for _, p in ipairs(poles_covering(surface, rec.x + C.half_offset, rec.y)) do
        t[p.unit_number] = true
      end
    end
  end
  cache[surface.index] = t
  return t
end

-- Dijkstra over copper wires. Edge weight = wire length (tiles).
-- Returns distance to the nearest pole that powers a step-up output, or nil.
-- Graph: nodes are poles, edges are copper wire connections, weight is the Euclidean wire length.
-- `starts` are the poles covering the step-down's input half (distance 0). The search stops at
-- the first popped pole that is in `targets`, which is the nearest by wire length.
-- The min-heap below stores (distance, pole) pairs; stale entries are skipped when popped.
local function shortest_wire_distance(starts, targets)
  if next(targets) == nil or #starts == 0 then return nil end
  local hd, hp, n = {}, {}, 0 -- binary min-heap (dist, pole)
  local function push(d, p)
    n = n + 1
    local i = n
    while i > 1 do
      local parent = math.floor(i / 2)
      if hd[parent] <= d then break end
      hd[i], hp[i] = hd[parent], hp[parent]
      i = parent
    end
    hd[i], hp[i] = d, p
  end
  local function pop()
    local rd, rp = hd[1], hp[1]
    local d, p = hd[n], hp[n]
    hd[n], hp[n] = nil, nil
    n = n - 1
    if n > 0 then
      local i = 1
      while true do
        local c = i * 2
        if c > n then break end
        if c < n and hd[c + 1] < hd[c] then c = c + 1 end
        if hd[c] >= d then break end
        hd[i], hp[i] = hd[c], hp[c]
        i = c
      end
      hd[i], hp[i] = d, p
    end
    return rd, rp
  end

  -- best[unit_number] = shortest known distance to that pole.
  local best = {}
  for _, p in ipairs(starts) do
    best[p.unit_number] = 0
    push(0, p)
  end
  while n > 0 do
    local d, p = pop()
    local un = p.unit_number
    if d <= best[un] then
      if targets[un] then return d end
      local conn = p.get_wire_connector(defines.wire_connector_id.pole_copper, false)
      if conn then
        local pp = p.position
        for _, c in pairs(conn.connections) do
          local q = c.target.owner
          if q.valid and q.type == "electric-pole" then
            local qp = q.position
            local nd = d + math.sqrt((qp.x - pp.x) ^ 2 + (qp.y - pp.y) ^ 2)
            local qn = q.unit_number
            if not best[qn] or nd < best[qn] then
              best[qn] = nd
              push(nd, q)
            end
          end
        end
      end
    end
  end
  return nil
end

-- Distance along the pylon line from a step-down at (x, y) to the nearest step-up.
-- Poles that cover the step-down's input half are the start of the search.
local function distance_to_step_up(surface, x, y, cache)
  local starts = poles_covering(surface, x - C.half_offset, y)
  return shortest_wire_distance(starts, get_targets(cache, surface))
end

---------------------------------------------------------------------------
-- Loss factors (computed on build / on pole changes, never per tick)
-- mult = input joules needed per output joule = 1 + conversion (+ line)
-- eta  = 1 / mult
---------------------------------------------------------------------------
-- Compute and store the transfer factors for one transformer.
--   conversion loss: fixed fraction of output power
--   line loss      : step-down only, distance * line_per_tile, also a fraction of output power
--   mult is capped by config so rated * mult + idle never exceeds the input flow limit.
-- If a step-down has no reachable step-up (dist == nil) both factors are 0 and it delivers nothing.
local function apply_factors(rec, dist)
  local t = C.tiers[rec.tier]
  local loss = t.conversion
  if rec.kind == "down" then
    rec.line_dist = dist
    if not dist then
      rec.mult, rec.eta = 0, 0 -- no source reachable: nothing is delivered
      return
    end
    loss = loss + dist * t.line_per_tile
  end
  local mult = math.min(1 + loss, C.max_input_multiplier)
  rec.mult, rec.eta = mult, 1 / mult
end

-- Re-evaluate line distances of every step-down. Only called from the debounced timer after
-- pole or step-up changes, never per tick.
local function recompute_all()
  local cache = {}
  for _, rec in pairs(storage.downs) do
    local surface = game.get_surface(rec.surface_index)
    if surface then
      apply_factors(rec, distance_to_step_up(surface, rec.x, rec.y, cache))
    end
  end
end

---------------------------------------------------------------------------
-- Build / destroy
---------------------------------------------------------------------------
-- Cancel a build: destroy the shell and give the item back (to the player if there is one and
-- there is room, otherwise spilled on the ground).
local function refuse(shell, info, event)
  local surface, pos, force = shell.surface, shell.position, shell.force
  local stack = { name = C.shell_name(info.kind, info.tier), count = 1, quality = shell.quality.name }
  local player = event.player_index and game.get_player(event.player_index)
  shell.destroy()
  if player and player.valid then
    player.create_local_flying_text{ text = { "pt-message.no-step-up" }, position = pos }
    if player.insert(stack) >= 1 then return end
  end
  surface.spill_item_stack{ position = pos, stack = stack, enable_looted = true, force = force }
end

-- Create one hidden half. It is made indestructible and non-operable so only this script
-- removes it. raise_built = false stops our own build handler from reacting to it.
local function create_half(surface, name, x, y, force)
  local e = surface.create_entity{ name = name, position = { x, y }, force = force, raise_built = false }
  if e then
    e.destructible = false
    e.operable = false
  end
  return e
end

-- Central build routine for a newly placed shell (player, robot, script, revive or clone).
-- Order matters: the step-down placement check runs before anything is created, so a refused
-- build leaves no halves behind.
local function build_shell(shell, info, event)
  local surface = shell.surface
  local pos = shell.position
  local x, y = pos.x, pos.y

  local dist
  if info.kind == "down" then
    dist = distance_to_step_up(surface, x, y, {})
    if not dist then return refuse(shell, info, event) end
  end

  local in_e = create_half(surface, info.in_name, x - C.half_offset, y, shell.force)
  local out_e = create_half(surface, info.out_name, x + C.half_offset, y, shell.force)
  if not (in_e and out_e) then
    if in_e then in_e.destroy() end
    if out_e then out_e.destroy() end
    return refuse(shell, info, event)
  end

  -- Register shell and halves for destruction notices. The shell's registration number is the key
  -- of the record; half_owner maps each half's number back to it, so losing any of the three
  -- removes the whole transformer.
  local reg = script.register_on_object_destroyed(shell)
  local in_reg = script.register_on_object_destroyed(in_e)
  local out_reg = script.register_on_object_destroyed(out_e)
  storage.half_owner[in_reg] = reg
  storage.half_owner[out_reg] = reg
  local rec = {
    kind = info.kind, tier = info.tier, surface_index = surface.index, x = x, y = y,
    shell = shell, in_e = in_e, out_e = out_e, cap = info.cap, mult = 1, eta = 1, reg = reg,
    in_reg = in_reg, out_reg = out_reg,
  }
  apply_factors(rec, dist)
  storage.records[reg] = rec
  if info.kind == "up" then
    storage.ups[reg] = rec
    storage.dirty = true -- a new source may shorten existing step-down lines
  else
    storage.downs[reg] = rec
  end
  bucket_insert(rec)
end

-- Forget a transformer and destroy whatever of it still exists. `destroy_shell` is true when
-- a half died first, so no inert shell is left behind. A removed step-up may lengthen or break
-- step-down lines, so it flags a recompute.
local function remove_record(reg, destroy_shell)
  local rec = storage.records[reg]
  if not rec then return end
  storage.records[reg] = nil
  if rec.in_reg then storage.half_owner[rec.in_reg] = nil end   -- nil on records from older saves
  if rec.out_reg then storage.half_owner[rec.out_reg] = nil end
  if destroy_shell and rec.shell and rec.shell.valid then rec.shell.destroy() end
  storage.ups[reg] = nil
  storage.downs[reg] = nil
  bucket_remove(rec)
  if rec.in_e.valid then rec.in_e.destroy() end
  if rec.out_e.valid then rec.out_e.destroy() end
  if rec.kind == "up" then storage.dirty = true end
end

-- Shared handler for all build events. Shells get halves; any electric pole just flags
-- the line distances as outdated.
local function on_built(event)
  local e = event.entity
  if not (e and e.valid) then return end
  local info = shell_info[e.name]
  if info then
    build_shell(e, info, event)
  elseif e.type == "electric-pole" then
    storage.dirty = true
  end
end

-- Pole removed or destroyed: only flag a recompute (done later by the timer, after the
-- pole is really gone).
local function on_pole_removed(event)
  local e = event.entity
  if e and e.valid and e.type == "electric-pole" then storage.dirty = true end
end

-- Cloning copies the hidden halves too, which would create duplicates. Throw the cloned halves
-- away and let the cloned shell build fresh ones.
local function on_cloned(event)
  local dest = event.destination
  if not (dest and dest.valid) then return end
  if half_names[dest.name] then
    dest.destroy() -- the clone of the shell recreates fresh halves
  elseif shell_info[dest.name] then
    build_shell(dest, shell_info[dest.name], {})
  end
end

-- Event filters keep the handlers from firing for unrelated entities.
local build_filters = { { filter = "type", type = "electric-pole" } }
for _, name in ipairs(shell_names) do build_filters[#build_filters + 1] = { filter = "name", name = name } end
local pole_filters = { { filter = "type", type = "electric-pole" } }

-- Register the build handler for every way an entity can appear.
for _, id in ipairs{ defines.events.on_built_entity, defines.events.on_robot_built_entity,
                     defines.events.script_raised_built, defines.events.script_raised_revive } do
  script.on_event(id, on_built, build_filters)
end
-- Register the pole removal handler for every way a pole can disappear.
for _, id in ipairs{ defines.events.on_player_mined_entity, defines.events.on_robot_mined_entity,
                     defines.events.on_entity_died, defines.events.script_raised_destroy } do
  script.on_event(id, on_pole_removed, pole_filters)
end
local clone_filters = {}
for _, name in ipairs(shell_names) do clone_filters[#clone_filters + 1] = { filter = "name", name = name } end
for name in pairs(half_names) do clone_filters[#clone_filters + 1] = { filter = "name", name = name } end
script.on_event(defines.events.on_entity_cloned, on_cloned, clone_filters)

-- Single cleanup path for mined, robot-mined, destroyed, replaced and scripted removals.
script.on_event(defines.events.on_object_destroyed, function(event)
  local reg = event.registration_number
  if not reg then return end
  local owner = storage.half_owner[reg]
  if owner then
    remove_record(owner, true) -- a half died on its own: the transformer is broken, remove the shell too
  else
    remove_record(reg)
  end
end)

---------------------------------------------------------------------------
-- Hot loop: each transformer is serviced once every N ticks, spread over buckets.
-- Per entry: 2 reads + 2 writes. No lookups, no validity checks.
-- Known limitation: the editor's "delete all entities" can destroy halves before the
-- destruction events are delivered, which crashes here. Accepted.
---------------------------------------------------------------------------
script.on_event(defines.events.on_tick, function(event)
  local bucket = buckets[event.tick % N + 1]
  for i = 1, #bucket do
    local r = bucket[i]
    local out = r.out_e
    local out_energy = out.energy
    local deficit = r.cap - out_energy
    if deficit > 0 then
      local inp = r.in_e
      local have = inp.energy
      local pull = deficit * r.mult
      if pull > have then pull = have end
      inp.energy = have - pull
      out.energy = out_energy + pull * r.eta
    end
  end
end)

-- Debounced recompute of line losses after pole / step-up changes (not a per-tick cost).
-- The check itself is one boolean every 15 ticks; the heavy work only runs after a change.
script.on_nth_tick(15, function()
  if storage.dirty then
    storage.dirty = false
    recompute_all()
  end
end)

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------
-- A new game: create the storage tables.
script.on_init(function()
  init_storage()
  bind()
end)

script.on_load(bind)

-- Runs when mods or startup settings change. The interval N may have changed, so all records are
-- re-bucketed and their output buffer capacity is refreshed. Records whose halves vanished are dropped.
script.on_configuration_changed(function()
  init_storage()
  -- Rebuild buckets (interval may have changed) and drop broken records.
  local old = storage.records
  storage.records, storage.ups, storage.downs, storage.buckets = {}, {}, {}, {}
  for i = 1, N do storage.buckets[i] = {} end
  bind()
  for reg, rec in pairs(old) do
    if rec.in_e.valid and rec.out_e.valid and C.tiers[rec.tier] then
      rec.cap = math.floor(C.tiers[rec.tier].rated_w * (N / 60) * C.buffer_safety + 0.5)
      storage.records[reg] = rec
      if rec.kind == "up" then storage.ups[reg] = rec else storage.downs[reg] = rec end
      bucket_insert(rec)
    else
      if rec.in_e.valid then rec.in_e.destroy() end
      if rec.out_e.valid then rec.out_e.destroy() end
    end
  end
  storage.dirty = true
end)

---------------------------------------------------------------------------
-- Debug helper: /pt-status
---------------------------------------------------------------------------
-- Prints each step-down's wire distance to its nearest step-up and its input/output ratio.
commands.add_command("pt-status", "Show transformer counts and step-down line losses.", function(cmd)
  local player = game.get_player(cmd.player_index)
  local ups, downs = 0, 0
  for _ in pairs(storage.ups) do ups = ups + 1 end
  for _, rec in pairs(storage.downs) do
    downs = downs + 1
    player.print(string.format("step-down T%d at (%.0f,%.0f): wire distance %s, input/output = %.4f",
      rec.tier, rec.x, rec.y, rec.line_dist and string.format("%.1f", rec.line_dist) or "UNREACHABLE", rec.mult))
  end
  player.print(string.format("step-up: %d, step-down: %d, update interval: %d ticks", ups, downs, N))
end)
