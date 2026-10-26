-- Shared balance constants. Pure data (no stage-specific globals).
--
-- Energy conventions (see docs/ENERGY_ACCOUNTING.md):
--   * Industrial steam and pressurised fuel gas are consumed by the turbines as FUEL: every generator uses
--     burns_fluid = true, so output = units x fuel_value x effectivity and never depends on fluid temperature.
--     (A temperature-based generator needs steam at a specific temperature, which locks fluid boxes and
--     blocks pipe connections under 2.1's fluid-mixing rules - do not stamp temperatures on recipes.)
--   * Industrial steam: fuel_value 50 kJ per unit.  Fuel gas: fuel_value 1 MJ per unit.
--   * A graded coal charge is exactly the energy of the coal it is made from (8 x 4 MJ = 32 MJ).
local D = {}

D.STEAM_KJ            = 50
D.FUEL_GAS_MJ         = 1
D.COAL_MJ             = 4
D.CHARGE_COAL         = 8
D.CHARGE_MJ           = D.COAL_MJ * D.CHARGE_COAL                   -- 32

-- Native turbine-generators (fusion-generator prototype).
--   per_second  : fluid units consumed per second at full load (= max_fluid_usage x 60)
--   effectivity : fraction of the input fluid's energy delivered as electricity
--   flow_mw     : electric output limit (just above full-load output)
--   scale       : footprint multiplier on the vanilla fusion generator (integer keeps tile alignment)
D.generators = {
  ["ipp-steam-turbine-generator"] = {
    input = "ipp-industrial-steam", output = "ipp-exhaust-steam",
    per_second = 132, effectivity = 0.985, burns = true, flow_mw = 6.6,
    scale = 2,
    tint = { r = 0.65, g = 0.78, b = 1.00 }, order = "c",
  },
  ["ipp-large-steam-turbine-generator"] = {
    input = "ipp-industrial-steam", output = "ipp-exhaust-steam",
    per_second = 450, effectivity = 0.985, burns = true, flow_mw = 22.2,
    scale = 3,
    tint = { r = 0.55, g = 0.65, b = 0.95 }, order = "j",
  },
  ["ipp-gas-turbine-generator"] = {
    input = "ipp-fuel-gas", output = "ipp-hot-exhaust",
    per_second = 84, effectivity = 0.54, burns = true, flow_mw = 45.4,
    scale = 3,
    tint = { r = 0.80, g = 0.90, b = 0.70 }, order = "h",
  },
}

-- Exhaust stack venting list. Single source of truth: vent recipes are generated from `allowed`, the
-- stack script reads both tables, and docs/VENTING.md mirrors them.
--   allowed : fluid -> { recipe, rate (units/s) }
--   denied  : fluid -> reason code (valuable | fuel | hazard); anything not listed is refused as "unlisted"
D.STACK = "ipp-exhaust-stack"
D.vent = {
  allowed = {
    ["ipp-exhaust-steam"] = { recipe = "ipp-vent-exhaust-steam", rate = 500 },
    ["ipp-flue-gas"]      = { recipe = "ipp-vent-flue-gas",      rate = 200 },
    ["ipp-hot-exhaust"]   = { recipe = "ipp-vent-hot-exhaust",   rate = 200 },
  },
  denied = {
    ["ipp-industrial-steam"] = "valuable",  -- send it to a turbine
    ["steam"]                = "valuable",
    ["water"]                = "valuable",
    ["ipp-fuel-gas"]         = "fuel",      -- burn it in a gas turbine
    ["petroleum-gas"]        = "fuel",
    ["light-oil"]            = "fuel",
    ["heavy-oil"]            = "fuel",
    ["crude-oil"]            = "fuel",
    ["lubricant"]            = "hazard",
    ["sulfuric-acid"]        = "hazard",
  },
}

return D
