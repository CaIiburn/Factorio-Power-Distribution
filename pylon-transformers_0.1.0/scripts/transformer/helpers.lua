-- The hidden entities every transformer owns: input and output energy halves, two ports (hidden
-- poles of the matching pole class) and (heat tiers only) a heat pipe. They are listed once, in
-- HELPERS, and creation, repair, destruction and rebuilding all work from that list.
--
-- Orientation: the shell is a normal rotatable entity with four directions, and the output end is
-- where it faces: facing north the building is 2x4 with the input at the bottom (south) end and the
-- output at the top (north) end, facing east it is 4x2 with the input on the left and the output on
-- the right, and so on. That is what the engine assumes when it flips a blueprint, so a flipped
-- transformer keeps its output end. The engine does the rotating (cursor, blueprints, R on a placed
-- entity); rebuild() moves the helpers to the matching ends when a placed transformer is rotated.
local Common = require("__pylon-transformers__.scripts.transformer.common")
local Ports = require("__pylon-transformers__.scripts.transformer.ports")

local C, OUTPUT_VECTOR = Common.C, Common.OUTPUT_VECTOR
local north, south = Common.north, Common.south

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

-- The heat pipe sits on the shell's position. Heat pipes cannot rotate, so facing east/west uses
-- the horizontal variant (long side along x) and north/south the vertical one.
local function create_heat(shell, info)
  local dir = shell.direction
  local vertical = (dir == north or dir == south)
  return shell.surface.create_entity{
    name = vertical and info.heat_v or info.heat_h,
    position = shell.position,
    force = shell.force,
    create_build_effect_smoke = false,
    raise_built = false,
  }
end

-- Every helper a record can own, in creation order.
--   key        field of the record that holds the entity
--   create     (shell, info) -> LuaEntity | nil
--   init       optional (rec, entity), runs once on a freshly created entity
--   heat_only  only for tiers with the heat mechanic
-- A fresh output half starts full, a fresh input half empty, a fresh heat pipe at ambient
-- temperature.
local HELPERS = {
  {
    key = "input",
    create = function(shell, info) return create_at_end(shell, info.in_name, -1) end,
    init = function(rec, half)
      rec.in_size = half.electric_buffer_size
    end,
  },
  {
    key = "output",
    create = function(shell, info) return create_at_end(shell, info.out_name, 1) end,
    init = function(rec, half)
      local size = half.electric_buffer_size
      half.energy = size
      rec.out_size = size
      rec.out_target = size * C.control.target
    end,
  },
  -- Ports: step-up = feeder-in + pylon-out, step-down = pylon-in + distribution-out. A new port
  -- is registered with the pole logic (cleanup of its wire record, no wires yet).
  {
    key = "in_pole",
    create = function(shell, info) return create_at_end(shell, info.in_port, -1) end,
    init = function(_, port) Ports.register(port) end,
  },
  {
    key = "out_pole",
    create = function(shell, info) return create_at_end(shell, info.out_port, 1) end,
    init = function(_, port) Ports.register(port) end,
  },
  {
    key = "heat",
    heat_only = true,
    create = create_heat,
  },
}

local KEYS = {}
for i, spec in ipairs(HELPERS) do KEYS[i] = spec.key end

-- The ports move with the ends. Each keeps its role (input / output) and its wires.
local POLE_KEYS = { "in_pole", "out_pole" }

local Helpers = {}

-- Creates whichever helper is missing.
-- Returns true when everything the transformer needs exists afterwards.
function Helpers.ensure(rec)
  local shell, info = rec.shell, rec.info
  local complete, created = true, false

  for _, spec in ipairs(HELPERS) do
    if info.heat or not spec.heat_only then
      local key = spec.key
      local entity = rec[key]
      if not (entity and entity.valid) then
        entity = spec.create(shell, info)
        created = true
        rec[key] = entity
        if entity and spec.init then spec.init(rec, entity) end
        if not (entity and entity.valid) then complete = false end
      end
    end
  end

  if created then Helpers.reset_rates(rec) end
  return complete
end

-- Both halves start without a rate (the engine's default), and the controller starts from the
-- current level of the output buffer. Called whenever a half was newly created.
function Helpers.reset_rates(rec)
  rec.prod, rec.usage, rec.vrate = 0, 0, 0
  local input, output = rec.input, rec.output
  if input and input.valid then input.power_usage = 0 end
  if output and output.valid then
    output.power_production = 0
    rec.out_prev = output.energy
  end
end

-- Destroys every helper of the record and forgets it.
function Helpers.destroy(rec)
  for _, key in ipairs(KEYS) do
    local entity = rec[key]
    if entity and entity.valid then entity.destroy() end
    rec[key] = nil
  end
end

-- Moves all helpers to where the shell's current direction wants them. They are recreated rather
-- than moved, and each keeps the energy / temperature it had, so rotating never creates or
-- destroys energy or heat. The ports' wires are taken off the old port and put on the new one;
-- wires that no longer reach are dropped, and the ones that are kept are checked against the pole
-- rules again. player_index (optional) is the player who rotated the transformer, for warnings.
function Helpers.rebuild(rec, player_index)
  local input, output, heat = rec.input, rec.output, rec.heat
  local in_energy = (input and input.valid) and input.energy or nil
  local out_energy = (output and output.valid) and output.energy or nil
  local temperature = (heat and heat.valid) and heat.temperature or nil

  local wires = {}
  for _, key in ipairs(POLE_KEYS) do
    local port = rec[key]
    if port and port.valid then wires[key] = Ports.wires(port) end
  end

  Helpers.destroy(rec)

  if not Helpers.ensure(rec) then return end

  local ctx = { player_index = player_index, force = rec.shell.force }
  for key, list in pairs(wires) do
    local port = rec[key]
    if port then
      Ports.restore(port, list)
      Ports.validate(port, ctx)
    end
  end

  -- ensure() started the new output half full; put the old charge back.
  if in_energy then
    rec.input.energy = math.min(in_energy, rec.input.electric_buffer_size)
  end
  if out_energy then
    rec.output.energy = math.min(out_energy, rec.output.electric_buffer_size)
    rec.out_prev = rec.output.energy
  end
  if temperature and rec.heat then
    rec.heat.temperature = temperature
  end
end

return Helpers
