# Tier 4: fast breeder with supercritical CO2 generation

An industrial nuclear complex built around **fuel utilization and high-temperature heat management**: a sodium-cooled
fast breeder on MOX fuel with a depleted-uranium breeding blanket, two isolated sodium loops and a recuperated
supercritical-CO2 power cycle. Everything below is configurable in `config.lua` (sections marked Tier 4).

Researched in two steps: **Sodium coolant production** (brine, salt, electrolysis, kiln, chlorine routes, hot-fluid tank),
then **Fast-breeder power** (needs Nuclear reprocessing, Kovarex enrichment and Sodium coolant production; costs production
science). The Tier 3 reprocessing plant, spent-fuel pool, dry casks, vitrifier, water treatment and startup bank are reused.

## The reference plant

The ratings are designed around a **2x2 array of breeder cores**: 4 cores x 300 MW x (1 + 2 neighbours) = **3600 MW of heat**, which
the plant turns into **2.5 GW net**. `config.reference_plant` sets the array; the numbers below are computed from the ratings
(`D.reference`, checked by the tests; the load-time checks warn if a rating change makes them fractional).

| Building | Count | Rating each | Together |
|---|---|---|---|
| Fast-breeder reactor (7x7, `fast_breeder.size`) | 4 | 300 MW base, +100 % per neighbouring core (x3 in a 2x2) | 3600 MW |
| Sodium circulation unit* | 48 | 75 MW, 150 primary sodium/s, 515 °C | 3600 MW, 7200 sodium/s |
| Intermediate sodium exchanger | 24 | 300 sodium/s = 150 MW (2 circulation units), 0.5 MW pumps | 3600 MW |
| Sodium-to-CO2 heater | 24 | 300 sodium/s = 150 MW, 0.25 MW | 7200 hot CO2/s |
| CO2 turbine-generator | 40 | 180 hot CO2/s x 1 MJ x 0.4 = 72 MW | 2880 MW gross |
| Supercritical CO2 compressor | 36 | 200 CO2/s, 8 MW | 7200 CO2/s |
| Recuperator | 36 | 200 CO2/s, returns 100 MW, 0.05 MW | 3600 MW returned |
| CO2 cooler | 36 | 200 exhaust CO2/s, 1.8 MW fans | |
| Heat pipe II* | as needed | vanilla conduction, 2000 °C (vanilla: 1000 °C) | |
| Blanket irradiation channel* | 3+ per core | no power | |
| Shielded fuel fabricator, sodium electrolyzer, hot-fluid tank | as needed | 4 MW / 20 MW / 100 000 units | |

\* not in the plan's building table; see "Implementation decisions". Heat pipe II (made from a vanilla heat pipe, refractory alloy and a
ceramic seal, researched with Fast-breeder power) fast-replaces vanilla heat pipes and connects to them. It stays 100 °C below the
core's warning (2100 °C; explosion 2500 °C), so the pipes are never the first thing to give; the circulation unit's heat connection
takes the same 2000 °C limit.

Net output: 2880 MW gross - 379 MW own use (compressors 292, coolers 67, exchangers 13, heaters 6, recuperators 2; working power plus idle drain at
full load) = **2501 MW**. Every flow balances exactly: 48 x 150 = 24 x 300 sodium/s, 24 x 300 = 40 x 180 = 36 x 200 CO2/s. All the plant's
pumps and fans need grid power, as in Tier 3: without power the primary loop stops and the core loses its cooling, so keep a startup bank.

Each core is a **7x7** block (`fast_breeder.size`, odd, 3 to 7). It has a heat connection on every tile of every side (a circulation unit or a
heat pipe can sit against any tile) and one neighbour point per side. The core's graphics, collision box and connection points all scale with
the size; the vanilla core stays 5x5. The vanilla "connection patch" sprites are drawn per vanilla connection, so the core has none (cosmetic).

```
4 cores 3600 MW --48 circulation units--> primary loop 7200/s --24 exchangers--> secondary loop 7200/s --24 heaters--> hot CO2 7200/s
 --> 40 turbines (2880 MW) --> exhaust --> 36 recuperators (give 3600 MW back to the compressed CO2) --> 36 coolers --> 36 compressors --> recuperators --> heaters
```

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

**Initial filling is expensive, routine consumption is zero.** Every recipe in the loops returns what it takes. Filling the reference plant's
machines alone needs about 57 600 sodium (one second of flow in every sodium port): 5760 dry salt, 144 000 brine (144 000 water and 7200 stone), and
38 minutes of 25 sodium/s per electrolyzer, so you want dozens of them. Every pipe segment and tank adds to that, and sodium is lost only
when a pipe or machine is destroyed (the electrolyzer then supplies the replacement). Chlorine (120 per 100 sodium) is a by-product of that filling.

**Chlorine always has a way out** (both unlock together with the electrolysis): *chlorine neutralization* (100 chlorine + 2 lime,
nothing left over) and *chlorinated plastic* (20 petroleum gas + 10 chlorine + 1 coal -> 3 plastic instead of 2). The exhaust stack
refuses chlorine and all sodium (hazard). **Lime** also makes *lime concrete* (cheaper concrete). Using lime in water treatment, which the
plan mentions, is not implemented: the water treatment plant makes the three Tier 3 loop fluids 1:1 and has nothing for lime to improve.

## The CO2 cycle and the recuperator

Fluids (energies measured from the compressor outlet): CO2 -> *compressed CO2* (0) -> *preheated CO2* (0.5 MJ/unit)
-> *hot CO2* (1 MJ/unit, the turbine's fuel value) -> turbine exhaust -> CO2. Like every turbine in the mod, the
CO2 turbine burns its fluid as fuel at default temperature, so it connects without temperature surprises.

**Removing the recuperator does not stop anything, it makes the plant need far more heat.** The heater has two recipes that
burn the same 300 sodium/s (150 MW):

| Feed | Hot CO2 made | Turbine output (0.4 of its fuel value) | Cycle efficiency |
|---|---|---|---|
| preheated CO2 (recuperator) | 300/s | 120 MW | 80 % |
| cold CO2 (straight from the compressor) | 150/s | 60 MW | 40 % |

So without the recuperator the same electricity costs **twice the heat** (the reference plant would make 1440 MW gross from its 3600 MW of
heat instead of 2880 MW, and you would need twice the cores). The heater chooses the recipe itself every second (`scripts/heaters.lua`) from the fluid at
its CO2 inlet (the right-hand port of the north face when unrotated), so adding or removing a recuperator needs no
clicking. The recuperator hands back 100 MW of the 120 MW the exhaust still holds (the config check refuses a recuperator that
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
no virgin enriched uranium, against 120 U-235 per GWh of electricity in Tier 3 without reprocessing. (A 2x2 array at full power burns one MOX assembly every 89 s, about 0.7 a minute.)

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
