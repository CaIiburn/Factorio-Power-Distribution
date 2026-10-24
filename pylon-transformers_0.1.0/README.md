# Pylon Transformers (Factorio 2.1)

Power pole classes and transformers in one mod. Power flows

    generators -> feeder network -> step-up transformer -> pylon line -> step-down transformer -> distribution network -> consumers

The vanilla poles are hidden and replaced by **pole classes**. A class only wires to itself, so the networks of different classes can only be joined by **transformers**.

## Pole classes

Five classes, six tiers each (30 poles):

| Class | Poles | Footprint | Supply area (tier 1 -> 6) | Wire reach (tier 1 -> 6) |
|---|---|---|---|---|
| Feeder | `pc-feeder-N` | 2x2 | 6 -> 16 | 16 -> 36 |
| Pylon | `pc-pylon-N` | 1x1 | none | 40 -> 64 |
| Distribution (large) | `pc-distribution-large-N` | 2x2 | 10 -> 30 | = area |
| Distribution (small) | `pc-distribution-small-N` | 1x1 | 5 -> 15 | = area + 2 |
| Auxiliary | `pc-aux-N` | 1x1 | 3 -> 7 | 6 -> 16 |

Vanilla poles are hidden (prototypes kept, recipes and tech unlocks removed). One technology per tier (`pc-poles-1...6`); tier 1 unlocks by crafting copper cable.

### Rules

* **Own class only.** A wire to another class or to a foreign pole is cut with a warning.
* **Feeder** supply areas may not touch consumers. **Distribution** areas may not touch producers. **Pylons** have no supply area. **Aux** may touch anything except transformers, and only wires to aux.
* Solar panels, accumulators, electric energy interfaces and poles are neutral.
* **Network size is capped by pole count** (weakest tier in the network decides): feeder 16/24/36/52/72/96, distribution 24/36/52/72/96/128, aux 8/12/16/24/32/48. Pylon lines have only a performance guard (400). There is no power cap; transformers limit throughput.
* **Transformer outputs:** feeder networks accept unlimited inputs and no outputs; pylon lines and distribution networks accept unlimited inputs and at most **2 outputs**. That caps a line to twice the rating of its biggest transformer.
* Holding a pole draws red zones where it may not be placed (per-player settings).

### Wiring

Engine auto-connection is off. The mod wires new poles itself (setting `pc-autowire-mode`):

* **chain** (default): connect to the previous pole you placed, then fill up to the class's auto-connection count (feeder 1, pylon 1, distribution 2, aux 1) from nearby line ends. Never merges networks beyond their cap.
* **nearest**: skip the chain step. **off**: never wire.
* **ALT + L** (`pc-break-line`): the next pole starts a new, unwired line, which is how you run parallel lines.
* **Pole wire tool** (shortcut): select = audit (cut illegal wires, mark placement conflicts); ALT-select = rewire the selection as a spanning forest.

Max wires per pole: feeder 6, pylon 4, distribution 6, aux 6.

## Transformers

Two kinds, **step-up** and **step-down**, each in 3 sizes (small, medium, large) and 6 tiers. Capacity doubles per size step and grows x5 per tier, from 625 kW (small, tier 1) to 7.8125 GW (large, tier 6). One technology per tier (`pt-transformer-t1...6`) unlocks every kind and size of that tier.

| Kind | Input end | Output end |
|---|---|---|
| Step-up | feeder pole | pylon |
| Step-down | pylon | distribution pole (large or small) |

* **One entity each.** A transformer is a single 4x2 building (2x4 when turned sideways). It can be blueprinted and upgraded with the upgrade planner or fast replace, which advances the tier and keeps the size and the direction.
* **Ports.** Each end has a hidden pole, its *port*, of the matching class: `pc-port-feeder-in`, `pc-port-pylon-out`, `pc-port-pylon-in`, `pc-port-distribution-out`. Poles of that class wire to the port like to any other pole (by hand, or automatically with the autowire modes above). Wires from any other class are cut. Ports reach 16 tiles, enough for every pole tier to connect from outside its own supply area.
* **Not inside a pole's supply area.** A transformer cannot be built, ghosted or rotated into the supply area of **any** electric pole (all pole classes, hidden vanilla poles and poles of other mods; pole ghosts count). The other way round, a pole of this mod cannot be placed with a supply area that touches a transformer. While a transformer is held, the supply areas of nearby poles are drawn.
* **Rotation.** The input is one end of the building, the output the other end. See [Rotation](#rotation).
* **Tooltip** shows the maximum output power, the idle loss and the conversion loss (and, for heat tiers, the cooling load and the explosion temperature).
* **Circuit network.** Connect a circuit wire to the transformer to read `pt-load` (delivered output, % of rated), `pt-power` (kW) and, for heat tiers, `pt-temperature` (degrees C). The values are updated every update interval and only written when they change.

### Rotation

* **Holding the item:** R rotates it like any other building, in 90 degree steps. The building turns between 4x2 and 2x4 tiles.
* **Placed:** R (Shift+R for the other way) rotates it the same way, as long as the turned footprint is free and does not newly reach into a pole's supply area.
* The two hidden energy halves and the two ports are moved to the matching ends. The halves keep the energy they had, so rotating never creates or destroys energy. The wires of the ports go with them; wires that no longer reach are dropped, and the rest is checked against the pole rules again.
* Blueprints store the direction, and rotating a blueprint rotates the transformers in it. Fast replace and the upgrade planner keep the direction.

Facing north (default), the input is on the left (west) end and the output on the right (east) end. Every other direction is that layout turned clockwise:

| Direction | Footprint | Input end | Output end |
|---|---|---|---|
| north | 4x2 | left | right |
| east | 2x4 | top | bottom |
| south | 4x2 | right | left |
| west | 2x4 | bottom | top |

### Losses

| Loss | How it works |
|---|---|
| Idle | Constant, drawn from the input network at all times (the engine drain of the input half). |
| Conversion | Grows with the square of the load: `(full_w - idle_w) * load^2`. Applied by the script on every transfer. |

Total loss at a given load: `loss = idle_w + (full_w - idle_w) * (load / capacity_w)^2`.

- **Maximum output power** is the value in the tooltip. It is a hard engine cap (the output flow limit of the output half).
- **Maximum input power** is the maximum output plus the total loss at full load (`capacity_w + full_w`).
- The tooltip's conversion loss is the additional loss at 100 % load, as a percentage of the rated output.
- Bigger sizes have a higher absolute idle loss but a lower loss at full load, so small transformers are more efficient at low load and large ones under load.
- Every tier removes another 12.5 % of the tier-1 loss fractions (multiplier 1.0, 0.875, 0.75, 0.625, 0.5, 0.375).

Rated output, idle loss, total loss at full load and the resulting efficiency at full load (all editable in `config.lua`):

| Tier | Small | Medium | Large |
|---|---|---|---|
| 1 | 625 kW, idle 6.25 kW, 9 %, 91.7 % | 1.25 MW, idle 18.75 kW, 6 %, 94.3 % | 2.5 MW, idle 50 kW, 4 %, 96.2 % |
| 2 | 3.125 MW, idle 27.3 kW, 7.88 %, 92.7 % | 6.25 MW, idle 82.0 kW, 5.25 %, 95.0 % | 12.5 MW, idle 218.8 kW, 3.5 %, 96.6 % |
| 3 | 15.625 MW, idle 117.2 kW, 6.75 %, 93.7 % | 31.25 MW, idle 351.6 kW, 4.5 %, 95.7 % | 62.5 MW, idle 937.5 kW, 3 %, 97.1 % |
| 4 | 78.125 MW, idle 488.3 kW, 5.62 %, 94.7 % | 156.25 MW, idle 1.465 MW, 3.75 %, 96.4 % | 312.5 MW, idle 3.906 MW, 2.5 %, 97.6 % |
| 5 | 390.625 MW, idle 1.953 MW, 4.5 %, 95.7 % | 781.25 MW, idle 5.859 MW, 3 %, 97.1 % | 1.5625 GW, idle 15.625 MW, 2 %, 98.0 % |
| 6 | 1.953 GW, idle 7.324 MW, 3.38 %, 96.7 % | 3.906 GW, idle 21.97 MW, 2.25 %, 97.8 % | 7.8125 GW, idle 58.59 MW, 1.5 %, 98.5 % |

Each cell reads: rated output, idle loss, total loss at full load as a percentage of rated output, efficiency at full load.

### Heat (tiers 3 and 4)

Tier 3 and 4 transformers have a temperature. The losses heat them; passive cooling holds a transformer up to 50 % load, above that it needs heat pipes on its long sides. An alert is raised at 70 % of the way to the explosion temperature (300 degrees C for tier 3, 400 for tier 4); at the explosion temperature the transformer explodes and damages its surroundings (runtime setting `pt-explosions`). Full load without any cooling takes 120 s from ambient to explosion. All numbers are in `config.lua` (`C.heat`).

## Settings

| Setting | Type | Default | Effect |
|---|---|---|---|
| `pt-update-interval` | startup | 10 ticks (1-60) | Ticks between two transfer updates of a transformer. Higher is cheaper but makes the buffers larger (handled automatically). |
| `pt-explosions` | runtime, global | on | Whether heat-tier transformers explode. When off they still heat up and raise alerts. |
| `pc-network-cap-multiplier` | startup | 1 (0.25-10) | Scales the pole-count cap of every network. |
| `pc-enforce-script-built` | startup | off | Makes entities built by other mods' scripts obey the placement rules (default: warn only). |
| `pc-autowire-mode` | per player | chain | chain / nearest / off. |
| `pc-show-zones`, `pc-zone-radius` | per player | on, 40 | Red zones while holding a pole. |

`config.lua` holds every other number: transformer tiers, loss and heat model, port geometry and reach, and (under `C.pole`) pole areas, reach, caps, degrees and output limits.

## How it works

Every transformer is made of these entities:

- a visible **shell**, a constant combinator (the building, with item, blueprint, upgrade, direction and circuit support; the script owns its signals),
- a hidden **input half**, a buffered consumer whose drain is the idle loss,
- a hidden **output half**, a buffered producer whose output flow limit is the rated power,
- two hidden **ports**, poles of the class of that end, on the halves,
- for heat tiers, a hidden **heat pipe** that owns the temperature.

The halves and ports sit on the two ends of the shell, 1.8 tiles from its centre along the long axis (`half_offset` in `config.lua`). A port's supply area (0.15) covers only the half at its end, so the port's network is connected to that half and nothing else.

The engine does the idle drain, power cap and buffering. A script moves energy from the input buffer to the output buffer once every N ticks (N = update interval): it tops the output buffer up to full, takes that amount plus the conversion loss from the input buffer, and scales both down if the input cannot pay. The transformers are split into N buckets, so each tick services about 1/N of them. Buffers are sized to carry a transformer through one update interval with a 1.1x safety factor (`buffer_safety`), so there are no brownouts between updates.

**UPS.** The pole classes have no `on_tick` handler: build events are filtered by name, and the two high-frequency events (hover, position) are registered only while a player holds a wire or a pole. Network walks stop as soon as the cap is exceeded. The transformers cost one bucket per tick, and the held-transformer overlay runs only while a transformer is held.

**Events.** Both parts share one event bus (`scripts/bus.lua`), which registers each event with the engine once and runs every module's handler for it.

## Integration with other mods

A mod that adds its own transformers or poles can classify its entities with a `mod-data` prototype named `pole-classes-config...` (data stage): `{ consumers = {...}, producers = {...}, neutral = {...}, transformers = {...}, ports = { [pole] = { class = ..., role = "in"|"out" } } }`. The remote interface `pole-classes` offers `get_pole_info`, `get_network_stats`, `validate_pole`, `is_transformer` and `can_place_pole(surface, position, name)`.

## Known limitations

- Rotation is followed only when a player rotates a transformer. If another mod changes the direction by script, the halves and ports stay on the old ends until the transformer is rebuilt.
- A pole of another mod that is built next to an existing transformer is not refused (only wires from it to a port are cut); transformers themselves obey the supply-area rule for every pole.
- `rewire_neighbours_when_destroying` is off: removing a mid-line pole splits the line.
- Power switches count as foreign. Fast-replacing to a lower tier can strip wires if the cap is exceeded.
- There is no wire event in the API; hand-placed wires are detected via hover/cursor changes and are validated when the player stops holding the wire.
- The graphics, recipes and technology prerequisites are placeholders.

## Verification status

The data stage and the runtime load were exercised against a stubbed Factorio API (syntax, prototype generation, locale keys, event registration). **Not yet tested in a real game.** In-game spikes to do first:

1. Is `supply_area_distance = 0` legal for pylons? (0.5 is used: `PYLON_SUPPLY_DISTANCE`.)
2. Is `maximum_wire_distance = 64` accepted?
3. Do `ghost_name` event filters work on `on_built_entity`?
4. Do wire items have the names `copper-cable`/`red-wire`/`green-wire`/`copper-wire` (`scripts/poles/held.lua`)?
5. `on_selected_entity_changed` provides `last_entity`?
6. `ItemToPlace` field name (`name` vs `item`), `entity.mine{inventory}`, `create_local_flying_text` arguments.
7. Selection tool `mode = "any-entity"` and `cursor_box_type = "entity"` flags.
8. Undo/redo action layout (handler is best-effort and wrapped in `pcall`).
9. Whether blueprint wires exist at build time (affects the "already wired" autowire skip).
10. Profile the cap BFS on a large base.
11. Can a port wire reach a pole of every tier from outside the pole's supply area (port reach 16, large distribution tier 6 needs 15.1)?
12. Does a 0.15 supply area connect the port to the half at its end (and to nothing else), including with end-to-end transformers?
13. Do `type` filters combine with `name` / `ghost_name` filters (as OR) in the combined build filters of `scripts/bus.lua`?

## Graphics

Sprites live in `graphics/entity/`. For every transformer there is a north sprite `pt-<kind>-<size>-t<tier>.png` (256x128 px: input left, output right) and three rotated copies with the suffixes `-east` (128x256), `-south` (256x128) and `-west` (128x256). The rotated copies are generated from the north sprite:

    pip install pillow
    python3 make_rotated_graphics.py <path to the mod folder>

Run it again whenever the north sprites change.

## Files

- `info.json`, `settings.lua`, `data.lua`, `data-final-fixes.lua` (classifies entities, hides vanilla poles)
- `config.lua`: transformer tiers, loss and heat model, port constants and `C.pole` (pole classes), shared by both stages
- `recipes.lua`, `technologies.lua`, `sprites.lua`: transformer generators
- `prototypes/`: `poles.lua`, `ports.lua`, `pole-items.lua`, `pole-technology.lua`, `wire-tool.lua`, `item-exists.lua` (pole classes), `transformers.lua` (all transformer prototypes)
- `control.lua`: loads the runtime modules into the event bus
- `scripts/bus.lua`: event bus
- `scripts/transformer/`: `common`, `supply`, `ports`, `helpers`, `circuit`, `registry`, `heat`, `transfer`, `placement`, `overlay`
- `scripts/poles/`: `lookup`, `state`, `graph`, `placement`, `wires`, `autowire`, `zones`, `tools`, `held`, `notify`, `events`
- `locale/en/`: `pylon-transformers.cfg`, `pole-classes.cfg`
- `graphics/`: icons, technology icons and entity sprites
- `make_rotated_graphics.py`, `generate_placeholders.py`: graphics tools
- `prototype-api.json`, `runtime-api.json`: latest factorio modding apis
