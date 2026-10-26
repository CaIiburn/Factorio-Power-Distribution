-- The radiator (prototypes/radiator.lua) is a heat interface, and a heat interface does nothing
-- useful until it is told what to do: "at most ambient" makes it take in whatever heat the connected
-- pipes have over ambient, and the engine's heat exchange with its small specific heat decides how
-- much per tick (see C.radiator in config.lua). Nothing else happens here: no polling, no storage.
local C = require("__pylon-transformers__.config")

local NAME = C.radiator.name
local SETTING = { temperature = C.heat.ambient, mode = "at-most" }

local function setup(entity)
  if entity and entity.valid and entity.name == NAME then
    entity.set_heat_setting(SETTING)
  end
end

-- A radiator was built, cloned or revived (player, robot, script, blueprint).
local function on_built(event)
  setup(event.destination or event.entity)
end

-- Radiators of an older version of the mod (or with other settings) get the current setting.
local function on_configuration_changed()
  for _, surface in pairs(game.surfaces) do
    for _, entity in pairs(surface.find_entities_filtered{ name = NAME }) do setup(entity) end
  end
end

return {
  build = { handler = on_built, names = { NAME } },
  on_configuration_changed = on_configuration_changed,
}
