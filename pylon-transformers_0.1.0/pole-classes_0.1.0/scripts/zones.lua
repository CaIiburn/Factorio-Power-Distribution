-- Red "do not place here" areas drawn while a pole is held.
-- An entity that the held pole's class may not cover forbids every pole CENTRE
-- within one supply half-width of its bounding box, so that is what is drawn.
local lookup = require("scripts.lookup")
local placement = require("scripts.placement")
local state = require("scripts.state")

local Z = {}

local COLOR = { r = 0.6, g = 0.05, b = 0.05, a = 0.35 }
local MAX_RECTS = 600

function Z.clear(player_index)
  local st = state.player(player_index)
  if st.zone then
    for _, obj in ipairs(st.zone.objs) do
      if obj.valid then obj.destroy() end
    end
    st.zone = nil
  end
end

local function setting(player_index, name, default)
  local ok, value = pcall(function() return settings.get_player_settings(player_index)[name].value end)
  if ok and value ~= nil then return value end
  return default
end

function Z.show(player, info)
  local pi = player.index
  if not info.has_area or not setting(pi, "pc-show-zones", true) then
    Z.clear(pi)
    return
  end
  local radius = setting(pi, "pc-zone-radius", 40)
  local pos = player.position
  local st = state.player(pi)
  local z = st.zone
  if z and z.name == info.name and z.surface == player.surface.index then
    local dx, dy = z.center.x - pos.x, z.center.y - pos.y
    if dx * dx + dy * dy < (radius / 4) * (radius / 4) then return end
  end
  Z.clear(pi)

  local names = lookup.restricted[info.class]
  if not names or #names == 0 then return end
  local surface = player.surface
  local found = surface.find_entities_filtered{
    area = { { pos.x - radius, pos.y - radius }, { pos.x + radius, pos.y + radius } },
    name = names,
  }
  local d = info.distance
  local objs = {}
  for i, e in ipairs(found) do
    if i > MAX_RECTS then break end
    local x1, y1, x2, y2 = placement.bbox(e)
    objs[#objs + 1] = rendering.draw_rectangle{
      color = COLOR, filled = true,
      left_top = { x1 - d, y1 - d }, right_bottom = { x2 + d, y2 + d },
      surface = surface, players = { player }, draw_on_ground = true,
    }
  end
  st.zone = { name = info.name, center = { x = pos.x, y = pos.y }, surface = surface.index, objs = objs }
end

return Z
