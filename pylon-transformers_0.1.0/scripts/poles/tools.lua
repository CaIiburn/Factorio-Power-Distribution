-- The pole wire tool.
--   select     : audit the selected poles (cut illegal wires, report placement problems)
--   alt-select : rebuild the wires between the selected poles as a spanning forest
local shared = require("__pylon-transformers__.config").pole
local lookup = require("__pylon-transformers__.scripts.poles.lookup")
local graph = require("__pylon-transformers__.scripts.poles.graph")
local wires = require("__pylon-transformers__.scripts.poles.wires")
local placement = require("__pylon-transformers__.scripts.poles.placement")

local T = {}

local NEAREST_PER_POLE = 6

local function ctx_of(player)
  return { player_index = player.index, force = player.force }
end

function T.audit(event)
  local player = game.get_player(event.player_index)
  if not player then return end
  local ctx = ctx_of(player)
  local cuts, problems = 0, 0
  for _, e in ipairs(event.entities) do
    if e.valid then
      local info = lookup.info(e.name)
      if info then
        cuts = cuts + wires.validate(e, ctx, true)
        if e.valid and info.has_area then
          local hit = placement.pole_conflict(e.surface, e.position, info)
          if hit then
            problems = problems + 1
            local x1, y1, x2, y2 = placement.bbox(hit)
            rendering.draw_rectangle{
              color = { r = 1, g = 0.1, b = 0.1, a = 0.5 }, filled = true,
              left_top = { x1, y1 }, right_bottom = { x2, y2 },
              surface = e.surface, players = { player }, time_to_live = 600, draw_on_ground = true,
            }
          end
        end
      end
    end
  end
  player.print({ "pc.audit-result", cuts, problems })
end

-- Union-find over unit numbers.
local function find(parent, u)
  while parent[u] ~= u do
    parent[u] = parent[parent[u]]
    u = parent[u]
  end
  return u
end

local function distance(a, b)
  local dx, dy = a.position.x - b.position.x, a.position.y - b.position.y
  return math.sqrt(dx * dx + dy * dy)
end

local function rewire_class(class, list, surface)
  table.sort(list, function(a, b) return a.entity.unit_number < b.entity.unit_number end)
  local sel = {}
  for _, it in ipairs(list) do sel[it.entity.unit_number] = it end

  -- 1. remove every wire whose two ends are both selected
  local removed = 0
  for _, it in ipairs(list) do
    local e = it.entity
    for _, nb in ipairs(graph.neighbors(e)) do
      if sel[nb.entity.unit_number] and e.unit_number < nb.entity.unit_number then
        if graph.connector(e).disconnect_from(nb.connector, nb.origin) then removed = removed + 1 end
      end
    end
  end

  -- 2. candidate edges: the nearest few poles of each pole
  local edges = {}
  for _, it in ipairs(list) do
    local e = it.entity
    local near = {}
    local found = surface.find_entities_filtered{
      position = e.position, radius = it.info.reach, name = lookup.pole_names_by_class[class],
    }
    for _, c in ipairs(found) do
      local cit = c.valid and c.unit_number and sel[c.unit_number]
      if cit and c.unit_number > e.unit_number then
        local d = distance(e, c)
        if d <= math.min(it.info.reach, cit.info.reach) then near[#near + 1] = { b = c, d = d } end
      end
    end
    table.sort(near, function(x, y)
      if x.d ~= y.d then return x.d < y.d end
      return x.b.unit_number < y.b.unit_number
    end)
    for i = 1, math.min(#near, NEAREST_PER_POLE) do
      edges[#edges + 1] = { a = e, b = near[i].b, d = near[i].d }
    end
  end
  table.sort(edges, function(x, y)
    if x.d ~= y.d then return x.d < y.d end
    if x.a.unit_number ~= y.a.unit_number then return x.a.unit_number < y.a.unit_number end
    return x.b.unit_number < y.b.unit_number
  end)

  -- 3. Kruskal, respecting free auto slots and the network rules
  local parent = {}
  for u in pairs(sel) do parent[u] = u end
  local added = 0
  local limit = shared.max_cap(class)
  for _, edge in ipairs(edges) do
    local ra, rb = find(parent, edge.a.unit_number), find(parent, edge.b.unit_number)
    if ra ~= rb
       and graph.degree(edge.a) < shared.AUTO_DEGREE[class]
       and graph.degree(edge.b) < shared.AUTO_DEGREE[class] then
      local ca, cb = graph.connector(edge.a), graph.connector(edge.b)
      if ca.connect_to(cb, true) then
        local comp = graph.component(edge.a, limit)
        if graph.violation(comp, class) then
          ca.disconnect_from(cb)
        else
          parent[ra] = rb
          added = added + 1
        end
      end
    end
  end

  for _, it in ipairs(list) do wires.refresh_snapshot(it.entity) end
  return removed, added
end

function T.rewire(event)
  local player = game.get_player(event.player_index)
  if not player then return end
  local groups = {}
  for _, e in ipairs(event.entities) do
    local info = e.valid and lookup.pole[e.name]
    if info then
      local g = groups[info.class]
      if not g then g = {}; groups[info.class] = g end
      g[#g + 1] = { entity = e, info = info }
    end
  end
  local removed, added = 0, 0
  for _, class in ipairs(shared.CLASSES) do
    if groups[class] then
      local r, a = rewire_class(class, groups[class], event.surface)
      removed, added = removed + r, added + a
    end
  end
  player.print({ "pc.rewire-result", removed, added })
end

return T
