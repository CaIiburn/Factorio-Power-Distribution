local stacks = require("scripts.stacks")
local reactors = require("scripts.reactors")
local heaters = require("scripts.heaters")
local breeders = require("scripts.breeders")
local events = require("scripts.events")

-- One registration per lifecycle event (the engine keeps a single handler per event): see scripts/events.lua
events.register { stacks.lifecycle, reactors.lifecycle, heaters.lifecycle, breeders.lifecycle }
stacks.register_events()
reactors.register_events()
heaters.register_events()
breeders.register_events()

script.on_init(function()
  storage.ipp_stacks = {}
  storage.ipp_reactors = {}
  storage.ipp_heaters = {}
  storage.ipp_channels = {}
end)
script.on_configuration_changed(function()
  storage.ipp_stacks = storage.ipp_stacks or {}
  storage.ipp_reactors = storage.ipp_reactors or {}
  storage.ipp_heaters = storage.ipp_heaters or {}
  storage.ipp_channels = storage.ipp_channels or {}
  storage.ipp = nil                      -- 0.1/0.2 saves: old turbine bookkeeping is no longer used
  stacks.rescan()
  reactors.rescan()
  heaters.rescan()
  breeders.rescan()
end)

commands.add_command("ipp-vent-list", { "ipp.cmd-vent-list-help" }, function(cmd)
  local out = game.get_player(cmd.player_index) or game
  for _, line in ipairs(stacks.vent_list_lines()) do out.print(line) end
end)

commands.add_command("ipp-reactor-debug", { "ipp.cmd-reactor-debug-help" }, function(cmd)
  local out = game.get_player(cmd.player_index) or game
  for _, line in ipairs(reactors.debug_lines()) do out.print(line) end
end)

commands.add_command("ipp-breeder-debug", { "ipp.cmd-breeder-debug-help" }, function(cmd)
  local out = game.get_player(cmd.player_index) or game
  for _, line in ipairs(breeders.debug_lines()) do out.print(line) end
end)
