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
--   * the ports of a transformer are wired the same way when the transformer is built (wire_port):
--     to the nearest pole ends of the port's class that have a free wire. They never chain from the
--     player's last pole, never join another port (that is done by hand) and do not touch the
--     player's chain.
local shared = require("__pylon-transformers__.config").pole
local lookup = require("__pylon-transformers__.scripts.poles.lookup")
local graph = require("__pylon-transformers__.scripts.poles.graph")
local wires = require("__pylon-transformers__.scripts.poles.wires")
local state = require("__pylon-transformers__.scripts.poles.state")

local A = {}

local function distance(a, b)
  local dx, dy = a.position.x - b.position.x, a.position.y - b.position.y
  return math.sqrt(dx * dx + dy * dy)
end

-- Poles a new pole or port may be wired to automatically, best first: open line ends, then the
-- nearest. A new pole only takes poles with a free automatic slot (AUTO_DEGREE). A port takes any
-- pole with a free wire (MAX_DEGREE): a transformer is placed on purpose, and the end of a line that
-- already has a transformer on it is full for poles but must still take the next transformer.
local function candidates(entity, info)
  local from_port = info.is_port
  local degree_limit = from_port and shared.MAX_DEGREE or shared.AUTO_DEGREE
  local found = entity.surface.find_entities_filtered{
    position = entity.position, radius = info.reach, name = lookup.names_by_class[info.class],
  }
  local list = {}
  for _, c in ipairs(found) do
    if c.valid and c.unit_number and c.unit_number ~= entity.unit_number then
      local cinfo = lookup.info(c.name)
      local d = distance(entity, c)
      if cinfo and not (from_port and cinfo.is_port)
         and d <= math.min(info.reach, cinfo.reach)
         and graph.degree(c) < degree_limit[cinfo.class] then
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
-- `entity` is a pole, or the port of a transformer (info.is_port).
function A.run(entity, info, ctx)
  local is_port = info.is_port
  -- The chain (last pole placed, ALT + L) belongs to the poles the player places, not to ports.
  local ps = (not is_port and ctx.player_index) and state.player(ctx.player_index) or nil
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
  -- A pole counts as one pole of its network. A port is no pole (it has no tier and does not count
  -- towards the cap), but an output port is one transformer output of the network it joins.
  local cur
  if is_port then
    cur = { count = 0, min_cap = math.huge, outputs = info.role == "out" and 1 or 0,
            set = { [entity.unit_number] = true } }
  else
    cur = { count = 1, min_cap = shared.cap(info.class, info.tier), outputs = 0,
            set = { [entity.unit_number] = true } }
  end
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

-- Entry point for every built pole. (Ports are created by the transformer script and are wired
-- through wire_port.)
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

-- Wires one freshly created, still unwired port of a transformer to nearby poles of its class,
-- like a pole that is placed next to them. Same rules as for poles: only open pole ends, never past
-- the pole cap or the transformer-output limit, nothing when the player's autowire mode is "off".
-- Returns the number of wires made.
function A.wire_port(port, ctx)
  local info = port.valid and lookup.port[port.name]
  if not info or graph.degree(port) > 0 then return 0 end
  return A.run(port, info, ctx)
end

return A
