# Pole Classes (Factorio 2.1)

Replaces the four vanilla poles with **five pole classes, six tiers each** (30 poles). Classes only
connect to themselves; transformers (from a separate mod) bridge them.

| Class | Poles | Footprint | Supply area (tier 1 → 6) | Wire reach (tier 1 → 6) |
|---|---|---|---|---|
| Feeder | `pc-feeder-N` | 2×2 | 6 → 16 | 16 → 36 |
| Pylon | `pc-pylon-N` | 1×1 | none | 40 → 64 |
| Distribution (large) | `pc-distribution-large-N` | 2×2 | 10 → 30 | = area |
| Distribution (small) | `pc-distribution-small-N` | 1×1 | 5 → 15 | = area + 2 |
| Auxiliary | `pc-aux-N` | 1×1 | 3 → 7 | 6 → 16 |

Vanilla poles are hidden (prototypes kept, recipes and tech unlocks removed). One technology per tier
(`pc-poles-1…6`); tier 1 unlocks by crafting copper cable.

## Rules

* **Own class only.** A wire to another class or to a foreign pole is cut with a warning.
* **Feeder** supply areas may not touch consumers. **Distribution** areas may not touch producers.
  **Pylons** have no supply area. **Aux** may touch anything except transformers, and only wires to aux.
* Solar panels, accumulators, electric energy interfaces and poles are neutral.
* Transformers may not stand inside any pole's supply area.
* **Network size is capped by pole count** (weakest tier in the network decides):
  feeder 16/24/36/52/72/96, distribution 24/36/52/72/96/128, aux 8/12/16/24/32/48. Pylon lines have only
  a performance guard (400). There is no power cap; transformers limit throughput.
* **Transformer outputs:** feeder networks accept unlimited inputs and no outputs; pylon lines and
  distribution networks accept unlimited inputs and at most **2 outputs**.
* Holding a pole draws red zones where it may not be placed (per-player settings).

## Wiring

Engine auto-connection is off. The mod wires new poles itself (setting `pc-autowire-mode`):

* **chain** (default): connect to the previous pole you placed, then fill up to the class's auto-connection
  count (feeder 1, pylon 1, distribution 2, aux 1) from nearby line ends. Never merges networks beyond their cap.
* **nearest**: skip the chain step. **off**: never wire.
* **ALT + L** (`pc-break-line`): the next pole starts a new, unwired line — this is how you run parallel lines.
* **Pole wire tool** (shortcut): select = audit (cut illegal wires, mark placement conflicts);
  ALT-select = rewire the selection as a spanning forest.

Max wires per pole: feeder 6, pylon 4, distribution 6, aux 6.

## UPS

No `on_tick` handler. Build events are filtered by name. Two high-frequency events (hover, position) are
registered only while a player holds a wire or a pole. Network walks stop as soon as the cap is exceeded.

## Tuning

`shared.lua` holds every number (areas, reach, caps, degrees, output limits). Startup setting
`pc-network-cap-multiplier` scales all caps; `pc-enforce-script-built` makes script-built entities obey the
placement rules (default: warn only).

## Integration with a transformer mod

1. Classify entities via a `mod-data` prototype named `pole-classes-config…` (data stage):
   `{ consumers = {…}, producers = {…}, neutral = {…}, transformers = {…}, ports = { [pole] = {class=, role="in"|"out"} } }`.
2. Hidden port poles are provided: `pc-port-feeder-in`, `pc-port-pylon-out`, `pc-port-pylon-in`,
   `pc-port-distribution-out` (step-up = feeder-in + pylon-out; step-down = pylon-in + distribution-out).
3. Create ports with `script_raised_built` (or call `validate_pole`) so they are registered and validated.
4. Remote interface `pole-classes`: `get_pole_info`, `get_network_stats`, `validate_pole`, `is_transformer`,
   `can_place_pole(surface, position, name)`. Ports are never rejected on build (that would leave a broken
   transformer), so check each port position with `can_place_pole` before placing the transformer.

## Known limitations

* `rewire_neighbours_when_destroying` is off: removing a mid-line pole splits the line.
* Power switches count as foreign. Fast-replacing to a lower tier can strip wires if the cap is exceeded.
* There is no wire event in the API; hand-placed wires are detected via hover/cursor changes and are
  validated when the player stops holding the wire.

## Verification status

Data stage and runtime logic were exercised against a stubbed Factorio API (`tests/`, run with `texlua`):
**not yet tested in a real game.** In-game spikes to do first:

1. Is `supply_area_distance = 0` legal for pylons? (0.5 is used: `PYLON_SUPPLY_DISTANCE`.)
2. Is `maximum_wire_distance = 64` accepted?
3. Do `ghost_name` event filters work on `on_built_entity`?
4. Do wire items have the names `copper-cable`/`red-wire`/`green-wire`/`copper-wire` (`scripts/held.lua`)?
5. `on_selected_entity_changed` provides `last_entity`?
6. `ItemToPlace` field name (`name` vs `item`), `entity.mine{inventory}`, `create_local_flying_text` arguments.
7. Selection tool `mode = "any-entity"` and `cursor_box_type = "entity"` flags.
8. Undo/redo action layout (handler is best-effort and wrapped in `pcall`).
9. Whether blueprint wires exist at build time (affects the "already wired" autowire skip).
10. Profile the cap BFS on a large base.
