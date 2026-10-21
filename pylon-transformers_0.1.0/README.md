# Pylon Transformers

Power transformers for Factorio. Power flows

    generating network -> step-up transformer -> pylon line -> step-down transformer -> consuming network

Each network is built from ordinary vanilla power poles. The pylon line in the middle is a separate pole network that only connects through the transformers.

## What the player gets

- **Two transformers:** step-up and step-down, each in 3 sizes (small, medium, large) and 6 tiers. Capacity doubles per size step and grows x5 per tier, from 625 kW (small, tier 1) to 7.8125 GW (large, tier 6). See the table below.
- **One entity each.** A transformer is a single 4x2 building (2x4 when turned sideways). It can be blueprinted and upgraded with the upgrade planner or fast replace, which advances the tier and keeps the size and the direction.
- **Rotation.** The input is one end of the building, the output the other end. See [Rotation](#rotation).
- **Tooltip** shows the maximum output power, the idle loss and the conversion loss.
- **Technologies:** one per tier, unlocking the recipes of that tier.

Step-up and step-down currently behave identically; they differ in name, description and item order only.

## Rotation

- **Holding the item:** R rotates it like any other building, in 90 degree steps. The building turns between 4x2 and 2x4 tiles.
- **Placed:** R (Shift+R for the other way) rotates it the same way, as long as the turned footprint is free.
- The two hidden energy halves are moved to the matching ends and keep the energy they had, so rotating never creates or destroys energy. The halves connect to poles through the poles' supply areas, so after a rotation the input and output may be covered by different poles than before. Check the connections.
- Blueprints store the direction, and rotating a blueprint rotates the transformers in it. Fast replace and the upgrade planner keep the direction.

Facing north (default), the input is on the left (west) end and the output on the right (east) end. Every other direction is that layout turned clockwise:

| Direction | Footprint | Input end | Output end |
|---|---|---|---|
| north | 4x2 | left | right |
| east | 2x4 | top | bottom |
| south | 4x2 | right | left |
| west | 2x4 | bottom | top |

## Losses

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

## Mod setting

**Transformer update interval** (startup, 1-60 ticks, default 10). Higher values are cheaper but make the buffers larger; this is handled automatically. Changing it needs a restart.

## How it works

Every transformer is made of three entities:

- a visible shell (a `simple-entity-with-owner`: the building, with item, blueprint, upgrade and direction support),
- a hidden **input half**, a buffered consumer whose drain is the idle loss,
- a hidden **output half**, a buffered producer whose output flow limit is the rated power.

The halves sit on the two ends of the shell, 1.8 tiles from its center along the long axis (`half_offset` in `config.lua`), so the poles of the two networks connect to them by their normal supply areas.

The engine does the idle drain, power cap and buffering. A script moves energy from the input buffer to the output buffer once every N ticks (N = update interval): it tops the output buffer up to full, takes that amount plus the conversion loss from the input buffer, and scales both down if the input cannot pay. The transformers are split into N buckets, so each tick services about 1/N of them.

Buffers are sized to carry a transformer through one update interval with a 1.1x safety factor (`buffer_safety`), so there are no brownouts between updates. The input flow limit is the rated output plus the total loss at full load.

How rotation works:

- The shell prototype is rotatable (no `not-rotatable` flag), so the engine rotates it in 90 degree steps and its collision box turns with it. It has one sprite per direction.
- When a shell is built, the script creates the halves on the ends that match the direction it was built with. This covers the cursor, blueprints, fast replace and robots.
- When a player rotates a placed transformer, `on_player_rotated_entity` fires and the script recreates both halves on the matching ends, carrying over their stored energy.

## Known limitations

- The graphics, recipes and technology prerequisites are placeholders.
- Only rotation by a player is followed. If another mod changes the direction of a transformer by script, its halves stay on the old ends until the transformer is rebuilt.

## Graphics

Sprites live in `graphics/entity/`. For every transformer there is a north sprite `pt-<kind>-<size>-t<tier>.png` (256x128 px: input left, output right) and three rotated copies with the suffixes `-east` (128x256), `-south` (256x128) and `-west` (128x256). The rotated copies are generated from the north sprite:

    pip install pillow
    python3 tools/make_rotated_graphics.py <path to the mod folder>

Run it again whenever the north sprites change.

## Files

- `info.json`, `settings.lua`, `data.lua`
- `config.lua`: tiers and constants shared by both stages
- `recipes.lua`, `technologies.lua`: recipe and technology generators
- `prototypes/transformers.lua`: all prototypes (shells, halves, items, recipes)
- `control.lua`: runtime logic
- `locale/en/`: text
- `graphics/`: generated placeholder graphics
- `tools/make_rotated_graphics.py`: creates the rotated sprites
- `prototype-api.json`, `runtime-api.json`: latest factorio modding apis
