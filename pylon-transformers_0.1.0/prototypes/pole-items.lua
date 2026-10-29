local shared = require("__pylon-transformers__.config").pole
local util = require("util")
local poles = require("__pylon-transformers__.prototypes.poles")

-- Ingredients per tier for a family multiplier of 1.
-- Entries whose item does not exist (modded-out) are skipped.
local TIER_COST = {
  { { "iron-plate", 2 }, { "copper-cable", 2 }, { "iron-stick", 2 } },
  { { "steel-plate", 2 }, { "copper-cable", 4 }, { "electronic-circuit", 1 } },
  { { "steel-plate", 3 }, { "copper-plate", 4 }, { "electronic-circuit", 3 } },
  { { "steel-plate", 5 }, { "copper-plate", 6 }, { "advanced-circuit", 3 } },
  { { "steel-plate", 8 }, { "copper-plate", 8 }, { "processing-unit", 3 } },
  { { "low-density-structure", 4 }, { "steel-plate", 10 }, { "processing-unit", 6 } },
}
-- 2x2 families cost double.
local FAMILY_MULTIPLIER = {
  ["feeder"] = 2, ["pylon"] = 1, ["distribution-large"] = 2,
  ["distribution-small"] = 1, ["aux"] = 1,
}

local item_exists = require("__pylon-transformers__.prototypes.item-exists")

local items, recipes = {}, {}
for _, def in ipairs(shared.POLES) do
  local fam = shared.FAMILY_BY_ID[def.family]
  local base_item = data.raw.item[fam.base]
  local tint = poles.tier_tint(fam.color, def.tier)

  items[#items + 1] = {
    type = "item",
    name = def.name,
    localised_name = { "pc.pole-name", { "pc.family-" .. def.family }, tostring(def.tier) },
    localised_description = { "pc.desc-" .. def.class },
    icons = poles.tinted_icons(base_item, tint, def.family),
    subgroup = "energy-pipe-distribution",
    order = string.format("z[pole-classes]-%s%d", fam.order, def.tier),
    place_result = def.name,
    stack_size = fam.stack,
  }

  local ingredients = {}
  for _, entry in ipairs(TIER_COST[def.tier]) do
    if item_exists(entry[1]) then
      ingredients[#ingredients + 1] = {
        type = "item", name = entry[1],
        amount = entry[2] * FAMILY_MULTIPLIER[def.family],
      }
    end
  end
  if #ingredients == 0 then
    ingredients[1] = { type = "item", name = "iron-plate", amount = 2 * FAMILY_MULTIPLIER[def.family] }
  end

  recipes[#recipes + 1] = {
    type = "recipe",
    name = def.name,
    enabled = false,
    energy_required = 0.5,
    ingredients = ingredients,
    results = { { type = "item", name = def.name, amount = 1 } },
  }
end
data:extend(items)
data:extend(recipes)
