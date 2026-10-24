-- Wire validation: which wires may exist, and cutting the ones that may not.
local shared = require("__pylon-transformers__.config").pole
local lookup = require("__pylon-transformers__.scripts.poles.lookup")
local graph = require("__pylon-transformers__.scripts.poles.graph")
local notify = require("__pylon-transformers__.scripts.poles.notify")

local W = {}

local function midpoint(a, b)
  return { x = (a.position.x + b.position.x) / 2, y = (a.position.y + b.position.y) / 2 }
end

-- Records the current wires of `entity` (and the reverse direction on its
-- neighbours) as "known good".  Wires not in this record are treated as new.
function W.refresh_snapshot(entity)
  local un = entity.unit_number
  local set = {}
  for _, nb in ipairs(graph.neighbors(entity)) do
    local u = nb.entity.unit_number
    set[u] = true
    local ns = storage.nbr[u]
    if not ns then ns = {}; storage.nbr[u] = ns end
    ns[un] = true
  end
  storage.nbr[un] = set
end

local function cut(entity, nb, reason, ctx)
  graph.connector(entity).disconnect_from(nb.connector, nb.origin)
  local ns = storage.nbr[nb.entity.unit_number]
  if ns then ns[entity.unit_number] = nil end
  local snap = storage.nbr[entity.unit_number]
  if snap then snap[nb.entity.unit_number] = nil end
  local mid = midpoint(entity, nb.entity)
  notify.warn(ctx, entity.surface, mid,
    { "pc.cut", { "pc.cut-" .. reason }, notify.gps(entity.surface, mid) })
end

-- Checks a wire that was not in the snapshot.  Returns nil or a reason key.
local function check_new_wire(entity, info, other, oinfo)
  local max_degree = shared.MAX_DEGREE[info.class]
  if graph.degree(entity) > max_degree or graph.degree(other) > shared.MAX_DEGREE[oinfo.class] then
    return "degree"
  end
  local comp = graph.component(entity, shared.max_cap(info.class))
  return graph.violation(comp, info.class)
end

-- Validates every wire of one pole or port.  `force_all` ignores the snapshot
-- (used by the audit tool).  Returns the number of wires cut.
function W.validate(entity, ctx, force_all)
  if not (entity and entity.valid) then return 0 end
  local info = lookup.info(entity.name)
  if not info or not entity.unit_number then return 0 end

  local snap = storage.nbr[entity.unit_number] or {}
  local cuts = 0
  for _, nb in ipairs(graph.neighbors(entity)) do
    local other = nb.entity
    local oinfo = lookup.info(other.name)
    local reason
    if not oinfo then
      reason = "foreign"
    elseif oinfo.class ~= info.class then
      reason = "class"
    elseif force_all or not snap[other.unit_number] then
      reason = check_new_wire(entity, info, other, oinfo)
      -- An audit never cuts a wire only because its network is already too big:
      -- the culprit could be any wire, so the player is told to split it instead.
      if force_all and (reason == "cap" or reason == "outputs") then
        notify.warn(ctx, entity.surface, entity.position, { "pc.network-over-cap" })
        reason = nil
      end
    end
    if reason then
      cut(entity, nb, reason, ctx)
      cuts = cuts + 1
    end
  end
  W.refresh_snapshot(entity)
  return cuts
end

-- A pole of another mod was built. Poles of other mods connect themselves to every pole in reach,
-- which can include a port of a transformer and would put a foreign pole on a network of this mod.
-- Cuts those wires. Returns the number of wires cut. Poles of this mod never need this.
function W.cut_foreign_at_ports(entity, ctx)
  if not (entity and entity.valid and entity.unit_number) then return 0 end
  local cuts = 0
  for _, nb in ipairs(graph.neighbors(entity)) do
    if lookup.port[nb.entity.name] then
      cut(entity, nb, "foreign", ctx)
      cuts = cuts + 1
    end
  end
  return cuts
end

return W
