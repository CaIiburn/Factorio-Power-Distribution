-- Copper wires of the hidden connection poles: keeping them across a rotation, and cutting the
-- wire an auto-connecting pole made to both ends of the same transformer.
local Common = require("__pylon-transformers__.scripts.common")

local C, shells, POLE_NAME = Common.C, Common.shells, Common.POLE_NAME

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

return {
  pole_wires = pole_wires,
  restore_wires = restore_wires,
  separate_ends = separate_ends,
}
