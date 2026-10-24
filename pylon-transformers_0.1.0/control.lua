-- Pylon Transformers - runtime script.
--
-- One mod, two parts:
--
-- Pole classes (scripts/poles/): feeder, pylon, distribution and auxiliary poles in six tiers.
-- Poles only wire to their own class, supply areas may not touch the wrong kind of entity, and
-- networks have tier-scaled size caps. Everything is event driven.
--
-- Transformers (scripts/transformer/): every transformer is a visible "shell" entity (a constant
-- combinator) plus hidden helper entities:
--   * two electric-energy-interface halves (input and output, on opposite ends of the shell).
--     The engine handles idle drain, the output power cap and the buffers natively.
--   * two ports, one on each half: hidden poles of the pole class that belongs to that end.
--     Step-up: feeder port in, pylon port out. Step-down: pylon port in, distribution port out.
--     Their supply area only reaches the half at their end and they never wire themselves to
--     anything (auto_connect_up_to_n_wires = 0). They are the connection points to the outside
--     grid: the player wires them by hand, or new poles of the right class wire to them. Only
--     poles of the port's own class can be wired to it, so a transformer is the only bridge
--     between two classes. The script keeps the wires when the transformer is rotated.
--   * for heat tiers (config: C.heat.tiers) one hidden heat-pipe that owns the temperature and
--     lets ordinary heat pipes connect to the long sides of the transformer.
-- The transformer script only
--   (1) creates / destroys / repositions the helpers together with the shell,
--   (2) moves energy from the input buffer to the output buffer,
--   (3) writes load / power (/ temperature) to the shell's circuit signals,
--   (4) heats and cools heat-tier transformers, raises alerts and lets them explode,
--   (5) refuses to build / rotate a transformer into the supply area of any power pole,
--   (6) shows the supply areas of nearby electric poles while a transformer is held.
--
-- Layout (all under scripts/, each file is a module required by the ones below it):
--   bus.lua            event bus: registers every handler with the engine once
--   transformer/
--     common.lua       constants and lookup tables built from config.lua
--     supply.lua       pole supply areas, find_covering_pole()
--     ports.lua        registering ports, keeping their wires across a rotation
--     port_wires.lua   wires of the ports for new transformers: autowire, blueprint / ghost tags
--     helpers.lua      the hidden entities: HELPERS spec list, ensure / destroy / rebuild
--     circuit.lua      circuit signals of the shell
--     registry.lua     storage, buckets, register / unregister, init and migration
--     heat.lua         temperature, alerts, explosion
--     transfer.lua     energy transfer and the on_tick bucket scheduler
--     placement.lua    placement rule and the build / clone / rotate / paste events
--     overlay.lua      supply-area overlay while a transformer is held
--   poles/
--     lookup.lua       static tables: classes, ports, restricted entities
--     state.lua        what is saved in storage
--     graph.lua        reading the copper-wire graph, network size and transformer outputs
--     placement.lua    supply-area rules for poles and the entities they may not cover
--     wires.lua        wire validation, cutting illegal wires
--     autowire.lua     automatic wiring of new poles
--     zones.lua        red areas while a pole is held
--     tools.lua        the pole wire tool
--     held.lua         what a player holds
--     notify.lua       player warnings
--     events.lua       the events of the pole classes and their remote interface
--
-- Shared constants (tiers, offsets, loss and heat limits, pole classes) come from config.lua,
-- which is also used by the data stage so both stages always agree.
--
-- The bus runs on_init / on_load / on_configuration_changed in the order below, so the transformer
-- registry goes first and storage exists for the others. The transformer placement comes before
-- the pole events: for entities that both care about (cloned ports) it gets the first word. The
-- port wires come before them too: a new pole first gets the wires that ports are waiting for, and
-- the pole logic then leaves a pole that has wires alone.
local Bus = require("__pylon-transformers__.scripts.bus")

Bus.add_libraries{
  require("__pylon-transformers__.scripts.transformer.registry"),
  require("__pylon-transformers__.scripts.transformer.placement"),
  require("__pylon-transformers__.scripts.transformer.heat"),
  require("__pylon-transformers__.scripts.transformer.transfer"),
  require("__pylon-transformers__.scripts.transformer.overlay"),
  require("__pylon-transformers__.scripts.transformer.port_wires").library,
  require("__pylon-transformers__.scripts.poles.events"),
}

Bus.install()
