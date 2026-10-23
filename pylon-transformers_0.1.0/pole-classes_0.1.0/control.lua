-- Pole Classes: runtime script.
-- Everything is event driven; there is no on_tick handler.  Two events that
-- fire often (hover changes, tile changes) are only registered while a player
-- actually holds a wire or a pole.
local shared = require("shared")
local lookup = require("scripts.lookup")
local state = require("scripts.state")
local graph = require("scripts.graph")
local placement = require("scripts.placement")
local wires = require("scripts.wires")
local autowire = require("scripts.autowire")
local zones = require("scripts.zones")
local tools = require("scripts.tools")
local held = require("scripts.held")

lookup.init()

-- ---------------------------------------------------------------------------
-- Builds
-- ---------------------------------------------------------------------------
local function enforce_script_builds()
  local s = settings.startup["pc-enforce-script-built"]
  return s and s.value
end

local function handle_built(event, source)
  local entity = event.entity or event.destination
  if not (entity and entity.valid) then return end
  local ghost = entity.type == "entity-ghost"
  local name = ghost and entity.ghost_name or entity.name

  local ctx = { player_index = event.player_index, force = entity.force, source = source }
  if source == "script" and not enforce_script_builds() then ctx.warn_only = true end

  if not placement.check_built(entity, name, ctx) then return end
  if ghost or not entity.valid then return end

  local info = lookup.info(name)
  if not info then return end
  script.register_on_object_destroyed(entity)
  autowire.on_built(entity, info, ctx)
end

local function register_build_events()
  local name_filters, full_filters = {}, {}
  for _, n in ipairs(lookup.watched) do
    name_filters[#name_filters + 1] = { filter = "name", name = n }
    full_filters[#full_filters + 1] = { filter = "name", name = n }
    full_filters[#full_filters + 1] = { filter = "ghost_name", name = n }
  end
  local specs = {
    { defines.events.on_built_entity, "player", full_filters },
    { defines.events.on_robot_built_entity, "robot", full_filters },
    { defines.events.on_space_platform_built_entity, "platform", full_filters },
    { defines.events.script_raised_built, "script", name_filters },
    { defines.events.script_raised_revive, "script", name_filters },
    { defines.events.on_entity_cloned, "script", name_filters },
  }
  for _, spec in ipairs(specs) do
    script.on_event(spec[1], function(e) handle_built(e, spec[2]) end, spec[3])
  end
end
register_build_events()

script.on_event(defines.events.on_blueprint_settings_pasted, function(e)
  local entity = e.entity
  if entity and entity.valid and entity.type ~= "entity-ghost" and lookup.info(entity.name) then
    wires.validate(entity, { player_index = e.player_index, force = entity.force })
  end
end)

script.on_event(defines.events.on_object_destroyed, function(e)
  if e.useful_id and storage.nbr then storage.nbr[e.useful_id] = nil end
end)

-- ---------------------------------------------------------------------------
-- Wires placed by hand.  There is no "wire added" event, so while a player holds
-- a wire the last two hovered entities are re-validated whenever the hover changes.
-- ---------------------------------------------------------------------------
local function validate_entity(entity, player_index)
  if entity and entity.valid and lookup.info(entity.name) then
    local player = game.get_player(player_index)
    wires.validate(entity, { player_index = player_index, force = player and player.force })
  end
end

local function on_selected_changed(e)
  local st = storage.players and storage.players[e.player_index]
  if not (st and st.wire) then return end
  local player = game.get_player(e.player_index)
  if not player then return end
  validate_entity(e.last_entity, e.player_index)
  validate_entity(player.selected, e.player_index)
  validate_entity(st.prev, e.player_index)
  st.prev = e.last_entity
end

local function on_moved(e)
  local st = storage.players and storage.players[e.player_index]
  if not (st and st.holding_pole) then return end
  local player = game.get_player(e.player_index)
  local info = player and held.pole_info(held.name(player))
  if info then zones.show(player, info) end
end

-- Registers the two frequent events only while somebody needs them.
local function sync_handlers()
  local need_zone, need_wire = false, false
  for _, st in pairs(storage.players or {}) do
    if st.holding_pole then need_zone = true end
    if st.wire then need_wire = true end
  end
  script.on_event(defines.events.on_player_changed_position, need_zone and on_moved or nil)
  script.on_event(defines.events.on_selected_entity_changed, need_wire and on_selected_changed or nil)
end

script.on_event(defines.events.on_player_cursor_stack_changed, function(e)
  local player = game.get_player(e.player_index)
  if not player then return end
  local st = state.player(e.player_index)
  local name = held.name(player)
  local pinfo = held.pole_info(name)

  if pinfo and pinfo.has_area then
    st.holding_pole = true
    zones.show(player, pinfo)
  elseif st.holding_pole then
    st.holding_pole = nil
    zones.clear(e.player_index)
  end

  if pinfo and st.anchor and st.anchor.valid then
    local ainfo = lookup.info(st.anchor.name)
    if ainfo and ainfo.class ~= pinfo.class then st.anchor = nil end
  end

  local wire_now = name ~= nil and held.is_wire(name)
  if st.wire and not wire_now then
    validate_entity(st.prev, e.player_index)
    validate_entity(player.selected, e.player_index)
    st.prev = nil
  end
  st.wire = wire_now or nil
  sync_handlers()
end)

local function drop_player(player_index)
  local st = storage.players and storage.players[player_index]
  if st then
    zones.clear(player_index)
    st.holding_pole, st.wire, st.prev = nil, nil, nil
  end
  sync_handlers()
end
script.on_event(defines.events.on_player_left_game, function(e) drop_player(e.player_index) end)
script.on_event(defines.events.on_player_removed, function(e)
  drop_player(e.player_index)
  if storage.players then storage.players[e.player_index] = nil end
end)

-- Undo / redo can restore wires.  The action layout is not documented in
-- detail, so this is best effort and can never raise an error.
local function on_undo_redo(e)
  pcall(function()
    local player = game.get_player(e.player_index)
    if not player then return end
    for _, action in ipairs(e.actions or {}) do
      local target = action.target
      if target and target.position then
        local surface = action.surface_index and game.get_surface(action.surface_index) or player.surface
        for _, class in ipairs(shared.CLASSES) do
          local found = surface.find_entities_filtered{
            position = target.position, radius = 1, name = lookup.names_by_class[class],
          }
          for _, pole in ipairs(found) do validate_entity(pole, e.player_index) end
        end
      end
    end
  end)
end
script.on_event(defines.events.on_undo_applied, on_undo_redo)
script.on_event(defines.events.on_redo_applied, on_undo_redo)

-- ---------------------------------------------------------------------------
-- Input, tool
-- ---------------------------------------------------------------------------
script.on_event("pc-break-line", function(e)
  local st = state.player(e.player_index)
  st.anchor = nil
  st.skip_next = true
  local player = game.get_player(e.player_index)
  if player then
    player.create_local_flying_text{ text = { "pc.new-line" }, create_at_cursor = true }
  end
end)

script.on_event(defines.events.on_player_selected_area, function(e)
  if e.item == "pc-wire-tool" then tools.audit(e) end
end)
script.on_event(defines.events.on_player_alt_selected_area, function(e)
  if e.item == "pc-wire-tool" then tools.rewire(e) end
end)

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------
script.on_init(function()
  state.init()
  sync_handlers()
end)
script.on_configuration_changed(function()
  state.init()
  sync_handlers()
end)
script.on_load(function()
  sync_handlers()
end)

-- ---------------------------------------------------------------------------
-- Remote interface for other mods (for example the transformer mod).
-- ---------------------------------------------------------------------------
remote.add_interface("pole-classes", {
  -- Definition table of a pole / port prototype name, or nil.
  get_pole_info = function(name)
    local info = lookup.info(name)
    if not info then return nil end
    return { class = info.class, tier = info.tier, family = info.family,
             is_port = info.is_port or false, role = info.role,
             reach = info.reach, supply_distance = info.distance }
  end,
  -- Size, cap and transformer outputs of the network that contains `entity`.
  get_network_stats = function(entity)
    local info = entity and entity.valid and lookup.info(entity.name)
    if not info then return nil end
    local comp = graph.component(entity, shared.max_cap(info.class))
    return { class = info.class, pole_count = comp.count,
             cap = comp.min_cap ~= math.huge and comp.min_cap or nil,
             outputs = comp.outputs, inputs = comp.inputs, truncated = comp.truncated }
  end,
  -- Re-validate every wire of a pole (cuts illegal wires).  Returns wires cut.
  validate_pole = function(entity, player_index)
    local player = player_index and game.get_player(player_index)
    return wires.validate(entity, { player_index = player_index, force = player and player.force })
  end,
  is_transformer = function(name) return lookup.transformers[name] == true end,
  -- Ports are never rejected when built (removing a hidden port would leave a broken
  -- transformer behind).  A transformer mod should call this for each of its ports
  -- before placing the transformer.  Returns the name of the first entity that the
  -- port's or pole's supply area would touch illegally, or nil when the spot is fine.
  can_place_pole = function(surface, position, name)
    local info = lookup.info(name)
    if not info or not surface or not position then return nil end
    local hit = placement.pole_conflict(surface, position, info)
    if not hit then return nil end
    return hit.type == "entity-ghost" and hit.ghost_name or hit.name
  end,
})
