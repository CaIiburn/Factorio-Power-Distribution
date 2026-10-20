# Pylon Transformers

One-directional power transformers for Factorio. Power flows

    generating network -> step-up transformer -> pylon line -> step-down transformer -> consuming network

Each network is built from ordinary vanilla power poles. The pylon line in the middle is a separate pole network that only connects through the transformers.

## What the player gets

- **Two transformers:** step-up and step-down, in three tiers (small 1 MW, medium 10 MW, large 100 MW).
- **One entity each.** A transformer is a single 4x2 building. It can be blueprinted and upgraded with the upgrade planner or fast replace (small -> medium -> large). The left side is the input, the right side is the output. It cannot be rotated yet.
- **Tooltip** shows the maximum output power, idle loss, conversion loss and (step-down) line loss per 1000 tiles.
- **Technologies:** Transformers (small / medium / large), unlocking both recipes of a tier.

## Losses

| Loss | Step-up | Step-down | How it works |
|---|---|---|---|
| Idle | yes | yes | Constant, drawn from the input network at all times. |
| Conversion | yes | yes | A fixed percentage of output power. |
| Line | no | yes | Grows with the wire distance along the pylon line between the step-down and the nearest step-up. |

- **Maximum output power** is the value in the tooltip. It is a hard engine cap.
- **Maximum input power** is the maximum output plus all losses.
- The input/output ratio is `1 + conversion + distance * line_per_tile`, capped at 2.5.

Default values (all editable in `config.lua`):

| Tier | Rated output | Idle loss | Conversion | Line loss per 1000 tiles |
|---|---|---|---|---|
| Small | 1 MW | 10 kW | 2 % | 50 % |
| Medium | 10 MW | 50 kW | 1.5 % | 20 % |
| Large | 100 MW | 300 kW | 1 % | 10 % |

## Placement rule

A step-down transformer can only be built on a pylon line that has a step-up transformer. Otherwise the build is cancelled and the item is returned to you (or dropped on the ground for robots and scripts). If a step-down loses its connection later, it stops delivering power until it is reconnected. Other placement restrictions are not implemented yet.

## Mod setting

**Transformer update interval** (startup, 1-60 ticks, default 10). Higher values are cheaper but make the buffers larger; this is handled automatically. Changing it needs a restart.

## How it works

Every transformer is made of three entities:

- a visible shell (the building, with item, blueprint and upgrade support),
- a hidden **input half**, a buffered consumer whose drain is the idle loss,
- a hidden **output half**, a buffered producer whose output flow limit is the rated power.

The engine does the idle drain, power cap and buffering. A script moves energy from the input buffer to the output buffer once every N ticks. Per update, a transformer costs 2 reads and 2 writes. The transformers are split into N buckets, so each tick services about 1/N of them.

The loss factor is computed once when the transformer is built. For a step-down, a Dijkstra search over copper wire connections finds the nearest step-up and its wire length. It is recomputed (debounced, not per tick) when a pole or a step-up is built or removed. Wires connected or cut by hand do not trigger a recompute.

Buffers are sized to carry a transformer through one update interval with a 2x safety factor, so there are no brownouts between updates. The input flow limit is 3x the rated output.

## Known limitations

- Using the editor's "delete all entities" can crash the update loop. Normal gameplay is not affected.
- The graphics, recipes and technology prerequisites are placeholders.
- Transformers cannot be rotated.
- Only the nearest step-up is used for line loss.

## Commands

`/pt-status` prints each step-down's wire distance, its input/output ratio and the transformer counts.

## Files

- `info.json`, `settings.lua`, `data.lua`
- `config.lua`: tiers and constants shared by both stages
- `prototypes/transformers.lua`: all prototypes
- `control.lua`: runtime logic
- `locale/en/`: text
- `graphics/`: generated placeholder graphics
