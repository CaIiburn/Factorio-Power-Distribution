local shared = require("shared")
local util = require("util")

-- One technology per tier. Tier 1 unlocks from the first copper cable craft so
-- that the very start of the game still has working poles.
local PACKS = {
  { "automation-science-pack" },
  { "automation-science-pack", "logistic-science-pack" },
  { "automation-science-pack", "logistic-science-pack", "chemical-science-pack" },
  { "automation-science-pack", "logistic-science-pack", "chemical-science-pack",
    "production-science-pack" },
  { "automation-science-pack", "logistic-science-pack", "chemical-science-pack",
    "production-science-pack", "utility-science-pack" },
  { "automation-science-pack", "logistic-science-pack", "chemical-science-pack",
    "production-science-pack", "utility-science-pack", "space-science-pack" },
}
local PREREQ_PACK_TECH = {
  nil, "logistic-science-pack", "chemical-science-pack", "production-science-pack",
  "utility-science-pack", "space-science-pack",
}
local COUNTS = { 0, 100, 200, 300, 400, 500 }

local ref = data.raw.technology["electric-energy-distribution-1"]
local ref_item = data.raw.item["medium-electric-pole"]
local function tech_icons()
  if ref and ref.icons then return util.table.deepcopy(ref.icons) end
  if ref and ref.icon then return { { icon = ref.icon, icon_size = ref.icon_size or 256 } } end
  if ref_item then return { { icon = ref_item.icon, icon_size = ref_item.icon_size or 64 } } end
end

local techs = {}
for tier = 1, shared.TIER_COUNT do
  local effects = {}
  for _, fam in ipairs(shared.FAMILIES) do
    effects[#effects + 1] = { type = "unlock-recipe", recipe = shared.name(fam.id, tier) }
  end

  local tech = {
    type = "technology",
    name = "pc-poles-" .. tier,
    localised_name = { "pc.tech-name", tostring(tier) },
    localised_description = { "pc.tech-desc", tostring(tier) },
    icons = tech_icons(),
    effects = effects,
    order = "c-e-z-" .. tier,
  }

  if tier == 1 then
    tech.research_trigger = { type = "craft-item", item = "copper-cable", count = 1 }
  else
    local prereq = { "pc-poles-" .. (tier - 1) }
    local pack_tech = PREREQ_PACK_TECH[tier]
    if pack_tech and data.raw.technology[pack_tech] then
      prereq[#prereq + 1] = pack_tech
    end
    local ingredients = {}
    for _, pack in ipairs(PACKS[tier]) do
      if data.raw.tool[pack] then ingredients[#ingredients + 1] = { pack, 1 } end
    end
    tech.prerequisites = prereq
    tech.unit = { count = COUNTS[tier], ingredients = ingredients, time = 30 }
  end
  techs[#techs + 1] = tech
end
data:extend(techs)
