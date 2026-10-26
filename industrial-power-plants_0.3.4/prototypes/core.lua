-- Categories, subgroups, fluids and fuel items.
local D = require("shared.defs")
local U = require("prototypes.ipp-helpers")

local cats = {
  "ipp-milling", "ipp-compacting", "ipp-boiling",
  "ipp-condensing", "ipp-venting", "ipp-gas-conditioning", "ipp-heat-recovery",
}
for _, c in ipairs(cats) do data:extend { { type = "recipe-category", name = c } } end

data:extend {
  { type = "fuel-category", name = "ipp-graded-coal" },
  { type = "item-subgroup", name = "ipp-components",      group = "intermediate-products", order = "z-a" },
  { type = "item-subgroup", name = "ipp-fuels",           group = "intermediate-products", order = "z-b" },
  { type = "item-subgroup", name = "ipp-process",         group = "intermediate-products", order = "z-c" },
  { type = "item-subgroup", name = "ipp-power-buildings", group = "production",            order = "z-a" },
  { type = "item-subgroup", name = "ipp-fluids",          group = "fluids",                order = "z-a" },
}

-- Working fluids. Fluid units are gameplay abstractions with documented energy content (defs.lua).
-- Every fluid stays at its default temperature: recipes never stamp a temperature, so all ports and pipes
-- can connect (2.1 fluid-mixing prevention locks a pipeline to the temperature of filtered boxes).
local function fluid(name, base, tint, order, extra)
  local f = {
    type = "fluid", name = name,
    icons = U.icons_of_fluid(base, tint),
    default_temperature = 15,
    base_color = tint, flow_color = tint,
    subgroup = "ipp-fluids", order = order,
    auto_barrel = false,   -- no barrelling of hot working fluids
  }
  for k, v in pairs(extra or {}) do f[k] = v end
  data:extend { f }
end
-- Consumed by turbine-generators as fuel (burns_fluid): 50 kJ per unit
fluid("ipp-industrial-steam", "steam",         U.color(0.90, 0.90, 1.00), "a", { fuel_value = D.STEAM_KJ .. "kJ" })
fluid("ipp-exhaust-steam",    "steam",         U.color(0.65, 0.70, 0.80), "b")
-- 1 MJ per unit
fluid("ipp-fuel-gas",         "petroleum-gas", U.color(0.85, 0.95, 0.60), "c", { fuel_value = D.FUEL_GAS_MJ .. "MJ" })
fluid("ipp-hot-exhaust",      "petroleum-gas", U.color(1.00, 0.55, 0.30), "d")
fluid("ipp-flue-gas",         "petroleum-gas", U.color(0.55, 0.55, 0.55), "e")

-- Fuel and residue items.
data:extend {
  {
    type = "item", name = "ipp-coal-charge",
    icons = U.icons_of_item("coal", U.color(0.75, 0.80, 1.0)),
    subgroup = "ipp-fuels", order = "a", stack_size = 50,
    fuel_category = "ipp-graded-coal",
    fuel_value = D.CHARGE_MJ .. "MJ",     -- = CHARGE_COAL x coal: a logistics form, not a multiplier
    burnt_result = "ipp-ash",
  },
  {
    type = "item", name = "ipp-ash",
    icons = U.icons_of_item("stone", U.color(0.45, 0.45, 0.45)),
    subgroup = "ipp-fuels", order = "b", stack_size = 100,
  },
  {
    type = "item", name = "ipp-ash-block",
    icons = U.icons_of_item("stone-brick", U.color(0.35, 0.35, 0.40)),
    subgroup = "ipp-fuels", order = "c", stack_size = 100,
  },
}
