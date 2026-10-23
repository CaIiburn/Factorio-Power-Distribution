local shared = require("shared")

-- ---------------------------------------------------------------------------
-- 1. Classify every entity prototype.
--
-- consumers    : feeder poles may not cover these
-- producers    : distribution poles may not cover these
-- transformers : no pole with a supply area may cover these
-- neutral      : exempt (solar panels, accumulators, electric energy interfaces...)
--
-- Other mods adjust this by adding a mod-data prototype whose name starts with
-- "pole-classes-config" and whose `data` table may contain the string arrays
-- `consumers`, `producers`, `neutral`, `transformers` and the dictionary
-- `ports = { [pole_name] = { class = "...", role = "in"|"out" } }`.
-- ---------------------------------------------------------------------------
local PRODUCER_TYPES = {
  ["generator"] = true, ["burner-generator"] = true,
  ["fusion-generator"] = true, ["lightning-attractor"] = true,
}
local NEUTRAL_TYPES = {
  ["solar-panel"] = true, ["accumulator"] = true,
  ["electric-energy-interface"] = true, ["electric-pole"] = true,
  ["power-switch"] = true,
}

local consumers, producers, neutral, transformers = {}, {}, {}, {}

for type_name, group in pairs(data.raw) do
  if type(group) == "table" then
    for name, proto in pairs(group) do
      local es = type(proto) == "table" and proto.energy_source
      if es and es.type == "electric" and (proto.collision_box or proto.selection_box) then
        local priority = es.usage_priority
        if NEUTRAL_TYPES[type_name] then
          neutral[name] = true
        elseif PRODUCER_TYPES[type_name] then
          producers[name] = true
        elseif priority == "primary-output" or priority == "secondary-output" then
          producers[name] = true
        elseif priority == "tertiary" then
          neutral[name] = true
        else
          consumers[name] = true
        end
      end
    end
  end
end

-- Hidden "port" poles are always neutral.
for _, port in ipairs(shared.PORTS) do neutral[port.name] = true end

local extra_ports = {}
local function apply_config(cfg)
  for _, n in ipairs(cfg.consumers or {}) do
    consumers[n] = true; producers[n] = nil; neutral[n] = nil
  end
  for _, n in ipairs(cfg.producers or {}) do
    producers[n] = true; consumers[n] = nil; neutral[n] = nil
  end
  for _, n in ipairs(cfg.neutral or {}) do
    neutral[n] = true; consumers[n] = nil; producers[n] = nil
  end
  for _, n in ipairs(cfg.transformers or {}) do
    transformers[n] = true; consumers[n] = nil; producers[n] = nil; neutral[n] = nil
  end
  for pole_name, port in pairs(cfg.ports or {}) do
    local proto = data.raw["electric-pole"][pole_name]
    if proto and port.class and port.role then
      extra_ports[pole_name] = {
        class = port.class, role = port.role,
        distance = proto.supply_area_distance or 0,
        reach = proto.maximum_wire_distance or 0,
      }
      neutral[pole_name] = true
    end
  end
end

local config_names = {}
for name in pairs(data.raw["mod-data"] or {}) do
  if string.sub(name, 1, #"pole-classes-config") == "pole-classes-config" then
    config_names[#config_names + 1] = name
  end
end
table.sort(config_names)
for _, name in ipairs(config_names) do
  apply_config(data.raw["mod-data"][name].data or {})
end

local function sorted_keys(set)
  local list = {}
  for name in pairs(set) do list[#list + 1] = name end
  table.sort(list)
  return list
end

data:extend({
  {
    type = "mod-data",
    name = "pole-classes-classification",
    data = {
      consumers = sorted_keys(consumers),
      producers = sorted_keys(producers),
      transformers = sorted_keys(transformers),
      ports = extra_ports,
    },
  },
})

-- ---------------------------------------------------------------------------
-- 2. Hide the vanilla poles: no recipes, no tech unlocks, hidden prototypes.
--    The prototypes stay so existing saves, tips-and-tricks and other mods work.
-- ---------------------------------------------------------------------------
local VANILLA = { "small-electric-pole", "medium-electric-pole", "big-electric-pole", "substation" }
local vanilla_set = {}
for _, name in ipairs(VANILLA) do vanilla_set[name] = true end

for _, name in ipairs(VANILLA) do
  local ent = data.raw["electric-pole"][name]
  if ent then ent.hidden = true end
  local item = data.raw.item[name]
  if item then item.hidden = true end
  local recipe = data.raw.recipe[name]
  if recipe then
    recipe.enabled = false
    recipe.hidden = true
  end
end

for _, tech in pairs(data.raw.technology) do
  if tech.effects then
    local kept = {}
    for _, effect in ipairs(tech.effects) do
      if not (effect.type == "unlock-recipe" and vanilla_set[effect.recipe]) then
        kept[#kept + 1] = effect
      end
    end
    tech.effects = kept
  end
end
