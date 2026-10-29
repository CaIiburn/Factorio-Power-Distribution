# Tier 3: pressurized-water nuclear power

Three fluid circuits, a reactor whose control rods you drive with circuit signals, and a spent-fuel route.
Every number below is the default of `config.lua`; `dev-tests/test_data.py` recomputes the energy chain from the prototypes.

## The plant

```
 fuel assembly                                    hot primary water                 steam            exhaust
      |                                                  |                            |                  |
 [reactor core] --heat--> [primary circulation unit] --> [nuclear steam generator] --> [HP turbine] --> [surface condenser]
   (rods: circuit)               ^                              |  feedwater (water) <-----------------------+  |
                                 +------ cool primary water <---+                                              |
                                                                                    cool cooling water ->  warm cooling water
                                                                                                  ^                |
                                                                       [cooling tower / dry cooler] <-------------+
```

| Circuit | Fluids | Closed? |
|---|---|---|
| Primary | primary water (cool) / hot primary water | yes, loses nothing |
| Steam | water (feedwater) / high-pressure steam / exhaust steam | yes, loses nothing |
| Cooling | cooling water / warm cooling water | loses 12/s makeup water at a cooling tower |

Numbers per core: **core 120 MW heat -> 1 circulation unit (120 MW, 400 primary/s) -> 1 steam generator (45 MW of steam energy)
-> 1 turbine train (45 MW electric); the condenser rejects the other 75 MW.** Cores next to each other boost each other as in
the base game (each neighbour adds +100 %: two neighbours give x3), so a bonused core needs more circulation units and
steam generators. Put units against the core's heat connections or link them with heat pipes.

| Building | Size | Notes |
|---|---|---|
| Pressurized-water reactor core | 5x5 | vanilla reactor prototype, circuit connector on the core |
| Primary circulation unit | 3x2 | vanilla heat exchanger: heat in at the bottom, cool primary in at either side, hot primary out at the top |
| Nuclear steam generator | 5x5 | north face: hot primary (left), feedwater (right) in. South face: steam (left), cool primary (right) out. 2 MW pumps |
| High-pressure turbine train | 9x15 | native fusion-generator, 500 steam/s x 90 kJ = 45 MW |
| Surface condenser | 5x5 | exhaust steam (left) + cooling water (right) in; feedwater (left) + warm cooling water (right) out |
| Cooling tower / dry cooler | 5x5 | tower 600/s warm, 12/s makeup, 1 MW; dry cooler 300/s, 6 MW, no water |
| Spent-fuel cooling pool | 5x5 | hot assembly + 100 water -> cooled assembly after a fixed 120 s |
| Dry-cask storage | 3x3 | 48 slots |
| Reprocessing plant (optional) | 5x5 | cooled assembly + 100 acid + 50 solvent -> U-238, U-235 (40 %), plutonium-bearing material, residue |
| Waste vitrifier (with reprocessing) | 3x3 | 4 residue + 2 glass frit -> vitrified waste canister |

Fuel: **vanilla uranium processing -> uranium fuel cells -> fuel assembly** (5 cells + 4 cladding + 1 frame, 40 GJ, 333 s of
one core at full power). Only the new core burns assemblies; vanilla reactors burn vanilla cells. The vanilla "Nuclear power"
research no longer unlocks the vanilla reactor, heat exchanger or steam turbine (`replace_vanilla_nuclear` in `config.lua`).

The steam generator and every cooling building need grid power. **Without power the primary loop stops circulating and the
core loses its cooling**; the decay heat then keeps heating it. Keep a startup bank on the grid.

## Control rods

The core reads two signals from its circuit connector (red and green wires are added together):

| Signal | Meaning |
|---|---|
| **Control-rod withdrawal** (`ipp-rod-withdrawal`) | 0-100 %. 0 = rods fully in = no fission. 100 = fully out = full power. Values outside 0-100 are clamped |
| **Reactor SCRAM** (`ipp-scram`) | any non-zero value: rods drop at 25 %/s whatever the withdrawal signal says |

* **Fail-safe.** A core with no wire attached drops its rods by itself. A new core starts with rods fully in. (A signal of
  0 on a connected wire is a normal "rods in" command at the normal speed.)
* **Rods are slow.** They move 2 %/s (50 s from fully in to fully out) and drop at 25 %/s on a SCRAM. The core's status
  line shows rod position, target, temperature, output multiplier and fuel.
* **Fission power** = withdrawal x 120 MW x (1 + neighbour bonus). The core is switched off and on every tick in exactly that
  proportion, so fuel burn follows the rods as well as heat.
* **Decay heat.** After power drops, 7 % of the earlier power stays as afterheat and fades with a time constant of 4 minutes
  (it builds up with 1 minute). The primary loop has to keep running after a shutdown.
* **Reading the core.** Switch on "read temperature" (signal T) and "read fuel" in the core's circuit settings.
  The power draw of the grid is assumed to be available as a signal from your own network; the mod never reads the grid.

### Overheating and meltdown

Nothing is compared instantly: heat made minus heat taken away accumulates in the core's native temperature
(thermal mass 20 MJ per degC). The circulation units only draw heat while the core is above 350 degC, so a healthy core sits
a little above that. The steam side takes only what the turbines use, so **if your rods ask for more heat than the grid
draws, the temperature climbs**:

* **800 degC** - warning: yellow status and a map alert.
* **920 degC for 5 s** (or 1000 degC at once) - **meltdown**: the core is destroyed and the standard vanilla reactor
  (nuclear) explosion goes off. Lost cooling (no power, closed valve, empty feedwater) does the same.

Time you have: thermal mass x temperature margin / surplus power. A single core at full rods with no cooling at all gains
6 degC/s (about 80 s from 450 degC); a core with two neighbours gains 18 degC/s (about 26 s).

There is no automatic protection beyond the fail-safe. Build your own SCRAM from the temperature signal if you want one.

### Example controller

Rods follow the demand, trimmed by temperature. For one core feeding one 45 MW turbine train:

1. `D` = your grid-demand signal in MW (any signal).
2. Arithmetic combinator: `D * 100 / 45 -> Control-rod withdrawal` (feed-forward: 45 MW of demand needs 100 % rods; scale the 45
   by the number of turbine trains the core feeds, and by its neighbour multiplier).
3. Trim: arithmetic `(signal-T - 450) * -1 -> Control-rod withdrawal`, added only when `signal-T > 450`, pulls the rods in
   when the core runs hot. The rods are slow and the core has thermal mass, so keep the gain small (a few %/degC) or it will oscillate.
4. Safety: decider `signal-T > 850 -> Reactor SCRAM = 1`, and wire the same network to every core so one signal drops them all.

`/ipp-reactor-debug` prints rods, duty, temperature, neighbour bonus, decay heat and wire state of every core.

## Assumptions to confirm in game (this could not be run here)
1. A reactor switched off by script (`disabled_by_script`) keeps its heat buffer, keeps exchanging heat with its neighbours
   and keeps its burning-fuel state. Check with `/ipp-reactor-debug` at 50 % rods: duty 0.5, temperature steady, fuel lasting twice as long.
   If a switched-off core stops conducting heat, the rod duty cycle has to be replaced by a heat-interface source.
2. `neighbour_bonus` reads as the sum of the neighbours' bonuses (two neighbours = 2), so output is x(1 + bonus).
3. The hot primary water leaves the circulation unit at 315 degC and the steam generator's input accepts that temperature
   (its recipe carries no temperature range). If pipes refuse to connect, check the connected fluid in the tooltip.
4. The heat exchanger prototype accepts non-steam fluids on both sides (filters `ipp-primary-water` / `ipp-primary-water-hot`).
5. `get_signal` on the core's connector sums the red and green networks and does not see the core's own temperature output as a rod signal.
