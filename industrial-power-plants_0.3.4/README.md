# Industrial Power Plants (slice 1 of the six-tier overhaul)

Requires Factorio 2.1 (written against 2.1.22+) and Space Age. Turbines are fully native; the only runtime script
is the exhaust stack's automatic recipe choice.

## Contents
* **Native turbines:** industrial steam (6.5 MW), large steam (22.2 MW) and gas (45.4 MW) turbine-generators are
  `fusion-generator` entities (footprint x2 / x3 / x3 of the vanilla one) - steam/fuel gas in, electricity out, exhaust fluid
  returned through the output pipe. Steam and fuel gas are burned as fuel (no temperature dependence).
* **Tier 1:** coal preparation mill, industrial boiler (13.2 MW, graded charges only, ash), air-cooled condenser,
  automatic exhaust stack (vent list: `docs/VENTING.md`, `/ipp-vent-list`), waste compactor, ash-blend concrete.
* **Tier 2:** fuel-gas conditioner, heat-recovery steam generator, large steam turbine, gas turbine.
* Startup-energy bank (200 MJ). Techs: Industrial steam power, Combined-cycle gas power, Startup-energy storage.
Balance and reference layouts: `docs/ENERGY_ACCOUNTING.md`.

## Assumptions to confirm in game (could not be run here)
1. A fusion generator returns as much output fluid as input fluid it consumes (1:1). If not, adjust condenser/vent amounts.
2. Generators draw fluid only as fast as the grid takes power (like steam engines).
3. The fusion-generator footprint and pipe positions are the vanilla ones; all three turbines share it.
4. Steam is a fuel (50 kJ/unit): a turbine at full steam should read about 6.5 MW. Pipes connect to every port because no
   temperatures are stamped anywhere.
5. Products-less recipes (exhaust stack) load; fixed-recipe machines work with recipes unlocked by technology.
Placeholder art: tinted vanilla sprites.

## Exhaust stack
Picks its vent recipe from the fluid at its inlet. Allowed: exhaust steam, flue gas, hot exhaust. Refused: industrial
steam, steam, water, fuels, lubricant, sulfuric acid and anything unlisted - see `docs/VENTING.md`.

## Removed from the previous design
Hidden electric buffer entities, the control script, the neighbour-efficiency bonus and `/ipp-status`.
