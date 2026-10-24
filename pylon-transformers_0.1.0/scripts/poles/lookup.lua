-- Static lookup tables, rebuilt on every load from config.lua (C.pole) and from the
-- classification mod-data produced in data-final-fixes. Nothing here is saved.
local shared = require("__pylon-transformers__.config").pole

local L = {}

local function sorted(set)
  local list = {}
  for name in pairs(set) do list[#list + 1] = name end
  table.sort(list)
  return list
end

function L.init()
  L.pole = {}              -- pole name -> definition
  L.port = {}              -- port pole name -> definition
  L.consumers, L.producers, L.transformers = {}, {}, {}
  L.restricted = {}        -- class -> array of entity names its supply area may not touch
  L.restricted_no_transformer = {}
  L.restricting = {}       -- entity name -> array of classes that may not cover it
  L.names_by_class = {}    -- class -> array of pole + port names
  L.pole_names_by_class = {}
  L.max_half = {}          -- class -> largest supply half-width
  L.watched = {}           -- names that need a build event

  for _, def in ipairs(shared.POLES) do L.pole[def.name] = def end
  for _, def in ipairs(shared.PORTS) do
    L.port[def.name] = {
      name = def.name, class = def.class, role = def.role, is_port = true,
      has_area = true, distance = shared.PORT_SUPPLY_DISTANCE, reach = shared.PORT_REACH,
    }
  end

  local md = prototypes and prototypes.mod_data and prototypes.mod_data["pole-classes-classification"]
  local d = (md and md.data) or {}
  for _, n in ipairs(d.consumers or {}) do L.consumers[n] = true end
  for _, n in ipairs(d.producers or {}) do L.producers[n] = true end
  for _, n in ipairs(d.transformers or {}) do L.transformers[n] = true end
  for name, p in pairs(d.ports or {}) do
    L.port[name] = {
      name = name, class = p.class, role = p.role, is_port = true,
      has_area = true, distance = p.distance, reach = p.reach,
    }
  end

  -- What each class with a supply area must not cover.
  local no_t = { feeder = L.consumers, distribution = L.producers, aux = {} }
  for _, class in ipairs({ "feeder", "distribution", "aux" }) do
    local set, set_no_t = {}, {}
    for n in pairs(no_t[class]) do set[n] = true; set_no_t[n] = true end
    for n in pairs(L.transformers) do set[n] = true end
    L.restricted[class] = sorted(set)
    L.restricted_no_transformer[class] = sorted(set_no_t)
    for n in pairs(set) do
      -- Transformers are not listed here: a pole may not cover one (L.restricted), but where a
      -- transformer may be built is decided by scripts/transformer/placement.lua, which checks
      -- the supply areas of every electric pole (quality aware, ghosts included).
      if not L.transformers[n] then
        local list = L.restricting[n]
        if not list then list = {}; L.restricting[n] = list end
        list[#list + 1] = class
      end
    end
  end
  for _, list in pairs(L.restricting) do table.sort(list) end

  for _, class in ipairs(shared.CLASSES) do
    local names, pole_names, half = {}, {}, 0
    for _, def in ipairs(shared.POLES) do
      if def.class == class then
        names[#names + 1] = def.name; pole_names[#pole_names + 1] = def.name
        if def.has_area and def.distance > half then half = def.distance end
      end
    end
    for name, port in pairs(L.port) do
      if port.class == class then
        names[#names + 1] = name
        if port.distance > half then half = port.distance end
      end
    end
    table.sort(names)
    L.names_by_class[class] = names
    L.pole_names_by_class[class] = pole_names
    L.max_half[class] = half
  end

  local seen = {}
  local function watch(n) if not seen[n] then seen[n] = true; L.watched[#L.watched + 1] = n end end
  for _, def in ipairs(shared.POLES) do watch(def.name) end
  for name in pairs(L.port) do watch(name) end
  for _, n in ipairs(sorted(L.consumers)) do watch(n) end
  for _, n in ipairs(sorted(L.producers)) do watch(n) end
  table.sort(L.watched)
end

-- Definition of one of our poles or ports, or nil for anything else.
function L.info(name)
  return L.pole[name] or L.port[name]
end

return L
