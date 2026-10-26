# Energy accounting (combined-cycle plant)

The tables below use the default numbers of `config.lua` (edit that file to tune; `shared/defs.lua` derives from it).
`dev-tests/test_data.py` recomputes every rating from the prototypes. The old coal-fired Tier 1 plant (mill, boiler,
small steam turbine, ash, compactor) has been removed.

## Native turbine model

Turbines are vanilla-style `fusion-generator` entities: they take one filtered input fluid, make electricity from it
and return a second fluid through their output fluid box. Output electricity = fluid used x energy per unit x effectivity.

| Fluid | Energy per unit | How |
|---|---|---|
| Industrial steam | 50 kJ | `fuel_value`, consumed with `burns_fluid = true` |
| Fuel gas | 1 MJ | `fuel_value`, consumed with `burns_fluid = true` |

Both turbines burn their input fluid. Power does not depend on fluid temperature on purpose: in 2.1 a recipe that
stamps a temperature locks the output box to it, and a filtered turbine port only accepts the fluid's default
temperature, so a temperature-based design blocks pipe connections. Everything here stays at default temperature.
Side effect: any other fluid burner that accepts fuel fluids (for example a heating tower) can also burn industrial steam;
it yields the same 50 kJ per unit, so no energy is created.

| Turbine | Input at full load | Effectivity | Output | Returns |
|---|---|---|---|---|
| Large steam turbine-generator | 450 steam/s | 98.5 % | 22.16 MW | 450 exhaust steam/s |
| Gas turbine-generator | 84 fuel gas/s | 54 % | 45.36 MW | 84 hot exhaust/s |

No turbine exceeds 100 % of its input.

Footprints (config `size` settings, defaults shown) are the vanilla fusion generator scaled by an integer factor (pipe connections are re-seated on the new
edge tiles): large steam turbine x3, gas turbine x3. The fuel-gas conditioner (chemical-stager art) and the
heat-recovery steam generator are 5x5 crafting machines.
Fluid-box volumes are at least 3 s of flow (since 2.1.7 pipe throughput is derived from fluid-box volume).

## Reference plant (125 MW class)

2 conditioners -> 2 gas turbines -> 2 heat-recovery generators -> 2 large steam turbines -> 4 condensers.

* Fuel gas 168/s from 210 petroleum gas/s (0.8 MJ per PG; vanilla solid fuel route 0.6 MJ/PG).
* Gas turbines 2 x 45.36 = 90.7 MW; exhaust 2 x 84 units. Each HRSG recovers 22.5 MJ of the 38.6 MJ exhaust heat
  (heat balance holds: 84 - 45.36 = 38.6 >= 22.5).
* Large steam turbines 2 x 22.16 = 44.3 MW. **Gross 135.0 MW.**
* Aux: conditioners 8.0 + HRSGs 1.0 + condensers 1.0 + drains ~0.3 = **~10.3 MW**; net **~124.7 MW**.
* 135.0 / 168 = 80 % gross efficiency; 0.643 MJ per PG (+7 % vs vanilla). Gas turbine alone: 0.43 MJ/PG (-28 %).

## Startup

The conditioner (compressor train, 4 MW) needs grid power, so a dead grid cannot restart the fuel gas supply. Keep a vanilla starter set or a startup-energy bank (200 MJ, 20 MW out).
