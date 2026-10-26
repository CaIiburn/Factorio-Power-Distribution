-- Industrial Power Plants: tuning config.
--
-- Every number that decides how much a machine consumes, produces, stores or costs to research lives
-- here. Edit a value, restart Factorio (this file is read while the game loads; no migration needed).
-- Pure data, no game API: it is read by the data stage (prototypes) and by the control stage (vent list).
--
-- SIZES: every building has a size setting (see the SIZE section below). Sprites are bitmaps that get scaled, so
-- big changes from the default look blurry or oversized; the pipe connections always follow the new edges.
--
-- Units are written in the key name. "per_second" means fluid units per second at full load
-- (every process recipe takes exactly 1 s, so the amounts below are also the amounts per craft).
--
-- Balance rules the mod assumes (a warning is written to factorio-current.log when one is broken):
--   * conditioner.fuel_gas_per_second      should equal turbines.gas.fluid_per_second
--   * heat_recovery.hot_exhaust_per_second should equal turbines.gas.fluid_per_second
--   * heat_recovery.steam_per_second       should equal turbines.large_steam.fluid_per_second
--   * a heat-recovery generator may not return more steam energy than the hot exhaust still holds
-- Energy from a turbine = fluid_per_second x energy per unit x effectivity (see C.fluids).
local C = {}

--------------------------------------------------------------------------------------------------
-- Fluid energy content. Both fluids are consumed by the turbines as FUEL, so the value is the
-- energy released by burning one unit.
--------------------------------------------------------------------------------------------------
C.fluids = {
  industrial_steam_kj = 50,    -- kJ per unit of industrial steam
  fuel_gas_mj         = 1,     -- MJ per unit of pressurised fuel gas
}

--------------------------------------------------------------------------------------------------
-- Turbine-generators (fusion-generator entities).
--   fluid_per_second : input fluid burned per second at full load (also the output fluid returned)
--   effectivity      : share of the input energy delivered as electricity (max 1.0)
--   output_limit_mw  : electric output limit. Leave nil to get the full-load output rounded up to
--                      the next 0.1 MW. A value below full-load output throttles the turbine.
--   health           : hit points
--   size_multiplier  : whole number >= 1. Footprint = multiplier x the vanilla fusion generator (3 x 5 tiles):
--                      1 = 3x5, 2 = 6x10, 3 = 9x15 (default). Sprites, pipe ports and fluid volume scale with it.
-- Defaults: large steam 450 x 50 kJ x 0.985 = 22.2 MW,  gas 84 x 1 MJ x 0.54 = 45.4 MW.
--------------------------------------------------------------------------------------------------
C.turbines = {
  large_steam = { fluid_per_second = 450, effectivity = 0.985, output_limit_mw = nil, health = 1800, size_multiplier = 3 },
  gas         = { fluid_per_second = 84,  effectivity = 0.54,  output_limit_mw = nil, health = 1800, size_multiplier = 3 },
}

--------------------------------------------------------------------------------------------------
-- Fuel-gas conditioner (compressor train, chemical-stager art). Needs grid power, so keep a startup bank.
--   size : square footprint in tiles, odd number >= 1 (default 5). Pipes sit in the middle of the north/south faces.
--   power_mw            : electric draw while working
--   idle_drain_kw       : electric draw while idle
--   pollution_per_minute: emissions while working (stands in for the plant's combustion pollution)
--------------------------------------------------------------------------------------------------
C.conditioner = {
  petroleum_gas_per_second = 105,
  fuel_gas_per_second      = 84,
  power_mw                 = 4,
  idle_drain_kw            = 100,
  pollution_per_minute     = 600,
  health                   = 400,
  size                     = 5,
}

--------------------------------------------------------------------------------------------------
-- Heat-recovery steam generator: hot gas-turbine exhaust + water -> industrial steam + flue gas.
--   size : square footprint in tiles, odd number >= 3 (default 5). Two pipes per face, one tile either side of centre.
--------------------------------------------------------------------------------------------------
C.heat_recovery = {
  hot_exhaust_per_second = 84,
  water_per_second       = 450,
  steam_per_second       = 450,
  flue_gas_per_second    = 84,
  power_kw               = 500,
  idle_drain_kw          = 20,
  health                 = 400,
  size                   = 3,
}

--------------------------------------------------------------------------------------------------
-- Air-cooled condenser: exhaust steam -> water.
--   size : square footprint in tiles, odd number >= 1 (default 3).
--------------------------------------------------------------------------------------------------
C.condenser = {
  exhaust_steam_per_second = 270,
  water_per_second         = 260,
  power_kw                 = 250,
  idle_drain_kw            = 10,
  health                   = 400,
  size                     = 3,
}

--------------------------------------------------------------------------------------------------
-- Exhaust stack: venting rate per stack, in fluid units per second. Which fluids may be vented at
-- all is decided in shared/defs.lua (D.vent), because that is a rule rather than a number.
--   size : square footprint in tiles, odd number >= 1 (default 3). The inlet is in the middle of the north face.
--------------------------------------------------------------------------------------------------
C.stack = {
  health = 400,
  size   = 1,
  vent_per_second = {
    exhaust_steam = 500,
    flue_gas      = 200,
    hot_exhaust   = 200,
  },
}

--------------------------------------------------------------------------------------------------
-- Startup-energy bank (accumulator): black-start reserve.
--   size : square footprint in tiles, whole number >= 1 (default 3; the vanilla accumulator is 2x2).
--------------------------------------------------------------------------------------------------
C.startup_bank = {
  capacity_mj  = 200,
  charge_mw    = 5,     -- input flow limit
  discharge_mw = 20,    -- output flow limit
  health       = 500,
  size         = 3,
}

--------------------------------------------------------------------------------------------------
-- Research cost: count x (time seconds per unit) x the packs listed in prototypes/technologies.lua.
--------------------------------------------------------------------------------------------------
C.research = {
  industrial_steam_power = { count = 150, time = 30 },
  combined_cycle_power   = { count = 300, time = 30 },
  startup_energy_storage = { count = 150, time = 30 },
}

return C
