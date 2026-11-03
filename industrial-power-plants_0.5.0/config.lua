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
--   * surface_condenser.water_per_second  should equal steam_generator.water_per_second (the secondary loop is closed;
--                                          it carries secondary water, not vanilla water)
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
  -- Tier 4 (supercritical CO2). Energies are measured from the compressor outlet (compressed CO2 = 0).
  sco2_hot_mj         = 1,     -- MJ per unit of hot CO2 (turbine fuel value): what the heater adds to a COLD feed
  sco2_recuperated_mj = 0.5,   -- MJ per unit of preheated CO2: what the recuperator has already added (must not exceed
                               -- the heat the turbine exhaust still holds, (1 - turbine effectivity) x sco2_hot_mj)
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
  hp          = { fluid_per_second = 375, effectivity = 1,    output_limit_mw = nil, health = 2200, size_multiplier = 3 },
  -- Tier 4 CO2 turbine-generator: 180 x 1 MJ x 0.4 = 72 MW. The 0.4 is the share of the HOT CO2's fuel value delivered as
  -- electricity per pass; with a recuperator the heater only has to add half of that fuel value (sco2_recuperated_mj), so the
  -- cycle turns 0.4 / 0.5 = 80 % of the sodium heat into electricity (40 % without a recuperator).
  sco2        = { fluid_per_second = 180, effectivity = 0.4,  output_limit_mw = nil, health = 2500, size_multiplier = 3 },
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
    co2           = 200,   -- Tier 4: surplus CO2 from the kiln
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
--   ipp-scram          (any non-zero) SCRAM: the rods are driven all the way in at scram speed, even if the signal
--                      is only a pulse, and cannot be withdrawn again for scram_lockout_s (counted from the trip). A
--                      scram signal that is still present when the lockout ends keeps the rods in.
-- An unwired core, or one whose wires were cut, drops its rods by itself (fail-safe, no lockout; a lockout that
-- is already running keeps running). Rods move at limited speed.
--   scram_lockout_s : seconds after a SCRAM before the rods may be withdrawn again (600 = 10 minutes). 0 = no
--                     waiting, but the rods still go all the way in.
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
  max_temperature_c        = 1550,
  health                   = 1500,
  fuel_slots               = 1,
  spent_slots              = 1,
  rod_speed_pct_per_second   = 1,
  scram_speed_pct_per_second = 25,
  scram_lockout_s          = 600,
  rod_exponent             = 1,
  decay_fraction           = 0.2,
  decay_rise_s             = 60,
  decay_fall_s             = 600,
  warning_temperature_c    = 1200,
  meltdown_temperature_c   = 1500,
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
  power_mw      = 36,
  target_c      = 315,
  min_working_c = 350,
  hot_fluid_max_c = 400,
  health        = 600,
}

--------------------------------------------------------------------------------------------------
-- Nuclear steam generator: hot primary water + secondary water -> high-pressure steam + cool primary water.
-- (water_per_second is the secondary-water intake; the middle loop runs on its own fluid, ipp-secondary-water.)
-- Needs grid power for its feed pumps: without power the primary loop stops circulating and the core
-- loses its cooling (keep a startup bank).
--   size : square footprint in tiles, odd number >= 3 (default 5). Two pipes per face.
--------------------------------------------------------------------------------------------------
C.steam_generator = {
  hot_primary_per_second  = 200,
  cool_primary_per_second = 200,
  water_per_second        = 250,
  steam_per_second        = 250,
  power_mw                = 1,
  idle_drain_kw           = 50,
  health                  = 800,
  size                    = 5,
}

--------------------------------------------------------------------------------------------------
-- Surface condenser: exhaust steam + cool cooling water -> secondary water + warm cooling water.
--   water_per_second is the secondary-water output.
--   size : odd number >= 3 (default 5)
--------------------------------------------------------------------------------------------------
C.surface_condenser = {
  exhaust_steam_per_second  = 250,
  cooling_water_per_second  = 150,
  water_per_second          = 250,
  power_kw                  = 250,
  idle_drain_kw             = 20,
  health                    = 800,
  size                      = 5,
}

--------------------------------------------------------------------------------------------------
-- Heat rejection: the cooling tower evaporates VANILLA water (makeup_per_second, 600 by default) while it moves the
-- cooling water, so a tower has to be built next to a water supply (one offshore pump gives 1200/s). The dry cooler
-- needs no water but moves less and draws much more power.
--   size : odd number >= 3 (default 5)
--------------------------------------------------------------------------------------------------
C.cooling_tower = {
  warm_per_second   = 600,
  makeup_per_second = 600,
  power_kw          = 1000,
  idle_drain_kw     = 30,
  health            = 800,
  size              = 9,
}
C.dry_cooler = {
  warm_per_second = 300,
  power_mw        = 6,
  idle_drain_kw   = 50,
  health          = 800,
  size            = 5,
}

--------------------------------------------------------------------------------------------------
-- Water treatment plant: turns vanilla water into the closed-loop fluids. The plant has three recipes, chosen
-- by hand in the machine: water -> primary water, water -> secondary water and water -> cooling water. The loops
-- lose nothing in operation (the cooling tower's evaporation is paid for with its own makeup water), so the plant
-- only fills them (and tops them up after a repair or a rebuild).
--   primary_per_second / secondary_per_second / cooling_per_second : water in = fluid out, per second (1:1, mass is conserved)
--   size : whole number >= 2 (default 4 = the size the oxidizer art was drawn for). One input on the north face, one
--          output on the south face; on an even size they sit one half tile left of centre (there is no centre tile).
--------------------------------------------------------------------------------------------------
C.water_treatment = {
  primary_per_second   = 200,
  secondary_per_second = 200,
  cooling_per_second   = 200,
  power_kw             = 500,
  idle_drain_kw        = 20,
  health               = 800,
  size                 = 4,
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
  sodium_coolant          = { count = 400, time = 45 },
  fast_breeder_power      = { count = 800, time = 60 },
}

--------------------------------------------------------------------------------------------------
-- TIER 4: fast breeder with supercritical CO2 generation (docs/FAST_BREEDER.md)
--
-- Balance rules checked at load time (a warning goes to factorio-current.log):
--   * sodium_exchanger takes a whole number of circulation units' flow; cool primary = hot primary; secondary in = secondary out
--   * co2_heater.sodium_per_second             should equal sodium_exchanger.secondary_per_second
--   * the heater's two recipes carry the same heat: co2 x (sco2_hot - preheat) = co2_direct x sco2_hot
--   * the compressor, recuperator and cooler handle the same flow
--   * the reference plant (D.reference, a 2x2 core array) needs whole numbers of every building
--   * the recuperator may not return more heat than the turbine exhaust holds
--   * breeding: fissile and heavy metal are conserved or lost, never created; the blankets' bred fissile must make the
--     breeding ratio land between 1 and 1.5, and the cycle must eat depleted uranium and make waste
--------------------------------------------------------------------------------------------------

-- Fast-breeder reactor core (vanilla reactor prototype, like the Tier 3 core; the same rod / SCRAM / afterheat script).
-- Burns MOX or starter assemblies (own fuel category, the Tier 3 core cannot burn them and vice versa). Its own neighbour
-- category: breeder cores boost each other (+neighbour_bonus per adjacent core, as in the base game), PWR cores do not join.
-- See C.reactor for the meaning of the individual keys.
C.fast_breeder = {
  size                     = 7,      -- footprint in tiles (size x size): odd, 3 to 7 (the engine allows 32 heat connections: 4 per tile of side)
  power_mw                 = 300,    -- base heat; each neighbouring core adds neighbour_bonus x this (a 2x2 array: 4 x 300 x 3 = 3600 MW)
  neighbour_bonus          = 1,
  specific_heat_mj         = 50,
  max_temperature_c        = 2550,
  health                   = 2000,
  fuel_slots               = 2,
  spent_slots              = 2,
  rod_speed_pct_per_second   = 1,
  scram_speed_pct_per_second = 25,
  scram_lockout_s          = 600,
  rod_exponent             = 1,
  decay_fraction           = 0.2,
  decay_rise_s             = 60,
  decay_fall_s             = 600,
  warning_temperature_c    = 2100,   -- above Heat pipe II's 2000 degC: the pipes never reach the warning before the core does
  meltdown_temperature_c   = 2500,
  meltdown_grace_s         = 5,
}

-- Reference plant (used by the load-time balance checks, the tests and docs/FAST_BREEDER.md): a cores_x x cores_y array of
-- breeder cores. 2 x 2 gives 4 x 300 MW x (1 + 2 neighbours) = 3600 MW of heat, which the default ratings turn into 2.5 GW net with
-- 48 circulation units, 24 intermediate exchangers and heaters, 40 turbines and 36 compressors, recuperators and coolers.
C.reference_plant = { cores_x = 2, cores_y = 2 }

-- Heat pipe II: the vanilla heat pipe (1000 degC) is too cold for a breeder core, which runs far hotter. Same conduction
-- as the vanilla pipe, higher limit. The sodium circulation unit's heat connection takes the same limit, otherwise it would
-- cap a pipe network at 1000 degC. Pipes also join the vanilla heat pipes (they connect to each other).
C.heat_pipe_2 = { max_temperature_c = 2000, health = 300 }

-- Sodium circulation unit: heat exchanger of the primary loop (vanilla heat exchanger). Same idea as primary_unit:
-- cool primary sodium (15 degC) is heated to target_c, one unit carries (target_c - 15) kJ (heat capacity 1 kJ per degC).
-- Derived: units per second = power / (target_c - 15 kJ) = 75 MW / 500 kJ = 150 /s.
C.sodium_unit = {
  power_mw        = 75,
  target_c        = 515,
  min_working_c   = 560,   -- only draws heat while the core is above this
  hot_fluid_max_c = 600,
  health          = 800,
}

-- Intermediate sodium exchanger: hot primary sodium + cool secondary sodium -> cool primary sodium + hot secondary sodium.
-- Heat passes 1:1 (a unit of hot secondary sodium carries as much as a unit of hot primary sodium). Its sodium pumps
-- need grid power: without power the primary loop stops and the core loses its cooling (keep a startup bank).
C.sodium_exchanger = {
  hot_primary_per_second  = 300,   -- = 150 MW at 500 kJ per unit = two circulation units
  cool_primary_per_second = 300,
  secondary_per_second    = 300,
  power_mw                = 0.5,
  idle_drain_kw           = 25,
  health                  = 1500,
  size                    = 5,
}

-- Sodium-to-CO2 heater: hot secondary sodium heats CO2. Two recipes, chosen by the heater itself from the fluid at its
-- CO2 inlet (scripts/heaters.lua): preheated CO2 (from a recuperator) or cold compressed CO2 (straight from the
-- compressor). Both burn the same sodium flow (the heater's heat rating); the cold feed simply yields less hot CO2.
--   recuperated_co2_per_second : hot CO2 made per second from preheated CO2 (300 x (1 - 0.5) MJ = 150 MW)
--   direct_co2_per_second      : hot CO2 made per second from cold CO2 (150 x 1 MJ = 150 MW)
C.co2_heater = {
  sodium_per_second          = 300,
  recuperated_co2_per_second = 300,
  direct_co2_per_second      = 150,
  power_kw                   = 250,
  idle_drain_kw              = 10,
  health                     = 1500,
  size                       = 5,
}

-- Supercritical-CO2 compressor (the working fluid's pump: this is where the cycle's own power demand sits).
C.sco2_compressor = {
  co2_per_second = 200,
  power_mw       = 8,
  idle_drain_kw  = 100,
  health         = 1200,
  size           = 5,
}

-- Recuperator: turbine exhaust gives its heat to the compressed CO2 (exhaust passes through, the compressed CO2 leaves
-- preheated). Removing it does not stop anything: the heater then takes the cold feed and needs more heat per MW.
C.recuperator = {
  co2_per_second = 200,
  power_kw       = 50,
  idle_drain_kw  = 5,
  health         = 1200,
  size           = 5,
}

-- CO2 cooler: air-cooled, rejects the remaining waste heat (fans, no coolant). Turns exhaust back into CO2.
C.sco2_cooler = {
  exhaust_per_second = 200,
  power_mw           = 1.8,
  idle_drain_kw      = 50,
  health             = 1000,
  size               = 5,
}

-- Hot-fluid storage tank: buffer for heat (hot sodium, hot CO2) or any other fluid. Vanilla storage tank, bigger.
C.hot_tank = { capacity = 100000, health = 1500 }

-- Shielded fuel fabricator: MOX, starter and blanket assemblies (recipes below).
C.fuel_fabricator = { power_mw = 4, idle_drain_kw = 100, health = 1500, size = 5 }

-- Blanket irradiation channel: a blanket assembly sits in it next to a running breeder core and is irradiated at a speed
-- that follows the core's ACTUAL fission power (scripts/breeders.lua): every channel touching a core gets an equal
-- share of the core's neutron budget, so more channels do not mean more breeding, only faster use of the same flux.
--   channel_time_s : recipe time when the channel gets full flux (duty 1); the real duty is
--                    channel_time_s x core power / (loaded channels x blanket.irradiation_gj)
--   reach_tiles    : a channel belongs to the nearest breeder core whose edge is within this many tiles of its own
C.blanket_channel = { channel_time_s = 600, reach_tiles = 1.5, health = 1000, size = 3 }

-- Fuel cycle. Fissile units ("fu") are the common currency: 1 plutonium-bearing material = 1 uranium-235 = 1 fu, and
-- burning 1 fu releases gj_per_fissile (a vanilla fuel cell: 0.1 U-235 for 8 GJ). Heavy metal (hm) = fu + depleted uranium.
--   mox / starter : assembly recipe; burnt_fissile is how much of its fissile content is fissioned (energy = x 80 GJ)
--   blanket       : irradiation_gj = core fission energy it takes to breed one blanket assembly
--   core_reprocessing / blanket_reprocessing : what a cooled spent core assembly / a bred blanket assembly gives back.
--                   residue holds the fission products plus the processing losses (what fission and chemistry destroy)
-- Net per MOX assembly (defaults): core gives back 4 of 6 fu, 1.33 blankets are bred meanwhile (+2.67 fu), 4 fu are
-- burnt -> breeding ratio (6.67 - 6 + 4) / 4 = 1.17. Without blankets it is (4 - 6 + 4) / 4 = 0.5, so the fissile stock shrinks.
C.breeder_fuel = {
  gj_per_fissile = 80,
  mox     = { pbm = 6,  du = 24, claddings = 2, burnt_fissile = 4 },
  starter = { u235 = 6, du = 24, claddings = 2, burnt_fissile = 4 },
  blanket = { du = 30, claddings = 1, irradiation_gj = 240 },
  core_reprocessing    = { pbm = 4, du = 21, residue = 5 },
  blanket_reprocessing = { pbm = 2, du = 27, residue = 1 },
  fabrication_time_s = 30,
}

-- Sodium electrolyzer (molten-salt electrolysis): dry sodium salt -> sodium + chlorine. Two recipes, chosen by hand
-- (like the water treatment plant): primary-loop sodium or secondary-loop sodium, so the two loops can never be mixed up.
-- Filling a plant is the expensive part (see docs/FAST_BREEDER.md): the loops lose nothing afterwards.
C.electrolyzer = {
  time_s = 4, salt = 10, sodium = 100, chlorine = 120,  -- per craft: 25 sodium/s from 2.5 salt/s (= 62 brine/s)
  power_mw = 20, idle_drain_kw = 200, health = 1500, size = 5,
}

-- Coolant and working-fluid chemistry (vanilla chemical plants):
--   brine   : water + stone -> brine      salt : brine -> dry sodium salt      kiln : stone -> lime + CO2
--   chlorine routes: neutralization (chlorine + lime, nothing left over) and chlorinated plastic (more plastic per gas)
C.sodium_chemistry = {
  brine_water = 100, brine_stone = 5, brine_out = 100,
  salt_brine = 100, salt_out = 4,
  kiln_stone = 4, kiln_lime = 2, kiln_co2 = 40, kiln_calcite = 2,
  neutralize_chlorine = 100, neutralize_lime = 2,
  plastic_gas = 20, plastic_chlorine = 10, plastic_coal = 1, plastic_out = 3,
  concrete_lime = 3, concrete_stone_brick = 5, concrete_water = 50, concrete_out = 10,
}

return C
