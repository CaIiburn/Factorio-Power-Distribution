-- The ports of a transformer: the two hidden poles on its ends (step-up: feeder in, pylon out;
-- step-down: pylon in, distribution out). They are ordinary poles of the pole classes, so the wire
-- rules of scripts/poles apply to them: only poles of the port's own class can be wired to it,
-- and the network limits (pole count, transformer outputs) are enforced on its wires.
--
-- This module is the transformer's side of that: registering a freshly created port, and moving
-- the copper wires of a port to its replacement when the transformer is rotated.
local Graph = require("__pylon-transformers__.scripts.poles.graph")
local Wires = require("__pylon-transformers__.scripts.poles.wires")

local Ports = {}

-- Copper wires of a port as { { owner = LuaEntity, origin = wire origin }, ... }.
function Ports.wires(port)
  local list = {}
  for _, nb in ipairs(Graph.neighbors(port)) do
    list[#list + 1] = { owner = nb.entity, origin = nb.origin }
  end
  return list
end

-- Puts wires taken with Ports.wires() onto another port. Wires that are out of reach are skipped.
function Ports.restore(port, list)
  local conn = Graph.connector(port)
  if not conn then return end
  for _, w in ipairs(list) do
    if w.owner.valid then
      local other = Graph.connector(w.owner)
      if other then conn.connect_to(other, true, w.origin) end
    end
  end
end

-- A freshly created port: have the engine tell us when it goes away (the wire record of the pole
-- logic is cleaned up then) and record that it has no wires yet.
function Ports.register(port)
  script.register_on_object_destroyed(port)
  Wires.refresh_snapshot(port)
end

-- Checks the wires of a port against the pole rules and cuts the ones that break them.
-- ctx = { player_index = n | nil, force = LuaForce | nil }, used for the warnings.
function Ports.validate(port, ctx)
  return Wires.validate(port, ctx)
end

return Ports
