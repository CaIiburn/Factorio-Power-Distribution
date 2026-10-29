-- Tier 3: pressurized-water nuclear power. Every rating comes from config.lua (through shared/defs.lua).
--
--   * Reactor core      : copy of the VANILLA `reactor` prototype, so heat buffer, temperature, neighbour bonus, circuit
--                         connector (temperature / fuel read-out), fuel and burnt-fuel slots and the meltdown explosion
--                         stay native. Only the control rods (scripts/reactors.lua) are scripted.
--   * Circulation unit  : copy of the vanilla heat exchanger (a `boiler`): heat from the core in, cool primary water
--                         in, hot primary water out.
--   * Steam generator, surface condenser, cooling tower, dry cooler, cooling pool, reprocessing plant, vitrifier :
--                         crafting machines with fixed recipes, built like the Tier 2 machines.
--   * High-pressure turbine train : a native fusion-generator (see D.generators and the loop in machines.lua).
--   * Dry-cask storage  : a scaled steel chest.
local D = require("shared.defs")
local U = require("prototypes.ipp-helpers")
local M = require("prototypes.machines")
local C = D.config

local unit, elec, vol = M.unit, M.elec, M.vol
local item_for, build_machine, process, building = M.item_for, M.build_machine, M.process, M.building

--------------------------------------------------------------------------------------------------
-- Items of the fuel cycle
--------------------------------------------------------------------------------------------------
local function plain_item(name, base, tint, order, extra)
  local it = {
    type = "item", name = name, icons = U.icons_of_item(base, tint),
    subgroup = "ipp-fuel-cycle", order = order, stack_size = 10,
  }
  for k, v in pairs(extra or {}) do it[k] = v end
  data:extend { it }
end

plain_item("ipp-fuel-assembly", "uranium-fuel-cell", U.color(0.70, 0.90, 1.00), "a", {
  fuel_category = "ipp-fuel-assembly",
  fuel_value = unit(C.fuel_assembly.energy_gj, "GJ"),
  burnt_result = "ipp-spent-fuel-assembly",
  localised_description = {
    "item-description.ipp-fuel-assembly",
    D.fmt(C.fuel_assembly.energy_gj)
  }
})
plain_item("ipp-spent-fuel-assembly",        "depleted-uranium-fuel-cell", U.color(1.00, 0.45, 0.35), "b")
plain_item("ipp-spent-fuel-assembly-cooled", "depleted-uranium-fuel-cell", U.color(0.60, 0.80, 1.00), "c")
plain_item("ipp-plutonium-bearing-material", "uranium-238",   U.color(0.95, 0.55, 1.00), "d", { stack_size = 50 })
plain_item("ipp-radioactive-residue",        "uranium-238",   U.color(0.55, 0.90, 0.40), "e", { stack_size = 50 })
plain_item("ipp-glass-frit",                 "stone-brick",   U.color(0.70, 0.95, 1.00), "f", { stack_size = 50 })
plain_item("ipp-vitrified-waste-canister",   "barrel",        U.color(0.60, 0.90, 0.50), "g")
--------------------------------------------------------------------------------------------------
-- Reactor core
--------------------------------------------------------------------------------------------------
local RC = C.reactor
local core_tint = U.color(0.75, 0.88, 1.00)
do
  local VR = data.raw["reactor"] and data.raw["reactor"]["nuclear-reactor"]
  assert(VR, "industrial-power-plants: vanilla nuclear-reactor prototype not found")
  local r = U.deepcopy(VR)
  r.name = D.REACTOR
  r.icon, r.icon_size = nil, nil
  r.icons = U.icons_of(data.raw.item["nuclear-reactor"], core_tint)
  r.minable = { mining_time = 0.5, result = D.REACTOR }
  r.fast_replaceable_group, r.next_upgrade, r.placeable_by = nil, nil, nil
  r.max_health = RC.health
  r.consumption = unit(RC.power_mw, "MW")
  r.neighbour_bonus = RC.neighbour_bonus
  -- Own neighbour category: cores boost each other, vanilla reactors do not join the array.
  for _, c in ipairs(r.neighbour_connectable.connections) do
    c.category = "ipp-pwr-reactor"
    c.neighbour_category = { "ipp-pwr-reactor" }
  end
  -- Own fuel: only fuel assemblies burn here (vanilla fuel cells are "nuclear" fuel, not "ipp-fuel-assembly").
  r.energy_source.fuel_categories = { "ipp-fuel-assembly" }
  r.energy_source.fuel_inventory_size = RC.fuel_slots
  r.energy_source.burnt_inventory_size = RC.spent_slots
  r.heat_buffer.max_temperature = RC.max_temperature_c
  r.heat_buffer.specific_heat = unit(RC.specific_heat_mj, "MJ")
  r.temperature_to_suppress_energy_icons = RC.warning_temperature_c
  -- meltdown_action / dying_explosion / corpse are the vanilla ones: the standard reactor explosion, fired when the
  -- core dies above 90 % of its maximum temperature (scripts/reactors.lua kills an overheated core).
  U.restyle(r.picture, 1, core_tint)
  if r.lower_layer_picture then U.restyle(r.lower_layer_picture, 1, core_tint) end
  local desc = { D.fmt(RC.power_mw), D.fmt(RC.warning_temperature_c), D.fmt(RC.meltdown_temperature_c), D.fmt(RC.meltdown_grace_s),
                 D.fmt(RC.rod_speed_pct_per_second), D.fmt(RC.scram_speed_pct_per_second) }
  r.localised_description = { "entity-description." .. D.REACTOR, table.unpack(desc) }
  data:extend { r, item_for(D.REACTOR, "nuclear-reactor", core_tint, "m", nil, desc) }
end

--------------------------------------------------------------------------------------------------
-- Primary circulation / pressurizer unit (vanilla heat exchanger, boiler prototype)
--------------------------------------------------------------------------------------------------
local PU = C.primary_unit
do
  local name = "ipp-primary-circulation-unit"
  local HX = data.raw["boiler"] and data.raw["boiler"]["heat-exchanger"]
  assert(HX, "industrial-power-plants: vanilla heat-exchanger prototype not found")
  local tint = U.color(0.70, 0.85, 1.00)
  local b = U.deepcopy(HX)
  b.name = name
  b.icon, b.icon_size = nil, nil
  b.icons = U.icons_of(data.raw.item["heat-exchanger"], tint)
  b.minable = { mining_time = 0.3, result = name }
  b.fast_replaceable_group, b.next_upgrade, b.placeable_by = nil, nil, nil
  b.max_health = PU.health
  b.mode = "output-to-separate-pipe"
  -- Heats cool primary water from its own temperature to target_temperature and hands it over as hot primary water.
  b.target_temperature = PU.target_c
  b.energy_consumption = unit(PU.power_mw, "MW")
  b.energy_source.min_working_temperature = PU.min_working_c
  local v = math.max(200, D.PRIMARY_FLOW * 3)       -- 3 s of flow (2.1.7 derives throughput from volume)
  b.fluid_box.filter, b.fluid_box.volume = "ipp-primary-water", v
  b.output_fluid_box.filter, b.output_fluid_box.volume = "ipp-primary-water-hot", v
  if b.pictures then U.restyle(b.pictures, 1, tint) end   -- vanilla keeps the boiler sprites in `pictures`
  local desc = { D.fmt(PU.power_mw), D.fmt(D.PRIMARY_FLOW), D.fmt(PU.target_c), D.fmt(PU.min_working_c) }
  b.localised_description = { "entity-description." .. name, table.unpack(desc) }
  data:extend { b, item_for(name, "heat-exchanger", tint, "n", nil, desc) }
end

--------------------------------------------------------------------------------------------------
-- Crafting machines (fixed recipes). Port layout of an unrotated machine, north face = inputs, south = outputs;
-- "left" = the west-side port (lateral -1), "right" = east side (+1). Fluids are assigned to ports in recipe order.
--------------------------------------------------------------------------------------------------
local sg, sc, ct, dc = C.steam_generator, C.surface_condenser, C.cooling_tower, C.dry_cooler
local sp, rp, vt = C.spent_fuel_pool, C.reprocessing, C.vitrifier
local function volume_for(floor, ...) return vol(math.max(...), floor) end

local machines = {
  -- hot primary (left) + feedwater (right) in; steam (left) + cool primary (right) out
  { name = "ipp-nuclear-steam-generator", base = "chemical-plant", size = sg.size, tint = U.color(0.75, 0.88, 1.00), order = "o",
    categories = { "ipp-steam-generation" }, fixed_recipe = "ipp-nuclear-steam-generation", health = sg.health,
    energy_source = elec(unit(sg.idle_drain_kw, "kW")), energy_usage = unit(sg.power_mw, "MW"),
    desc = { D.fmt(sg.hot_primary_per_second), D.fmt(sg.water_per_second), D.fmt(sg.steam_per_second), D.fmt(sg.power_mw) },
    fluid_boxes = (function()
      local v = volume_for(2000, sg.hot_primary_per_second, sg.water_per_second, sg.steam_per_second, sg.cool_primary_per_second)
      return { { kind = "input", dir = "north", lat = -1, volume = v }, { kind = "input", dir = "north", lat = 1, volume = v },
               { kind = "output", dir = "south", lat = -1, volume = v }, { kind = "output", dir = "south", lat = 1, volume = v } }
    end)() },

  -- exhaust steam (left) + cool cooling water (right) in; feedwater (left) + warm cooling water (right) out
  { name = "ipp-surface-condenser", base = "chemical-plant", size = sc.size, tint = U.color(0.70, 0.90, 1.00), order = "p",
    categories = { "ipp-surface-condensing" }, fixed_recipe = "ipp-surface-condensation", health = sc.health,
    energy_source = elec(unit(sc.idle_drain_kw, "kW")), energy_usage = unit(sc.power_kw, "kW"),
    desc = { D.fmt(sc.exhaust_steam_per_second), D.fmt(sc.cooling_water_per_second), D.fmt(sc.water_per_second) },
    fluid_boxes = (function()
      local v = volume_for(1000, sc.exhaust_steam_per_second, sc.cooling_water_per_second, sc.water_per_second)
      return { { kind = "input", dir = "north", lat = -1, volume = v }, { kind = "input", dir = "north", lat = 1, volume = v },
               { kind = "output", dir = "south", lat = -1, volume = v }, { kind = "output", dir = "south", lat = 1, volume = v } }
    end)() },

  -- warm cooling water (left) + makeup water (right) in; cool cooling water out
  { name = "ipp-cooling-tower", base = "chemical-plant", size = ct.size, tint = U.color(0.80, 0.85, 0.90), order = "q",
    categories = { "ipp-evaporative-cooling" }, fixed_recipe = "ipp-cooling-tower-cycle", health = ct.health,
    energy_source = elec(unit(ct.idle_drain_kw, "kW")), energy_usage = unit(ct.power_kw, "kW"),
    desc = { D.fmt(ct.warm_per_second), D.fmt(ct.makeup_per_second) },
    fluid_boxes = (function()
      local v = volume_for(1000, ct.warm_per_second, ct.makeup_per_second)
      return { { kind = "input", dir = "north", lat = -1, volume = v }, { kind = "input", dir = "north", lat = 1, volume = v },
               { kind = "output", dir = "south", lat = 0, volume = v } }
    end)() },

  { name = "ipp-dry-cooler", base = "chemical-plant", size = dc.size, tint = U.color(0.95, 0.85, 0.70), order = "r",
    categories = { "ipp-dry-cooling" }, fixed_recipe = "ipp-dry-cooler-cycle", health = dc.health,
    energy_source = elec(unit(dc.idle_drain_kw, "kW")), energy_usage = unit(dc.power_mw, "MW"),
    desc = { D.fmt(dc.warm_per_second), D.fmt(dc.power_mw) },
    fluid_boxes = (function()
      local v = volume_for(1000, dc.warm_per_second)
      return { { kind = "input", dir = "north", lat = 0, volume = v }, { kind = "output", dir = "south", lat = 0, volume = v } }
    end)() },

  -- hot spent assembly + water -> cooled spent assembly after a fixed time
  { name = "ipp-spent-fuel-pool", base = "assembling-machine-3", size = sp.size, tint = U.color(0.55, 0.80, 1.00), order = "s",
    categories = { "ipp-fuel-cooling" }, fixed_recipe = "ipp-spent-fuel-cooling", health = sp.health,
    energy_source = elec(unit(sp.idle_drain_kw, "kW")), energy_usage = unit(sp.power_kw, "kW"),
    desc = { D.fmt(sp.cooling_time_s), D.fmt(sp.water_per_assembly) },
    fluid_boxes = { { kind = "input", dir = "north", lat = 0, volume = volume_for(1000, sp.water_per_assembly) } } },

  -- cooled assembly + acid (left) + solvent (right) -> uranium, plutonium-bearing material, residue
  { name = "ipp-reprocessing-plant", base = "centrifuge", size = rp.size, tint = U.color(0.85, 1.00, 0.70), order = "u",
    categories = { "ipp-reprocessing" }, fixed_recipe = "ipp-spent-fuel-reprocessing", health = rp.health,
    energy_source = elec(unit(rp.idle_drain_kw, "kW")), energy_usage = unit(rp.power_mw, "MW"),
    desc = { D.fmt(rp.time_s), D.fmt(rp.acid), D.fmt(rp.solvent) },
    fluid_boxes = (function()
      local v = volume_for(1000, rp.acid, rp.solvent)
      return { { kind = "input", dir = "north", lat = -1, volume = v }, { kind = "input", dir = "north", lat = 1, volume = v } }
    end)() },

  { name = "ipp-waste-vitrifier", base = "assembling-machine-3", size = vt.size, tint = U.color(1.00, 0.80, 0.55), order = "v",
    categories = { "ipp-vitrification" }, fixed_recipe = "ipp-vitrification", health = vt.health,
    energy_source = elec(unit(vt.idle_drain_kw, "kW")), energy_usage = unit(vt.power_mw, "MW"),
    desc = { D.fmt(vt.residue), D.fmt(vt.frit), D.fmt(vt.time_s) } },
}
for _, m in ipairs(machines) do build_machine(m) end

--------------------------------------------------------------------------------------------------
-- Dry-cask storage: steel chest scaled to config dry_cask.size
--------------------------------------------------------------------------------------------------
do
  local name, DC = "ipp-dry-cask-storage", C.dry_cask
  local SC = data.raw["container"] and data.raw["container"]["steel-chest"]
  assert(SC, "industrial-power-plants: vanilla steel-chest prototype not found")
  local tint = U.color(0.70, 0.78, 0.70)
  local c = U.deepcopy(SC)
  c.name = name
  c.icon, c.icon_size = nil, nil
  c.icons = U.icons_of(data.raw.item["steel-chest"], tint)
  c.minable = { mining_time = 0.5, result = name }
  c.fast_replaceable_group, c.next_upgrade, c.placeable_by = nil, nil, nil
  c.max_health = DC.health
  c.inventory_size = DC.inventory_slots
  local half, f = DC.size / 2, DC.size          -- the vanilla chest is 1 x 1
  c.selection_box = { { -half, -half }, { half, half } }
  c.collision_box = { { -half + 0.1, -half + 0.1 }, { half - 0.1, half - 0.1 } }
  U.restyle(c.picture, f, tint)
  if c.water_reflection then U.restyle(c.water_reflection, f) end
  if c.circuit_connector then U.scale_connector_positions(c.circuit_connector, f) end
  if c.alert_icon_shift then c.alert_icon_shift = { c.alert_icon_shift[1] * f, c.alert_icon_shift[2] * f } end
  c.localised_description = { "entity-description." .. name, D.fmt(DC.inventory_slots) }
  data:extend { c, item_for(name, "steel-chest", tint, "t", nil, { D.fmt(DC.inventory_slots) }) }
end

--------------------------------------------------------------------------------------------------
-- Process recipes (fixed-recipe machines)
--------------------------------------------------------------------------------------------------
local fl, it = U.icons_of_fluid, U.icons_of_item
process("ipp-nuclear-steam-generation", { "ipp-steam-generation" }, 1,
  { { "fluid", "ipp-primary-water-hot", sg.hot_primary_per_second }, { "fluid", "water", sg.water_per_second } },
  { { "fluid", "ipp-hp-steam", sg.steam_per_second }, { "fluid", "ipp-primary-water", sg.cool_primary_per_second } },
  fl("ipp-hp-steam"))
process("ipp-surface-condensation", { "ipp-surface-condensing" }, 1,
  { { "fluid", "ipp-exhaust-steam", sc.exhaust_steam_per_second }, { "fluid", "ipp-cooling-water", sc.cooling_water_per_second } },
  { { "fluid", "water", sc.water_per_second }, { "fluid", "ipp-cooling-water-warm", sc.cooling_water_per_second } },
  fl("ipp-cooling-water-warm"))
process("ipp-cooling-tower-cycle", { "ipp-evaporative-cooling" }, 1,
  { { "fluid", "ipp-cooling-water-warm", ct.warm_per_second }, { "fluid", "water", ct.makeup_per_second } },
  { { "fluid", "ipp-cooling-water", ct.warm_per_second } }, fl("ipp-cooling-water"))
process("ipp-dry-cooler-cycle", { "ipp-dry-cooling" }, 1,
  { { "fluid", "ipp-cooling-water-warm", dc.warm_per_second } },
  { { "fluid", "ipp-cooling-water", dc.warm_per_second } }, fl("ipp-cooling-water"))
process("ipp-spent-fuel-cooling", { "ipp-fuel-cooling" }, sp.cooling_time_s,
  { { "item", "ipp-spent-fuel-assembly", 1 }, { "fluid", "water", sp.water_per_assembly } },
  { { "item", "ipp-spent-fuel-assembly-cooled", 1 } }, it("ipp-spent-fuel-assembly-cooled"))
process("ipp-spent-fuel-reprocessing", { "ipp-reprocessing" }, rp.time_s,
  { { "item", "ipp-spent-fuel-assembly-cooled", 1 }, { "fluid", "sulfuric-acid", rp.acid }, { "fluid", "ipp-solvent", rp.solvent } },
  { { "item", "uranium-238", rp.uranium_238 }, { "item", "uranium-235", rp.uranium_235, nil, rp.uranium_235_chance },
    { "item", "ipp-plutonium-bearing-material", rp.plutonium }, { "item", "ipp-radioactive-residue", rp.residue } },
  it("ipp-plutonium-bearing-material"))
process("ipp-vitrification", { "ipp-vitrification" }, vt.time_s,
  { { "item", "ipp-radioactive-residue", vt.residue }, { "item", "ipp-glass-frit", vt.frit } },
  { { "item", "ipp-vitrified-waste-canister", 1 } }, it("ipp-vitrified-waste-canister"))

--------------------------------------------------------------------------------------------------
-- Hand / assembler / chemical-plant recipes
--------------------------------------------------------------------------------------------------
local function recipe(name, time, ings, results, cats, extra)
  local r = {
    type = "recipe", name = name, enabled = false, energy_required = time,
    categories = cats or { "crafting" }, ingredients = U.stacks(ings), results = U.stacks(results),
  }
  for k, v in pairs(extra or {}) do r[k] = v end
  data:extend { r }
end
local F = "ipp-structural-frame"
recipe("ipp-fuel-assembly", 15,
  { { "item", "uranium-fuel-cell", C.fuel_assembly.cells }, { "item", "ipp-fuel-cladding", C.fuel_assembly.claddings }, { "item", F, 1 } },
  { { "item", "ipp-fuel-assembly", 1 } })
recipe("ipp-glass-frit", 3, { { "item", "stone-brick", 6 }, { "item", "sulfur", 2 } }, { { "item", "ipp-glass-frit", 2 } })
recipe("ipp-solvent", 2, { { "fluid", "light-oil", 30 }, { "fluid", "sulfuric-acid", 5 } }, { { "fluid", "ipp-solvent", 25 } },
  { "chemistry" }, { subgroup = "ipp-fluids", order = "k", icons = fl("ipp-solvent") })

--------------------------------------------------------------------------------------------------
-- Building recipes (components follow the Tier 3 plan table)
--------------------------------------------------------------------------------------------------
building(D.REACTOR, 30, { { "item", F, 20 }, { "item", "ipp-pressure-vessel", 6 }, { "item", "ipp-nuclear-shielding", 20 },
  { "item", "ipp-control-rod-assembly", 8 }, { "item", "ipp-radhard-controller", 4 } })
building("ipp-primary-circulation-unit", 10, { { "item", "ipp-pressure-vessel", 3 }, { "item", "ipp-pump-assembly", 4 },
  { "item", "ipp-reinforced-pipe", 10 }, { "item", "ipp-radhard-controller", 1 } })
building("ipp-nuclear-steam-generator", 15, { { "item", "ipp-pressure-vessel", 4 }, { "item", "ipp-heat-exchanger-panel", 16 },
  { "item", "ipp-nuclear-shielding", 4 }, { "item", "ipp-reinforced-pipe", 10 } })
building("ipp-hp-turbine-generator", 20, { { "item", F, 4 }, { "item", "ipp-high-speed-rotor", 4 }, { "item", "ipp-generator-winding", 6 },
  { "item", "ipp-pressure-vessel", 3 }, { "item", "ipp-control-cabinet", 3 } })
building("ipp-surface-condenser", 12, { { "item", F, 3 }, { "item", "ipp-heat-exchanger-panel", 16 }, { "item", "ipp-pump-assembly", 3 },
  { "item", "pipe", 20 } })
-- Cooling tower and dry cooler share one recipe.
local cooler = { { "item", F, 4 }, { "item", "ipp-heat-exchanger-panel", 8 }, { "item", "ipp-pump-assembly", 2 }, { "item", "concrete", 20 } }
building("ipp-cooling-tower", 10, cooler)
building("ipp-dry-cooler", 10, cooler)
building("ipp-spent-fuel-pool", 15, { { "item", "concrete", 50 }, { "item", "steel-plate", 30 }, { "item", "ipp-nuclear-shielding", 6 },
  { "item", "ipp-pump-assembly", 2 }, { "item", "ipp-radhard-controller", 1 } })
building("ipp-dry-cask-storage", 8, { { "item", "concrete", 40 }, { "item", "steel-plate", 20 }, { "item", "ipp-nuclear-shielding", 4 } })
building("ipp-reprocessing-plant", 20, { { "item", "ipp-nuclear-shielding", 10 }, { "item", "ipp-pressure-vessel", 4 },
  { "item", "ipp-chemical-resistant-pipe", 12 }, { "item", "ipp-pump-assembly", 4 }, { "item", "ipp-radhard-controller", 3 } })
building("ipp-waste-vitrifier", 15, { { "item", "ipp-refractory-lining", 10 }, { "item", "ipp-nuclear-shielding", 6 },
  { "item", "ipp-heating-element", 6 }, { "item", "ipp-electric-motor", 4 }, { "item", F, 2 } })
