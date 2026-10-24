-- Wires of the ports of a transformer, for everything that builds a transformer:
--
--   * placing a transformer next to poles that are already there: its ports are wired to the
--     nearest open pole ends of their class (autowire.lua), like a pole that is placed next to them
--   * blueprints, ghosts and robots: the ports are hidden entities that no blueprint contains, so
--     the wires between a port and its poles are saved as TAGS on the transformer. Tags travel with
--     the transformer through blueprints (a copy or a blueprint book) and through the ghost the game
--     leaves when a transformer dies (an exploded or shot transformer is rebuilt by robots with its
--     wires). When the transformer is built from them, the wires are made again.
--
-- What a tag holds (key TAG on the transformer): for the input and the output port a list of
--     { u = along the transformer, v = across it, class = pole class of the other end }
-- the position of the other end relative to the transformer, in the transformer's own frame: u is
-- measured towards the output end, v is perpendicular to that (clockwise). Because the frame turns
-- with the transformer, a rotated blueprint wires the same poles. A mirrored blueprint does not
-- (transformers cannot be mirrored), so there the poles are not found: the wires are only wished for.
--
-- A wire whose pole is not built yet (robots build in any order) is remembered as a "wish" of the
-- port and made when a pole of that class appears at that spot. Wishes live in
-- storage.port_wishes[port unit number] = { { x, y, class }, ... } and go away with the port.
--
-- A port with no wire in the tag (or no tag) is autowired. A port with wires in the tag is wired only
-- as the tag says, which is what a blueprint of poles and transformers should reproduce.
local Common = require("__pylon-transformers__.scripts.transformer.common")
local lookup = require("__pylon-transformers__.scripts.poles.lookup")
local graph = require("__pylon-transformers__.scripts.poles.graph")
local wires = require("__pylon-transformers__.scripts.poles.wires")
local autowire = require("__pylon-transformers__.scripts.poles.autowire")

local C, shells, OUTPUT_VECTOR, north = Common.C, Common.shells, Common.OUTPUT_VECTOR, Common.north

local TAG = "pt_ports"

-- The end of a transformer each tag list belongs to, and the record field that holds its port.
local ROLES = {
  { role = "input", key = "in_pole" },
  { role = "output", key = "out_pole" },
}

-- A recorded wire only has to hit its pole this closely (tiles); blueprint positions are exact.
local MATCH_RADIUS = 0.3

local PortWires = {}

-- Tables in storage are created when first needed, so a save that was made before this module
-- existed needs no migration.
local function wishes()
  local list = storage.port_wishes
  if not list then
    list = {}
    storage.port_wishes = list
  end
  return list
end

local function dying()
  local list = storage.dying_ports
  if not list then
    list = {}
    storage.dying_ports = list
  end
  return list
end

-- The frame of a shell: unit vector towards its output end, and the one across it.
local function frame(shell)
  local o = OUTPUT_VECTOR[shell.direction] or OUTPUT_VECTOR[north]
  return o, { -o[2], o[1] }
end

---------------------------------------------------------------------------------------------------
-- Reading the wires of a transformer
---------------------------------------------------------------------------------------------------

-- The tag value of a registered transformer: { input = { entries }, output = { entries } }.
-- `scope` (optional) is a set of unit numbers: only wires to those entities are recorded. A
-- blueprint passes the entities it contains, so it never wires a pasted transformer to poles that
-- were not part of it. Without a scope every wire is recorded (death of the transformer).
function PortWires.capture(rec, scope)
  local shell = rec.shell
  local o, p = frame(shell)
  local sx, sy = shell.position.x, shell.position.y

  local tag = {}
  for _, def in ipairs(ROLES) do
    local list = {}
    local port = rec[def.key]
    if port and port.valid then
      for _, nb in ipairs(graph.neighbors(port)) do
        local other = nb.entity
        local info = lookup.info(other.name)
        if info and (not scope or scope[other.unit_number]) then
          local rx, ry = other.position.x - sx, other.position.y - sy
          list[#list + 1] = {
            u = rx * o[1] + ry * o[2],
            v = rx * p[1] + ry * p[2],
            class = info.class,
          }
        end
      end
    end
    tag[def.role] = list
  end
  return tag
end

---------------------------------------------------------------------------------------------------
-- Making the wires
---------------------------------------------------------------------------------------------------

local function connect(port, other)
  return graph.connector(port).connect_to(graph.connector(other), true)
end

-- The pole (or port of another transformer) of the class at the position, or nil.
local function find_target(surface, x, y, class, port)
  local names = lookup.names_by_class[class]
  if not names then return nil end
  for _, e in ipairs(surface.find_entities_filtered{
    position = { x = x, y = y }, radius = MATCH_RADIUS, name = names,
  }) do
    if e.valid and e.unit_number and e.unit_number ~= port.unit_number then return e end
  end
  return nil
end

local function add_wish(port, x, y, class)
  local all = wishes()
  local list = all[port.unit_number]
  if not list then
    list = {}
    all[port.unit_number] = list
  end
  list[#list + 1] = { x = x, y = y, class = class }
end

-- Wires a port as the tag list says. Poles that are there are wired now, the others are wished.
local function apply_list(rec, port, list, ctx)
  local o, p = frame(rec.shell)
  local sx, sy = rec.shell.position.x, rec.shell.position.y
  local surface = rec.shell.surface

  for _, entry in ipairs(list) do
    local x = sx + entry.u * o[1] + entry.v * p[1]
    local y = sy + entry.u * o[2] + entry.v * p[2]
    local target = find_target(surface, x, y, entry.class, port)
    if target then
      connect(port, target)
    else
      add_wish(port, x, y, entry.class)
    end
  end
  -- Cuts what the pole rules do not allow (pole cap, transformer outputs, wire degree).
  wires.validate(port, ctx)
end

-- A pole or port of this mod has just come into the world: makes the wires that ports are waiting
-- for. Costs nothing while no port is waiting for anything.
function PortWires.fulfil(entity, ctx)
  local all = storage.port_wishes
  if not all or next(all) == nil then return end
  local info = lookup.info(entity.name)
  if not info then return end

  local ports = entity.surface.find_entities_filtered{
    position = entity.position, radius = C.port_reach, name = C.pole.PORT_NAMES,
  }
  local pos = entity.position
  for _, port in ipairs(ports) do
    local list = port.valid and all[port.unit_number]
    if list and port.unit_number ~= entity.unit_number then
      local made = false
      for i = #list, 1, -1 do
        local wish = list[i]
        if wish.class == info.class
           and math.abs(wish.x - pos.x) <= MATCH_RADIUS and math.abs(wish.y - pos.y) <= MATCH_RADIUS then
          table.remove(list, i)
          if connect(port, entity) then made = true end
        end
      end
      if #list == 0 then all[port.unit_number] = nil end
      if made then wires.validate(port, ctx) end
    end
  end
end

-- A transformer was built (by a player, robots, a script, or revived from a ghost). `tags` are the
-- tags of the blueprint entity / ghost it was built from, if any.
function PortWires.on_transformer_built(rec, tags, ctx)
  local tag = tags and tags[TAG]
  for _, def in ipairs(ROLES) do
    local port = rec[def.key]
    if port and port.valid then
      local list = type(tag) == "table" and tag[def.role] or nil
      if list and #list > 0 then
        apply_list(rec, port, list, ctx)
      else
        autowire.wire_port(port, ctx)
      end
    end
  end
  -- Another transformer's port may be waiting for these ports.
  for _, def in ipairs(ROLES) do
    local port = rec[def.key]
    if port and port.valid then PortWires.fulfil(port, ctx) end
  end
end

---------------------------------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------------------------------

-- Any pole of this mod that was built: first the wires that ports are waiting for, then (in the
-- pole logic that runs after this) the pole's own autowiring, which leaves a pole that already has
-- wires alone.
local function on_pole_built(event, source)
  local entity = event.entity
  if not (entity and entity.valid) or entity.type == "entity-ghost" then return end
  if not lookup.info(entity.name) then return end
  PortWires.fulfil(entity, { player_index = event.player_index, force = entity.force, source = source })
end

-- The set of the entities a blueprint contains, plus the ports of the transformers among them.
local function blueprint_scope(entities)
  local scope = {}
  for _, e in pairs(entities) do
    if e.valid and e.unit_number then
      scope[e.unit_number] = true
      local rec = shells[e.name] and storage.transformers[e.unit_number]
      if rec then
        for _, def in ipairs(ROLES) do
          local port = rec[def.key]
          if port and port.valid then scope[port.unit_number] = true end
        end
      end
    end
  end
  return scope
end

-- Where a blueprint can be written: a record (library) or the item stack, whichever the event gives.
local function blueprint_target(event)
  local record = event.record
  if record and record.valid and record.valid_for_write then return record end
  local stack = event.stack
  if stack and stack.valid and stack.valid_for_read then return stack end
  return nil
end

-- The player has set up a blueprint: write the port wires of every transformer in it as tags.
local function on_player_setup_blueprint(event)
  local target = blueprint_target(event)
  if not (target and event.mapping and event.mapping.valid) then return end

  local entities = event.mapping.get()
  local scope
  for index, entity in pairs(entities) do
    local rec = entity.valid and shells[entity.name] and storage.transformers[entity.unit_number]
    if rec then
      scope = scope or blueprint_scope(entities)
      target.set_blueprint_entity_tag(index, TAG, PortWires.capture(rec, scope))
    end
  end
end

-- A transformer dies: its ports are destroyed with it, and the ghost the game leaves behind (when
-- the force builds ghosts of dead entities) does not know their wires. Take them now, while the
-- ports still exist, and put them on the ghost in on_post_entity_died.
local function on_entity_died(event)
  local entity = event.entity
  local rec = entity.valid and shells[entity.name] and storage.transformers[entity.unit_number]
  if not rec then return end

  local list = dying()
  for unit_number, saved in pairs(list) do
    if saved.tick < event.tick then list[unit_number] = nil end   -- never came to a ghost
  end
  list[entity.unit_number] = { tick = event.tick, tag = PortWires.capture(rec) }
end

local function on_post_entity_died(event)
  local list = storage.dying_ports
  local saved = list and event.unit_number and list[event.unit_number]
  if not saved then return end
  list[event.unit_number] = nil

  local ghost = event.ghost
  if not (ghost and ghost.valid) then return end
  local tags = ghost.tags or {}
  tags[TAG] = saved.tag
  ghost.tags = tags
end

-- A port is gone: so are its wishes.
local function on_object_destroyed(event)
  local all = storage.port_wishes
  if all and event.type == defines.target_type.entity and event.useful_id then
    all[event.useful_id] = nil
  end
end

-- Names of everything that can satisfy a wish: poles and ports of this mod.
local names = {}
for _, def in ipairs(C.pole.POLES) do names[#names + 1] = def.name end
for _, port in ipairs(C.pole.PORTS) do names[#names + 1] = port.name end

-- Only the transformer shells are interesting when something dies.
local shell_filters = {}
for name in pairs(shells) do shell_filters[#shell_filters + 1] = { filter = "name", name = name } end
table.sort(shell_filters, function(a, b) return a.name < b.name end)

PortWires.library = {
  build = { handler = on_pole_built, names = names },
  events = {
    [defines.events.on_player_setup_blueprint] = on_player_setup_blueprint,
    [defines.events.on_entity_died] = on_entity_died,
    [defines.events.on_post_entity_died] = on_post_entity_died,
    [defines.events.on_object_destroyed] = on_object_destroyed,
  },
  event_filters = {
    [defines.events.on_entity_died] = shell_filters,
    -- The filters of this event only know entity types. Everything else is dropped by the lookup.
    [defines.events.on_post_entity_died] = { { filter = "type", type = "constant-combinator" } },
  },
}

return PortWires
