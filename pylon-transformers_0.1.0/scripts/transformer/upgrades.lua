-- Keeping the kind and size when a transformer is upgraded or fast-replaced.
--
-- Only the item of C.item_kind / C.item_size (a small step-up transformer) can place a transformer,
-- so the upgrade planner can only build that one of the next tier (every shell's `next_upgrade` is
-- it, and all kinds and sizes share one fast replace group). The engine replaces the old
-- transformer with a new small step-up one, and this module gives it the kind and size the old one
-- had:
--   * the upgrade planner (robots or a player in the editor): the order is marked on the old shell,
--     so its kind and size are remembered then (on_marked_for_upgrade) until a transformer is built
--     there.
--   * fast replace by hand: the old shell under the cursor is looked at just before the build
--     (on_pre_build), and the next build of that player in the same tick gets them.
-- The build handler (placement.lua) asks with Upgrades.take() and swaps to them.
local Common = require("__pylon-transformers__.scripts.transformer.common")

local shells = Common.shells
local SHELL_NAMES = {}
for name in pairs(shells) do SHELL_NAMES[#SHELL_NAMES + 1] = name end
table.sort(SHELL_NAMES)

local Upgrades = {}

local function key_of(surface_index, position)
  return string.format("%d:%.2f:%.2f", surface_index, position.x, position.y)
end

-- The upgrade planner marked a transformer: remember its size for the one that replaces it.
local function on_marked_for_upgrade(event)
  local entity = event.entity
  if not (entity and entity.valid) then return end
  local info = shells[entity.name]
  if not info then return end
  local pending = storage.upgrade_sizes
  if not pending then pending = {}; storage.upgrade_sizes = pending end
  pending[key_of(entity.surface.index, entity.position)] = { size = info.size, kind = info.kind }
end

local function on_cancelled_upgrade(event)
  local entity = event.entity
  local pending = storage.upgrade_sizes
  if pending and entity and entity.valid and shells[entity.name] then
    pending[key_of(entity.surface.index, entity.position)] = nil
  end
end

-- A player is about to build with a transformer in the cursor: if a transformer stands where it
-- goes, the build is a fast replace and keeps that one's size.
local function on_pre_build(event)
  local player = game.get_player(event.player_index)
  if not player then return end
  local stack = player.cursor_stack
  if not (stack and stack.valid_for_read and shells[stack.name]) then return end
  local found = player.surface.find_entities_filtered{ position = event.position, name = SHELL_NAMES, limit = 1 }[1]
  local replaced = storage.fast_replaced
  if not replaced then replaced = {}; storage.fast_replaced = replaced end
  if found then
    local info = shells[found.name]
    replaced[event.player_index] = { key = key_of(player.surface.index, found.position),
                                     size = info.size, kind = info.kind, tick = event.tick }
  else
    replaced[event.player_index] = nil
  end
end

-- The size and kind the transformer that was just built has to take over, or nil. Each is given out
-- once. `event` is the build event.
function Upgrades.take(entity, event)
  local key = key_of(entity.surface.index, entity.position)

  local replaced = storage.fast_replaced
  local by_hand = replaced and event.player_index and replaced[event.player_index]
  if by_hand then
    replaced[event.player_index] = nil
    if by_hand.key == key and by_hand.tick == event.tick then return by_hand.size, by_hand.kind end
  end

  local pending = storage.upgrade_sizes
  local saved = pending and pending[key]
  if not saved then return nil end
  pending[key] = nil
  if type(saved) == "string" then return saved, nil end   -- (an entry of an earlier version: size only)
  return saved.size, saved.kind
end

return {
  take = Upgrades.take,
  events = {
    [defines.events.on_marked_for_upgrade] = on_marked_for_upgrade,
    [defines.events.on_cancelled_upgrade] = on_cancelled_upgrade,
    [defines.events.on_pre_build] = on_pre_build,
  },
}
