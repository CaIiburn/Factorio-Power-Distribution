local stacks = require("scripts.stacks")

stacks.register_events()

script.on_init(function() storage.ipp_stacks = {} end)
script.on_configuration_changed(function()
  storage.ipp_stacks = storage.ipp_stacks or {}
  storage.ipp = nil                      -- 0.1/0.2 saves: old turbine bookkeeping is no longer used
  stacks.rescan()
end)

commands.add_command("ipp-vent-list", { "ipp.cmd-vent-list-help" }, function(cmd)
  local out = game.get_player(cmd.player_index) or game
  for _, line in ipairs(stacks.vent_list_lines()) do out.print(line) end
end)
