# Industrial Power Plants (slice 1 of the six-tier overhaul)

Requires Factorio 2.1 (written against 2.1.22+) and Space Age. Turbines are fully native. Runtime scripts: the exhaust
stack's automatic recipe choice, the reactor cores' control rods (`scripts/reactors.lua`), the CO2 heater's automatic
recipe choice (`scripts/heaters.lua`) and the blanket channels (`scripts/breeders.lua`); `scripts/events.lua` registers every
build / remove event once for all of them (the engine keeps one handler per event).

## Contents
* **Native turbines:** large steam (22.2 MW) and gas (45.4 MW) turbine-generators are `fusion-generator` entities
  (footprint x3 of the vanilla one) - steam/fuel gas in, electricity out, exhaust fluid returned through the output
  pipe. Steam and fuel gas are burned as fuel (no temperature dependence).
* **Combined-cycle plant:** fuel-gas conditioner (5x5, chemical-stager art), gas turbine, heat-recovery steam generator
  (5x5), large steam turbine, air-cooled condenser and an automatic exhaust stack (vent list: `docs/VENTING.md`,
  `/ipp-vent-list`).
* **Tier 3, pressurized-water nuclear power** (`docs/NUCLEAR.md`): reactor core whose control rods follow circuit signals
  (Control-rod withdrawal, Reactor SCRAM - latched, with a configurable lockout, 10 minutes by default; fail-safe when unwired; explodes when it makes more heat than is taken away),
  primary circulation unit, nuclear steam generator, high-pressure turbine train (45 MW), surface condenser, cooling tower
  and dry cooler, water treatment plant (fills the primary and secondary loops from vanilla water), spent-fuel cooling
  pool, dry-cask storage and, as a second research, reprocessing plant and waste vitrifier. The middle loop runs on its
  own fluid, secondary water; the cooling tower evaporates 600 vanilla water/s, so it has to be built by the water.
  Replaces the vanilla nuclear reactor. `/ipp-reactor-debug` prints core state.
* **Tier 4, fast breeder with supercritical-CO2 generation** (`docs/FAST_BREEDER.md`): sodium-cooled fast-breeder core (MOX or
  enriched-uranium starter assemblies, same rods / SCRAM / meltdown as Tier 3), blanket irradiation channels that breed depleted
  uranium at the core's real fission power, primary and secondary sodium loops, a recuperated CO2 cycle (50 % efficient; 30 %
  without the recuperator, which keeps working), fuel fabricator, sodium electrolyzer with brine / salt / kiln chemistry and chlorine
  routes, hot-fluid tank. Reuses the Tier 3 reprocessing plant, spent-fuel pool, casks and vitrifier. `/ipp-breeder-debug`
  prints channel state.
* Startup-energy bank (200 MJ). Techs: Industrial steam power, Combined-cycle gas power, Startup-energy storage, Pressurized-water nuclear power,
  Nuclear reprocessing, Sodium coolant production, Fast-breeder power.
* The former coal-fired Tier 1 plant (coal mill, industrial boiler, small steam turbine, waste compactor, ash and
  ash-blend concrete) has been removed.
Balance and reference layouts: `docs/ENERGY_ACCOUNTING.md`.

## Configuration
All ratings live in **`config.lua`** (mod root): turbine fluid use and effectivity (and optional output limit),
conditioner / heat-recovery / condenser flow rates, electric draw, idle drain and pollution, vent rates, startup-bank
capacity and flow, fluid energy values, health, research costs and the **size of every building**. Edit a number and
restart Factorio. Every
tooltip number follows the config. Invalid numbers stop loading with the key name; a balance that breaks the plant's
energy chain (for example a mismatched turbine intake) is reported in `factorio-current.log`.
Machine recipe ingredients (building costs) are in `prototypes/machines.lua`.

Sizes (defaults): turbines `size_multiplier` 3 (x the vanilla 3x5 fusion generator = 9x15; whole number >= 1),
conditioner 5, heat-recovery generator 5 (>= 3), condenser 3, exhaust stack 3 (odd numbers: pipes sit on tile
centres), startup bank 3 (vanilla accumulator is 2x2; any whole number). Pipe ports, collision/selection boxes,
sprites, circuit connectors and the stack's inlet check all follow the size. Sprites are scaled bitmaps, so large
changes from the default get blurry or oversized.

## Assumptions to confirm in game (could not be run here)
1. A fusion generator returns as much output fluid as input fluid it consumes (1:1). If not, adjust condenser/vent amounts.
2. Generators draw fluid only as fast as the grid takes power (like steam engines).
3. The fusion-generator footprint is the vanilla one and all turbines share it. Each turbine has exactly four pipe ports: two
   inputs on the south face and two exhaust outputs on the north face (vanilla positions, scaled with `size_multiplier`). The
   five pass-through "output" connections the vanilla input box carries (north face and both sides) are removed, so nothing
   can leave through the input side.
4. Steam is a fuel (50 kJ/unit): a large turbine at full steam should read about 22.2 MW. Pipes connect to every port because no
   temperatures are stamped anywhere.
5. Products-less recipes (exhaust stack) load; fixed-recipe machines work with recipes unlocked by technology.
Tier 4 assumptions to confirm in game are in `docs/FAST_BREEDER.md`.
Art: the fuel-gas conditioner uses the chemical-stager sprites (`graphics/chemical-stager`) and the water treatment plant
the oxidizer sprites (`graphics/oxidizer`, 280x320 frames, used at their native 4x4 size), both by Hurricane46, see
`graphics/License.txt`; everything else is tinted vanilla sprites. The 5x5 heat-recovery generator is the vanilla
chemical plant scaled by 5/3.

## Tests
`python3 dev-tests/test_data.py`, `test_stacks.py`, `test_reactors.py`, `test_breeders.py`, `test_lint.py` (need `pip install lupa`). They run the
data stage and the scripts against a mock world; the engine itself is not tested - see the assumptions in `docs/NUCLEAR.md`.

## Exhaust stack
Picks its vent recipe from the fluid at its inlet. Allowed: exhaust steam, flue gas, hot exhaust, surplus CO2. Refused: industrial
steam, high-pressure steam, steam, water, secondary water, cooling water, primary water, sodium, chlorine, solvent, fuels, lubricant, sulfuric acid and anything unlisted - see `docs/VENTING.md`.

## Removed from the previous design
Hidden electric buffer entities, the control script, the neighbour-efficiency bonus and `/ipp-status`.
