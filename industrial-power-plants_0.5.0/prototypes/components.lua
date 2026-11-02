-- Intermediate components shared by all tiers (outline quantities, to be balanced in play-testing).
local U = require("prototypes.ipp-helpers")

-- name, icon source item, tint, time, {ingredients}, result count, optional categories
local list = {
  { "ipp-structural-frame",       "steel-chest",         {0.70,0.75,0.85}, 5, { {"item","steel-plate",8}, {"item","iron-gear-wheel",10} } },
  { "ipp-electric-motor",         "electric-engine-unit",{0.80,0.80,0.90}, 3, { {"item","iron-plate",4}, {"item","iron-gear-wheel",2}, {"item","copper-cable",10}, {"item","electronic-circuit",2} } },
  { "ipp-pump-assembly",          "pump",                {0.80,0.90,1.00}, 4, { {"item","pipe",6}, {"item","iron-gear-wheel",4}, {"item","ipp-electric-motor",1}, {"item","electronic-circuit",2} } },
  { "ipp-generator-winding",      "copper-cable",        {1.00,0.80,0.60}, 4, { {"item","copper-cable",40}, {"item","iron-plate",4}, {"item","stone-brick",2} } },
  { "ipp-turbine-rotor",          "iron-gear-wheel",     {0.75,0.80,0.95}, 4, { {"item","steel-plate",6}, {"item","iron-gear-wheel",8} } },
  { "ipp-heat-exchanger-panel",   "heat-pipe",           {1.00,0.85,0.70}, 4, { {"item","copper-plate",10}, {"item","pipe",10}, {"item","steel-plate",2} } },
  { "ipp-refractory-lining",      "stone-brick",         {1.00,0.70,0.55}, 3, { {"item","stone-brick",10}, {"item","steel-plate",2} } },
  { "ipp-heat-resistant-alloy",   "steel-plate",         {1.00,0.60,0.50}, 8, { {"item","steel-plate",6}, {"item","stone-brick",4}, {"item","sulfur",1} }, 2 },
  { "ipp-pressure-vessel",        "storage-tank",        {0.85,0.85,0.95}, 8, { {"item","steel-plate",20}, {"item","pipe",10}, {"item","ipp-heat-resistant-alloy",4} } },
  { "ipp-seal-pack",              "plastic-bar",         {0.70,0.70,0.75}, 4, { {"item","plastic-bar",10}, {"item","steel-plate",2}, {"fluid","lubricant",10} }, 1, {"crafting-with-fluid"} },
  { "ipp-control-cabinet",        "advanced-circuit",    {0.80,0.90,0.80}, 6, { {"item","electronic-circuit",10}, {"item","advanced-circuit",5}, {"item","copper-cable",20} } },
  { "ipp-high-speed-rotor",       "engine-unit",         {0.90,0.75,0.75}, 6, { {"item","ipp-turbine-rotor",1}, {"item","ipp-heat-resistant-alloy",4}, {"item","electronic-circuit",5} } },
  -- Tier 3 (nuclear). Researched with Pressurized-water nuclear power, except the two marked (reprocessing).
  { "ipp-nuclear-shielding",      "concrete",            {0.65,0.70,0.75}, 6, { {"item","concrete",10}, {"item","steel-plate",10}, {"item","ipp-heat-resistant-alloy",2} } },
  { "ipp-control-rod-assembly",   "steel-plate",         {0.60,0.75,1.00}, 8, { {"item","steel-plate",6}, {"item","ipp-heat-resistant-alloy",6}, {"item","electronic-circuit",4} } },
  { "ipp-radhard-controller",     "advanced-circuit",    {0.95,0.85,0.55}, 10, { {"item","ipp-control-cabinet",1}, {"item","advanced-circuit",10}, {"item","ipp-nuclear-shielding",1} } },
  { "ipp-reinforced-pipe",        "pipe",                {0.80,0.85,1.00}, 4, { {"item","pipe",10}, {"item","steel-plate",4}, {"item","ipp-heat-resistant-alloy",2} } },
  { "ipp-fuel-cladding",          "steel-plate",         {0.90,0.90,0.70}, 4, { {"item","steel-plate",2}, {"item","ipp-heat-resistant-alloy",2} } },
  { "ipp-chemical-resistant-pipe","pipe",                {0.70,1.00,0.70}, 4, { {"item","pipe",10}, {"item","plastic-bar",6}, {"item","steel-plate",2} } },
  { "ipp-heating-element",        "copper-cable",        {1.00,0.60,0.40}, 4, { {"item","copper-cable",20}, {"item","ipp-heat-resistant-alloy",2}, {"item","stone-brick",4} } },
  -- Tier 4 (fast breeder). Researched with Fast-breeder power, except the two marked (sodium).
  { "ipp-refractory-alloy",       "steel-plate",         {0.90,0.55,0.45}, 12, { {"item","ipp-heat-resistant-alloy",6}, {"item","ipp-refractory-lining",2}, {"item","sulfur",2} }, 2 },
  { "ipp-ceramic-seal",           "stone-brick",         {0.95,0.90,0.80}, 5, { {"item","stone-brick",8}, {"item","ipp-heat-resistant-alloy",1}, {"item","plastic-bar",2} } },
  { "ipp-precision-rotor",        "engine-unit",         {0.80,0.85,1.00}, 8, { {"item","ipp-high-speed-rotor",1}, {"item","ipp-heat-resistant-alloy",4}, {"item","processing-unit",2} } },
  { "ipp-refractory-rotor",       "engine-unit",         {1.00,0.70,0.55}, 10, { {"item","ipp-precision-rotor",1}, {"item","ipp-refractory-alloy",4} } },
  { "ipp-pressure-housing",       "storage-tank",        {0.95,0.80,0.75}, 10, { {"item","ipp-pressure-vessel",1}, {"item","ipp-refractory-alloy",4}, {"item","ipp-ceramic-seal",2} } },
  { "ipp-recuperator-matrix",     "heat-pipe",           {0.85,0.95,1.00}, 10, { {"item","ipp-heat-exchanger-panel",6}, {"item","ipp-refractory-alloy",3}, {"item","ipp-ceramic-seal",1} } },
  { "ipp-handling-machinery",     "electric-engine-unit",{0.85,0.85,0.60}, 10, { {"item","ipp-electric-motor",4}, {"item","processing-unit",4}, {"item","ipp-control-cabinet",1}, {"item","ipp-nuclear-shielding",1} } },
  -- Sodium research
  { "ipp-electrode-assembly",     "copper-cable",        {0.60,0.60,0.65}, 6, { {"item","coal",10}, {"item","steel-plate",4}, {"item","copper-cable",20} } },
  { "ipp-thermal-insulation",     "stone-brick",         {1.00,0.95,0.70}, 5, { {"item","stone-brick",10}, {"item","plastic-bar",4}, {"item","steel-plate",1} } },
}

for i, c in ipairs(list) do
  local name, base, tint, time, ings, count, cats = c[1], c[2], c[3], c[4], c[5], c[6] or 1, c[7]
  local order = string.format("%02d", i)
  data:extend {
    {
      type = "item", name = name, icons = U.icons_of_item(base, tint),
      subgroup = "ipp-components", order = order, stack_size = 50,
    },
    {
      type = "recipe", name = name, enabled = false, energy_required = time,
      categories = cats or { "crafting" },
      ingredients = U.stacks(ings),
      results = { { type = "item", name = name, amount = count } },
    },
  }
end
