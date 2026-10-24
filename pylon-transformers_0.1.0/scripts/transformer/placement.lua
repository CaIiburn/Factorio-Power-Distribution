-- Placement rule (a transformer may not stand in the supply area of any power pole) and the
-- events that put a transformer into the world or change it: build, clone, rotate, settings paste.
--
-- The rule is checked here, for every electric pole of every mod (see supply.lua). The opposite
-- direction, a new pole whose supply area would touch a transformer, is part of the pole rules
-- (scripts/poles/placement.lua): transformers are on the list of entities a pole may not cover.
local Common = require("__pylon-transformers__.scripts.transformer.common")
local Supply = require("__pylon-transformers__.scripts.transformer.supply")
local Helpers = require("__pylon-transformers__.scripts.transformer.helpers")
local Circuit = require("__pylon-transformers__.scripts.transformer.circuit")
local Registry = require("__pylon-transformers__.scripts.transformer.registry")

local shells, hidden_names = Common.shells, Common.hidden_names
local find_covering_pole = Supply.find_covering_pole
local register = Registry.register

-- Tells the player (flying text) or, without a player, the force (chat message with a map tag).
local function notify(player, force, surface, pos, message)
  if player and player.valid then
    player.create_local_flying_text{ text = message, position = pos }
  else
    force.print({ "", message, " ", string.format("[gps=%d,%d,%s]", pos.x, pos.y, surface.name) })
  end
end

-- Undoes a build: the entity (or ghost) disappears and the item goes back to the player, or onto
-- the ground when the player's inventory is full or a robot / script built it.
local function reject_build(entity, event)
  local surface, pos, force = entity.surface, entity.position, entity.force
  local is_ghost = entity.type == "entity-ghost"
  local item = is_ghost and entity.ghost_name or entity.name
  local quality = entity.quality.name
  local player = event.player_index and game.get_player(event.player_index) or nil

  entity.destroy()
  notify(player, force, surface, pos, { "pt-message.in-pole-area" })
  if is_ghost then return end

  local stack = { name = item, count = 1, quality = quality }
  if player and player.valid and player.insert(stack) >= 1 then return end
  surface.create_entity{ name = "item-on-ground", position = pos, stack = stack }
end

-- Cloning (e.g. surface.clone_area, space platform tools) may copy the hidden helpers too.
-- Helpers are always created by this script, so cloned ones are dropped and the cloned shell
-- gets its own set.
local function on_cloned(entity)
  if hidden_names[entity.name] then
    entity.destroy()
  elseif shells[entity.name] then
    register(entity)
  end
end

-- A transformer (or its ghost) was built or cloned. `source` is "player", "robot", "platform" or
-- "script", see bus.lua.
local function on_built(event)
  if event.destination then
    if event.destination.valid then on_cloned(event.destination) end
    return
  end

  local entity = event.entity
  if not (entity and entity.valid) then return end
  local name = entity.name

  -- A transformer ghost is refused right away where the real thing could not be built.
  if name == "entity-ghost" then
    if shells[entity.ghost_name]
       and find_covering_pole(entity.surface, entity.position, entity.direction) then
      reject_build(entity, event)
    end
    return
  end

  if not shells[name] then return end

  if find_covering_pole(entity.surface, entity.position, entity.direction) then
    reject_build(entity, event)
    return
  end
  register(entity)
end

-- Settings pasted onto a transformer would overwrite its signals: wipe them and rewrite.
local function on_entity_settings_pasted(event)
  local entity = event.destination
  if not (entity and entity.valid and shells[entity.name]) then return end

  local rec = storage.transformers[entity.unit_number]
  if rec then Circuit.init(rec) end
end

-- A player rotated a placed transformer (R / Shift+R): move the helpers to the ends that match the
-- new direction. Placing a transformer with a direction (cursor, blueprint, fast replace) does not
-- need this, because register() creates the helpers for the direction it is built with.
local function on_player_rotated_entity(event)
  local entity = event.entity
  if not (entity and entity.valid and shells[entity.name]) then return end

  -- The turned footprint must not newly reach into a pole's supply area. A transformer that is
  -- already inside one (a pole built next to it later) can still be rotated.
  if not find_covering_pole(entity.surface, entity.position, event.previous_direction)
     and find_covering_pole(entity.surface, entity.position, entity.direction) then
    entity.direction = event.previous_direction
    notify(game.get_player(event.player_index), entity.force, entity.surface, entity.position,
      { "pt-message.in-pole-area" })
    return
  end

  local rec = storage.transformers[entity.unit_number]
  if rec then Helpers.rebuild(rec, event.player_index) end
end

-- Names the build events are filtered for: the shells (and their ghosts), and every hidden helper,
-- so that cloned helpers can be dropped.
local names, ghost_names = {}, {}
for name in pairs(shells) do
  names[#names + 1] = name
  ghost_names[#ghost_names + 1] = name
end
for name in pairs(hidden_names) do names[#names + 1] = name end
table.sort(names)
table.sort(ghost_names)

return {
  build = { handler = on_built, names = names, ghost_names = ghost_names },
  events = {
    [defines.events.on_entity_settings_pasted] = on_entity_settings_pasted,
    [defines.events.on_player_rotated_entity] = on_player_rotated_entity,
  },
}
