-- Pylon Transformers - runtime script.
--
-- Design: every transformer is a visible "shell" entity (a constant combinator) plus hidden
-- helper entities:
--   * two electric-energy-interface halves (input and output, on opposite ends of the shell).
--     The engine handles idle drain, the output power cap and the buffers natively.
--   * two small connection poles, one on each half. Their supply area only reaches the half at
--     their end and they never wire themselves to anything (auto_connect_up_to_n_wires = 0). They
--     are the connection points to the outside grid: the player wires them by hand. The script
--     keeps the wires when the transformer is rotated and cuts a wire that an auto-connecting
--     pole built nearby made to both ends of the same transformer.
--   * for heat tiers (config: C.heat.tiers) one hidden heat-pipe that owns the temperature and
--     lets ordinary heat pipes connect to the long sides of the transformer.
-- This script only
--   (1) creates / destroys / repositions the helpers together with the shell,
--   (2) moves energy from the input buffer to the output buffer,
--   (3) writes load / power (/ temperature) to the shell's circuit signals,
--   (4) heats and cools heat-tier transformers, raises alerts and lets them explode,
--   (5) refuses to build / rotate a transformer into the supply area of any electric pole,
--   (6) shows the supply areas of nearby electric poles while a transformer is held.
--
-- Orientation: the shell is a normal rotatable entity with four directions. Facing north the
-- building is 4x2 with the input on the left (west) end and the output on the right (east) end.
-- Every other direction is that layout turned clockwise (east: input on top, output at the bottom;
-- south: input right, output left; west: input at the bottom, output on top). East and west are
-- 2x4 tiles. The engine does the rotating (cursor, blueprints, R on a placed entity); this script
-- moves the helpers to the matching ends when a placed transformer is rotated, and each keeps
-- its stored energy / temperature.
--
-- Transfer, per transformer, once every N ticks (N = startup setting "pt-update-interval"):
--   missing   = output buffer size - output energy
--   load      = (missing / dt_seconds) / capacity_w            (clamped to 0..1)
--   loss      = (full_w - idle_w) * load^2 * dt_seconds         (conversion loss, on top of idle drain)
--   input    -= missing + loss
--   output   += missing
-- If the input buffer cannot pay for missing + loss, both are scaled down proportionally so
-- no energy is ever created and the input never goes below zero.
--
-- Heat (heat tiers only), same update:
--   P     = idle_w (only while the input has energy) + loss actually paid / dt
--   T_eq  = ambient + P / cooling
--   T     = T_eq + (T - T_eq) * exp(-dt * cooling / specific_heat)
--   T >= explode_c  ->  the shell dies and damages everything around it.
--
-- Circuit output: pt-load (% of rated), pt-power (kW), pt-temperature (heat tiers). A constant
-- combinator is only written when a quantised value changed, so a steady load costs nothing.
--
-- Scheduling: all transformers are spread over N buckets and one bucket is serviced per tick
-- (bucket index = game.tick % N), so every transformer runs exactly once every N ticks.
--
-- Shared constants (tiers, offsets, loss and heat limits) come from config.lua, which is also
-- used by the data stage so both stages always agree.
local C = require("__pylon-transformers__.config")

-- Update interval in ticks (startup setting). Each transformer is serviced once every N ticks.
local N = math.max(1, math.floor(settings.startup["pt-update-interval"].value))

-- Runtime setting, cached; kept current by on_runtime_mod_setting_changed.
local explosions_enabled = settings.global["pt-explosions"].value

-- Bump when the layout of storage.transformers records changes incompatibly.
local STORAGE_VERSION = 2

local AMBIENT = C.heat.ambient
local ALERT_INTERVAL = C.heat.alert_interval

local POLE_NAME = C.pole_name
-- Tolerance for the supply-area rule: an area that merely touches the footprint does not count.
local EPS = 0.001

-- Held-item overlay: radius around the player that is searched for poles, and refresh interval.
local OVERLAY_RADIUS = 48
local OVERLAY_INTERVAL = 15
local OVERLAY_COLOR = { r = 0.08, g = 0.22, b = 0.35, a = 0.28 }

-- Signal ids, created once. The engine copies them on every write.
local SIG_LOAD = { type = "virtual", name = C.signal.load, quality = "normal" }
local SIG_POWER = { type = "virtual", name = C.signal.power, quality = "normal" }
local SIG_TEMPERATURE = { type = "virtual", name = C.signal.temperature, quality = "normal" }

---------------------------------------------------------------------------------------------------
-- Static lookup tables (built from config, identical to what the data stage generated)
---------------------------------------------------------------------------------------------------

-- shell prototype name -> info (see below)
local shells = {}
-- hidden helper prototype name -> true (halves and heat pipes)
local hidden_names = { [POLE_NAME] = true }

for _, kind in ipairs(C.kinds) do
  for tier, tier_data in ipairs(C.tiers) do
    for _, size in ipairs(C.sizes) do
      local t = tier_data[size]
      local info = {
        in_name = C.in_name(kind, tier, size),
        out_name = C.out_name(kind, tier, size),
        capacity_w = t.capacity_w,
        idle_w = t.idle_w,
        -- Additional loss at 100 % load. full_w includes idle_w, so subtract it.
        -- Clamped at 0 so bad data can never turn the transformer into an energy source.
        loss_w = math.max(0, t.full_w - t.idle_w),
        -- Resolution of the power signal in kW.
        power_step = math.max(1, math.floor(t.capacity_w / 1000 * C.signal_power_resolution)),
      }
      hidden_names[info.in_name] = true
      hidden_names[info.out_name] = true

      local h = t.heat
      if h then
        info.heat = h
        -- exp() factor for the normal case dt == N, so the hot path needs no math.exp call.
        info.heat_decay = math.exp(-(N / 60) * h.cooling / h.specific_heat)
        info.heat_h = C.heat_name(kind, tier, size, false)
        info.heat_v = C.heat_name(kind, tier, size, true)
        info.blast = C.heat.blast[size]
        hidden_names[info.heat_h] = true
        hidden_names[info.heat_v] = true
      end

      shells[C.shell_name(kind, tier, size)] = info
    end
  end
end

local north, east, south, west =
  defines.direction.north, defines.direction.east, defines.direction.south, defines.direction.west

-- Direction of the shell -> unit vector from the shell center towards its OUTPUT end.
-- The input end is the opposite one. Turning clockwise: right -> down -> left -> up.
local OUTPUT_VECTOR = {
  [north] = {  1,  0 },
  [east]  = {  0,  1 },
  [south] = { -1,  0 },
  [west]  = {  0, -1 },
}

---------------------------------------------------------------------------------------------------
-- Electric pole supply areas
---------------------------------------------------------------------------------------------------

-- Supply area "radius" of a pole prototype at a quality level. Falls back to the normal quality
-- if the quality argument is not accepted, and to 0 if the prototype has no supply area.
local function proto_supply_distance(proto, quality_name)
  local ok, d = pcall(function() return proto.get_supply_area_distance(quality_name) end)
  if ok and d then return d end
  ok, d = pcall(function() return proto.get_supply_area_distance() end)
  return (ok and d) or 0
end

-- Largest supply radius of any pole at any quality. Used as the margin when searching for poles.
local MAX_SUPPLY = 0
for _, proto in pairs(prototypes.get_entity_filtered{ { filter = "type", type = "electric-pole" } }) do
  for _, quality in pairs(prototypes.quality) do
    MAX_SUPPLY = math.max(MAX_SUPPLY, proto_supply_distance(proto, quality.name))
  end
end

local supply_cache = {}
local function supply_distance(pole)
  local quality = pole.quality.name
  local key = pole.name .. "/" .. quality
  local d = supply_cache[key]
  if not d then
    d = proto_supply_distance(pole.prototype, quality)
    supply_cache[key] = d
  end
  return d
end

---------------------------------------------------------------------------------------------------
-- Storage
--
-- storage.transformers[unit_number] = {
--   shell = LuaEntity, input = LuaEntity, output = LuaEntity, heat = LuaEntity | nil,
--   in_pole = LuaEntity, out_pole = LuaEntity   (hidden connection poles, one per end),
--   info = shells[...], bucket = index, last_tick = tick of last update,
--   out_size = output buffer size (constant, cached to save an API call per update),
--   s_load / s_power / s_temp = last values written to the circuit (nil = nothing written yet),
--   next_alert = first tick at which another overheating alert may be raised,
-- }
-- storage.buckets[i][unit_number] = same record table
-- storage.overlays[player_index] = { surface_index, objects = { [pole unit_number] = LuaRenderObject } }
---------------------------------------------------------------------------------------------------

-- Spread all records over N buckets. Called whenever the bucket count differs from N
-- (first run, or the startup setting changed between saves).
local function rebuild_buckets()
  local buckets = {}
  for i = 1, N do buckets[i] = {} end

  local i = 0
  for unit_number, rec in pairs(storage.transformers) do
    i = i % N + 1
    buckets[i][unit_number] = rec
    rec.bucket = i
  end

  storage.buckets = buckets
  storage.bucket_count = N
  storage.next_bucket = i % N + 1
end

---------------------------------------------------------------------------------------------------
-- Hidden helpers
---------------------------------------------------------------------------------------------------

-- Creates a hidden entity on one end of the shell. side = 1 for the output end, -1 for the input end.
local function create_at_end(shell, name, side)
  local v = OUTPUT_VECTOR[shell.direction] or OUTPUT_VECTOR[north]
  local d = C.half_offset * side
  local pos = shell.position
  return shell.surface.create_entity{
    name = name,
    position = { pos.x + v[1] * d, pos.y + v[2] * d },
    force = shell.force,
    create_build_effect_smoke = false,
    raise_built = false,
  }
end

-- The heat pipe sits on the shell's position. Heat pipes cannot rotate, so facing north/south
-- uses the horizontal variant (long side along x) and east/west the vertical one.
local function create_heat(shell, info)
  local dir = shell.direction
  local vertical = (dir == east or dir == west)
  return shell.surface.create_entity{
    name = vertical and info.heat_v or info.heat_h,
    position = shell.position,
    force = shell.force,
    create_build_effect_smoke = false,
    raise_built = false,
  }
end

local POLE_COPPER = defines.wire_connector_id.pole_copper

-- Copper wires of a pole as { { owner = LuaEntity, origin = wire origin }, ... }.
local function pole_wires(pole)
  local wires = {}
  local conn = pole.get_wire_connector(POLE_COPPER, true)
  if conn then
    for _, c in pairs(conn.connections) do
      local owner = c.target.owner
      if owner.valid then wires[#wires + 1] = { owner = owner, origin = c.origin } end
    end
  end
  return wires
end

-- Puts wires taken with pole_wires() onto another pole. Wires that are out of reach are skipped.
local function restore_wires(pole, wires)
  local conn = pole.get_wire_connector(POLE_COPPER, true)
  if not conn then return end
  for _, w in ipairs(wires) do
    if w.owner.valid then
      local other = w.owner.get_wire_connector(POLE_COPPER, true)
      if other then conn.connect_to(other, true, w.origin) end
    end
  end
end

-- The record of the transformer a connection pole belongs to, or nil.
local function rec_of_pole(pole)
  local pos = pole.position
  local best, best_d
  for _, e in pairs(pole.surface.find_entities_filtered{
    position = pos, radius = C.half_offset + 0.5, type = "constant-combinator",
  }) do
    if shells[e.name] then
      local dx, dy = e.position.x - pos.x, e.position.y - pos.y
      local d = dx * dx + dy * dy
      if not best_d or d < best_d then best, best_d = e, d end
    end
  end
  local rec = best and storage.transformers[best.unit_number] or nil
  if rec and (rec.in_pole == pole or rec.out_pole == pole) then return rec end
  return nil
end

-- The connection poles have a wire reach of C.pole_reach, so an electric pole that was just built
-- (and auto-connected by the engine) can easily have been wired to BOTH ends of one transformer,
-- which would join its input and output networks. Keep the nearest end, cut the other.
-- Wires the player makes by hand are left alone.
local function separate_ends(pole)
  local conn = pole.get_wire_connector(POLE_COPPER, true)
  if not conn then return end

  local by_rec = {}
  for _, c in pairs(conn.connections) do
    local owner = c.target.owner
    if owner.valid and owner.name == POLE_NAME then
      local rec = rec_of_pole(owner)
      if rec then
        local list = by_rec[rec]
        if not list then list = {}; by_rec[rec] = list end
        local dx, dy = owner.position.x - pole.position.x, owner.position.y - pole.position.y
        list[#list + 1] = { target = c.target, origin = c.origin, d = dx * dx + dy * dy }
      end
    end
  end

  for _, list in pairs(by_rec) do
    if #list > 1 then
      table.sort(list, function(a, b) return a.d < b.d end)
      for i = 2, #list do conn.disconnect_from(list[i].target, list[i].origin) end
    end
  end
end

local function fill_buffer(half)
  half.energy = half.electric_buffer_size
end

-- Creates whichever helper is missing. A fresh output half starts full, a fresh input half
-- empty, a fresh heat pipe at ambient temperature.
-- Returns true when everything the transformer needs exists afterwards.
local function ensure_halves(rec)
  local shell, info = rec.shell, rec.info

  if not (rec.input and rec.input.valid) then
    rec.input = create_at_end(shell, info.in_name, -1)
  end
  if not (rec.output and rec.output.valid) then
    rec.output = create_at_end(shell, info.out_name, 1)
    if rec.output then
      fill_buffer(rec.output)
      rec.out_size = rec.output.electric_buffer_size
    end
  end
  if not (rec.in_pole and rec.in_pole.valid) then
    rec.in_pole = create_at_end(shell, POLE_NAME, -1)
  end
  if not (rec.out_pole and rec.out_pole.valid) then
    rec.out_pole = create_at_end(shell, POLE_NAME, 1)
  end
  if info.heat and not (rec.heat and rec.heat.valid) then
    rec.heat = create_heat(shell, info)
  end

  local ok = rec.input and rec.input.valid and rec.output and rec.output.valid
             and rec.in_pole and rec.in_pole.valid and rec.out_pole and rec.out_pole.valid
  if ok and info.heat then ok = rec.heat and rec.heat.valid end
  return ok and true or false
end

-- Moves all helpers to where the shell's current direction wants them. They are recreated rather
-- than moved, and each keeps the energy / temperature it had, so rotating never creates or
-- destroys energy or heat.
local function rebuild_halves(rec)
  local input, output, heat = rec.input, rec.output, rec.heat
  local in_energy = (input and input.valid) and input.energy or nil
  local out_energy = (output and output.valid) and output.energy or nil
  local temperature = (heat and heat.valid) and heat.temperature or nil

  if input and input.valid then input.destroy() end
  if output and output.valid then output.destroy() end
  if heat and heat.valid then heat.destroy() end
  -- The poles move with the ends. Each keeps its role (input / output) and its wires: they are
  -- taken off the old pole and put on the new one. Wires that no longer reach are dropped.
  local wires = {}
  for _, key in ipairs{ "in_pole", "out_pole" } do
    local pole = rec[key]
    if pole and pole.valid then
      wires[key] = pole_wires(pole)
      pole.destroy()
    end
    rec[key] = nil
  end
  rec.input, rec.output, rec.heat = nil, nil, nil

  if not ensure_halves(rec) then return end

  for key, list in pairs(wires) do
    if rec[key] then restore_wires(rec[key], list) end
  end

  -- ensure_halves() started the new output half full; put the old charge back.
  if in_energy then
    rec.input.energy = math.min(in_energy, rec.input.electric_buffer_size)
  end
  if out_energy then
    rec.output.energy = math.min(out_energy, rec.output.electric_buffer_size)
  end
  if temperature and rec.heat then
    rec.heat.temperature = temperature
  end
end

---------------------------------------------------------------------------------------------------
-- Circuit output
---------------------------------------------------------------------------------------------------

-- Removes every signal section (e.g. ones pasted from a blueprint) and forgets what was written,
-- so the next update writes a correct state. Also locks the GUI: the script owns the signals.
local function init_circuit(rec)
  local shell = rec.shell
  shell.operable = false
  local cb = shell.get_control_behavior()
  if cb then
    for i = cb.sections_count, 1, -1 do cb.remove_section(i) end
  end
  rec.s_load, rec.s_power, rec.s_temp = nil, nil, nil
end

-- Called only when a quantised value changed. temp_c is nil for tiers without temperature.
local function write_signals(rec, load_pct, power_kw, temp_c)
  local cb = rec.shell.get_control_behavior()
  if not cb then return false end
  local section = cb.get_section(1) or cb.add_section()
  if not section then return false end

  local filters = {
    { value = SIG_LOAD,  min = load_pct },
    { value = SIG_POWER, min = power_kw },
  }
  if temp_c then
    filters[3] = { value = SIG_TEMPERATURE, min = temp_c }
  end
  section.filters = filters
  return true
end

---------------------------------------------------------------------------------------------------
-- Register / unregister
---------------------------------------------------------------------------------------------------

local function register(shell)
  local info = shells[shell.name]
  local unit_number = shell.unit_number
  if not info or not unit_number or storage.transformers[unit_number] then return end

  local bucket = storage.next_bucket
  storage.next_bucket = bucket % N + 1

  local rec = {
    shell = shell,
    info = info,
    bucket = bucket,
    last_tick = game.tick,
    next_alert = 0,
  }
  storage.transformers[unit_number] = rec
  storage.buckets[bucket][unit_number] = rec

  -- Fires on_object_destroyed when the shell goes away for any reason (mined, killed, script,
  -- fast-replaced, surface deleted), so the helpers are always cleaned up.
  script.register_on_object_destroyed(shell)

  init_circuit(rec)

  -- Creates all helpers for the shell's direction and fills the output buffer.
  ensure_halves(rec)
end

local function unregister(unit_number)
  local rec = storage.transformers[unit_number]
  if not rec then return end

  storage.transformers[unit_number] = nil
  local bucket = storage.buckets[rec.bucket]
  if bucket then bucket[unit_number] = nil end

  if rec.input and rec.input.valid then rec.input.destroy() end
  if rec.output and rec.output.valid then rec.output.destroy() end
  if rec.heat and rec.heat.valid then rec.heat.destroy() end
  if rec.in_pole and rec.in_pole.valid then rec.in_pole.destroy() end
  if rec.out_pole and rec.out_pole.valid then rec.out_pole.destroy() end
end

local function init_storage()
  storage.transformers = storage.transformers or {}

  if storage.version ~= STORAGE_VERSION then
    -- Records from an older layout (the shell used to be a different entity type). Throw the
    -- hidden helpers away and re-register every shell that survived.
    local old = storage.transformers
    storage.transformers = {}
    storage.version = STORAGE_VERSION
    rebuild_buckets()
    for _, rec in pairs(old) do
      for _, key in ipairs{ "input", "output", "heat", "in_pole", "out_pole" } do
        local e = rec[key]
        if e and e.valid then e.destroy() end
      end
      if rec.shell and rec.shell.valid then register(rec.shell) end
    end
  else
    rebuild_buckets()
  end
end

---------------------------------------------------------------------------------------------------
-- Overheating
---------------------------------------------------------------------------------------------------

-- Kills the shell and damages everything around it. Records the position first, because the shell
-- is gone afterwards. The later on_object_destroyed finds no record and does nothing.
local function explode(rec, unit_number)
  local shell = rec.shell
  local surface, pos, force = shell.surface, shell.position, shell.force
  local blast = rec.info.blast

  unregister(unit_number)
  shell.die()

  force.print({ "pt-message.exploded",
    string.format("[gps=%d,%d,%s]", pos.x, pos.y, surface.name) })

  if not blast then return end
  for _, e in pairs(surface.find_entities_filtered{ position = pos, radius = blast.radius }) do
    if e.valid and e.is_entity_with_health and not hidden_names[e.name]
       and (e.unit_number == nil or e.unit_number ~= unit_number) then
      local dx, dy = e.position.x - pos.x, e.position.y - pos.y
      local dist = math.sqrt(dx * dx + dy * dy)
      e.damage(blast.damage * (1 - 0.75 * math.min(dist / blast.radius, 1)), "neutral", "explosion")
    end
  end
end

local function raise_alert(rec, temperature, tick)
  rec.next_alert = tick + ALERT_INTERVAL
  local shell = rec.shell
  local icon = { type = "item", name = shell.name }
  local message = { "pt-message.overheating", string.format("%d", temperature) }
  for _, player in pairs(shell.force.connected_players) do
    player.add_custom_alert(shell, icon, message, true)
  end
end

---------------------------------------------------------------------------------------------------
-- Energy transfer
---------------------------------------------------------------------------------------------------

local function update(rec, tick, unit_number)
  local dt = tick - rec.last_tick
  if dt <= 0 then return end
  rec.last_tick = tick

  local input, output, info = rec.input, rec.output, rec.info
  local dt_s = dt / 60

  local out_energy = output.energy
  local missing = rec.out_size - out_energy

  -- The input is only read when it matters: something has to be moved, or the idle heat depends
  -- on whether the input network is supplying power.
  local available = 0
  if missing > 0 or info.heat then available = input.energy end

  local transfer, loss = 0, 0
  if missing > 0 and available > 0 then
    local load = math.min(missing / dt_s / info.capacity_w, 1)
    loss = info.loss_w * load * load * dt_s

    transfer = missing
    local total = transfer + loss
    if total > available then
      -- Input cannot pay for everything: scale transfer and loss down together.
      local scale = available / total
      transfer = transfer * scale
      loss = loss * scale
      total = available
    end

    input.energy = available - total
    output.energy = out_energy + transfer
  end

  -- Heat ---------------------------------------------------------------------------------------
  local temp_q
  local h = info.heat
  if h then
    local heat = rec.heat
    local temperature = heat.temperature

    -- Waste heat: the conversion loss that was actually paid plus the idle drain while powered.
    local power = loss / dt_s
    if available > 0 then power = power + info.idle_w end

    local decay = info.heat_decay
    if dt ~= N then decay = math.exp(-dt_s * h.cooling / h.specific_heat) end

    local t_eq = AMBIENT + power / h.cooling
    local t_new = t_eq + (temperature - t_eq) * decay
    if math.abs(t_new - temperature) > 0.01 then
      heat.temperature = t_new
    end

    if explosions_enabled and (temperature >= h.explode_c or t_new >= h.explode_c) then
      explode(rec, unit_number)
      return
    end

    if t_new >= h.warn_c and tick >= rec.next_alert then
      raise_alert(rec, t_new, tick)
    end

    temp_q = math.floor(t_new + 0.5)
  end

  -- Circuit signals (only written when a quantised value changed) -----------------------------
  local load_pct = math.min(100, math.floor(transfer / dt_s / info.capacity_w * 100 + 0.5))
  local power_kw = math.floor(transfer / dt_s / 1000 / info.power_step + 0.5) * info.power_step
  if load_pct ~= rec.s_load or power_kw ~= rec.s_power or temp_q ~= rec.s_temp then
    if write_signals(rec, load_pct, power_kw, temp_q) then
      rec.s_load, rec.s_power, rec.s_temp = load_pct, power_kw, temp_q
    end
  end
end

local function on_tick(event)
  -- Startup setting changed since the buckets were built.
  if storage.bucket_count ~= N then rebuild_buckets() end

  local tick = event.tick
  for unit_number, rec in pairs(storage.buckets[tick % N + 1]) do
    if not rec.shell.valid then
      unregister(unit_number)
    elseif ensure_halves(rec) then
      update(rec, tick, unit_number)
    end
  end
end

---------------------------------------------------------------------------------------------------
-- Placement rule: not inside the supply area of an electric pole
---------------------------------------------------------------------------------------------------

-- Returns an electric pole whose supply area overlaps the footprint of a transformer standing at
-- pos with the given direction, or nil. The hidden poles of transformers do not count.
local function find_covering_pole(surface, pos, direction)
  local vertical = (direction == east or direction == west)
  local hx = vertical and C.footprint.short or C.footprint.long
  local hy = vertical and C.footprint.long or C.footprint.short
  local margin = MAX_SUPPLY + 1

  local poles = surface.find_entities_filtered{
    area = { { pos.x - hx - margin, pos.y - hy - margin }, { pos.x + hx + margin, pos.y + hy + margin } },
    type = "electric-pole",
  }
  for _, pole in pairs(poles) do
    if not hidden_names[pole.name] then
      local d = supply_distance(pole)
      local p = pole.position
      if p.x - d < pos.x + hx - EPS and p.x + d > pos.x - hx + EPS
         and p.y - d < pos.y + hy - EPS and p.y + d > pos.y - hy + EPS then
        return pole
      end
    end
  end
  return nil
end

-- Tells the player (flying text) or, without a player, the force (chat message with a map tag).
local function notify(player, force, surface, pos, message)
  if player and player.valid then
    player.create_local_flying_text{ text = message, position = pos }
  else
    force.print({ "", message, " ", string.format("[gps=%d,%d,%s]", pos.x, pos.y, surface.name) })
  end
end

-- Undoes a build: the entity (or ghost) disappears and the item goes back to the player, or onto
-- the ground when the player's inventory is full or a robot / script built it.
local function reject_build(entity, event)
  local surface, pos, force = entity.surface, entity.position, entity.force
  local is_ghost = entity.type == "entity-ghost"
  local item = is_ghost and entity.ghost_name or entity.name
  local quality = entity.quality.name
  local player = event.player_index and game.get_player(event.player_index) or nil

  entity.destroy()
  notify(player, force, surface, pos, { "pt-message.in-pole-area" })
  if is_ghost then return end

  local stack = { name = item, count = 1, quality = quality }
  if player and player.valid and player.insert(stack) >= 1 then return end
  surface.create_entity{ name = "item-on-ground", position = pos, stack = stack }
end

---------------------------------------------------------------------------------------------------
-- Rotation
---------------------------------------------------------------------------------------------------

-- A player rotated a placed transformer (R / Shift+R): move the helpers to the ends that match the
-- new direction. Placing a transformer with a direction (cursor, blueprint, fast replace) does not
-- need this, because register() creates the helpers for the direction it is built with.
local function on_player_rotated_entity(event)
  local entity = event.entity
  if not (entity and entity.valid and shells[entity.name]) then return end

  -- The turned footprint must not newly reach into a pole's supply area. A transformer that is
  -- already inside one (a pole built next to it later) can still be rotated.
  if not find_covering_pole(entity.surface, entity.position, event.previous_direction)
     and find_covering_pole(entity.surface, entity.position, entity.direction) then
    entity.direction = event.previous_direction
    notify(game.get_player(event.player_index), entity.force, entity.surface, entity.position,
      { "pt-message.in-pole-area" })
    return
  end

  local rec = storage.transformers[entity.unit_number]
  if rec then rebuild_halves(rec) end
end

---------------------------------------------------------------------------------------------------
-- Held-item overlay
--
-- The engine only shows the supply areas of electric poles while the cursor holds an entity with an
-- electric energy source, which a transformer shell (a constant combinator) has not. So while a
-- transformer item (or its ghost) is in the cursor, the supply areas of the poles around the
-- player are drawn by script, visible to that player only. Those are exactly the areas a
-- transformer cannot be built in. Nothing runs while nobody holds a transformer.
---------------------------------------------------------------------------------------------------

local function get_overlays()
  local overlays = storage.overlays
  if not overlays then
    overlays = {}
    storage.overlays = overlays
  end
  return overlays
end

local function holds_transformer(player)
  local stack = player.cursor_stack
  if stack and stack.valid_for_read and shells[stack.name] then return true end

  local ghost = player.cursor_ghost
  if ghost then
    local name = ghost.name
    if type(name) ~= "string" then name = name.name end
    return shells[name] ~= nil
  end
  return false
end

local function clear_overlay(player_index)
  local overlays = get_overlays()
  local overlay = overlays[player_index]
  if not overlay then return end
  for _, object in pairs(overlay.objects) do
    if object.valid then object.destroy() end
  end
  overlays[player_index] = nil
end

-- Brings the drawn rectangles in line with the poles around the player: draws the missing ones
-- and removes the ones whose pole is gone or out of range. Unchanged poles cost nothing.
local function refresh_overlay(player)
  local overlays = get_overlays()
  local overlay = overlays[player.index]
  if overlay and overlay.surface_index ~= player.surface_index then
    clear_overlay(player.index)
    overlay = nil
  end
  if not overlay then
    overlay = { surface_index = player.surface_index, objects = {} }
    overlays[player.index] = overlay
  end

  local surface = player.surface
  local seen = {}
  for _, pole in pairs(surface.find_entities_filtered{
    position = player.position, radius = OVERLAY_RADIUS, type = "electric-pole",
  }) do
    if not hidden_names[pole.name] then
      local id = pole.unit_number
      seen[id] = true
      if not overlay.objects[id] then
        local d = supply_distance(pole)
        local p = pole.position
        overlay.objects[id] = rendering.draw_rectangle{
          color = OVERLAY_COLOR,
          filled = true,
          left_top = { p.x - d, p.y - d },
          right_bottom = { p.x + d, p.y + d },
          surface = surface,
          players = { player },
          draw_on_ground = true,
        }
      end
    end
  end

  for id, object in pairs(overlay.objects) do
    if not seen[id] then
      if object.valid then object.destroy() end
      overlay.objects[id] = nil
    end
  end
end

local function on_cursor_stack_changed(event)
  local player = game.get_player(event.player_index)
  if not player then return end
  if holds_transformer(player) then
    refresh_overlay(player)
  else
    clear_overlay(player.index)
  end
end

local function on_overlay_tick()
  local overlays = storage.overlays
  if not overlays or next(overlays) == nil then return end

  for player_index in pairs(overlays) do
    local player = game.get_player(player_index)
    if player and player.valid and player.connected and holds_transformer(player) then
      refresh_overlay(player)
    else
      clear_overlay(player_index)
    end
  end
end

local function on_player_gone(event)
  clear_overlay(event.player_index)
end

---------------------------------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------------------------------

local function on_built(event)
  local entity = event.entity
  if not (entity and entity.valid) then return end
  local name = entity.name

  -- A transformer ghost is refused right away where the real thing could not be built.
  if name == "entity-ghost" then
    if shells[entity.ghost_name]
       and find_covering_pole(entity.surface, entity.position, entity.direction) then
      reject_build(entity, event)
    end
    return
  end

  -- A new electric pole: the engine may have auto-connected it to both ends of a transformer.
  if entity.type == "electric-pole" then
    if not hidden_names[name] then separate_ends(entity) end
    return
  end

  if not shells[name] then return end

  if find_covering_pole(entity.surface, entity.position, entity.direction) then
    reject_build(entity, event)
    return
  end
  register(entity)
end

-- Cloning (e.g. surface.clone_area, space platform tools) may copy the hidden helpers too.
-- Helpers are always created by this script, so cloned ones are dropped and the cloned shell
-- gets its own set.
local function on_cloned(event)
  local entity = event.destination
  if not (entity and entity.valid) then return end

  if hidden_names[entity.name] then
    entity.destroy()
  elseif shells[entity.name] then
    register(entity)
  end
end

-- Settings pasted onto a transformer would overwrite its signals: wipe them and rewrite.
local function on_entity_settings_pasted(event)
  local entity = event.destination
  if not (entity and entity.valid and shells[entity.name]) then return end

  local rec = storage.transformers[entity.unit_number]
  if rec then init_circuit(rec) end
end

local function on_object_destroyed(event)
  if event.type == defines.target_type.entity then
    unregister(event.useful_id)
  end
end

local function on_runtime_mod_setting_changed(event)
  if event.setting == "pt-explosions" then
    explosions_enabled = settings.global["pt-explosions"].value
  end
end

for _, event_id in ipairs{
  defines.events.on_built_entity,
  defines.events.on_robot_built_entity,
  defines.events.on_space_platform_built_entity,
  defines.events.script_raised_built,
  defines.events.script_raised_revive,
} do
  script.on_event(event_id, on_built)
end

script.on_event(defines.events.on_entity_cloned, on_cloned)
script.on_event(defines.events.on_entity_settings_pasted, on_entity_settings_pasted)
script.on_event(defines.events.on_object_destroyed, on_object_destroyed)
script.on_event(defines.events.on_player_rotated_entity, on_player_rotated_entity)
script.on_event(defines.events.on_runtime_mod_setting_changed, on_runtime_mod_setting_changed)
script.on_event(defines.events.on_tick, on_tick)

script.on_event(defines.events.on_player_cursor_stack_changed, on_cursor_stack_changed)
script.on_event(defines.events.on_player_left_game, on_player_gone)
script.on_event(defines.events.on_player_removed, on_player_gone)
script.on_nth_tick(OVERLAY_INTERVAL, on_overlay_tick)

script.on_init(init_storage)
script.on_configuration_changed(init_storage)
