-- Tier 4: fast breeder with supercritical CO2 generation (docs/FAST_BREEDER.md). Every rating comes from config.lua.
--
--   * Reactor core        : copy of the VANILLA `reactor` prototype, exactly like the Tier 3 core (native heat buffer,
--                           neighbour bonus, circuit connector, meltdown explosion) with its own fuel category and its own
--                           neighbour category. The same script (scripts/reactors.lua) drives the rods.
--   * Sodium circulation  : copy of the vanilla heat exchanger: core heat in, cool primary sodium in, hot primary sodium out.
--   * Intermediate sodium exchanger, CO2 heater, compressor, recuperator, cooler, electrolyzer, fuel fabricator and the
--     blanket channel are crafting machines built like the Tier 2 / 3 ones (fixed recipes unless noted).
--   * CO2 turbine-generator : a native fusion-generator (see D.generators and the loop in machines.lua), burns hot CO2.
--   * Hot-fluid storage tank: a bigger vanilla storage tank.
--   * Blanket irradiation   : the channel is a crafting machine that scripts/breeders.lua switches on and off in proportion
--                             to the power of the breeder core it touches (a vanilla reactor burns one item at a time, so
--                             it cannot irradiate a second kind of assembly by itself).
local D = require("shared.defs")
local U = require("prototypes.ipp-helpers")
local M = require("prototypes.machines")
local C = D.config

local unit, elec, vol = M.unit, M.elec, M.vol
local item_for, build_machine, process, building = M.item_for, M.build_machine, M.process, M.building
local VOID = M.VOID
local function volume_for(floor, ...) return vol(math.max(...), floor) end
local fl, it = U.icons_of_fluid, U.icons_of_item
local F = "ipp-structural-frame"
local BF = C.breeder_fuel

--------------------------------------------------------------------------------------------------
-- Fuel-cycle items
--------------------------------------------------------------------------------------------------
local function plain_item(name, base, tint, order, extra)
  local item = {
    type = "item", name = name, icons = U.icons_of_item(base, tint),
    subgroup = "ipp-fuel-cycle", order = order, stack_size = 10,
  }
  for k, v in pairs(extra or {}) do item[k] = v end
  data:extend { item }
end

local function core_assembly(name, tint, order, gj)
  plain_item(name, "uranium-fuel-cell", tint, order, {
    fuel_categories = { "ipp-fast-fuel" },
    fuel_value = unit(gj, "GJ"),
    burnt_result = "ipp-spent-core-assembly",
    localised_description = { "item-description." .. name, D.fmt(gj) },
  })
end
core_assembly("ipp-mox-assembly",     U.color(1.00, 0.75, 0.45), "h-a", D.fuel.mox_gj)
core_assembly("ipp-starter-assembly", U.color(0.55, 1.00, 0.70), "h-b", D.fuel.starter_gj)
plain_item("ipp-blanket-assembly",             "depleted-uranium-fuel-cell", U.color(0.70, 0.80, 0.60), "h-c")
plain_item("ipp-bred-blanket-assembly",        "depleted-uranium-fuel-cell", U.color(1.00, 0.60, 0.90), "h-d")
plain_item("ipp-spent-core-assembly",          "depleted-uranium-fuel-cell", U.color(1.00, 0.35, 0.25), "h-e")
plain_item("ipp-spent-core-assembly-cooled",   "depleted-uranium-fuel-cell", U.color(0.55, 0.75, 1.00), "h-f")
data:extend {
  { type = "item", name = "ipp-dry-sodium-salt", icons = U.icons_of_item("stone-brick", U.color(0.95, 0.95, 1.00)),
    subgroup = "ipp-fuel-cycle", order = "h-g", stack_size = 50 },
  { type = "item", name = "ipp-lime", icons = U.icons_of_item("stone-brick", U.color(1.00, 1.00, 0.90)),
    subgroup = "ipp-fuel-cycle", order = "h-h", stack_size = 50 },
}

--------------------------------------------------------------------------------------------------
-- Fast-breeder reactor core
--------------------------------------------------------------------------------------------------
local FB = C.fast_breeder
local core_tint = U.color(1.00, 0.80, 0.60)
do
  local VR = data.raw["reactor"] and data.raw["reactor"]["nuclear-reactor"]
  assert(VR, "industrial-power-plants: vanilla nuclear-reactor prototype not found")
  local r = U.deepcopy(VR)
  r.name = D.FBR
  r.icon, r.icon_size = nil, nil
  r.icons = U.icons_of(data.raw.item["nuclear-reactor"], core_tint)
  r.minable = { mining_time = 0.5, result = D.FBR }
  r.fast_replaceable_group, r.next_upgrade, r.placeable_by = nil, nil, nil
  r.max_health = FB.health
  r.consumption = unit(FB.power_mw, "MW")
  r.neighbour_bonus = FB.neighbour_bonus
  -- Own neighbour category: breeder cores boost each other; vanilla and pressurized-water cores do not join the array.
  for _, c in ipairs(r.neighbour_connectable.connections) do
    c.category = "ipp-fbr-reactor"
    c.neighbour_category = { "ipp-fbr-reactor" }
  end
  r.energy_source.fuel_categories = { "ipp-fast-fuel" }
  r.energy_source.fuel_inventory_size = FB.fuel_slots
  r.energy_source.burnt_inventory_size = FB.spent_slots
  r.heat_buffer.max_temperature = FB.max_temperature_c
  r.heat_buffer.specific_heat = unit(FB.specific_heat_mj, "MJ")
  r.temperature_to_suppress_energy_icons = FB.warning_temperature_c
  U.restyle(r.picture, 1, core_tint)
  if r.lower_layer_picture then U.restyle(r.lower_layer_picture, 1, core_tint) end
  local desc = { D.fmt(FB.power_mw), D.fmt(FB.warning_temperature_c), D.fmt(FB.meltdown_temperature_c), D.fmt(FB.meltdown_grace_s),
                 D.fmt(FB.rod_speed_pct_per_second), D.fmt(FB.scram_speed_pct_per_second), D.fmt(FB.scram_lockout_s / 60) }
  r.localised_description = { "entity-description." .. D.FBR, table.unpack(desc) }
  data:extend { r, item_for(D.FBR, "nuclear-reactor", core_tint, "w-a", nil, desc) }
end

--------------------------------------------------------------------------------------------------
-- Sodium circulation unit (vanilla heat exchanger, boiler prototype): the heat exchanger of the primary loop
--------------------------------------------------------------------------------------------------
local SU = C.sodium_unit
do
  local name = "ipp-sodium-circulation-unit"
  local HX = data.raw["boiler"] and data.raw["boiler"]["heat-exchanger"]
  assert(HX, "industrial-power-plants: vanilla heat-exchanger prototype not found")
  local tint = U.color(1.00, 0.78, 0.60)
  local b = U.deepcopy(HX)
  b.name = name
  b.icon, b.icon_size = nil, nil
  b.icons = U.icons_of(data.raw.item["heat-exchanger"], tint)
  b.minable = { mining_time = 0.3, result = name }
  b.fast_replaceable_group, b.next_upgrade, b.placeable_by = nil, nil, nil
  b.max_health = SU.health
  b.mode = "output-to-separate-pipe"
  b.target_temperature = SU.target_c
  b.energy_consumption = unit(SU.power_mw, "MW")
  b.energy_source.min_working_temperature = SU.min_working_c
  b.energy_source.max_temperature = C.heat_pipe_2.max_temperature_c   -- do not cap a Heat pipe II network at the vanilla 1000 degC
  local v = math.max(200, D.SODIUM_FLOW * 3)
  b.fluid_box.filter, b.fluid_box.volume = "ipp-primary-sodium", v
  b.output_fluid_box.filter, b.output_fluid_box.volume = "ipp-primary-sodium-hot", v
  if b.pictures then U.restyle(b.pictures, 1, tint) end
  local desc = { D.fmt(SU.power_mw), D.fmt(D.SODIUM_FLOW), D.fmt(SU.target_c), D.fmt(SU.min_working_c) }
  b.localised_description = { "entity-description." .. name, table.unpack(desc) }
  data:extend { b, item_for(name, "heat-exchanger", tint, "w-b", nil, desc) }
end

--------------------------------------------------------------------------------------------------
-- Heat pipe II: the vanilla heat pipe with a higher temperature limit (everything else, including the connections, is copied)
--------------------------------------------------------------------------------------------------
do
  local name, HP2 = "ipp-heat-pipe-2", C.heat_pipe_2
  local VP = data.raw["heat-pipe"] and data.raw["heat-pipe"]["heat-pipe"]
  assert(VP, "industrial-power-plants: vanilla heat-pipe prototype not found")
  local tint = U.color(1.00, 0.72, 0.55)
  local h = U.deepcopy(VP)
  h.name = name
  h.icon, h.icon_size = nil, nil
  h.icons = U.icons_of(data.raw.item["heat-pipe"], tint)
  h.minable = { mining_time = 0.1, result = name }
  h.fast_replaceable_group = VP.fast_replaceable_group   -- can be dropped on a vanilla heat pipe to replace it
  h.next_upgrade, h.placeable_by = nil, nil
  h.max_health = HP2.health
  h.heat_buffer.max_temperature = HP2.max_temperature_c
  if h.connection_sprites then U.restyle(h.connection_sprites, 1, tint) end
  h.localised_description = { "entity-description." .. name, D.fmt(HP2.max_temperature_c) }
  local item = item_for(name, "heat-pipe", tint, "w-0", nil, { D.fmt(HP2.max_temperature_c) })
  item.stack_size = 50   -- laid by the hundred
  data:extend { h, item }
end

--------------------------------------------------------------------------------------------------
-- Crafting machines. Layout of an unrotated machine: north face = inputs, south face = outputs; "left" = lateral -1,
-- "right" = lateral +1. Fluids are assigned to ports in recipe order.
--------------------------------------------------------------------------------------------------
local se, ch, cp, rc, cl = C.sodium_exchanger, C.co2_heater, C.sco2_compressor, C.recuperator, C.sco2_cooler
local el, ff, bc = C.electrolyzer, C.fuel_fabricator, C.blanket_channel
local TB = D.generators["ipp-sco2-turbine-generator"]

local function four(v)   -- two inputs (north) + two outputs (south), the layout of the Tier 3 steam generator
  return { { kind = "input", dir = "north", lat = -1, volume = v }, { kind = "input", dir = "north", lat = 1, volume = v },
           { kind = "output", dir = "south", lat = -1, volume = v }, { kind = "output", dir = "south", lat = 1, volume = v } }
end

local machines = {
  -- hot primary sodium (left) + cool secondary sodium (right) in; cool primary sodium (left) + hot secondary sodium (right) out
  { name = "ipp-intermediate-sodium-exchanger", base = "chemical-plant", size = se.size, tint = U.color(1.00, 0.80, 0.65), order = "w-c",
    categories = { "ipp-sodium-exchange" }, fixed_recipe = "ipp-sodium-heat-exchange", health = se.health,
    energy_source = elec(unit(se.idle_drain_kw, "kW")), energy_usage = unit(se.power_mw, "MW"),
    desc = { D.fmt(se.hot_primary_per_second), D.fmt(se.secondary_per_second), D.fmt(se.power_mw) },
    fluid_boxes = four(volume_for(2000, se.hot_primary_per_second, se.cool_primary_per_second, se.secondary_per_second)) },

  -- hot secondary sodium (left) + CO2 feed (right) in; cool secondary sodium (left) + hot CO2 (right) out.
  -- No fixed recipe: scripts/heaters.lua picks preheated or cold feed from the fluid at the CO2 inlet.
  { name = D.HEATER, base = "chemical-plant", size = ch.size, tint = U.color(1.00, 0.65, 0.45), order = "w-d",
    categories = { "ipp-co2-heating" }, health = ch.health,
    energy_source = elec(unit(ch.idle_drain_kw, "kW")), energy_usage = unit(ch.power_kw, "kW"),
    desc = { D.fmt(ch.sodium_per_second), D.fmt(ch.recuperated_co2_per_second), D.fmt(ch.direct_co2_per_second), D.fmt(ch.power_kw),
             D.fmt(ch.sodium_per_second * D.SODIUM_UNIT_KJ / 1000) },
    fluid_boxes = four(volume_for(2000, ch.sodium_per_second, ch.recuperated_co2_per_second, ch.direct_co2_per_second)) },

  { name = "ipp-sco2-compressor", base = "chemical-plant", size = cp.size, tint = U.color(0.70, 0.85, 1.00), order = "w-e",
    categories = { "ipp-co2-compression" }, fixed_recipe = "ipp-sco2-compression", health = cp.health,
    energy_source = elec(unit(cp.idle_drain_kw, "kW")), energy_usage = unit(cp.power_mw, "MW"),
    desc = { D.fmt(cp.co2_per_second), D.fmt(cp.power_mw) },
    fluid_boxes = (function() local v = volume_for(1000, cp.co2_per_second)
      return { { kind = "input", dir = "north", lat = 0, volume = v }, { kind = "output", dir = "south", lat = 0, volume = v } } end)() },

  -- exhaust (left) + compressed CO2 (right) in; exhaust (left) + preheated CO2 (right) out
  { name = "ipp-recuperator", base = "chemical-plant", size = rc.size, tint = U.color(0.85, 0.95, 1.00), order = "w-f",
    categories = { "ipp-co2-recuperation" }, fixed_recipe = "ipp-sco2-recuperation", health = rc.health,
    energy_source = elec(unit(rc.idle_drain_kw, "kW")), energy_usage = unit(rc.power_kw, "kW"),
    desc = { D.fmt(rc.co2_per_second), D.fmt(rc.co2_per_second * D.SCO2_PREHEAT_MJ) },
    fluid_boxes = four(volume_for(1000, rc.co2_per_second)) },

  { name = "ipp-sco2-cooler", base = "chemical-plant", size = cl.size, tint = U.color(0.80, 0.90, 0.95), order = "w-g",
    categories = { "ipp-co2-cooling" }, fixed_recipe = "ipp-sco2-cooling", health = cl.health,
    energy_source = elec(unit(cl.idle_drain_kw, "kW")), energy_usage = unit(cl.power_mw, "MW"),
    desc = { D.fmt(cl.exhaust_per_second), D.fmt(cl.power_mw) },
    fluid_boxes = (function() local v = volume_for(1000, cl.exhaust_per_second)
      return { { kind = "input", dir = "north", lat = 0, volume = v }, { kind = "output", dir = "south", lat = 0, volume = v } } end)() },

  -- dry sodium salt in (items); sodium (left) + chlorine (right) out. Two recipes, chosen by hand.
  { name = "ipp-sodium-electrolyzer", base = "chemical-plant", size = el.size, tint = U.color(0.80, 0.85, 0.95), order = "w-h",
    categories = { "ipp-electrolysis" }, health = el.health,
    energy_source = elec(unit(el.idle_drain_kw, "kW")), energy_usage = unit(el.power_mw, "MW"),
    desc = { D.fmt(el.salt), D.fmt(el.sodium), D.fmt(el.chlorine), D.fmt(el.time_s), D.fmt(el.power_mw) },
    fluid_boxes = (function() local v = volume_for(1000, el.sodium, el.chlorine)
      return { { kind = "output", dir = "south", lat = -1, volume = v }, { kind = "output", dir = "south", lat = 1, volume = v } } end)() },

  -- MOX, starter and blanket assemblies (item recipes, chosen by hand)
  { name = "ipp-shielded-fuel-fabricator", base = "assembling-machine-3", size = ff.size, tint = U.color(0.75, 0.85, 0.75), order = "w-i",
    categories = { "ipp-fuel-fabrication" }, health = ff.health,
    energy_source = elec(unit(ff.idle_drain_kw, "kW")), energy_usage = unit(ff.power_mw, "MW"),
    desc = { D.fmt(ff.power_mw) } },

  -- Blanket irradiation channel: no power, its speed is the flux of the core it touches (scripts/breeders.lua)
  { name = D.CHANNEL, base = "assembling-machine-3", size = bc.size, tint = U.color(1.00, 0.70, 0.85), order = "w-j",
    categories = { "ipp-irradiation" }, fixed_recipe = "ipp-blanket-irradiation", health = bc.health,
    energy_source = VOID, energy_usage = "1kW",
    desc = { D.fmt(bc.channel_time_s), D.fmt(BF.blanket.irradiation_gj), D.fmt(bc.reach_tiles) } },
}
for _, m in ipairs(machines) do build_machine(m) end

--------------------------------------------------------------------------------------------------
-- Hot-fluid storage tank: vanilla storage tank with a big, unfiltered fluid box
--------------------------------------------------------------------------------------------------
do
  local name, HT = "ipp-hot-fluid-tank", C.hot_tank
  local ST = data.raw["storage-tank"] and data.raw["storage-tank"]["storage-tank"]
  assert(ST, "industrial-power-plants: vanilla storage-tank prototype not found")
  local tint = U.color(1.00, 0.85, 0.70)
  local t = U.deepcopy(ST)
  t.name = name
  t.icon, t.icon_size = nil, nil
  t.icons = U.icons_of(data.raw.item["storage-tank"], tint)
  t.minable = { mining_time = 0.5, result = name }
  t.fast_replaceable_group, t.next_upgrade, t.placeable_by = nil, nil, nil
  t.max_health = HT.health
  t.fluid_box.volume = HT.capacity
  t.fluid_box.filter = nil
  if t.pictures then U.restyle(t.pictures, 1, tint) end
  t.localised_description = { "entity-description." .. name, D.fmt(HT.capacity) }
  data:extend { t, item_for(name, "storage-tank", tint, "w-k", nil, { D.fmt(HT.capacity) }) }
end

--------------------------------------------------------------------------------------------------
-- Process recipes (fixed-recipe machines). Everything is at default temperature: only the circulation unit stamps one.
--------------------------------------------------------------------------------------------------
process("ipp-sodium-heat-exchange", { "ipp-sodium-exchange" }, 1,
  { { "fluid", "ipp-primary-sodium-hot", se.hot_primary_per_second }, { "fluid", "ipp-secondary-sodium", se.secondary_per_second } },
  { { "fluid", "ipp-primary-sodium", se.cool_primary_per_second }, { "fluid", "ipp-secondary-sodium-hot", se.secondary_per_second } },
  fl("ipp-secondary-sodium-hot"))
-- The heater's two recipes burn the same sodium; fed with preheated CO2 it makes more hot CO2 from it.
process("ipp-co2-heating-recuperated", { "ipp-co2-heating" }, 1,
  { { "fluid", "ipp-secondary-sodium-hot", ch.sodium_per_second }, { "fluid", "ipp-sco2-warm", ch.recuperated_co2_per_second } },
  { { "fluid", "ipp-secondary-sodium", ch.sodium_per_second }, { "fluid", "ipp-sco2-hot", ch.recuperated_co2_per_second } },
  fl("ipp-sco2-hot"))
process("ipp-co2-heating-direct", { "ipp-co2-heating" }, 1,
  { { "fluid", "ipp-secondary-sodium-hot", ch.sodium_per_second }, { "fluid", "ipp-sco2", ch.direct_co2_per_second } },
  { { "fluid", "ipp-secondary-sodium", ch.sodium_per_second }, { "fluid", "ipp-sco2-hot", ch.direct_co2_per_second } },
  fl("ipp-sco2-hot"))
process("ipp-sco2-compression", { "ipp-co2-compression" }, 1,
  { { "fluid", "ipp-co2", cp.co2_per_second } }, { { "fluid", "ipp-sco2", cp.co2_per_second } }, fl("ipp-sco2"))
process("ipp-sco2-recuperation", { "ipp-co2-recuperation" }, 1,
  { { "fluid", "ipp-sco2-exhaust", rc.co2_per_second }, { "fluid", "ipp-sco2", rc.co2_per_second } },
  { { "fluid", "ipp-sco2-exhaust", rc.co2_per_second }, { "fluid", "ipp-sco2-warm", rc.co2_per_second } }, fl("ipp-sco2-warm"))
process("ipp-sco2-cooling", { "ipp-co2-cooling" }, 1,
  { { "fluid", "ipp-sco2-exhaust", cl.exhaust_per_second } }, { { "fluid", "ipp-co2", cl.exhaust_per_second } }, fl("ipp-co2"))
process("ipp-blanket-irradiation", { "ipp-irradiation" }, bc.channel_time_s,
  { { "item", "ipp-blanket-assembly", 1 } }, { { "item", "ipp-bred-blanket-assembly", 1 } }, it("ipp-bred-blanket-assembly"))

-- Molten-salt electrolysis: one recipe per loop so the primary and secondary sodium are never mixed up.
process("ipp-primary-sodium-electrolysis", { "ipp-electrolysis" }, el.time_s,
  { { "item", "ipp-dry-sodium-salt", el.salt } },
  { { "fluid", "ipp-primary-sodium", el.sodium }, { "fluid", "ipp-chlorine", el.chlorine } }, fl("ipp-primary-sodium"))
process("ipp-secondary-sodium-electrolysis", { "ipp-electrolysis" }, el.time_s,
  { { "item", "ipp-dry-sodium-salt", el.salt } },
  { { "fluid", "ipp-secondary-sodium", el.sodium }, { "fluid", "ipp-chlorine", el.chlorine } }, fl("ipp-secondary-sodium"))

-- Coolant and working-fluid chemistry (vanilla chemical plants)
local SC = C.sodium_chemistry
process("ipp-brine-preparation", { "chemistry" }, 2,
  { { "fluid", "water", SC.brine_water }, { "item", "stone", SC.brine_stone } },
  { { "fluid", "ipp-brine", SC.brine_out } }, fl("ipp-brine"))
process("ipp-sodium-salt-drying", { "chemistry" }, 2,
  { { "fluid", "ipp-brine", SC.salt_brine } }, { { "item", "ipp-dry-sodium-salt", SC.salt_out } }, it("ipp-dry-sodium-salt"))
-- The kiln is a vanilla chemical plant. Its CO2 is the working fluid of the CO2 loop (fill it with this) and surplus can be vented.
process("ipp-lime-kiln", { "chemistry" }, 2,
  { { "item", "stone", SC.kiln_stone } },
  { { "item", "ipp-lime", SC.kiln_lime }, { "fluid", "ipp-co2", SC.kiln_co2 } }, it("ipp-lime"))
if data.raw.item["calcite"] then   -- Space Age calcite is nearly pure calcium carbonate: half the rock for the same lime
  process("ipp-lime-kiln-calcite", { "chemistry" }, 2,
    { { "item", "calcite", SC.kiln_calcite } },
    { { "item", "ipp-lime", SC.kiln_lime }, { "fluid", "ipp-co2", SC.kiln_co2 } }, it("ipp-lime"))
end
-- Chlorine has two ways out: neutralised with lime (nothing is left over) or used to make chlorinated plastic.
process("ipp-chlorine-neutralization", { "chemistry" }, 2,
  { { "fluid", "ipp-chlorine", SC.neutralize_chlorine }, { "item", "ipp-lime", SC.neutralize_lime } }, {}, fl("ipp-chlorine"))
process("ipp-chlorinated-plastic", { "chemistry" }, 1,
  { { "fluid", "petroleum-gas", SC.plastic_gas }, { "fluid", "ipp-chlorine", SC.plastic_chlorine }, { "item", "coal", SC.plastic_coal } },
  { { "item", "plastic-bar", SC.plastic_out } }, it("plastic-bar"))
-- Lime in construction: a cheaper way to make concrete
data:extend { {
  type = "recipe", name = "ipp-lime-concrete", enabled = false, energy_required = 10,
  categories = { "crafting-with-fluid" },
  ingredients = U.stacks { { "item", "stone-brick", SC.concrete_stone_brick }, { "item", "ipp-lime", SC.concrete_lime },
                           { "item", "iron-stick", 1 }, { "fluid", "water", SC.concrete_water } },
  results = U.stacks { { "item", "concrete", SC.concrete_out } },
  subgroup = "ipp-process", order = "ipp-lime-concrete", icons = it("concrete"), allow_productivity = true,
} }

--------------------------------------------------------------------------------------------------
-- Fuel cycle recipes (fabricator) and the spent-fuel route
--------------------------------------------------------------------------------------------------
local function fabricate(name, ings, result, icons)
  data:extend { {
    type = "recipe", name = name, enabled = false, energy_required = BF.fabrication_time_s,
    categories = { "ipp-fuel-fabrication" }, ingredients = U.stacks(ings), results = U.stacks { { "item", result, 1 } },
    subgroup = "ipp-process", order = name, icons = icons, hide_from_player_crafting = true,
    allow_productivity = false, allow_quality = false, auto_recycle = false,
  } }
end
fabricate("ipp-mox-assembly-fabrication",
  { { "item", "ipp-plutonium-bearing-material", BF.mox.pbm }, { "item", "uranium-238", BF.mox.du }, { "item", "ipp-fuel-cladding", BF.mox.claddings } },
  "ipp-mox-assembly", it("ipp-mox-assembly"))
fabricate("ipp-starter-assembly-fabrication",
  { { "item", "uranium-235", BF.starter.u235 }, { "item", "uranium-238", BF.starter.du }, { "item", "ipp-fuel-cladding", BF.starter.claddings } },
  "ipp-starter-assembly", it("ipp-starter-assembly"))
fabricate("ipp-blanket-assembly-fabrication",
  { { "item", "uranium-238", BF.blanket.du }, { "item", "ipp-fuel-cladding", BF.blanket.claddings } },
  "ipp-blanket-assembly", it("ipp-blanket-assembly"))

-- Hot spent core assemblies cool in the Tier 3 spent-fuel pool and are reprocessed in the Tier 3 reprocessing plant
-- (both machines now take several recipes); bred blanket assemblies go straight to reprocessing.
local sp, rp = C.spent_fuel_pool, C.reprocessing
process("ipp-spent-core-cooling", { "ipp-fuel-cooling" }, sp.cooling_time_s,
  { { "item", "ipp-spent-core-assembly", 1 }, { "fluid", "water", sp.water_per_assembly } },
  { { "item", "ipp-spent-core-assembly-cooled", 1 } }, it("ipp-spent-core-assembly-cooled"))
process("ipp-spent-core-reprocessing", { "ipp-reprocessing" }, rp.time_s,
  { { "item", "ipp-spent-core-assembly-cooled", 1 }, { "fluid", "sulfuric-acid", rp.acid }, { "fluid", "ipp-solvent", rp.solvent } },
  { { "item", "ipp-plutonium-bearing-material", BF.core_reprocessing.pbm }, { "item", "uranium-238", BF.core_reprocessing.du },
    { "item", "ipp-radioactive-residue", BF.core_reprocessing.residue } },
  it("ipp-plutonium-bearing-material"))
process("ipp-bred-blanket-reprocessing", { "ipp-reprocessing" }, rp.time_s,
  { { "item", "ipp-bred-blanket-assembly", 1 }, { "fluid", "sulfuric-acid", rp.acid }, { "fluid", "ipp-solvent", rp.solvent } },
  { { "item", "ipp-plutonium-bearing-material", BF.blanket_reprocessing.pbm }, { "item", "uranium-238", BF.blanket_reprocessing.du },
    { "item", "ipp-radioactive-residue", BF.blanket_reprocessing.residue } },
  it("ipp-bred-blanket-assembly"))

--------------------------------------------------------------------------------------------------
-- Building recipes (components follow the Tier 4 plan table)
--------------------------------------------------------------------------------------------------
local A, SH, CR, RC, PV = "ipp-refractory-alloy", "ipp-nuclear-shielding", "ipp-control-rod-assembly", "ipp-radhard-controller", "ipp-pressure-vessel"
local HP, CS = "ipp-heat-exchanger-panel", "ipp-ceramic-seal"
building("ipp-heat-pipe-2", 2, { { "item", "heat-pipe", 1 }, { "item", A, 2 }, { "item", CS, 1 } })
building(D.FBR, 40, { { "item", F, 30 }, { "item", A, 20 }, { "item", SH, 30 }, { "item", CR, 12 }, { "item", RC, 6 } })
building("ipp-sodium-circulation-unit", 12, { { "item", PV, 3 }, { "item", "ipp-pump-assembly", 4 }, { "item", A, 6 },
  { "item", "ipp-reinforced-pipe", 10 }, { "item", RC, 1 } })
building(D.CHANNEL, 15, { { "item", F, 4 }, { "item", SH, 6 }, { "item", A, 4 }, { "item", CR, 2 } })
building("ipp-intermediate-sodium-exchanger", 15, { { "item", A, 12 }, { "item", HP, 20 }, { "item", CS, 8 }, { "item", SH, 4 } })
building(D.HEATER, 15, { { "item", PV, 4 }, { "item", A, 12 }, { "item", HP, 20 }, { "item", CS, 8 } })
building("ipp-sco2-compressor", 15, { { "item", "ipp-precision-rotor", 4 }, { "item", PV, 3 }, { "item", "ipp-electric-motor", 4 },
  { "item", "ipp-seal-pack", 4 }, { "item", "processing-unit", 4 } })
building("ipp-sco2-turbine-generator", 25, { { "item", F, 4 }, { "item", "ipp-refractory-rotor", 4 }, { "item", "ipp-generator-winding", 8 },
  { "item", "ipp-pressure-housing", 4 }, { "item", "processing-unit", 6 } })
building("ipp-recuperator", 15, { { "item", "ipp-recuperator-matrix", 8 }, { "item", PV, 4 }, { "item", CS, 8 } })
building("ipp-sco2-cooler", 12, { { "item", HP, 24 }, { "item", PV, 3 }, { "item", "ipp-pump-assembly", 4 } })
building("ipp-shielded-fuel-fabricator", 20, { { "item", SH, 12 }, { "item", "ipp-handling-machinery", 4 }, { "item", A, 8 }, { "item", RC, 3 } })
building("ipp-sodium-electrolyzer", 15, { { "item", "ipp-refractory-lining", 12 }, { "item", "ipp-electrode-assembly", 8 },
  { "item", PV, 3 }, { "item", "ipp-control-cabinet", 3 } })
building("ipp-hot-fluid-tank", 10, { { "item", PV, 4 }, { "item", "ipp-refractory-lining", 8 }, { "item", "ipp-thermal-insulation", 10 },
  { "item", "ipp-pump-assembly", 2 } })
