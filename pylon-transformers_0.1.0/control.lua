-- Pylon Transformers - runtime script.
--
-- Design: every transformer is a visible "shell" entity plus two hidden electric-energy-interface
-- halves (input = left, output = right). The engine handles idle drain, the output power cap and
-- the buffers natively. This script only
--   (1) creates / destroys the halves together with the shell, and
--   (2) moves energy from the input buffer to the output buffer.
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
-- Scheduling: all transformers are spread over N buckets and one bucket is serviced per tick
-- (bucket index = game.tick % N), so every transformer runs exactly once every N ticks.
--
-- Shared constants (tiers, offsets, loss limits) come from config.lua, which is also used by the
-- data stage so both stages always agree.
local C = require("__pylon-transformers__.config")

-- Update interval in ticks (startup setting). Each transformer is serviced once every N ticks.
local N = math.max(1, math.floor(settings.startup["pt-update-interval"].value))

---------------------------------------------------------------------------------------------------
-- Static lookup tables (built from config, identical to what the data stage generated)
---------------------------------------------------------------------------------------------------

-- shell prototype name -> { in_name, out_name, capacity_w, loss_w }
local shells = {}
-- hidden half prototype name -> true
local half_names = {}

for _, kind in ipairs(C.kinds) do
  for tier, tier_data in ipairs(C.tiers) do
    for _, size in ipairs(C.sizes) do
      local t = tier_data[size]
      local info = {
        in_name = C.in_name(kind, tier, size),
        out_name = C.out_name(kind, tier, size),
        capacity_w = t.capacity_w,
        -- Additional loss at 100 % load. full_w includes idle_w, so subtract it.
        -- Clamped at 0 so bad data can never turn the transformer into an energy source.
        loss_w = math.max(0, t.full_w - t.idle_w),
      }
      shells[C.shell_name(kind, tier, size)] = info
      half_names[info.in_name] = true
      half_names[info.out_name] = true
    end
  end
end

---------------------------------------------------------------------------------------------------
-- Storage
--
-- storage.transformers[unit_number] = {
--   shell = LuaEntity, input = LuaEntity, output = LuaEntity,
--   info = shells[...], bucket = index, last_tick = tick of last update,
-- }
-- storage.buckets[i][unit_number] = same record table
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

local function init_storage()
  storage.transformers = storage.transformers or {}
  rebuild_buckets()
end

---------------------------------------------------------------------------------------------------
-- Hidden halves
---------------------------------------------------------------------------------------------------

local function create_half(shell, name, dx)
  return shell.surface.create_entity{
    name = name,
    position = { shell.position.x + dx, shell.position.y },
    force = shell.force,
    create_build_effect_smoke = false,
    raise_built = false,
  }
end

local function fill_buffer(half)
  half.energy = half.electric_buffer_size
end

-- Creates whichever half is missing. A fresh output half starts full, a fresh input half empty.
-- Returns true when both halves exist afterwards.
local function ensure_halves(rec)
  local shell, info = rec.shell, rec.info

  if not (rec.input and rec.input.valid) then
    rec.input = create_half(shell, info.in_name, -C.half_offset)
  end
  if not (rec.output and rec.output.valid) then
    rec.output = create_half(shell, info.out_name, C.half_offset)
    if rec.output then fill_buffer(rec.output) end
  end

  return (rec.input and rec.input.valid and rec.output and rec.output.valid) and true or false
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
  }
  storage.transformers[unit_number] = rec
  storage.buckets[bucket][unit_number] = rec

  -- Fires on_object_destroyed when the shell goes away for any reason (mined, killed, script,
  -- fast-replaced, surface deleted), so the halves are always cleaned up.
  script.register_on_object_destroyed(shell)

  -- Creates both halves and fills the output buffer.
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
end

---------------------------------------------------------------------------------------------------
-- Energy transfer
---------------------------------------------------------------------------------------------------

local function update(rec, tick)
  local dt = tick - rec.last_tick
  if dt <= 0 then return end
  rec.last_tick = tick

  local input, output, info = rec.input, rec.output, rec.info

  local missing = output.electric_buffer_size - output.energy
  if missing <= 0 then return end

  local available = input.energy
  if available <= 0 then return end

  local dt_s = dt / 60
  local load = math.min(missing / dt_s / info.capacity_w, 1)
  local loss = info.loss_w * load * load * dt_s

  local transfer = missing
  local total = transfer + loss
  if total > available then
    -- Input cannot pay for everything: scale transfer and loss down together.
    transfer = transfer * (available / total)
    total = available
  end

  input.energy = available - total
  output.energy = output.energy + transfer
end

local function on_tick(event)
  -- Startup setting changed since the buckets were built.
  if storage.bucket_count ~= N then rebuild_buckets() end

  local tick = event.tick
  for unit_number, rec in pairs(storage.buckets[tick % N + 1]) do
    if not rec.shell.valid then
      unregister(unit_number)
    elseif ensure_halves(rec) then
      update(rec, tick)
    end
  end
end

---------------------------------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------------------------------

local function on_built(event)
  local entity = event.entity
  if entity and entity.valid and shells[entity.name] then
    register(entity)
  end
end

-- Cloning (e.g. surface.clone_area, space platform tools) may copy the hidden halves too.
-- Halves are always created by this script, so cloned ones are dropped and the cloned shell
-- gets its own pair.
local function on_cloned(event)
  local entity = event.destination
  if not (entity and entity.valid) then return end

  if half_names[entity.name] then
    entity.destroy()
  elseif shells[entity.name] then
    register(entity)
  end
end

local function on_object_destroyed(event)
  if event.type == defines.target_type.entity then
    unregister(event.useful_id)
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
script.on_event(defines.events.on_object_destroyed, on_object_destroyed)
script.on_event(defines.events.on_tick, on_tick)

script.on_init(init_storage)
script.on_configuration_changed(init_storage)