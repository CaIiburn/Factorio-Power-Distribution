-- Does an item prototype of this name exist?
--
-- Items are spread over several prototype types (item, tool, ammo, module, ...), and which type an
-- item has can change between game versions (science packs were `tool` and are not in 2.1). So
-- this does not look at one data.raw group: an item is any prototype with that name that has a
-- stack_size, which every ItemPrototype requires and recipes, technologies and entities do not.
local cache = {}

return function(name)
  local known = cache[name]
  if known ~= nil then return known end
  local found = false
  for _, group in pairs(data.raw) do
    local proto = type(group) == "table" and group[name]
    if type(proto) == "table" and proto.stack_size ~= nil then
      found = true
      break
    end
  end
  cache[name] = found
  return found
end
