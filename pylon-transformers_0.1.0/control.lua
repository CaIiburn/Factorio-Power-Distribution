-- Pylon Transformers - runtime script.
--
-- Design: every transformer is a visible "shell" entity (a constant combinator) plus hidden
-- helper entities:
--   * two electric-energy-interface halves (input and output, on opposite ends of the shell).
--     The engine handles idle drain, the output power cap and the buffers natively.
--   * two small connection poles, one on each half. Their supply area only reaches the half at
--     their end and they never wire themselves to anything (auto_connect_up_to_n_wires = 0). They
--     are the connection points to the outside grid: the player wires them by hand. The script
--     keeps the wires when the transformer is rotated and cuts a wire that an auto-connecting
--     pole built nearby made to both ends of the same transformer.
--   * for heat tiers (config: C.heat.tiers) one hidden heat-pipe that owns the temperature and
--     lets ordinary heat pipes connect to the long sides of the transformer.
-- The script only
--   (1) creates / destroys / repositions the helpers together with the shell,
--   (2) moves energy from the input buffer to the output buffer,
--   (3) writes load / power (/ temperature) to the shell's circuit signals,
--   (4) heats and cools heat-tier transformers, raises alerts and lets them explode,
--   (5) refuses to build / rotate a transformer into the supply area of any electric pole,
--   (6) shows the supply areas of nearby electric poles while a transformer is held.
--
-- Layout (all under scripts/, each file is a module required by the ones below it):
--   common.lua     constants and lookup tables built from config.lua
--   supply.lua     pole supply areas, find_covering_pole()
--   wiring.lua     keeping / cutting wires of the connection poles
--   helpers.lua    the hidden entities: HELPERS spec list, ensure / destroy / rebuild
--   circuit.lua    circuit signals of the shell
--   registry.lua   storage, buckets, register / unregister, init and migration
--   heat.lua       temperature, alerts, explosion
--   transfer.lua   energy transfer and the on_tick bucket scheduler
--   placement.lua  placement rule and the build / clone / rotate / paste events
--   overlay.lua    supply-area overlay while a transformer is held
--
-- Shared constants (tiers, offsets, loss and heat limits) come from config.lua, which is also
-- used by the data stage so both stages always agree.
--
-- Events are registered by event_handler (a core lualib), which takes the `events`, `on_nth_tick`,
-- `on_init` and `on_configuration_changed` of each module. The order below is the order in which
-- on_init / on_configuration_changed run; registry goes first so storage exists for the others.
local handler = require("event_handler")

handler.add_libraries{
  require("__pylon-transformers__.scripts.registry"),
  require("__pylon-transformers__.scripts.placement"),
  require("__pylon-transformers__.scripts.heat"),
  require("__pylon-transformers__.scripts.transfer"),
  require("__pylon-transformers__.scripts.overlay"),
}
