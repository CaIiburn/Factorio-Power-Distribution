-- Categories, subgroups and fluids.
local D = require("shared.defs")
local U = require("prototypes.ipp-helpers")

local cats = {
  "ipp-condensing", "ipp-venting", "ipp-gas-conditioning", "ipp-heat-recovery",
  -- tier 3
  "ipp-steam-generation", "ipp-surface-condensing", "ipp-evaporative-cooling", "ipp-dry-cooling", "ipp-fuel-cooling",
  "ipp-reprocessing", "ipp-vitrification",
}
for _, c in ipairs(cats) do data:extend { { type = "recipe-category", name = c } } end

data:extend {
  { type = "item-subgroup", name = "ipp-components",      group = "intermediate-products", order = "z-a" },
  { type = "item-subgroup", name = "ipp-process",         group = "intermediate-products", order = "z-c" },
  { type = "item-subgroup", name = "ipp-power-buildings", group = "production",            order = "z-a" },
  { type = "item-subgroup", name = "ipp-fluids",          group = "fluids",                order = "z-a" },
  { type = "item-subgroup", name = "ipp-fuel-cycle",      group = "intermediate-products", order = "z-b" },
  -- Tier 3: assemblies burn in the reactor core only (vanilla fuel cells are not "ipp-fuel-assembly" fuel)
  { type = "fuel-category", name = "ipp-fuel-assembly" },
}

-- Control-rod signals read by the reactor core (see scripts/reactors.lua).
data:extend {
  { type = "virtual-signal", name = D.SIGNAL_ROD,
    icons = { { icon = "__base__/graphics/icons/uranium-fuel-cell.png", icon_size = 64, tint = U.color(0.7, 0.9, 1.0) } },
    subgroup = "virtual-signal-special", order = "z[ipp]-a[rod-withdrawal]" },
  { type = "virtual-signal", name = D.SIGNAL_SCRAM,
    icons = { { icon = "__base__/graphics/icons/uranium-fuel-cell.png", icon_size = 64, tint = U.color(1.0, 0.35, 0.3) } },
    subgroup = "virtual-signal-special", order = "z[ipp]-b[scram]" },
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

-- Tier 3 fluids. The two primary-water fluids carry heat as temperature: the circulation unit heats cool primary
-- water from 15 degC to config primary_unit.target_c (1 kJ per unit per degC, so one unit of hot water holds
-- target-15 kJ). Nothing else ever stamps a temperature, and the hot fluid only travels between the circulation
-- unit's output and the steam generator's input, which take any temperature.
fluid("ipp-primary-water",     "water",         U.color(0.55, 0.85, 1.00), "f", { heat_capacity = "1kJ" })
fluid("ipp-primary-water-hot", "water",         U.color(1.00, 0.55, 0.45), "g", { heat_capacity = "1kJ",
  max_temperature = D.config.primary_unit.hot_fluid_max_c })
fluid("ipp-hp-steam",          "steam",         U.color(0.80, 0.90, 1.00), "h", { fuel_value = D.HP_STEAM_KJ .. "kJ",
  localised_description = { "fluid-description.ipp-hp-steam", D.fmt(D.HP_STEAM_KJ) } })
fluid("ipp-cooling-water",      "water",        U.color(0.35, 0.75, 0.95), "i")
fluid("ipp-cooling-water-warm", "water",        U.color(0.95, 0.75, 0.40), "j")
fluid("ipp-solvent",            "light-oil",    U.color(0.80, 0.95, 0.55), "k")
