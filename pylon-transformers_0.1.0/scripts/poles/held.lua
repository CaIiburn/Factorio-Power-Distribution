-- What a player holds in their cursor.
local lookup = require("__pylon-transformers__.scripts.poles.lookup")

local H = {}

local WIRE_ITEMS = {
  ["copper-cable"] = true, ["red-wire"] = true, ["green-wire"] = true, ["copper-wire"] = true,
}

function H.name(player)
  local cs = player.cursor_stack
  if cs and cs.valid_for_read then return cs.name end
  local ghost = player.cursor_ghost
  if ghost then
    local n = ghost.name
    if type(n) ~= "string" then n = n and n.name end
    return n
  end
  return nil
end

function H.is_wire(name)
  return WIRE_ITEMS[name] == true
end

function H.pole_info(name)
  return name and lookup.pole[name] or nil
end

return H
