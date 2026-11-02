-- One registration per lifecycle event, shared by every script.
--
-- Factorio keeps ONE handler per event for the whole mod: a second script.on_event(id, ...) replaces the first, even with
-- different filters. So the scripts (stacks, reactors, heaters, breeders) do not register build / clone / remove events
-- themselves; each one exports a `lifecycle` table and control.lua hands the list to M.register, which registers every
-- event once with the combined name filter and passes the entity on to the scripts that own its name.
--
--   lifecycle = { names = { [entity name] = true }, built = fn(entity), cloned = fn(entity), removed = fn(unit_number) }
local M = {}

local BUILT = { "on_built_entity", "on_robot_built_entity", "on_space_platform_built_entity",
                "script_raised_built", "script_raised_revive" }
local REMOVED = { "on_player_mined_entity", "on_robot_mined_entity", "on_space_platform_mined_entity",
                  "on_entity_died", "script_raised_destroy" }

function M.register(modules)
  local names = {}
  for _, m in ipairs(modules) do for name in pairs(m.names) do names[#names + 1] = name end end
  table.sort(names)
  local filters = {}
  for i, name in ipairs(names) do filters[i] = { filter = "name", name = name, mode = "or" } end

  local ev = defines.events
  local function dispatch(entity, kind)
    if not (entity and entity.valid ~= false) then return end
    for _, m in ipairs(modules) do
      if m.names[entity.name] then
        if kind == "removed" then
          if entity.unit_number and m.removed then m.removed(entity.unit_number) end
        elseif m[kind] then
          m[kind](entity)
        end
      end
    end
  end
  -- Event filters can only be attached when registering ONE event at a time (not an array).
  for _, id in ipairs(BUILT) do script.on_event(ev[id], function(e) dispatch(e.entity, "built") end, filters) end
  script.on_event(ev.on_entity_cloned, function(e) dispatch(e.destination, "built") end, filters)
  for _, id in ipairs(REMOVED) do script.on_event(ev[id], function(e) dispatch(e.entity, "removed") end, filters) end
end

return M
