-- Electric pole supply areas, and the test behind the placement rule "not inside the supply area
-- of a power pole".
--
-- The rule covers EVERY electric pole, whichever mod it comes from: the pole classes of this mod
-- (feeder, pylon, distribution, auxiliary), hidden vanilla poles and poles of other mods. Pole
-- ghosts count too, so a transformer ghost cannot be planned inside the area of a planned pole.
-- Only the ports of transformers are exempt: they are meant to sit on the transformer.
local Common = require("__pylon-transformers__.scripts.transformer.common")

local C, hidden_names = Common.C, Common.hidden_names
local north, south = Common.north, Common.south

-- Tolerance for the supply-area rule: an area that merely touches the footprint does not count.
local EPS = 0.001

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

-- Prototype and prototype name of a pole or of a pole ghost.
local function pole_proto(pole)
  if pole.type == "entity-ghost" then return pole.ghost_prototype, pole.ghost_name end
  return pole.prototype, pole.name
end

local supply_cache = {}
local function supply_distance(pole)
  local proto, name = pole_proto(pole)
  local quality = pole.quality.name
  local key = name .. "/" .. quality
  local d = supply_cache[key]
  if not d then
    d = proto_supply_distance(proto, quality)
    supply_cache[key] = d
  end
  return d
end

-- Returns an electric pole (or pole ghost) whose supply area overlaps the footprint of a
-- transformer standing at pos with the given direction, or nil. Ports do not count.
local function find_covering_pole(surface, pos, direction)
  local vertical = (direction == north or direction == south)
  local hx = vertical and C.footprint.short or C.footprint.long
  local hy = vertical and C.footprint.long or C.footprint.short
  local margin = MAX_SUPPLY + 1
  local area = {
    { pos.x - hx - margin, pos.y - hy - margin },
    { pos.x + hx + margin, pos.y + hy + margin },
  }

  local function first_covering(poles)
    for _, pole in pairs(poles) do
      local _, name = pole_proto(pole)
      if not hidden_names[name] then
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

  return first_covering(surface.find_entities_filtered{ area = area, type = "electric-pole" })
      or first_covering(surface.find_entities_filtered{ area = area, ghost_type = "electric-pole" })
end

return {
  supply_distance = supply_distance,
  find_covering_pole = find_covering_pole,
}
