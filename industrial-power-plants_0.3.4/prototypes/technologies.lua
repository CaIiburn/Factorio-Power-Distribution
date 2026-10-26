local U = require("prototypes.ipp-helpers")

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
      "ipp-coal-mill", "ipp-industrial-boiler", "ipp-steam-turbine-generator", "ipp-air-condenser",
      "ipp-exhaust-stack", "ipp-waste-compactor",
      "ipp-coal-charge", "ipp-ash-compaction", "ipp-boiler-cycle", 
      "ipp-condensation", "ipp-vent-exhaust-steam", "ipp-ash-concrete",
    },
    unit = { count = 150, time = 30, ingredients = { { "automation-science-pack", 1 }, { "logistic-science-pack", 1 } } },
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
    unit = { count = 300, time = 30, ingredients = {
      { "automation-science-pack", 1 }, { "logistic-science-pack", 1 }, { "chemical-science-pack", 1 } } },
    order = "e-p-b",
  },
  {
    type = "technology", name = "ipp-startup-energy-storage",
    icons = U.tech_icons("battery", U.color(0.8, 0.9, 1.0)),
    prerequisites = { "ipp-industrial-steam-power", "battery" },
    effects = unlock { "ipp-startup-bank" },
    unit = { count = 150, time = 30, ingredients = { { "automation-science-pack", 1 }, { "logistic-science-pack", 1 } } },
    order = "e-p-c",
  },
}
