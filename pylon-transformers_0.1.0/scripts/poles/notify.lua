-- Player-facing warnings. Printing is throttled per message type so that a
-- blueprint with hundreds of illegal poles does not flood the chat.
local N = {}

local THROTTLE_TICKS = 60
local RED = { r = 1, g = 0.35, b = 0.35 }

function N.gps(surface, position)
  return string.format("[gps=%d,%d,%s]", math.floor(position.x), math.floor(position.y), surface.name)
end

-- ctx = { player_index = n | nil, force = LuaForce | nil }
function N.warn(ctx, surface, position, message)
  local player = ctx and ctx.player_index and game.get_player(ctx.player_index)
  if player and not player.valid then player = nil end
  if player then
    player.create_local_flying_text{
      text = message, position = position, surface = surface, color = RED, time_to_live = 180,
    }
  end

  local key = (player and ("p" .. player.index) or ("f" .. (ctx and ctx.force and ctx.force.index or 0))) .. ":" .. tostring(message[1])
  local last = storage.last_notify[key]
  if last and game.tick - last < THROTTLE_TICKS then return end
  storage.last_notify[key] = game.tick

  if player then
    player.print(message, { color = RED })
  elseif ctx and ctx.force and ctx.force.valid then
    ctx.force.print(message, RED)
  end
end

return N
