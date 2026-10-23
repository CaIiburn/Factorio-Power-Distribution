-- The hidden entities every transformer owns: input and output energy halves, two connection
-- poles and (heat tiers only) a heat pipe. They are listed once, in HELPERS, and creation,
-- repair, destruction and rebuilding all work from that list.
--
-- Orientation: the shell is a normal rotatable entity with four directions. Facing north the
-- building is 4x2 with the input on the left (west) end and the output on the right (east) end.
-- Every other direction is that layout turned clockwise (east: input on top, output at the bottom;
-- south: input right, output left; west: input at the bottom, output on top). East and west are
-- 2x4 tiles. The engine does the rotating (cursor, blueprints, R on a placed entity); rebuild()
-- moves the helpers to the matching ends when a placed transformer is rotated.
local Common = require("__pylon-transformers__.scripts.common")
local Wiring = require("__pylon-transformers__.scripts.wiring")

local C, POLE_NAME, OUTPUT_VECTOR = Common.C, Common.POLE_NAME, Common.OUTPUT_VECTOR
local north, east, west = Common.north, Common.east, Common.west
local pole_wires, restore_wires = Wiring.pole_wires, Wiring.restore_wires

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
  },
  {
    key = "output",
    create = function(shell, info) return create_at_end(shell, info.out_name, 1) end,
    init = function(rec, half)
      local size = half.electric_buffer_size
      half.energy = size
      rec.out_size = size
    end,
  },
  {
    key = "in_pole",
    create = function(shell) return create_at_end(shell, POLE_NAME, -1) end,
  },
  {
    key = "out_pole",
    create = function(shell) return create_at_end(shell, POLE_NAME, 1) end,
  },
  {
    key = "heat",
    heat_only = true,
    create = create_heat,
  },
}

local KEYS = {}
for i, spec in ipairs(HELPERS) do KEYS[i] = spec.key end

-- The poles move with the ends. Each keeps its role (input / output) and its wires.
local POLE_KEYS = { "in_pole", "out_pole" }

local Helpers = {}

-- Creates whichever helper is missing.
-- Returns true when everything the transformer needs exists afterwards.
function Helpers.ensure(rec)
  local shell, info = rec.shell, rec.info
  local complete = true

  for _, spec in ipairs(HELPERS) do
    if info.heat or not spec.heat_only then
      local key = spec.key
      local entity = rec[key]
      if not (entity and entity.valid) then
        entity = spec.create(shell, info)
        rec[key] = entity
        if entity and spec.init then spec.init(rec, entity) end
        if not (entity and entity.valid) then complete = false end
      end
    end
  end

  return complete
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
-- destroys energy or heat. The poles' wires are taken off the old pole and put on the new one;
-- wires that no longer reach are dropped.
function Helpers.rebuild(rec)
  local input, output, heat = rec.input, rec.output, rec.heat
  local in_energy = (input and input.valid) and input.energy or nil
  local out_energy = (output and output.valid) and output.energy or nil
  local temperature = (heat and heat.valid) and heat.temperature or nil

  local wires = {}
  for _, key in ipairs(POLE_KEYS) do
    local pole = rec[key]
    if pole and pole.valid then wires[key] = pole_wires(pole) end
  end

  Helpers.destroy(rec)

  if not Helpers.ensure(rec) then return end

  for key, list in pairs(wires) do
    if rec[key] then restore_wires(rec[key], list) end
  end

  -- ensure() started the new output half full; put the old charge back.
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

return Helpers
