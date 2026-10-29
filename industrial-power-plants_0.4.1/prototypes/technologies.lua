local U = require("prototypes.ipp-helpers")
local D = require("shared.defs")
local R = D.config.research

local function unlock(list)
  local e = {}
  for _, r in ipairs(list) do e[#e + 1] = { type = "unlock-recipe", recipe = r } end
  return e
end

data:extend {
  {
    type = "technology", name = "ipp-industrial-steam-power",
    icons = U.tech_icons("steel-processing", U.color(1.0, 0.8, 0.7)),
    prerequisites = { "steel-processing", "logistic-science-pack" },
    effects = unlock {
      "ipp-structural-frame", "ipp-electric-motor", "ipp-generator-winding", "ipp-turbine-rotor",
      "ipp-heat-exchanger-panel", "ipp-refractory-lining",
      "ipp-air-condenser", "ipp-exhaust-stack",
      "ipp-condensation", "ipp-vent-exhaust-steam",
    },
    unit = { count = R.industrial_steam_power.count, time = R.industrial_steam_power.time,
             ingredients = { { "automation-science-pack", 1 }, { "logistic-science-pack", 1 } } },
    order = "e-p-a",
  },
  {
    type = "technology", name = "ipp-combined-cycle-power",
    icons = U.tech_icons("oil-processing", U.color(0.8, 1.0, 0.8)),
    prerequisites = { "ipp-industrial-steam-power", "chemical-science-pack", "oil-processing", "plastics" },
    effects = unlock {
      "ipp-pump-assembly", "ipp-heat-resistant-alloy", "ipp-pressure-vessel", "ipp-seal-pack",
      "ipp-control-cabinet", "ipp-high-speed-rotor",
      "ipp-fuel-gas-conditioner", "ipp-gas-turbine-generator", "ipp-heat-recovery-steam-generator",
      "ipp-large-steam-turbine-generator",
      "ipp-fuel-gas-conditioning", "ipp-heat-recovery",
      "ipp-vent-flue-gas", "ipp-vent-hot-exhaust",
    },
    unit = { count = R.combined_cycle_power.count, time = R.combined_cycle_power.time, ingredients = {
      { "automation-science-pack", 1 }, { "logistic-science-pack", 1 }, { "chemical-science-pack", 1 } } },
    order = "e-p-b",
  },
  {
    type = "technology", name = "ipp-pressurized-water-power",
    icons = U.tech_icons("nuclear-power", U.color(0.75, 0.88, 1.0)),
    prerequisites = { "ipp-combined-cycle-power", "ipp-startup-energy-storage", "nuclear-power" },
    effects = unlock {
      "ipp-nuclear-shielding", "ipp-control-rod-assembly", "ipp-radhard-controller", "ipp-reinforced-pipe",
      "ipp-fuel-cladding", "ipp-fuel-assembly",
      D.REACTOR, "ipp-primary-circulation-unit", "ipp-nuclear-steam-generator", "ipp-hp-turbine-generator",
      "ipp-surface-condenser", "ipp-cooling-tower", "ipp-dry-cooler", "ipp-spent-fuel-pool", "ipp-dry-cask-storage",
      "ipp-nuclear-steam-generation", "ipp-surface-condensation", "ipp-cooling-tower-cycle", "ipp-dry-cooler-cycle",
      "ipp-spent-fuel-cooling",
    },
    unit = { count = R.pressurized_water_power.count, time = R.pressurized_water_power.time, ingredients = {
      { "automation-science-pack", 1 }, { "logistic-science-pack", 1 }, { "chemical-science-pack", 1 } } },
    order = "e-p-d",
  },
  {
    type = "technology", name = "ipp-nuclear-reprocessing",
    icons = U.tech_icons("nuclear-fuel-reprocessing", U.color(0.85, 1.0, 0.7)),
    prerequisites = { "ipp-pressurized-water-power", "sulfur-processing" },
    effects = unlock {
      "ipp-chemical-resistant-pipe", "ipp-heating-element", "ipp-glass-frit", "ipp-solvent",
      "ipp-reprocessing-plant", "ipp-waste-vitrifier", "ipp-spent-fuel-reprocessing", "ipp-vitrification",
    },
    unit = { count = R.nuclear_reprocessing.count, time = R.nuclear_reprocessing.time, ingredients = {
      { "automation-science-pack", 1 }, { "logistic-science-pack", 1 }, { "chemical-science-pack", 1 } } },
    order = "e-p-e",
  },
  {
    type = "technology", name = "ipp-startup-energy-storage",
    icons = U.tech_icons("battery", U.color(0.8, 0.9, 1.0)),
    prerequisites = { "ipp-industrial-steam-power", "battery" },
    effects = unlock { "ipp-startup-bank" },
    unit = { count = R.startup_energy_storage.count, time = R.startup_energy_storage.time,
             ingredients = { { "automation-science-pack", 1 }, { "logistic-science-pack", 1 } } },
    order = "e-p-c",
  },
}

-- Tier 3 replaces the vanilla nuclear branch instead of sitting beside a simpler bypass: the vanilla "Nuclear power"
-- research keeps its fuel cells and heat pipes (the new plant needs them) but no longer unlocks the vanilla reactor,
-- heat exchanger or steam turbine. Switch it off with config replace_vanilla_nuclear = false.
if D.config.replace_vanilla_nuclear then
  local t = data.raw.technology["nuclear-power"]
  if t and t.effects then
    local drop = { ["nuclear-reactor"] = true, ["heat-exchanger"] = true, ["steam-turbine"] = true }
    local kept = {}
    for _, e in ipairs(t.effects) do
      if not (e.type == "unlock-recipe" and drop[e.recipe]) then kept[#kept + 1] = e end
    end
    t.effects = kept
  end
end
