-- Exhaust stacks pick their vent recipe automatically.
--
-- Every second a stack looks at the entity connected to its inlet, reads the fluids it holds and
-- sets the matching vent recipe. Only fluids on the vent list (shared/defs.lua) can be vented;
-- everything else is refused with a reason shown in the stack's status line.
local defs = require("shared.defs")

local M = {}
local POLL_TICKS = 60

-- Tile just outside the stack's inlet face (inlet is on the north face of an unrotated stack). The distance
-- follows the configured stack size: half the footprint plus half a tile (2 for the default 3x3).
local function inlet_offset(direction)
  local d = defines.direction
  local o = (defs.config.stack.size + 1) / 2
  if direction == d.north then return 0, -o
  elseif direction == d.east then return o, 0
  elseif direction == d.south then return 0, o
  elseif direction == d.west then return -o, 0 end
  return 0, -o
end

local function stacks()
  storage.ipp_stacks = storage.ipp_stacks or {}
  return storage.ipp_stacks
end

-- Fluids held by whatever is connected to the inlet: { [fluid name] = amount } or nil.
function M.inlet_contents(stack)
  local dx, dy = inlet_offset(stack.direction)
  local at = { x = stack.position.x + dx, y = stack.position.y + dy }
  local merged, any = {}, false
  for _, e in pairs(stack.surface.find_entities_filtered { position = at, radius = 0.45 }) do
    if e.valid and e ~= stack and e.type ~= "entity-ghost" then
      local ok, contents = pcall(e.get_fluid_contents, e)
      if ok and type(contents) == "table" then
        for name, amount in pairs(contents) do
          if amount > 0 then merged[name] = (merged[name] or 0) + amount; any = true end
        end
      end
    end
  end
  return any and merged or nil
end

-- Classify the contents: best ventable fluid, or the most plentiful refused fluid with its reason.
function M.classify(contents)
  local best, best_amount = nil, 0
  for name, amount in pairs(contents) do
    if defs.vent.allowed[name] and amount > best_amount then best, best_amount = name, amount end
  end
  if best then return "allowed", best end
  local worst, worst_amount = nil, -1
  for name, amount in pairs(contents) do
    if amount > worst_amount then worst, worst_amount = name, amount end
  end
  return "denied", worst, defs.vent.denied[worst] or "unlisted"
end

local function fluid_label(name)
  local proto = prototypes.fluid[name]
  return proto and proto.localised_name or name
end

local function set_status(stack, diode, label)
  stack.custom_status = { diode = diode, label = label }
end

local function recipe_name(stack)
  local r = stack.get_recipe()
  return r and r.name or nil
end

function M.update(stack)
  local contents = M.inlet_contents(stack)
  local current = recipe_name(stack)
  local diode = defines.entity_status_diode

  if not contents then
    if current then
      set_status(stack, diode.green, { "ipp.status-venting-idle" })
    else
      set_status(stack, diode.yellow, { "ipp.status-waiting" })
    end
    return
  end

  local kind, fluid, reason = M.classify(contents)
  if kind == "allowed" then
    local info = defs.vent.allowed[fluid]
    local recipe = stack.force.recipes[info.recipe]
    if not (recipe and recipe.enabled) then
      if current then stack.set_recipe(nil) end
      set_status(stack, diode.yellow, { "ipp.status-research", fluid_label(fluid) })
      return
    end
    if current ~= info.recipe then stack.set_recipe(info.recipe) end
    set_status(stack, diode.green, { "ipp.status-venting", fluid_label(fluid) })
  else
    if current then stack.set_recipe(nil) end   -- never keep venting something that is not allowed
    set_status(stack, diode.red, { "ipp.status-denied", fluid_label(fluid), { "ipp.vent-denied-" .. reason } })
  end
end

function M.register(stack)
  if not (stack and stack.valid and stack.name == defs.STACK and stack.unit_number) then return end
  stacks()[stack.unit_number] = stack
  M.update(stack)
end

function M.unregister(unit)
  stacks()[unit] = nil
end

function M.poll()
  for unit, stack in pairs(stacks()) do
    if stack.valid then M.update(stack) else stacks()[unit] = nil end
  end
end

function M.rescan()
  for _, surface in pairs(game.surfaces) do
    for _, e in pairs(surface.find_entities_filtered { name = defs.STACK }) do M.register(e) end
  end
end

-- Lists for players: what can and cannot be vented.
function M.vent_list_lines()
  local lines = { { "ipp.vent-list-allowed-header" } }
  local names = {}
  for name in pairs(defs.vent.allowed) do names[#names + 1] = name end
  table.sort(names)
  for _, name in ipairs(names) do lines[#lines + 1] = { "ipp.vent-list-allowed", fluid_label(name) } end
  lines[#lines + 1] = { "ipp.vent-list-denied-header" }
  names = {}
  for name in pairs(defs.vent.denied) do names[#names + 1] = name end
  table.sort(names)
  for _, name in ipairs(names) do
    lines[#lines + 1] = { "ipp.vent-list-denied", fluid_label(name), { "ipp.vent-denied-" .. defs.vent.denied[name] } }
  end
  lines[#lines + 1] = { "ipp.vent-list-unlisted" }
  return lines
end

function M.register_events()
  local filters = { { filter = "name", name = defs.STACK } }
  local ev = defines.events
  -- Event filters can only be attached when registering ONE event at a time (not an array).
  local function on(events, handler)
    for _, id in ipairs(events) do script.on_event(id, handler, filters) end
  end
  on({ ev.on_built_entity, ev.on_robot_built_entity, ev.on_space_platform_built_entity,
       ev.script_raised_built, ev.script_raised_revive },
    function(e) M.register(e.entity) end)
  on({ ev.on_entity_cloned }, function(e) M.register(e.destination) end)
  on({ ev.on_player_mined_entity, ev.on_robot_mined_entity, ev.on_space_platform_mined_entity,
       ev.on_entity_died, ev.script_raised_destroy },
    function(e) if e.entity and e.entity.unit_number then M.unregister(e.entity.unit_number) end end)
  script.on_nth_tick(POLL_TICKS, M.poll)
  -- a finished research can unlock a recipe a waiting stack needs (unfiltered event)
  script.on_event(ev.on_research_finished, function() M.poll() end)
end

return M
