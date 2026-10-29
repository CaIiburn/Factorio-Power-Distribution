-- technologies.lua
-- One tech per tier, unlocks the transformer of that tier (step-up / step-down and the size are chosen in the GUI).

local technologies = {}

-- Science pack progression gate per tier — adjust to match your mod's pacing.
local tier_science_packs = {
  { {"automation-science-pack", 1} },
  { {"automation-science-pack", 1}, {"logistic-science-pack", 1} },
  { {"automation-science-pack", 1}, {"logistic-science-pack", 1}, {"chemical-science-pack", 1} },
  { {"automation-science-pack", 1}, {"logistic-science-pack", 1},
    {"chemical-science-pack", 1}, {"utility-science-pack", 1} },
  { {"automation-science-pack", 1}, {"logistic-science-pack", 1},
    {"chemical-science-pack", 1}, {"utility-science-pack", 1}, {"space-science-pack", 1} },
  { {"automation-science-pack", 1}, {"logistic-science-pack", 1},
    {"chemical-science-pack", 1}, {"utility-science-pack", 1},
    {"space-science-pack", 1}, {"production-science-pack", 1} },
}

-- Research cost scaling per tier (count + time), sub-linear like recipe costs.
local tier_research_count = { 50, 150, 400, 800, 1500, 3000 }
local tier_research_time  = { 15, 20, 30, 45, 60, 60 }

function technologies.generate(C)
  local out = {}

  local first_heat_tier = math.huge
  for tier in pairs(C.heat.tiers) do first_heat_tier = math.min(first_heat_tier, tier) end

  for tier = 1, #C.tiers do
    local tech_name = "pt-transformer-t" .. tier

    local unlocks = {}
    table.insert(unlocks, { type = "unlock-recipe", recipe = C.item_name(tier) })

    -- The radiator comes with the first tier that has heat.
    if tier == first_heat_tier then
      unlocks[#unlocks + 1] = { type = "unlock-recipe", recipe = C.radiator.name }
    end

    out[#out + 1] = {
      type = "technology",
      name = tech_name,
      icon = "__pylon-transformers__/graphics/technology/pt-tier-" .. tier .. ".png",
      icon_size = 128,
      prerequisites = (tier > 1) and { "pt-transformer-t" .. (tier - 1) } or { "electronics" },
      unit = {
        count = tier_research_count[tier],
        ingredients = tier_science_packs[tier],
        time = tier_research_time[tier],
      },
      effects = unlocks,
      order = "pt-transformer-t" .. tier,
    }
  end

  return out
end

return technologies