-- Automatic wiring of freshly built poles.
--
-- Vanilla auto-connection is switched off on every pole prototype
-- (auto_connect_up_to_n_wires = 0), so this module is the only thing that
-- creates wires on its own.  Rules:
--   * a pole that already has wires (blueprint, fast-replace) is left alone
--   * chain mode: continue from the last pole the player placed
--   * otherwise join the nearest pole that still has free auto slots, preferring line ends
--   * never merge networks beyond the pole cap, never exceed the transformer-output limit
--   * "break line" makes the next pole start a new, unwired line
local shared = require("shared")
local lookup = require("scripts.lookup")
local graph = require("scripts.graph")
local wires = require("scripts.wires")
local state = require("scripts.state")

local A = {}

local function distance(a, b)
  local dx, dy = a.position.x - b.position.x, a.position.y - b.position.y
  return math.sqrt(dx * dx + dy * dy)
end

local function candidates(entity, info)
  local found = entity.surface.find_entities_filtered{
    position = entity.position, radius = info.reach, name = lookup.names_by_class[info.class],
  }
  local list = {}
  for _, c in ipairs(found) do
    if c.valid and c.unit_number and c.unit_number ~= entity.unit_number then
      local cinfo = lookup.info(c.name)
      local d = distance(entity, c)
      if cinfo and d <= math.min(info.reach, cinfo.reach)
         and graph.degree(c) < shared.AUTO_DEGREE[cinfo.class] then
        list[#list + 1] = { entity = c, info = cinfo, dist = d, is_end = graph.degree(c) <= 1 }
      end
    end
  end
  table.sort(list, function(a, b)
    if a.is_end ~= b.is_end then return a.is_end end
    if a.dist ~= b.dist then return a.dist < b.dist end
    return a.entity.unit_number < b.entity.unit_number
  end)
  return list
end

local function player_mode(player_index)
  if not player_index then return "nearest" end
  local ok, value = pcall(function()
    return settings.get_player_settings(player_index)["pc-autowire-mode"].value
  end)
  return ok and value or "chain"
end

-- Returns the number of wires made.
function A.run(entity, info, ctx)
  local ps = ctx.player_index and state.player(ctx.player_index) or nil
  local mode = player_mode(ctx.player_index)

  if mode == "off" then
    if ps then ps.anchor = entity end
    return 0
  end
  if ps and ps.skip_next then
    ps.skip_next = false
    ps.anchor = entity
    return 0
  end

  local limit = shared.max_cap(info.class)
  local out_limit = shared.OUTPUT_LIMIT[info.class]
  local cur = { count = 1, min_cap = shared.cap(info.class, info.tier), outputs = 0,
                set = { [entity.unit_number] = true } }
  local cache, linked, made = {}, {}, 0
  local want = shared.AUTO_CONNECTIONS[info.class]
  local mine = graph.connector(entity)

  local function component_of(c)
    local comp = cache[c.unit_number]
    if not comp then
      comp = graph.component(c, limit)
      for u in pairs(comp.set) do cache[u] = comp end
    end
    return comp
  end

  local function connect(c)
    if linked[c.unit_number] then return false end
    local merged, cc
    if not cur.set[c.unit_number] then
      cc = component_of(c)
      if cc.truncated then return false end
      merged = { count = cur.count + cc.count,
                 min_cap = math.min(cur.min_cap, cc.min_cap),
                 outputs = cur.outputs + cc.outputs }
      if merged.count > merged.min_cap then return false end
      if out_limit and merged.outputs > out_limit then return false end
    end
    if not mine.connect_to(graph.connector(c), true) then return false end
    linked[c.unit_number] = true
    made = made + 1
    if merged then
      cur.count, cur.min_cap, cur.outputs = merged.count, merged.min_cap, merged.outputs
      for u in pairs(cc.set) do cur.set[u] = true end
    end
    return true
  end

  -- 1. chain mode: continue from the player's last pole
  local anchor = ps and ps.anchor
  if mode == "chain" and anchor and anchor.valid and anchor.unit_number ~= entity.unit_number then
    local ainfo = lookup.info(anchor.name)
    if ainfo and ainfo.class == info.class
       and distance(entity, anchor) <= math.min(info.reach, ainfo.reach)
       and graph.degree(anchor) < shared.MAX_DEGREE[ainfo.class] then
      connect(anchor)
    end
  end

  -- 2. fill the remaining slots with the best nearby poles
  if made < want then
    for _, cand in ipairs(candidates(entity, info)) do
      if made >= want then break end
      connect(cand.entity)
    end
  end

  wires.refresh_snapshot(entity)
  if ps then ps.anchor = entity end
  return made
end

-- Entry point for every built pole or port.
function A.on_built(entity, info, ctx)
  local before = graph.connector(entity).connection_count
  wires.validate(entity, ctx)
  if info.is_port then return end
  if before == 0 and entity.valid then
    A.run(entity, info, ctx)
  elseif ctx.player_index then
    state.player(ctx.player_index).anchor = entity
  end
end

return A
