local shared = require("__pylon-transformers__.config").pole
local util = require("util")
local PylonArt = require("__pylon-transformers__.prototypes.pylon-art")

local M = {}

local function tier_tint(color, tier)
  local k = 0.6 + 0.4 * (tier - 1) / (shared.TIER_COUNT - 1)
  return { r = color[1] * k, g = color[2] * k, b = color[3] * k, a = 1 }
end
M.tier_tint = tier_tint

-- Adds a tint to every non-shadow sprite found under `node`.
-- The tint is assigned before the node is iterated, so no key is added
-- to a table while it is being traversed.
local function tint_sprites(node, tint)
  if type(node) ~= "table" then return end
  if node.filename and not node.draw_as_shadow then
    node.tint = tint
  end
  for key, value in pairs(node) do
    if key ~= "tint" and type(value) == "table" then
      tint_sprites(value, tint)
    end
  end
end

-- The icons of a pole family's item and entity, tinted. The pylon has an icon of its own (its
-- sprite); the others take the icon of the vanilla pole they are based on.
local function tinted_icons(item, tint, family)
  if family == "pylon" then
    return { { icon = PylonArt.icon, icon_size = PylonArt.icon_size, tint = PylonArt.tint(tint) } }
  end
  local icons
  if item and item.icons then
    icons = util.table.deepcopy(item.icons)
    for _, layer in ipairs(icons) do layer.tint = tint end
  elseif item and item.icon then
    icons = { { icon = item.icon, icon_size = item.icon_size or 64, tint = tint } }
  end
  return icons
end
M.tinted_icons = tinted_icons

local function tooltip_fields(def)
  local fields = {
    { name = { "pc.tt-class" }, value = { "pc.class-" .. def.class }, order = 100 },
    { name = { "pc.tt-reach" }, value = tostring(def.reach), order = 101 },
  }
  if def.has_area then
    fields[#fields + 1] = { name = { "pc.tt-area" }, value = def.area .. "x" .. def.area, order = 102 }
  else
    fields[#fields + 1] = { name = { "pc.tt-area" }, value = { "pc.none" }, order = 102 }
  end
  if def.class ~= "pylon" then
    fields[#fields + 1] = {
      name = { "pc.tt-cap" }, value = tostring(shared.cap(def.class, def.tier)), order = 103,
    }
  end
  return fields
end

local poles = {}
for _, def in ipairs(shared.POLES) do
  local fam = shared.FAMILY_BY_ID[def.family]
  local base = data.raw["electric-pole"][fam.base]
  if not base then
    error("pole-classes: base pole prototype '" .. fam.base .. "' is missing")
  end
  local base_item = data.raw.item[fam.base]
  local tint = tier_tint(fam.color, def.tier)

  local ent = util.table.deepcopy(base)
  ent.name = def.name
  ent.localised_name = { "pc.pole-name", { "pc.family-" .. def.family }, tostring(def.tier) }
  ent.localised_description = { "pc.desc-" .. def.class }
  ent.minable = { mining_time = (base.minable and base.minable.mining_time) or 0.1, result = def.name }
  ent.placeable_by = nil
  ent.fast_replaceable_group = "pc-" .. def.family
  ent.next_upgrade = (def.tier < shared.TIER_COUNT) and shared.name(def.family, def.tier + 1) or nil
  ent.maximum_wire_distance = def.reach
  ent.supply_area_distance = def.distance
  ent.auto_connect_up_to_n_wires = 0
  ent.rewire_neighbours_when_destroying = false
  ent.track_coverage_during_drag_building = false
  ent.icon, ent.icon_size, ent.icons = nil, nil, tinted_icons(base_item or base, tint, def.family)
  ent.custom_tooltip_fields = tooltip_fields(def)
  ent.hidden = nil
  if def.family == "pylon" then
    -- 2x2 tower with its own sprite, shadow and wire points.
    ent.collision_box = util.table.deepcopy(PylonArt.collision_box)
    ent.selection_box = util.table.deepcopy(PylonArt.selection_box)
    ent.drawing_box_vertical_extension = PylonArt.drawing_box_vertical_extension
    ent.pictures = util.table.deepcopy(PylonArt.pictures)
    ent.connection_points = util.table.deepcopy(PylonArt.connection_points)
    ent.water_reflection = util.table.deepcopy(PylonArt.water_reflection)
    tint = PylonArt.tint(tint)
  end
  tint_sprites(ent.pictures, tint)
  poles[#poles + 1] = ent
end
data:extend(poles)

return M
