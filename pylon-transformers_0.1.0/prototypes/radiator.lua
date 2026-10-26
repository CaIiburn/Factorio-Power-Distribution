-- The radiator: a 2x2 heat interface that removes a fixed amount of heat per tick from whatever
-- heat pipes (or heat-tier transformers) it is connected to. See C.radiator in config.lua.
--
-- Heat interface = the engine's infinity heat pipe. scripts/radiator.lua sets it to "at most
-- ambient" when it is built, so it is always at ambient, and the engine's own heat exchange does
-- the cooling: every tick it moves heat between two connected buffers until their temperatures
-- meet, so a connected pipe loses (T - ambient) * specific_heat of the radiator per tick. That
-- specific heat is the one number here (C.radiator.specific_heat, derived in config.lua from the
-- number of radiators a transformer is supposed to need). max_transfer is only set high enough to
-- stay out of the way.
local C = require("__pylon-transformers__.config")
local R = C.radiator

local ICON = "__pylon-transformers__/graphics/icons/pt-radiator.png"
local SPRITE = "__pylon-transformers__/graphics/entity/pt-radiator.png"
local SHADOW = "__pylon-transformers__/graphics/entity/pt-radiator-shadow.png"

-- One heat connection on each perimeter tile of the 2x2 body (8 of them), pointing outwards.
local function connections()
  local list = {}
  for _, x in ipairs({ -0.5, 0.5 }) do
    for _, y in ipairs({ -0.5, 0.5 }) do
      list[#list + 1] = { position = { x, y }, direction = (y < 0) and defines.direction.north or defines.direction.south }
      list[#list + 1] = { position = { x, y }, direction = (x < 0) and defines.direction.west or defines.direction.east }
    end
  end
  return list
end

data:extend({
  {
    type = "heat-interface",
    name = R.name,
    icon = ICON, icon_size = 128,
    flags = { "placeable-neutral", "player-creation" },
    minable = { mining_time = 0.3, result = R.name },
    max_health = R.max_health,
    collision_box = { { -0.85, -0.85 }, { 0.85, 0.85 } },
    selection_box = { { -1, -1 }, { 1, 1 } },
    heating_radius = 0,        -- it cools, it does not warm its surroundings
    gui_mode = "none",         -- the heat setting is the script's, not the player's
    heat_buffer = {
      max_temperature = R.max_temperature,
      default_temperature = C.heat.ambient,
      min_working_temperature = C.heat.ambient,
      specific_heat = string.format("%.6gJ", R.specific_heat),
      max_transfer = "1GW",
      connections = connections(),
    },
    picture = {
      layers = {
        { filename = SPRITE, width = 160, height = 192, scale = 0.5, shift = { 0, -0.5 }, priority = "high" },
        { filename = SHADOW, width = 160, height = 192, scale = 0.5, shift = { 0, -0.5 }, priority = "high",
          draw_as_shadow = true },
      },
    },
    custom_tooltip_fields = {
      { name = { "pt-tooltip.radiator-cooling" }, value = string.format("%.3g kW/°C", R.conductance / 1e3), order = 1 },
    },
  },
  {
    type = "item",
    name = R.name,
    icon = ICON, icon_size = 128,
    subgroup = "energy",
    order = "e[pt]-c[radiator]",
    place_result = R.name,
    stack_size = 20,
  },
  {
    type = "recipe",
    name = R.name,
    enabled = false,
    energy_required = 5,
    ingredients = {
      { type = "item", name = "heat-pipe", amount = 10 },
      { type = "item", name = "steel-plate", amount = 20 },
      { type = "item", name = "copper-plate", amount = 20 },
    },
    results = { { type = "item", name = R.name, amount = 1 } },
  },
})
