-- Event bus: every runtime module registers its handlers here, and install() hands them to the
-- engine once.
--
-- script.on_event replaces whatever handler an event had before, so two modules that both want
-- on_object_destroyed or the build events cannot call it themselves. The bus keeps one list per
-- event and installs one handler that runs the whole list in registration order.
--
-- A library is a table with any of these fields:
--   events                    { [event id or custom input name] = function(event) }
--   event_filters             { [event id] = { engine event filters } }, for entries of `events`
--   on_nth_tick               { [ticks] = function(event) }
--   on_init, on_load, on_configuration_changed   function()
--   remote_interfaces         { [interface name] = { function name -> function } }
--   build                     { handler = function(event, source), names = {...},
--                               ghost_names = {...}, types = {...} }
--
-- `build` is for entities that were created or cloned. The handler runs for all of these events:
-- on_built_entity (source "player"), on_robot_built_entity ("robot"), on_space_platform_built_entity
-- ("platform"), script_raised_built, script_raised_revive and on_entity_cloned (all "script"). The
-- entity is event.entity, or event.destination for a clone. The events are filtered by the engine:
-- one filter per name (and per ghost name, for the events that can build ghosts) and per entity
-- type of all libraries together, so nothing runs for an entity nobody asked for. A handler is
-- called for everything that passes the combined filter and must pick out its own entities.
-- Build events must not also be listed under `events`.
--
-- Filters of `events` entries: an event is registered with the union of the filters of all
-- libraries that handle it. If any of them handles the event without a filter, it is registered
-- without one. Either way a handler can be called for an event that passes another library's
-- filter and must check that it is its own.
local Bus = {}

local events = {}
local event_filters = {}      -- event id -> list of filters, only while every handler has a filter
local unfiltered = {}         -- event id -> true when some handler has none
local nth_tick = {}
local on_init, on_load, on_configuration_changed = {}, {}, {}
local remote_interfaces = {}
local builds = {}

-- The events that build or clone entities. `ghosts`: the event can build ghosts, so ghost names
-- are part of its filter.
local BUILD_EVENTS = {
  { id = defines.events.on_built_entity, source = "player", ghosts = true },
  { id = defines.events.on_robot_built_entity, source = "robot", ghosts = true },
  { id = defines.events.on_space_platform_built_entity, source = "platform", ghosts = true },
  { id = defines.events.script_raised_built, source = "script" },
  { id = defines.events.script_raised_revive, source = "script" },
  { id = defines.events.on_entity_cloned, source = "script" },
}

local function push(map, key, fn)
  local list = map[key]
  if not list then
    list = {}
    map[key] = list
  end
  list[#list + 1] = fn
end

-- Adds the filters of one handler to the union for its event.
local function add_filters(id, filters)
  if not filters then
    unfiltered[id] = true
    return
  end
  for _, f in ipairs(filters) do push(event_filters, id, f) end
end

function Bus.add_library(lib)
  for id, fn in pairs(lib.events or {}) do
    push(events, id, fn)
    add_filters(id, lib.event_filters and lib.event_filters[id])
  end
  for ticks, fn in pairs(lib.on_nth_tick or {}) do push(nth_tick, ticks, fn) end
  if lib.on_init then on_init[#on_init + 1] = lib.on_init end
  if lib.on_load then on_load[#on_load + 1] = lib.on_load end
  if lib.on_configuration_changed then
    on_configuration_changed[#on_configuration_changed + 1] = lib.on_configuration_changed
  end
  for name, interface in pairs(lib.remote_interfaces or {}) do remote_interfaces[name] = interface end
  if lib.build then
    assert(lib.build.names or lib.build.ghost_names or lib.build.types,
      "a build handler needs at least one filter")
    builds[#builds + 1] = lib.build
  end
end

function Bus.add_libraries(libs)
  for _, lib in ipairs(libs) do Bus.add_library(lib) end
end

-- One function that calls every function of the list with the same arguments.
local function chain(list)
  if #list == 1 then return list[1] end
  return function(...)
    for i = 1, #list do list[i](...) end
  end
end

-- Union of the filters of all libraries for one build event.
local function build_filters(ghosts)
  local filters, seen = {}, {}
  local function add(kind, key, value)
    local id = kind .. "/" .. value
    if seen[id] then return end
    seen[id] = true
    filters[#filters + 1] = { filter = kind, [key] = value }
  end
  for _, b in ipairs(builds) do
    for _, name in ipairs(b.names or {}) do add("name", "name", name) end
    if ghosts then
      for _, name in ipairs(b.ghost_names or {}) do add("ghost_name", "name", name) end
    end
    for _, type_name in ipairs(b.types or {}) do add("type", "type", type_name) end
  end
  return filters
end

local function install_builds()
  if #builds == 0 then return end
  for _, spec in ipairs(BUILD_EVENTS) do
    assert(not events[spec.id], "build events are registered through `build`, not `events`")
    local filters = build_filters(spec.ghosts)
    if #filters > 0 then
      local source = spec.source
      script.on_event(spec.id, function(event)
        for i = 1, #builds do builds[i].handler(event, source) end
      end, filters)
    end
  end
end

-- Registers everything with the engine. Call once, at the end of control.lua.
function Bus.install()
  for id, list in pairs(events) do
    local filters = (not unfiltered[id]) and event_filters[id] or nil
    if filters and #filters > 0 then
      script.on_event(id, chain(list), filters)
    else
      script.on_event(id, chain(list))
    end
  end
  for ticks, list in pairs(nth_tick) do script.on_nth_tick(ticks, chain(list)) end
  install_builds()

  if #on_init > 0 then script.on_init(chain(on_init)) end
  if #on_load > 0 then script.on_load(chain(on_load)) end
  if #on_configuration_changed > 0 then
    script.on_configuration_changed(chain(on_configuration_changed))
  end

  for name, interface in pairs(remote_interfaces) do remote.add_interface(name, interface) end
end

return Bus
