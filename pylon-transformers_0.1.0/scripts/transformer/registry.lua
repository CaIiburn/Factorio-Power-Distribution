-- Storage and the record of every placed transformer.
--
-- storage.transformers[unit_number] = {
--   shell = LuaEntity, input = LuaEntity, output = LuaEntity, heat = LuaEntity | nil,
--   in_pole = LuaEntity, out_pole = LuaEntity   (the ports: hidden poles of the matching pole class, one per end),
--   info = shells[...], bucket = index, last_tick = tick of last update,
--   out_size = output buffer size (constant, cached to save an API call per update),
--   s_load / s_power / s_temp = last values written to the circuit (nil = nothing written yet),
--   next_alert = first tick at which another overheating alert may be raised,
-- }
-- storage.buckets[i][unit_number] = same record table
-- storage.overlays[player_index] = { surface_index, objects = { [pole unit_number] = LuaRenderObject } }
--   (the overlay table is owned by overlay.lua)
--
-- Scheduling: all transformers are spread over N buckets and one bucket is serviced per tick
-- (bucket index = game.tick % N), so every transformer runs exactly once every N ticks.
local Common = require("__pylon-transformers__.scripts.transformer.common")
local Helpers = require("__pylon-transformers__.scripts.transformer.helpers")
local Circuit = require("__pylon-transformers__.scripts.transformer.circuit")

local N, shells = Common.N, Common.shells

-- Bump when the layout of storage.transformers records changes incompatibly.
local STORAGE_VERSION = 2

-- Which version of the power flow the helpers belong to: 3 = the halves run at set rates and the input buffer pays
-- for the output (transfer.lua, C.control). Older saves have energy halves with other buffer sizes: they are made again.
local FLOW_VERSION = 3

-- Which way the shell's direction names point (see OUTPUT_VECTOR in common.lua). Saves without
-- this number were made when "north" meant "output on the right", one clockwise step off.
local SHELL_FRAME = 2

-- Turns every shell and every transformer ghost one step clockwise, which gives them the same
-- footprint and the same input and output ends under the current meaning of the directions. The
-- hidden helpers already stand at those ends; only the heat pipe variant name follows the footprint
-- and stays right as well (the horizontal one is still the 4x2 one).
local function turn_to_current_frame()
  local names = {}
  for name in pairs(shells) do names[#names + 1] = name end
  if #names == 0 then return end
  local step = defines.direction.east
  for _, surface in pairs(game.surfaces) do
    for _, e in pairs(surface.find_entities_filtered{ name = names }) do
      e.direction = (e.direction + step) % 16
    end
    for _, e in pairs(surface.find_entities_filtered{ ghost_name = names }) do
      e.direction = (e.direction + step) % 16
    end
  end
end

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

  Circuit.init(rec)

  -- Creates all helpers for the shell's direction and fills the output buffer.
  Helpers.ensure(rec)
end

local function unregister(unit_number)
  local rec = storage.transformers[unit_number]
  if not rec then return end

  storage.transformers[unit_number] = nil
  local bucket = storage.buckets[rec.bucket]
  if bucket then bucket[unit_number] = nil end

  Helpers.destroy(rec)
end

local function init_storage()
  local fresh = storage.transformers == nil
  storage.transformers = storage.transformers or {}

  if storage.shell_frame ~= SHELL_FRAME then
    -- A new world has nothing to turn.
    if not fresh then turn_to_current_frame() end
    storage.shell_frame = SHELL_FRAME
  end

  if storage.version ~= STORAGE_VERSION then
    -- Records from an older layout (the shell used to be a different entity type). Throw the
    -- hidden helpers away and re-register every shell that survived.
    local old = storage.transformers
    storage.transformers = {}
    storage.version = STORAGE_VERSION
    rebuild_buckets()
    for _, rec in pairs(old) do
      Helpers.destroy(rec)
      if rec.shell and rec.shell.valid then register(rec.shell) end
    end
    storage.flow_version = FLOW_VERSION
  else
    rebuild_buckets()
  end

  -- A record keeps a copy of its shell's info table from the time it was made, and a save stores
  -- that copy: after a mod update it lacks the fields that were added since. Point every record at
  -- the current table (the info of a shell that is gone stays; on_tick removes that record).
  for _, rec in pairs(storage.transformers) do
    local shell = rec.shell
    if shell and shell.valid then rec.info = shells[shell.name] or rec.info end
  end

  if storage.flow_version ~= FLOW_VERSION then
    -- Only the energy halves change, the ports (and their wires) and the heat pipes stay.
    if not fresh then
      for _, rec in pairs(storage.transformers) do
        for _, key in ipairs({ "input", "output" }) do
          local half = rec[key]
          if half and half.valid then half.destroy() end
          rec[key] = nil
        end
        if rec.shell and rec.shell.valid then Helpers.ensure(rec) end
      end
    end
    storage.flow_version = FLOW_VERSION
  end
end

return {
  register = register,
  unregister = unregister,
  rebuild_buckets = rebuild_buckets,

  on_init = init_storage,
  on_configuration_changed = init_storage,

  events = {
    [defines.events.on_object_destroyed] = function(event)
      if event.type == defines.target_type.entity then
        unregister(event.useful_id)
      end
    end,
  },
}
