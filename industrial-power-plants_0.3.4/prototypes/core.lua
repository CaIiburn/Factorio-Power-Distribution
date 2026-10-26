-- Categories, subgroups and fluids.
local D = require("shared.defs")
local U = require("prototypes.ipp-helpers")

local cats = {
  "ipp-condensing", "ipp-venting", "ipp-gas-conditioning", "ipp-heat-recovery",
}
for _, c in ipairs(cats) do data:extend { { type = "recipe-category", name = c } } end

data:extend {
  { type = "item-subgroup", name = "ipp-components",      group = "intermediate-products", order = "z-a" },
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
-- Consumed by turbine-generators as fuel (burns_fluid); energy per unit comes from config.lua
fluid("ipp-industrial-steam", "steam",         U.color(0.90, 0.90, 1.00), "a", { fuel_value = D.STEAM_KJ .. "kJ",
  localised_description = { "fluid-description.ipp-industrial-steam", D.fmt(D.STEAM_KJ) } })
fluid("ipp-exhaust-steam",    "steam",         U.color(0.65, 0.70, 0.80), "b")
fluid("ipp-fuel-gas",         "petroleum-gas", U.color(0.85, 0.95, 0.60), "c", { fuel_value = D.FUEL_GAS_MJ .. "MJ",
  localised_description = { "fluid-description.ipp-fuel-gas", D.fmt(D.FUEL_GAS_MJ) } })
fluid("ipp-hot-exhaust",      "petroleum-gas", U.color(1.00, 0.55, 0.30), "d")
fluid("ipp-flue-gas",         "petroleum-gas", U.color(0.55, 0.55, 0.55), "e")
