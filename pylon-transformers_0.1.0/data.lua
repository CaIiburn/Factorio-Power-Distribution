-- Data stage entry point.
--   poles, ports, pole-items, pole-technology, wire-tool: the pole classes and their ports
--   transformers: all transformer prototypes (shells, halves, items, recipes, technologies)
--   radiator: the heat radiator for the heat-tier transformers (unlocked by the first heat tier)
-- data-final-fixes.lua classifies the entities of all mods and hides the vanilla poles.
--
-- Modules are required by their full name so they can never collide with a module of another mod
-- that is called "config" or the like.
require("__pylon-transformers__.prototypes.poles")
require("__pylon-transformers__.prototypes.ports")
require("__pylon-transformers__.prototypes.pole-items")
require("__pylon-transformers__.prototypes.pole-technology")
require("__pylon-transformers__.prototypes.wire-tool")
require("__pylon-transformers__.prototypes.transformers")
require("__pylon-transformers__.prototypes.radiator")
