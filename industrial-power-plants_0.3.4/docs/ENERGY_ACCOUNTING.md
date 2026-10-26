# Energy accounting (Tier 1 and Tier 2)

Numbers live in `shared/defs.lua`; `dev-tests/test_data.py` recomputes every rating from the prototypes.

## Native turbine model

Turbines are vanilla-style `fusion-generator` entities: they take one filtered input fluid, make electricity from it
and return a second fluid through their output fluid box. Output electricity = fluid used x energy per unit x effectivity.

| Fluid | Energy per unit | How |
|---|---|---|
| Industrial steam | 50 kJ | `fuel_value`, consumed with `burns_fluid = true` |
| Fuel gas | 1 MJ | `fuel_value`, consumed with `burns_fluid = true` |
| Graded coal charge | 32 MJ | exactly 8 coal; the mill adds no energy |

All three turbines burn their input fluid. Power does not depend on fluid temperature on purpose: in 2.1 a recipe that
stamps a temperature locks the output box to it, and a filtered turbine port only accepts the fluid's default
temperature, so a temperature-based design blocks pipe connections. Everything here stays at default temperature.
Side effect: any other fluid burner that accepts fuel fluids (for example a heating tower) can also burn industrial steam;
it yields the same 50 kJ per unit, so no energy is created.

| Turbine | Input at full load | Effectivity | Output | Returns |
|---|---|---|---|---|
| Industrial steam turbine-generator | 132 steam/s | 98.5 % | 6.50 MW | 132 exhaust steam/s |
| Large steam turbine-generator | 450 steam/s | 98.5 % | 22.16 MW | 450 exhaust steam/s |
| Gas turbine-generator | 84 fuel gas/s | 54 % | 45.36 MW | 84 hot exhaust/s |

No turbine exceeds 100 % of its input.

Footprints are the vanilla fusion generator scaled by an integer factor (pipe connections are re-seated on the new
edge tiles): steam turbine x2, large steam turbine x3, gas turbine x3.
Fluid-box volumes are at least 3 s of flow (since 2.1.7 pipe throughput is derived from fluid-box volume).

## Tier 1 reference plant (25 MW class)

2 boilers (13.2 MW each, 264 steam/s) -> 4 turbines -> 2 condensers (270 exhaust/s each) + 1 mill.

* Steam 528/s = 26.4 MW; turbines 4 x 6.50 = **26.0 MW gross**.
* Aux: mill ~0.33 MW average, condensers 0.5 MW, drains ~0.06 MW = **~0.9 MW**; net **~25.1 MW**.
* Fuel per net MWh vs vanilla steam: 26.4 / 25.1 = **1.05**.
* Coal 6.6/s (0.825 charges/s); ash 0.825/s (one compactor handles 10/s).
* Open cycle (stacks instead of condensers) saves 0.5 MW aux but burns water; condensers return 260 of 270 units (96 %).

## Tier 2 reference plant (125 MW class)

2 conditioners -> 2 gas turbines -> 2 heat-recovery generators -> 2 large steam turbines -> 4 condensers.

* Fuel gas 168/s from 210 petroleum gas/s (0.8 MJ per PG; vanilla solid fuel route 0.6 MJ/PG).
* Gas turbines 2 x 45.36 = 90.7 MW; exhaust 2 x 84 units. Each HRSG recovers 22.5 MJ of the 38.6 MJ exhaust heat
  (heat balance holds: 84 - 45.36 = 38.6 >= 22.5).
* Large steam turbines 2 x 22.16 = 44.3 MW. **Gross 135.0 MW.**
* Aux: conditioners 8.0 + HRSGs 1.0 + condensers 1.0 + drains ~0.3 = **~10.3 MW**; net **~124.7 MW**.
* 135.0 / 168 = 80 % gross efficiency; 0.643 MJ per PG (+7 % vs vanilla). Gas turbine alone: 0.43 MJ/PG (-28 %).

## Startup

The conditioner (compressor train, 4 MW) and the coal mill need grid power, so a dead grid cannot restart Tier 1 charges
or Tier 2 fuel gas. Keep a vanilla starter set or a startup-energy bank (200 MJ, 20 MW out).
