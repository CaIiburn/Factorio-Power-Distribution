# Tier 4: fast breeder with supercritical CO2 generation

An industrial nuclear complex built around **fuel utilization and high-temperature heat management**: a sodium-cooled
fast breeder on MOX fuel with a depleted-uranium breeding blanket, two isolated sodium loops and a recuperated
supercritical-CO2 power cycle. Everything below is configurable in `config.lua` (sections marked Tier 4).

Researched in two steps: **Sodium coolant production** (brine, salt, electrolysis, kiln, chlorine routes, hot-fluid tank),
then **Fast-breeder power** (needs Nuclear reprocessing, Kovarex enrichment and Sodium coolant production; costs production
science). The Tier 3 reprocessing plant, spent-fuel pool, dry casks, vitrifier, water treatment and startup bank are reused.

## The plant at a glance (default numbers, one core)

```
core 300 MW  --3x circulation unit (100 MW, 200 primary sodium/s each)-->  primary loop (600/s)
  --> intermediate sodium exchanger (3 MW pumps) -->  secondary loop (600/s)
  --> sodium-to-CO2 heater -->  hot CO2 250/s  --> CO2 turbine-generator 150 MW
turbine exhaust --> recuperator (gives 200 MW back to the compressed CO2) --> cooler (6 MW fans) --> compressor (15 MW) --> recuperator --> heater
```

| Building | Purpose | Rating |
|---|---|---|
| Fast-breeder reactor | heat, uses MOX / starter assemblies; same rods, SCRAM, afterheat and meltdown as the Tier 3 core | 300 MW, +100 % per neighbouring breeder core; warning 2100 °C, explosion 2500 °C |
| Heat pipe II* | connects the core to the circulation units | vanilla conduction, 2000 °C (vanilla: 1000 °C) |
| Sodium circulation unit* | the "heat exchanger" of the primary loop: core heat in, hot primary sodium out | 100 MW, 200 sodium/s, 515 °C |
| Blanket irradiation channel* | holds a blanket assembly next to a running core | no power |
| Intermediate sodium exchanger | primary sodium gives its heat to secondary sodium, nothing mixes | 600/s, 3 MW |
| Sodium-to-CO2 heater | secondary sodium heats CO2 | 300 MW, 1 MW |
| Supercritical CO2 compressor | the working fluid's pump | 250/s, 15 MW |
| CO2 turbine-generator | burns hot CO2 | 250/s x 2 MJ x 0.3 = 150 MW |
| Recuperator | exhaust heat back into the compressed CO2 | 250/s, 0.5 MW |
| CO2 cooler | air-cooled, rejects the rest | 250/s, 6 MW |
| Shielded fuel fabricator | MOX, starter and blanket assemblies | 4 MW |
| Sodium electrolyzer | primary or secondary sodium + chlorine from dry salt | 25 sodium/s, 20 MW |
| Hot-fluid storage tank | heat buffer | 100 000 units |

\* not in the plan's building table; see "Implementation decisions". Heat pipe II (researched with Fast-breeder power, made from a vanilla heat pipe,
refractory alloy and a ceramic seal) fast-replaces vanilla heat pipes and connects to them. It stays 100 °C below the core's warning, so the
pipes are never the first thing to give; the circulation unit's heat connection takes the same 2000 °C limit.

Net output of one train is about 124 MW after the plant's own use (the compressor, cooler and pumps). All the plant's pumps and
fans need grid power, as in Tier 3: without power the primary loop stops and the core loses its cooling, so keep a startup bank.

## Sodium

Two loops, two fluids each: *primary sodium* (radioactive, never leaves the primary loop) and *secondary sodium* (the second
isolation barrier). They are different fluids and the electrolyzer has one recipe per loop, so they cannot be mixed up.
Cool sodium is at default temperature; only the circulation unit stamps a temperature (hot primary sodium at 515 °C, 500 kJ per
unit), exactly like the Tier 3 primary water. The heat in the secondary loop is accounted in the recipes.

Coolant manufacture, all in vanilla chemical plants except the electrolysis:

| Step | Recipe |
|---|---|
| brine | 100 water + 5 stone -> 100 brine |
| dry sodium salt | 100 brine -> 4 salt |
| molten-salt electrolysis | 10 salt -> 100 sodium + 120 chlorine, 4 s, 20 MW |
| kiln | 4 stone (or 2 calcite, if Space Age's calcite exists) -> 2 lime + 40 CO2 |

The kiln's CO2 is the working fluid of the CO2 cycle, so it also fills that loop; surplus CO2 can be vented
by an exhaust stack.

**Initial filling is expensive, routine consumption is zero.** Every recipe in the loops returns what it takes. Filling the
machines alone needs about 10 800 sodium (1080 salt, 27 000 brine, 27 000 water and 1350 stone, 7 minutes of one
electrolyzer); every pipe segment and tank adds to that, and sodium is lost only when a pipe or machine is destroyed (the
electrolyzer then supplies the replacement). Chlorine is a by-product of that filling.

**Chlorine always has a way out** (both unlock together with the electrolysis): *chlorine neutralization* (100 chlorine + 2 lime,
nothing left over) and *chlorinated plastic* (20 petroleum gas + 10 chlorine + 1 coal -> 3 plastic instead of 2). The exhaust stack
refuses chlorine and all sodium (hazard). **Lime** also makes *lime concrete* (cheaper concrete). Using lime in water treatment, which the
plan mentions, is not implemented: the water treatment plant makes the three Tier 3 loop fluids 1:1 and has nothing for lime to improve.

## The CO2 cycle and the recuperator

Fluids (energies measured from the compressor outlet): CO2 -> *compressed CO2* (0) -> *preheated CO2* (0.8 MJ/unit)
-> *hot CO2* (2 MJ/unit, the turbine's fuel value) -> turbine exhaust -> CO2. Like every turbine in the mod, the
CO2 turbine burns its fluid as fuel at default temperature, so it connects without temperature surprises.

**Removing the recuperator does not stop anything, it makes the plant need far more heat.** The heater has two recipes that
burn the same 600 sodium/s (300 MW):

| Feed | Hot CO2 made | Turbine output | Efficiency |
|---|---|---|---|
| preheated CO2 (recuperator) | 250/s | 150 MW | 50 % |
| cold CO2 (straight from the compressor) | 150/s | 90 MW | 30 % |

So without the recuperator the same electricity costs 1.67 times the heat (one train gives 90 MW instead of 150 MW, or needs a
second core for the same output). The heater chooses the recipe itself every second (`scripts/heaters.lua`) from the fluid at
its CO2 inlet (the right-hand port of the north face when unrotated), so adding or removing a recuperator needs no
clicking. The recuperator hands back 200 MW of the 350 MW the exhaust still holds (the config check refuses a recuperator that
returns more than the exhaust has).

## Fuel cycle

Fissile units (fu) are the common currency: 1 plutonium-bearing material (PBM) = 1 uranium-235 = 1 fu, and 1 fu fissioned releases 80 GJ
(the Tier 3 assembly: 0.5 U-235 burnt for 40 GJ).

```
normal    : 6 PBM + 24 depleted uranium + 2 cladding        -> MOX assembly          (320 GJ, 4 fu fissioned)
bootstrap : 6 enriched uranium + 24 depleted uranium + 2 cladding -> starter assembly  (320 GJ)   no breeder needed
blanket   : 30 depleted uranium + 1 cladding                -> blanket assembly   -- irradiated (240 GJ of core energy) --> bred blanket
spent core assembly (hot) --pool--> cooled --reprocessing--> 4 PBM + 21 depleted uranium + 5 residue
bred blanket                     --reprocessing--> 2 PBM + 27 depleted uranium + 1 residue
```

Per MOX assembly burnt, 1.33 blankets are bred in the meantime: 6.67 PBM come back for the 6 that went in, **breeding ratio
1.17**, consuming 7 depleted uranium and making 6.3 residue. The core alone (no blankets) returns 4 of 6: ratio 0.5, the fissile stock
shrinks. Fission and processing losses are in the residue; heavy metal is never created (the tests check every recipe). The enriched
uranium for the first breeder is a one-time cost; after that the cycle needs depleted uranium only, so a delivered GWh needs essentially
no virgin enriched uranium, against 120 U-235 per GWh of electricity in Tier 3 without reprocessing.

There is **no closed recipe** that returns its inputs and adds fissile material without eating depleted uranium: blankets are the only
source of surplus, they need depleted uranium, and they only breed while a core actually burns fuel.

### How blankets are irradiated (`scripts/breeders.lua`)

A vanilla reactor burns one item at a time and has no second inventory, so it cannot irradiate a second kind of assembly by itself. The
blanket sits in a **blanket irradiation channel** touching the core (within 1.5 tiles of its edge). The script switches the channel
on and off in proportion to the core's *actual* fission power:

    duty = 600 s x core power / (loaded channels x 240 GJ), at most 1

* a scrammed, locked-out or fuel-less core irradiates nothing, a core at half rods breeds at half speed;
* the loaded channels of one core share its flux equally, so more channels do not breed more per unit of core energy: they let a
  boosted core keep up (a x3 core needs three channels; the channel's status says "core makes more flux than this channel can use");
* an empty channel takes no share. `/ipp-breeder-debug` prints duty, core and power of every channel.

## Implementation decisions to review

1. **Two buildings that are not in the plan's table**, because the engine needs them: the *sodium circulation unit* is the "heat
   exchanger" of the primary circuit (a vanilla heat exchanger, the sodium twin of the Tier 3 circulation unit), and the *blanket irradiation
   channel* (above). Both are researched with Fast-breeder power.
2. **The Tier 3 spent-fuel pool and reprocessing plant lost their fixed recipe** so they can take the Tier 4 recipes; they are now chosen by
   hand (existing machines keep what they had). Hot spent core assemblies cool in the same pool.
3. **One event registration for the whole mod** (`scripts/events.lua`). The engine keeps one handler per event; the exhaust-stack and
   reactor scripts both registered the build/remove events and the second silently replaced the first. All four scripts now export a
   `lifecycle` table and `control.lua` registers each event once (`test_breeders.py` fails on any duplicate).
4. New fluid *brine* comes from water + stone because the base game has none. Refractory alloy is made from Tier 3 heat-resistant alloy,
   refractory lining and sulfur, so Tier 4 needs nothing from another planet (calcite is used when Space Age provides it).

## Assumptions to confirm in game (this could not be run here)

1. A crafting machine with no fixed recipe accepts either CO2 state at its inlet until the script has set a recipe, and a changed recipe clears the
   old fluid. If the heater does not switch, check `custom_status` and the pipe at its inlet; the poll is every 59 ticks.
2. The heater inlet tile is `(+1, -(size+1)/2)` from its centre, rotated with it: the same rule the exhaust stack uses for its inlet.
3. A recipe that takes and returns the same fluid (the recuperator's exhaust) loads and uses two ports.
4. Disabling a crafting machine by script pauses its crafting progress and keeps its ingredients (the channel relies on it, as the reactor does).
5. As in Tier 3: hot primary sodium leaves the circulation unit at 515 °C and the exchanger's input accepts that temperature (its recipe has no
   temperature range); a boiler with a fluid filter on the output works for any fluid.
6. `selection_box` of both entities is available at runtime for the channel/core reach test, and the burner `currently_burning` / fuel inventory
   tell whether the breeder core has fuel.
