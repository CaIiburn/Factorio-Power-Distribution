-- Held-item overlay.
--
-- The engine only shows the supply areas of electric poles while the cursor holds an entity with an
-- electric energy source, which a transformer shell (a constant combinator) has not. So while a
-- transformer item (or its ghost) is in the cursor, the supply areas of the poles around the
-- player are drawn by script, visible to that player only. Those are exactly the areas a
-- transformer cannot be built in. Nothing runs while nobody holds a transformer.
local Common = require("__pylon-transformers__.scripts.transformer.common")
local Supply = require("__pylon-transformers__.scripts.transformer.supply")

local shells, hidden_names = Common.shells, Common.hidden_names
local supply_distance = Supply.supply_distance

-- Radius around the player that is searched for poles, and refresh interval in ticks.
local OVERLAY_RADIUS = 48
local OVERLAY_INTERVAL = 15
local OVERLAY_COLOR = { r = 0.08, g = 0.22, b = 0.35, a = 0.28 }

local function get_overlays()
  local overlays = storage.overlays
  if not overlays then
    overlays = {}
    storage.overlays = overlays
  end
  return overlays
end

local function holds_transformer(player)
  local stack = player.cursor_stack
  if stack and stack.valid_for_read and shells[stack.name] then return true end

  local ghost = player.cursor_ghost
  if ghost then
    local name = ghost.name
    if type(name) ~= "string" then name = name.name end
    return shells[name] ~= nil
  end
  return false
end

local function clear_overlay(player_index)
  local overlays = get_overlays()
  local overlay = overlays[player_index]
  if not overlay then return end
  for _, object in pairs(overlay.objects) do
    if object.valid then object.destroy() end
  end
  overlays[player_index] = nil
end

-- Brings the drawn rectangles in line with the poles around the player: draws the missing ones
-- and removes the ones whose pole is gone or out of range. Unchanged poles cost nothing.
local function refresh_overlay(player)
  local overlays = get_overlays()
  local overlay = overlays[player.index]
  if overlay and overlay.surface_index ~= player.surface_index then
    clear_overlay(player.index)
    overlay = nil
  end
  if not overlay then
    overlay = { surface_index = player.surface_index, objects = {} }
    overlays[player.index] = overlay
  end

  local surface = player.surface
  local seen = {}
  for _, pole in pairs(surface.find_entities_filtered{
    position = player.position, radius = OVERLAY_RADIUS, type = "electric-pole",
  }) do
    if not hidden_names[pole.name] then
      local id = pole.unit_number
      seen[id] = true
      if not overlay.objects[id] then
        local d = supply_distance(pole)
        local p = pole.position
        overlay.objects[id] = rendering.draw_rectangle{
          color = OVERLAY_COLOR,
          filled = true,
          left_top = { p.x - d, p.y - d },
          right_bottom = { p.x + d, p.y + d },
          surface = surface,
          players = { player },
          draw_on_ground = true,
        }
      end
    end
  end

  for id, object in pairs(overlay.objects) do
    if not seen[id] then
      if object.valid then object.destroy() end
      overlay.objects[id] = nil
    end
  end
end

local function on_cursor_stack_changed(event)
  local player = game.get_player(event.player_index)
  if not player then return end
  if holds_transformer(player) then
    refresh_overlay(player)
  else
    clear_overlay(player.index)
  end
end

local function on_overlay_tick()
  local overlays = storage.overlays
  if not overlays or next(overlays) == nil then return end

  for player_index in pairs(overlays) do
    local player = game.get_player(player_index)
    if player and player.valid and player.connected and holds_transformer(player) then
      refresh_overlay(player)
    else
      clear_overlay(player_index)
    end
  end
end

local function on_player_gone(event)
  clear_overlay(event.player_index)
end

return {
  events = {
    [defines.events.on_player_cursor_stack_changed] = on_cursor_stack_changed,
    [defines.events.on_player_left_game] = on_player_gone,
    [defines.events.on_player_removed] = on_player_gone,
  },
  on_nth_tick = {
    [OVERLAY_INTERVAL] = on_overlay_tick,
  },
}
