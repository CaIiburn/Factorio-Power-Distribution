-- Supply-area rules:
--   feeder / distribution / aux poles may not cover the entities their class forbids,
--   and the forbidden entities may not be built inside such an area.
local shared = require("shared")
local lookup = require("scripts.lookup")
local notify = require("scripts.notify")

local P = {}

local EPS = 0.01   -- overlaps shallower than this do not count as "touching"

function P.bbox(entity)
  local bb = entity.bounding_box
  local lt = bb.left_top or bb[1]
  local rb = bb.right_bottom or bb[2]
  return (lt.x or lt[1]), (lt.y or lt[2]), (rb.x or rb[1]), (rb.y or rb[2])
end

local function overlap(ax1, ay1, ax2, ay2, bx1, by1, bx2, by2)
  return ax1 < bx2 - EPS and bx1 < ax2 - EPS and ay1 < by2 - EPS and by1 < ay2 - EPS
end

-- Entity (or ghost) inside the supply area of the pole at `position`, or nil.
function P.pole_conflict(surface, position, info)
  if not info.has_area then return nil end
  local names = info.is_port and lookup.restricted_no_transformer[info.class]
                or lookup.restricted[info.class]
  if not names or #names == 0 then return nil end
  local d = info.distance
  local area = { { position.x - d + EPS, position.y - d + EPS },
                 { position.x + d - EPS, position.y + d - EPS } }
  local found = surface.find_entities_filtered{ area = area, name = names }
  if found[1] then return found[1] end
  found = surface.find_entities_filtered{ area = area, ghost_name = names }
  return found[1]
end

-- Pole (or pole ghost) whose supply area covers `entity`, or nil.
-- Returns pole, info.
function P.entity_conflict(entity, name)
  local classes = lookup.restricting[name]
  if not classes then return nil end
  local surface = entity.surface
  local x1, y1, x2, y2 = P.bbox(entity)
  local is_transformer = lookup.transformers[name]
  for _, class in ipairs(classes) do
    local half = lookup.max_half[class]
    local area = { { x1 - half, y1 - half }, { x2 + half, y2 + half } }
    local names = lookup.names_by_class[class]
    for pass = 1, 2 do
      local found
      if pass == 1 then
        found = surface.find_entities_filtered{ area = area, name = names }
      else
        found = surface.find_entities_filtered{ area = area, ghost_name = names }
      end
      for _, pole in ipairs(found) do
        local pname = pass == 1 and pole.name or pole.ghost_name
        local info = lookup.info(pname)
        -- A transformer's own port poles are meant to overlap it.
        if info and info.has_area and not (info.is_port and is_transformer) then
          local px, py, d = pole.position.x, pole.position.y, info.distance
          if overlap(x1, y1, x2, y2, px - d, py - d, px + d, py + d) then
            return pole, info
          end
        end
      end
    end
  end
  return nil
end

-- Removes a freshly built entity and gives the item back.
function P.reject(entity, ctx, message)
  local surface, pos = entity.surface, entity.position
  notify.warn(ctx, surface, pos, message)
  if ctx.warn_only then return false end

  if entity.type == "entity-ghost" then
    entity.destroy()
    return true
  end

  local proto = entity.prototype
  local place = proto and proto.items_to_place_this and proto.items_to_place_this[1]
  local item_name = place and (place.name or place.item)
  local quality = entity.quality and entity.quality.name

  local done = false
  if ctx.player_index then
    local player = game.get_player(ctx.player_index)
    if player and player.valid then
      local inv = player.get_main_inventory()
      if inv then done = entity.mine{ inventory = inv } end
    end
  end
  if not done and entity.valid then
    if item_name then
      surface.spill_item_stack{
        position = pos, stack = { name = item_name, count = 1, quality = quality },
        enable_looted = true,
      }
    end
    entity.destroy()
  end
  return true
end

-- Applies the placement rules to a built entity or ghost.
-- Returns true when the entity is still there afterwards.
function P.check_built(entity, name, ctx)
  local pinfo = lookup.pole[name]
  if pinfo and pinfo.has_area then
    local hit = P.pole_conflict(entity.surface, entity.position, pinfo)
    if hit then
      local hit_name = hit.type == "entity-ghost" and hit.ghost_name or hit.name
      local msg = { "pc.reject-pole", entity.localised_name or name,
                    hit.localised_name or hit_name, notify.gps(entity.surface, entity.position) }
      return not P.reject(entity, ctx, msg)
    end
    return true
  end

  if lookup.restricting[name] then
    local pole, info = P.entity_conflict(entity, name)
    if pole then
      local pole_name = info.name or pole.name
      local msg = { "pc.reject-entity", entity.localised_name or name,
                    pole.localised_name or pole_name, notify.gps(entity.surface, entity.position) }
      return not P.reject(entity, ctx, msg)
    end
  end
  return true
end

return P
