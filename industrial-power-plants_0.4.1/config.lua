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
--
-- Tier 3 (pressurized-water nuclear) balance rules, also checked at load time:
--   * fuel_assembly.energy_gj              should equal fuel_assembly.cells x 8 GJ (vanilla uranium fuel cell)
--   * primary_unit.flow_per_second         (derived) should equal steam_generator.hot_primary_per_second
--   * steam_generator.cool_primary_per_second should equal steam_generator.hot_primary_per_second (closed loop)
--   * steam generator steam energy         may not exceed the heat it takes from the primary loop
--   * steam_generator.steam_per_second     should equal turbines.hp.fluid_per_second
--   * surface_condenser.exhaust_steam_per_second should equal turbines.hp.fluid_per_second
local C = {}

-- Tier 3 replaces the vanilla nuclear branch: when true the vanilla "Nuclear power" research stops unlocking the
-- vanilla nuclear reactor, heat exchanger and steam turbine (fuel cells and heat pipes stay, the new plant needs
-- them). Space Age's own Aquilo research still unlocks heat exchanger and steam turbine for its heating use.
C.replace_vanilla_nuclear = true

--------------------------------------------------------------------------------------------------
-- Fluid energy content. Both fluids are consumed by the turbines as FUEL, so the value is the
-- energy released by burning one unit.
--------------------------------------------------------------------------------------------------
C.fluids = {
  industrial_steam_kj = 50,    -- kJ per unit of industrial steam
  fuel_gas_mj         = 1,     -- MJ per unit of pressurised fuel gas
  hp_steam_kj         = 90,    -- kJ per unit of high-pressure steam (already net of the thermal cycle's losses)
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
  large_steam = { fluid_per_second = 500, effectivity = 1, output_limit_mw = nil, health = 1800, size_multiplier = 3 },
  gas         = { fluid_per_second = 100,  effectivity = 0.5,  output_limit_mw = nil, health = 1800, size_multiplier = 3 },
  -- Tier 3 high-pressure turbine train: 500 x 90 kJ x 1.0 = 45 MW
  hp          = { fluid_per_second = 500, effectivity = 1,    output_limit_mw = nil, health = 2200, size_multiplier = 3 },
}

--------------------------------------------------------------------------------------------------
-- Fuel-gas conditioner (compressor train, chemical-stager art). Needs grid power, so keep a startup bank.
--   size : square footprint in tiles, odd number >= 1 (default 5). Pipes sit in the middle of the north/south faces.
--   power_mw            : electric draw while working
--   idle_drain_kw       : electric draw while idle
--   pollution_per_minute: emissions while working (stands in for the plant's combustion pollution)
--------------------------------------------------------------------------------------------------
C.conditioner = {
  petroleum_gas_per_second = 100,
  fuel_gas_per_second      = 100,
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
  hot_exhaust_per_second = 100,
  water_per_second       = 500,
  steam_per_second       = 500,
  flue_gas_per_second    = 100,
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
  exhaust_steam_per_second = 300,
  water_per_second         = 250,
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
-- TIER 3: pressurized-water nuclear power
--------------------------------------------------------------------------------------------------

-- Fuel assembly: burnt in the reactor core (own fuel category, vanilla fuel cells are NOT accepted directly).
--   energy_gj : fuel value of one assembly
--   cells     : vanilla uranium fuel cells in the recipe (a cell is worth 8 GJ)
--   claddings : fuel-cladding items in the recipe
C.fuel_assembly = { energy_gj = 40, cells = 5, claddings = 4 }

--------------------------------------------------------------------------------------------------
-- Pressurized-water reactor core (vanilla reactor prototype: native heat buffer, temperature, neighbour
-- bonus, circuit connector, fuel and burnt-fuel slots, meltdown explosion). 5 x 5 tiles, fixed.
--   power_mw         : heat output at 100 % rod withdrawal, before the neighbour bonus
--   neighbour_bonus  : bonus per adjacent core, as in the base game (2 neighbours = x3 output)
--   specific_heat_mj : thermal mass in MJ per degC. The reaction window after cooling is lost is
--                      specific_heat x (meltdown_temperature - operating temperature) / surplus power
--   max_temperature_c: heat buffer limit
--   fuel_slots / spent_slots : inventory slots (fuel in, hot spent assemblies out)
--
-- Control rods (script, scripts/reactors.lua). The core reads two virtual signals from its circuit connector:
--   ipp-rod-withdrawal (0..100 %)  how far the rods are pulled out. 0 = fully inserted = no fission.
--   ipp-scram          (any non-zero) drops the rods at scram speed.
-- An unwired core, or one whose wires were cut, SCRAMs by itself (fail-safe). Rods move at limited speed.
-- Fission power = withdrawal^rod_exponent x power x (1 + neighbour bonus). The core is switched on and off
-- every tick in the right proportion to get that average, so fuel burn follows the rods too.
--
-- Decay heat: after power drops, a fraction of the previous power keeps heating the core and dies away slowly.
--   decay_fraction : share of full power that stays as afterheat
--   decay_rise_s / decay_fall_s : time constants for it building up / dying away
--
-- Meltdown: the core explodes (vanilla reactor explosion) when its temperature stays at or above
-- meltdown_temperature_c for meltdown_grace_s seconds, or reaches max_temperature_c at once. That is what
-- happens when it makes more heat than the steam side takes away. warning_temperature_c raises an alert.
--------------------------------------------------------------------------------------------------
C.reactor = {
  power_mw                 = 120,
  neighbour_bonus          = 1,
  specific_heat_mj         = 20,
  max_temperature_c        = 1050,
  health                   = 1500,
  fuel_slots               = 1,
  spent_slots              = 1,
  rod_speed_pct_per_second   = 1,
  scram_speed_pct_per_second = 25,
  rod_exponent             = 1,
  decay_fraction           = 0.2,
  decay_rise_s             = 60,
  decay_fall_s             = 600,
  warning_temperature_c    = 800,
  meltdown_temperature_c   = 1000,
  meltdown_grace_s         = 5,
}

--------------------------------------------------------------------------------------------------
-- Primary circulation / pressurizer unit: heat-coupled to the core (native heat connection), moves cool
-- primary water through the core's heat and returns hot primary water. Vanilla heat-exchanger prototype.
-- Each unit takes up to power_mw out of the core. Put as many next to a core (or on heat pipes) as the
-- core's output needs.
--   target_c            : temperature the hot primary water leaves at
--   min_working_c       : the unit only draws heat while the core is above this temperature
--   hot_fluid_max_c     : maximum temperature of the hot fluid (>= target_c)
-- Derived: units per second = power / (heat capacity 1 kJ x (target - 15 degC)) = 120 MW / 300 kJ = 400 /s.
--------------------------------------------------------------------------------------------------
C.primary_unit = {
  power_mw      = 120,
  target_c      = 315,
  min_working_c = 350,
  hot_fluid_max_c = 400,
  health        = 600,
}

--------------------------------------------------------------------------------------------------
-- Nuclear steam generator: hot primary water + feedwater -> high-pressure steam + cool primary water.
-- Needs grid power for its feed pumps: without power the primary loop stops circulating and the core
-- loses its cooling (keep a startup bank).
--   size : square footprint in tiles, odd number >= 3 (default 5). Two pipes per face.
--------------------------------------------------------------------------------------------------
C.steam_generator = {
  hot_primary_per_second  = 400,
  cool_primary_per_second = 400,
  water_per_second        = 500,
  steam_per_second        = 500,
  power_mw                = 2,
  idle_drain_kw           = 50,
  health                  = 800,
  size                    = 5,
}

--------------------------------------------------------------------------------------------------
-- Surface condenser: exhaust steam + cool cooling water -> feedwater (water) + warm cooling water.
--   size : odd number >= 3 (default 5)
--------------------------------------------------------------------------------------------------
C.surface_condenser = {
  exhaust_steam_per_second  = 500,
  cooling_water_per_second  = 300,
  water_per_second          = 500,
  power_kw                  = 500,
  idle_drain_kw             = 20,
  health                    = 800,
  size                      = 5,
}

--------------------------------------------------------------------------------------------------
-- Heat rejection: the cooling tower evaporates a little water (makeup) but moves a lot of cooling water;
-- the dry cooler needs no water but moves less and draws much more power.
--   size : odd number >= 3 (default 5)
--------------------------------------------------------------------------------------------------
C.cooling_tower = {
  warm_per_second   = 600,
  makeup_per_second = 12,
  power_kw          = 1000,
  idle_drain_kw     = 30,
  health            = 800,
  size              = 5,
}
C.dry_cooler = {
  warm_per_second = 300,
  power_mw        = 6,
  idle_drain_kw   = 50,
  health          = 800,
  size            = 5,
}

--------------------------------------------------------------------------------------------------
-- Spent-fuel cooling pool: one hot spent assembly + water -> one cooled spent assembly, after a FIXED time.
--   size : odd number >= 3 (default 5)
--------------------------------------------------------------------------------------------------
C.spent_fuel_pool = {
  cooling_time_s = 120,
  water_per_assembly = 100,
  power_kw       = 300,
  idle_drain_kw  = 10,
  health         = 1200,
  size           = 5,
}

--------------------------------------------------------------------------------------------------
-- Dry-cask storage: a big passive container (store cooled spent assemblies or vitrified waste).
--   size : whole number >= 1 (default 3)
--------------------------------------------------------------------------------------------------
C.dry_cask = { inventory_slots = 48, health = 1500, size = 3 }

--------------------------------------------------------------------------------------------------
-- Nuclear reprocessing plant (optional): cooled spent assembly + sulfuric acid + solvent
--   -> uranium-238 + uranium-235 (chance) + plutonium-bearing material + radioactive residue.
--   uranium_235_chance : probability of recovering the one uranium-235 (a vanilla fuel cell consumes 0.1 each,
--                        so 5 cells = 0.5 burnt; the default chance gives back 0.4 on average)
--   size : odd number >= 3 (default 5)
--------------------------------------------------------------------------------------------------
C.reprocessing = {
  time_s = 60,
  acid = 100, solvent = 50,
  uranium_238 = 8, uranium_235 = 1, uranium_235_chance = 0.4,
  plutonium = 2, residue = 4,
  power_mw = 8, idle_drain_kw = 100, health = 1200, size = 5,
}

--------------------------------------------------------------------------------------------------
-- Waste vitrifier: radioactive residue + glass frit -> vitrified waste canister.
--   size : odd number >= 3 (default 3)
--------------------------------------------------------------------------------------------------
C.vitrifier = {
  time_s = 20,
  residue = 4, frit = 2,
  power_mw = 5, idle_drain_kw = 50, health = 800, size = 3,
}

--------------------------------------------------------------------------------------------------
-- Research cost: count x (time seconds per unit) x the packs listed in prototypes/technologies.lua.
--------------------------------------------------------------------------------------------------
C.research = {
  industrial_steam_power = { count = 150, time = 30 },
  combined_cycle_power   = { count = 300, time = 30 },
  startup_energy_storage = { count = 150, time = 30 },
  pressurized_water_power = { count = 500, time = 45 },
  nuclear_reprocessing    = { count = 300, time = 45 },
}

return C
