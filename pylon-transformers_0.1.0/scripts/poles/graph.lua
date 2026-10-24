-- Reading the copper-wire graph of our poles.
local shared = require("__pylon-transformers__.config").pole
local lookup = require("__pylon-transformers__.scripts.poles.lookup")

local G = {}

function G.connector(entity)
  return entity.get_wire_connector(defines.wire_connector_id.pole_copper, true)
end

-- Real (non-ghost) wires of `entity`, sorted by neighbour unit number so that
-- every machine in multiplayer walks the graph in the same order.
function G.neighbors(entity)
  local conn = G.connector(entity)
  local list = {}
  if not conn then return list end
  for _, c in ipairs(conn.real_connections) do
    local target = c.target
    local owner = target and target.owner
    if owner and owner.valid and owner.unit_number then
      list[#list + 1] = { entity = owner, connector = target, origin = c.origin }
    end
  end
  table.sort(list, function(a, b) return a.entity.unit_number < b.entity.unit_number end)
  return list
end

function G.degree(entity)
  local conn = G.connector(entity)
  return conn and conn.real_connection_count or 0
end

-- Walks the network that contains `start`, through our poles and ports only.
-- Stops as soon as more than `limit` poles were counted.
-- Returns { count, min_cap, outputs, inputs, set, truncated }.
function G.component(start, limit)
  local result = { count = 0, min_cap = math.huge, outputs = 0, inputs = 0,
                   set = { [start.unit_number] = true }, truncated = false }
  local queue, head = { start }, 1
  while head <= #queue do
    local e = queue[head]
    head = head + 1
    local info = lookup.info(e.name)
    if info then
      if info.is_port then
        if info.role == "out" then result.outputs = result.outputs + 1
        else result.inputs = result.inputs + 1 end
      else
        result.count = result.count + 1
        local cap = shared.cap(info.class, info.tier)
        if cap < result.min_cap then result.min_cap = cap end
        if result.count > limit then
          result.truncated = true
          break
        end
      end
      for _, nb in ipairs(G.neighbors(e)) do
        local u = nb.entity.unit_number
        if not result.set[u] and lookup.info(nb.entity.name) then
          result.set[u] = true
          queue[#queue + 1] = nb.entity
        end
      end
    end
  end
  return result
end

-- Does a component break any network rule?  Returns nil or a reason key.
function G.violation(comp, class)
  if comp.truncated or comp.count > comp.min_cap then return "cap" end
  local limit = shared.OUTPUT_LIMIT[class]
  if limit ~= nil and comp.outputs > limit then return "outputs" end
  return nil
end

return G
