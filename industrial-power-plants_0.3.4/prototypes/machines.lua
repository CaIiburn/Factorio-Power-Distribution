-- Buildings and process recipes.
--   * Turbine-generators are NATIVE fusion-generator entities: one input fluid in, electricity out,
--     a second fluid returned through the output fluid box (no scripting, no hidden buffers).
--   * Boilers, condensers, conditioners and heat-recovery generators are crafting machines with fixed recipes.
local D = require("shared.defs")
local U = require("prototypes.ipp-helpers")

local dir = defines.direction
local AM = data.raw["assembling-machine"]

--------------------------------------------------------------------------------------------------
-- Fluid boxes for crafting machines. Pipe pictures/covers come from the base machine itself (or a
-- vanilla chemical plant); connection `position` must lie INSIDE the entity on its edge tile and
-- `direction` points outward, so the edge tile is derived from the base machine's real size.
--------------------------------------------------------------------------------------------------
local function edge_tile(base, side, lat)
  local sb = base.selection_box or base.collision_box
  local half = math.max(math.abs(sb[1][1]), math.abs(sb[1][2]), math.abs(sb[2][1]), math.abs(sb[2][2]))
  local edge = math.floor(half * 2 + 0.5) / 2 - 0.5
  if side == "north" then return { lat, -edge }
  elseif side == "south" then return { lat, edge }
  elseif side == "east" then return { edge, lat }
  else return { -edge, lat } end
end

local function build_fluid_boxes(base, boxes)
  local tpl = (base.fluid_boxes and base.fluid_boxes[1])
      or (AM["chemical-plant"] and AM["chemical-plant"].fluid_boxes and AM["chemical-plant"].fluid_boxes[1])
      or AM["assembling-machine-2"].fluid_boxes[1]
  local out = {}
  for _, b in ipairs(boxes) do
    local fb = U.deepcopy(tpl)
    fb.production_type = b.kind
    fb.volume = b.volume or 1000
    fb.filter = nil
    fb.minimum_temperature, fb.maximum_temperature = nil, nil   -- removed in 2.1.22; loading them is an error
    fb.enable_working_visualisations = nil   -- would reference visualisation names of the template
    -- The editor's PipeConnectionDefinition typedef marks defaulted fields (connection_type, positions,
    -- connection_category, hide_connection_info) as required; the game treats them as optional.
    ---@diagnostic disable: missing-fields
    fb.pipe_connections = { {
      flow_direction = b.kind,
      direction = dir[b.dir],
      position = edge_tile(base, b.dir, b.lat),
    } }
    ---@diagnostic enable: missing-fields
    out[#out + 1] = fb
  end
  return out
end

local function item_for(name, base_item, tint, order)
  return {
    type = "item", name = name, icons = U.icons_of(data.raw.item[base_item], tint),
    subgroup = "ipp-power-buildings", order = order, place_result = name, stack_size = 10,
  }
end

--------------------------------------------------------------------------------------------------
-- Crafting-machine builder (graphics_set is kept intact apart from tint/scale so every name that
-- visual states, sounds and fluid boxes use to refer to working visualisations stays valid).
--------------------------------------------------------------------------------------------------
local function build_machine(s)
  local base = AM[s.base]
  assert(base, "industrial-power-plants: missing base prototype " .. s.base)
  local p = U.deepcopy(base)
  p.name = s.name
  p.icon, p.icon_size = nil, nil
  p.icons = U.icons_of(data.raw.item[s.base] or base, s.tint)
  p.minable = { mining_time = 0.5, result = s.name }
  p.fast_replaceable_group, p.next_upgrade, p.placeable_by = nil, nil, nil
  p.max_health = s.health or 400
  p.crafting_speed = 1
  p.crafting_categories = s.categories
  p.fixed_recipe = s.fixed_recipe
  p.energy_source = s.energy_source
  p.energy_usage = s.energy_usage
  p.module_slots = 0
  p.allowed_effects = nil
  -- Replaces the base machine's intrinsic effects (e.g. the foundry's productivity bonus). The editor typedef
  -- lists the *_limits and uses_local_effects fields as required; they are optional in the game.
  ---@diagnostic disable: missing-fields
  p.effect_receiver = { base_effect = {}, uses_module_effects = false,
                        uses_beacon_effects = false, uses_surface_effects = false }
  ---@diagnostic enable: missing-fields
  if s.fluid_boxes then
    p.fluid_boxes = build_fluid_boxes(base, s.fluid_boxes)
    p.fluid_boxes_off_when_no_fluid_recipe = false
  else
    p.fluid_boxes = nil
  end
  if p.graphics_set then U.restyle(p.graphics_set, s.scale or 1, s.tint) end
  if p.graphics_set_flipped then U.restyle(p.graphics_set_flipped, s.scale or 1, s.tint) end
  data:extend { p, item_for(s.name, s.base, s.tint, s.order) }
end

local function elec(drain, pollution)
  local e = { type = "electric", usage_priority = "secondary-input", drain = drain }
  if pollution then e.emissions_per_minute = { pollution = pollution } end
  return e
end
local VOID = { type = "void" }

local mach = {
  { name = "ipp-coal-mill", base = "assembling-machine-2", tint = U.color(0.62, 0.62, 0.70), order = "a",
    categories = { "ipp-milling" }, fixed_recipe = "ipp-coal-charge",
    energy_source = elec("20kW"), energy_usage = "400kW" },

  { name = "ipp-industrial-boiler", base = "foundry", tint = U.color(0.85, 0.65, 0.55), order = "b",
    categories = { "ipp-boiling" }, fixed_recipe = "ipp-boiler-cycle", health = 600,
    energy_source = { type = "burner", fuel_categories = { "ipp-graded-coal" }, effectivity = 1,
                      fuel_inventory_size = 1, burnt_inventory_size = 1,
                      emissions_per_minute = { pollution = 195 } },
    energy_usage = "13.2MW",
    fluid_boxes = { { kind = "input",  dir = "south", lat = 0 },
                    { kind = "output", dir = "north", lat = 0 } } },

  { name = "ipp-air-condenser", base = "chemical-plant", tint = U.color(0.70, 0.88, 1.00), order = "d",
    categories = { "ipp-condensing" }, fixed_recipe = "ipp-condensation",
    energy_source = elec("10kW"), energy_usage = "250kW",
    fluid_boxes = { { kind = "input",  dir = "north", lat = 0 },
                    { kind = "output", dir = "south", lat = 0 } } },

  { name = D.STACK, base = "assembling-machine-1", tint = U.color(0.50, 0.50, 0.55), order = "e",
    categories = { "ipp-venting" }, energy_source = VOID, energy_usage = "1kW",
    fluid_boxes = { { kind = "input", dir = "north", lat = 0, volume = 2000 } } },

  { name = "ipp-waste-compactor", base = "assembling-machine-1", tint = U.color(0.65, 0.55, 0.45), order = "f",
    categories = { "ipp-compacting" }, fixed_recipe = "ipp-ash-compaction",
    energy_source = elec("10kW"), energy_usage = "150kW" },

  -- Tier 2: the conditioner is the compressor train. It needs grid power, so a dead grid cannot
  -- restart the gas turbines (startup requirement); its emissions stand in for combustion pollution.
  { name = "ipp-fuel-gas-conditioner", base = "chemical-plant", tint = U.color(0.65, 0.95, 0.80), order = "g",
    categories = { "ipp-gas-conditioning" }, fixed_recipe = "ipp-fuel-gas-conditioning",
    energy_source = elec("100kW", 600), energy_usage = "4MW",
    fluid_boxes = { { kind = "input",  dir = "north", lat = 0 },
                    { kind = "output", dir = "south", lat = 0 } } },

  { name = "ipp-heat-recovery-steam-generator", base = "chemical-plant", tint = U.color(1.00, 0.78, 0.55), order = "i",
    categories = { "ipp-heat-recovery" }, fixed_recipe = "ipp-heat-recovery",
    energy_source = elec("20kW"), energy_usage = "500kW",
    fluid_boxes = { { kind = "input",  dir = "north", lat = -1, volume = 2000 },
                    { kind = "input",  dir = "north", lat = 1,  volume = 2000 },
                    { kind = "output", dir = "south", lat = -1, volume = 2000 },
                    { kind = "output", dir = "south", lat = 1,  volume = 2000 } } },
}
for _, m in ipairs(mach) do build_machine(m) end

--------------------------------------------------------------------------------------------------
-- Native turbine-generators (fusion-generator prototype).
-- Pipe layout, size and graphics are the vanilla fusion generator's; only fluids, rating and tint change.
--------------------------------------------------------------------------------------------------
local FG = data.raw["fusion-generator"] and data.raw["fusion-generator"]["fusion-generator"]
assert(FG, "industrial-power-plants: vanilla fusion-generator prototype not found (Space Age required)")

-- Boxes may be {{x1,y1},{x2,y2}} or {left_top=..., right_bottom=...}.
local function box_corners(b)
  if b.left_top then return b.left_top.x or b.left_top[1], b.left_top.y or b.left_top[2],
                            b.right_bottom.x or b.right_bottom[1], b.right_bottom.y or b.right_bottom[2] end
  return b[1][1], b[1][2], b[2][1], b[2][2]
end

-- Scale the vanilla footprint by an integer factor. The selection box grows by `s`; the collision box is the
-- selection box minus the vanilla 0.3 tile margin, so edge-tile pipe connections stay inside it.
local function scaled_boxes(s)
  local x1, y1, x2, y2 = box_corners(FG.selection_box or FG.collision_box)
  local sx1, sy1, sx2, sy2 = x1 * s, y1 * s, x2 * s, y2 * s
  return { { sx1, sy1 }, { sx2, sy2 } },
         { { sx1 + 0.3, sy1 + 0.3 }, { sx2 - 0.3, sy2 - 0.3 } },
         math.floor((sx2 - sx1) + 0.5), math.floor((sy2 - sy1) + 0.5)
end

-- Rebuild the pipe connections of a vanilla fusion-generator fluid box.
--   * Position is re-seated on the edge tile of the (scaled) footprint, on the connection's original side.
--   * Only flow_direction, direction and position are kept. Everything else the vanilla connection carries
--     (notably connection_category - Space Age uses a special category for fusion plasma so that ordinary pipes
--     cannot attach - plus connection_type / linked ids / alt positions) is dropped, which gives a plain
--     "default" connection that normal pipes connect to.
local function snap(v, size)            -- nearest valid tile centre for this footprint parity, symmetric about 0
  if size % 2 == 1 then return math.floor(v + 0.5) end
  local sign = (v < 0) and -1 or 1
  return sign * (math.floor(math.abs(v)) + 0.5)
end

local function rebuild_connections(box, boxname, s, w, h)
  local rebuilt = {}
  for _, c in ipairs(box.pipe_connections) do
    assert(c.position, "industrial-power-plants: fusion generator connection without a single `position`")
    local px, py = c.position[1] or c.position.x, c.position[2] or c.position.y
    local d = c.direction
    local pos
    if d == dir.north then pos = { snap(px * s, w), -(h / 2 - 0.5) }
    elseif d == dir.south then pos = { snap(px * s, w), h / 2 - 0.5 }
    elseif d == dir.east then pos = { w / 2 - 0.5, snap(py * s, h) }
    else pos = { -(w / 2 - 0.5), snap(py * s, h) } end
    local dropped = {}
    for k in pairs(c) do
      if k ~= "flow_direction" and k ~= "direction" and k ~= "position" then dropped[#dropped + 1] = k end
    end
    if #dropped > 0 then
      table.sort(dropped)
      log("industrial-power-plants: " .. boxname .. " connection dropped fields: " .. table.concat(dropped, ", ")
          .. (c.connection_category and (" (connection_category=" .. serpent.line(c.connection_category) .. ")") or ""))
    end
    rebuilt[#rebuilt + 1] = { flow_direction = c.flow_direction, direction = d, position = pos }
  end
  box.pipe_connections = rebuilt
end

for name, g in pairs(D.generators) do
  local s = g.scale or 1
  local p = U.deepcopy(FG)
  ---@cast p table  -- older editor typedefs lack some 2.1.x fields we clear below
  p.name = name
  p.icon, p.icon_size = nil, nil
  p.icons = U.icons_of(data.raw.item["fusion-generator"], g.tint)
  p.minable = { mining_time = 0.5, result = name }
  p.fast_replaceable_group, p.next_upgrade, p.placeable_by = nil, nil, nil
  p.max_health = 600 * s
  p.energy_source = U.deepcopy(FG.energy_source)
  p.energy_source.output_flow_limit = string.format("%.1fMW", g.flow_mw)
  p.input_fluid_box.filter = g.input
  p.output_fluid_box.filter = g.output
  -- Burning generators ignore temperature. Make sure no inherited temperature limits or removed keys survive.
  p.input_fluid_box.minimum_temperature, p.input_fluid_box.maximum_temperature = nil, nil
  p.output_fluid_box.minimum_temperature, p.output_fluid_box.maximum_temperature = nil, nil
  p.minimum_input_temperature, p.maximum_input_temperature = nil, nil
  -- Since 2.1.7 pipe throughput comes from fluid-box volume: give each box at least 3 seconds of flow.
  p.input_fluid_box.volume = math.max(p.input_fluid_box.volume or 0, g.per_second * 3)
  p.output_fluid_box.volume = math.max(p.output_fluid_box.volume or 0, g.per_second * 3)
  p.max_fluid_usage = g.per_second / 60
  p.burns_fluid = g.burns
  p.effectivity = g.effectivity
  do
    local sel, col, w, h = scaled_boxes(s)
    if s ~= 1 then p.selection_box, p.collision_box = sel, col end
    rebuild_connections(p.input_fluid_box, name .. ".input_fluid_box", s, w, h)
    rebuild_connections(p.output_fluid_box, name .. ".output_fluid_box", s, w, h)
  end
  if s ~= 1 then
    p.input_fluid_box.volume = (p.input_fluid_box.volume or 100) * s * s
    p.output_fluid_box.volume = (p.output_fluid_box.volume or 100) * s * s
    if p.drawing_box_vertical_extension then p.drawing_box_vertical_extension = p.drawing_box_vertical_extension * s end
  end
  if p.graphics_set then U.restyle(p.graphics_set, s, g.tint) end
  data:extend { p, item_for(name, "fusion-generator", g.tint, g.order) }
end

--------------------------------------------------------------------------------------------------
-- Startup-energy bank: scaled/tinted accumulator.
--------------------------------------------------------------------------------------------------
do
  local acc = U.deepcopy(data.raw["accumulator"]["accumulator"])
  local tint = U.color(0.75, 0.85, 1.0)
  acc.name = "ipp-startup-bank"
  acc.icon, acc.icon_size = nil, nil
  acc.icons = U.icons_of(data.raw.item["accumulator"], tint)
  acc.minable = { mining_time = 0.5, result = "ipp-startup-bank" }
  acc.fast_replaceable_group, acc.next_upgrade, acc.placeable_by = nil, nil, nil
  acc.max_health = 500
  acc.collision_box = { { -1.4, -1.4 }, { 1.4, 1.4 } }
  acc.selection_box = { { -1.5, -1.5 }, { 1.5, 1.5 } }
  acc.energy_source = { type = "electric", buffer_capacity = "200MJ", usage_priority = "tertiary",
                        input_flow_limit = "5MW", output_flow_limit = "20MW" }
  U.restyle(acc.chargable_graphics, 1.5, tint)
  if acc.water_reflection then U.restyle(acc.water_reflection, 1.5) end
  data:extend { acc, item_for("ipp-startup-bank", "accumulator", tint, "k") }
end

--------------------------------------------------------------------------------------------------
-- Process recipes. No fluid temperatures are stamped: steam keeps its default temperature and carries its
-- energy as a fuel value (STEAM_KJ per unit), so every pipe and port can connect.
--------------------------------------------------------------------------------------------------
local BOILER_UNITS = 13.2 * 1000 / D.STEAM_KJ            -- 264 steam/s per boiler
local ST_LARGE = D.generators["ipp-large-steam-turbine-generator"].per_second   -- 450
local GT = D.generators["ipp-gas-turbine-generator"].per_second                 -- 84

local function process(name, cats, time, ings, results, icons, extra)
  local r = {
    type = "recipe", name = name, categories = cats, enabled = false, energy_required = time,
    ingredients = U.stacks(ings), results = U.stacks(results),
    subgroup = "ipp-process", order = name, icons = icons, hide_from_player_crafting = true,
    allow_productivity = false, allow_quality = false, auto_recycle = false,
  }
  for k, v in pairs(extra or {}) do r[k] = v end
  data:extend { r }
end

local fl = U.icons_of_fluid
process("ipp-coal-charge", { "ipp-milling" }, 1, { { "item", "coal", D.CHARGE_COAL } },
  { { "item", "ipp-coal-charge", 1 } }, U.icons_of_item("ipp-coal-charge"))
process("ipp-ash-compaction", { "ipp-compacting" }, 2, { { "item", "ipp-ash", 20 } },
  { { "item", "ipp-ash-block", 1 } }, U.icons_of_item("ipp-ash-block"))
process("ipp-boiler-cycle", { "ipp-boiling" }, 1, { { "fluid", "water", BOILER_UNITS } },
  { { "fluid", "ipp-industrial-steam", BOILER_UNITS } }, fl("ipp-industrial-steam"))
process("ipp-condensation", { "ipp-condensing" }, 1, { { "fluid", "ipp-exhaust-steam", 270 } },
  { { "fluid", "water", 260 } }, U.icons_of_fluid("water"))
process("ipp-fuel-gas-conditioning", { "ipp-gas-conditioning" }, 1, { { "fluid", "petroleum-gas", 105 } },
  { { "fluid", "ipp-fuel-gas", GT } }, fl("ipp-fuel-gas"))
process("ipp-heat-recovery", { "ipp-heat-recovery" }, 1,
  { { "fluid", "ipp-hot-exhaust", GT }, { "fluid", "water", ST_LARGE } },
  { { "fluid", "ipp-industrial-steam", ST_LARGE }, { "fluid", "ipp-flue-gas", GT } },
  fl("ipp-industrial-steam"))

-- Venting: recipes with no products (the fluid is discarded), generated from the vent list in defs.lua.
-- The exhaust stack picks among them automatically (scripts/stacks.lua); only listed fluids can be vented.
local vent_fluids = {}
for fluid_name in pairs(D.vent.allowed) do vent_fluids[#vent_fluids + 1] = fluid_name end
table.sort(vent_fluids)
for _, fluid_name in ipairs(vent_fluids) do
  local v = D.vent.allowed[fluid_name]
  process(v.recipe, { "ipp-venting" }, 1, { { "fluid", fluid_name, v.rate } }, {}, fl(fluid_name))
end

-- Ash as a partial concrete ingredient (fewer bricks, uses residue).
data:extend { {
  type = "recipe", name = "ipp-ash-concrete", categories = { "crafting-with-fluid" }, enabled = false,
  energy_required = 10,
  ingredients = U.stacks { { "item", "stone-brick", 3 }, { "item", "iron-ore", 1 },
                           { "item", "ipp-ash", 4 }, { "fluid", "water", 100 } },
  results = U.stacks { { "item", "concrete", 10 } },
  main_product = "concrete", allow_productivity = true,
} }

--------------------------------------------------------------------------------------------------
-- Building recipes
--------------------------------------------------------------------------------------------------
local function building(name, time, ings)
  data:extend { {
    type = "recipe", name = name, enabled = false, energy_required = time,
    ingredients = U.stacks(ings), results = { { type = "item", name = name, amount = 1 } },
  } }
end
local F, M, G, R = "ipp-structural-frame", "ipp-electric-motor", "iron-gear-wheel", "ipp-refractory-lining"
building("ipp-coal-mill", 5, { {"item",F,1}, {"item",G,20}, {"item",M,2}, {"item","electronic-circuit",10} })
building("ipp-industrial-boiler", 10, { {"item",F,3}, {"item","steel-plate",20}, {"item","pipe",20}, {"item",R,4}, {"item","ipp-heat-exchanger-panel",6} })
building("ipp-steam-turbine-generator", 10, { {"item",F,2}, {"item","ipp-turbine-rotor",2}, {"item","ipp-generator-winding",2}, {"item","pipe",10}, {"item","electronic-circuit",10} })
building("ipp-air-condenser", 8, { {"item",F,2}, {"item","ipp-heat-exchanger-panel",8}, {"item",M,2}, {"item","pipe",10} })
building("ipp-exhaust-stack", 5, { {"item",F,1}, {"item","pipe",10}, {"item",R,2} })
building("ipp-waste-compactor", 5, { {"item",F,1}, {"item",G,20}, {"item",M,2}, {"item","electronic-circuit",5} })
building("ipp-fuel-gas-conditioner", 10, { {"item",F,3}, {"item","ipp-pressure-vessel",2}, {"item","ipp-high-speed-rotor",2}, {"item","ipp-seal-pack",2}, {"item","ipp-control-cabinet",1} })
building("ipp-gas-turbine-generator", 15, { {"item",F,5}, {"item","ipp-high-speed-rotor",3}, {"item","ipp-generator-winding",6}, {"item","ipp-heat-resistant-alloy",20}, {"item","ipp-control-cabinet",3} })
building("ipp-heat-recovery-steam-generator", 12, { {"item",F,3}, {"item","ipp-pressure-vessel",3}, {"item","ipp-heat-exchanger-panel",12}, {"item","pipe",20}, {"item","ipp-pump-assembly",2} })
building("ipp-large-steam-turbine-generator", 15, { {"item",F,4}, {"item","ipp-turbine-rotor",4}, {"item","ipp-high-speed-rotor",2}, {"item","ipp-generator-winding",4}, {"item","ipp-pressure-vessel",2}, {"item","ipp-control-cabinet",1} })
building("ipp-startup-bank", 10, { {"item",F,2}, {"item","ipp-turbine-rotor",2}, {"item","ipp-generator-winding",4}, {"item","battery",30} })
