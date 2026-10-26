-- Buildings and process recipes. Every rating comes from config.lua (through shared/defs.lua).
--   * Turbine-generators are NATIVE fusion-generator entities: one input fluid in, electricity out,
--     a second fluid returned through the output fluid box (no scripting, no hidden buffers).
--   * Condensers, conditioners and heat-recovery generators are crafting machines with fixed recipes.
local D = require("shared.defs")
local U = require("prototypes.ipp-helpers")
local C = D.config

local dir = defines.direction
local AM = data.raw["assembling-machine"]
local GFX = "__industrial-power-plants__/graphics/"

-- "4" MW -> "4MW": energy strings for the prototypes.
local function unit(v, suffix) return string.format("%.6g%s", v, suffix) end

-- Boxes may be {{x1,y1},{x2,y2}} or {left_top=..., right_bottom=...}.
local function box_corners(b)
  if b.left_top then return b.left_top.x or b.left_top[1], b.left_top.y or b.left_top[2],
                            b.right_bottom.x or b.right_bottom[1], b.right_bottom.y or b.right_bottom[2] end
  return b[1][1], b[1][2], b[2][1], b[2][2]
end

--------------------------------------------------------------------------------------------------
-- Fluid boxes for crafting machines. Pipe pictures/covers come from the base machine itself (or a
-- vanilla chemical plant); connection `position` must lie INSIDE the entity on its edge tile and
-- `direction` points outward, so the edge tile is derived from the (possibly resized) entity's real size.
--------------------------------------------------------------------------------------------------
local function edge_tile(ent, side, lat)
  local sb = ent.selection_box or ent.collision_box
  local half = math.max(math.abs(sb[1][1]), math.abs(sb[1][2]), math.abs(sb[2][1]), math.abs(sb[2][2]))
  local edge = math.floor(half * 2 + 0.5) / 2 - 0.5
  if side == "north" then return { lat, -edge }
  elseif side == "south" then return { lat, edge }
  elseif side == "east" then return { edge, lat }
  else return { -edge, lat } end
end

-- Fluid box volume: `floor`, or 3x the largest amount moved per craft if that is more (crafting machines
-- need room for three crafts of fluid, so a higher config rate must raise the volume with it).
local function vol(amount, floor) return math.max(floor or 1000, amount * 3) end

local function build_fluid_boxes(base, ent, boxes)
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
      position = edge_tile(ent, b.dir, b.lat),
    } }
    ---@diagnostic enable: missing-fields
    out[#out + 1] = fb
  end
  return out
end

-- Item for a placeable building. `icons` overrides the tinted copy of the base item's icon;
-- `desc` ({ params... }) makes the tooltip use the entity-description locale key with those numbers.
local function item_for(name, base_item, tint, order, icons, desc)
  local item = {
    type = "item", name = name, icons = icons or U.icons_of(data.raw.item[base_item], tint),
    subgroup = "ipp-power-buildings", order = order, place_result = name, stack_size = 10,
  }
  if desc then item.localised_description = { "entity-description." .. name, table.unpack(desc) } end
  return item
end

--------------------------------------------------------------------------------------------------
-- Chemical-stager art (Hurricane46, see graphics/License.txt), used for the fuel-gas conditioner.
-- 400 x 400 px frames, 60 frames in an 8-column sheet (the preview plays at 20 fps = animation_speed 1/3),
-- drawn at scale 0.5 (64 px per tile) for the 5x5 footprint it was made for (so scale = 0.5 x size / 5), a
-- separate emission sheet and a single shadow image.
--------------------------------------------------------------------------------------------------
local STAGER = GFX .. "chemical-stager/chemical-stager-"
local STAGER_NATIVE_SIZE = 5
local function stager_layer(file, scale, extra)
  local l = { filename = STAGER .. file, priority = "high", width = 400, height = 400,
              frame_count = 60, line_length = 8, scale = scale, animation_speed = 1 / 3 }
  for k, v in pairs(extra or {}) do l[k] = v end
  return l
end
local function stager_graphics(size)
  local scale = 0.5 * size / STAGER_NATIVE_SIZE
  return {
    animation = { layers = {
      stager_layer("hr-animation-1.png", scale),
      { filename = STAGER .. "hr-shadow.png", priority = "high", width = 800, height = 600,
        frame_count = 1, repeat_count = 60, scale = scale, draw_as_shadow = true },
    } },
    working_visualisations = { { animation = stager_layer("hr-emission-1.png", scale,
      { draw_as_glow = true, blend_mode = "additive" }) } },
  }
end
local function stager_icons() return { { icon = STAGER .. "icon.png", icon_size = 64 } } end

--------------------------------------------------------------------------------------------------
-- Crafting-machine builder. Without `graphics` the base machine's graphics_set is kept intact apart from
-- tint/scale, so every name that visual states, sounds and fluid boxes use to refer to working
-- visualisations stays valid. With `graphics` (a function) the graphics_set is replaced by that table.
--   size   : footprint in tiles (square). Boxes, pipe edge tiles, sprites, circuit connectors follow.
--   desc   : locale parameters for entity-description.<name> (numbers shown in the tooltip)
--------------------------------------------------------------------------------------------------
local function build_machine(s)
  local base = AM[s.base]
  assert(base, "industrial-power-plants: missing base prototype " .. s.base)
  local p = U.deepcopy(base)
  p.name = s.name
  p.icon, p.icon_size = nil, nil
  p.icons = s.icons and s.icons() or U.icons_of(data.raw.item[s.base] or base, s.tint)
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

  -- Resize (config size): selection box = size x size, collision box 0.1 smaller per side (vanilla 5x5 machines).
  local factor = 1
  if s.size then
    local x1, _, x2 = box_corners(base.selection_box or base.collision_box)
    factor = s.size / math.floor((x2 - x1) + 0.5)
    local half = s.size / 2
    if factor ~= 1 then   -- at the base machine's own size its vanilla boxes are kept as they are
      p.selection_box = { { -half, -half }, { half, half } }
      p.collision_box = { { -half + 0.1, -half + 0.1 }, { half - 0.1, half - 0.1 } }
    end
    if p.drawing_box_vertical_extension then p.drawing_box_vertical_extension = p.drawing_box_vertical_extension * factor end
    if factor ~= 1 then
      if p.circuit_connector then U.scale_connector_positions(p.circuit_connector, factor) end
      if p.alert_icon_shift then p.alert_icon_shift = { p.alert_icon_shift[1] * factor, p.alert_icon_shift[2] * factor } end
    end
  end

  if s.fluid_boxes then
    p.fluid_boxes = build_fluid_boxes(base, p, s.fluid_boxes)
    p.fluid_boxes_off_when_no_fluid_recipe = false
  else
    p.fluid_boxes = nil
  end

  if s.graphics then
    p.graphics_set, p.graphics_set_flipped = s.graphics(s.size), nil
    -- The sprite is a little taller than the footprint (like vanilla refineries): extend the drawing box.
    p.drawing_box_vertical_extension = math.max(p.drawing_box_vertical_extension or 0, s.drawing_extension or 0.7)
    if p.water_reflection then U.restyle(p.water_reflection, factor) end
  else
    local f = (s.scale or 1) * factor
    if p.graphics_set then U.restyle(p.graphics_set, f, s.tint) end
    if p.graphics_set_flipped then U.restyle(p.graphics_set_flipped, f, s.tint) end
    if p.water_reflection and factor ~= 1 then U.restyle(p.water_reflection, factor) end
  end
  if s.desc then p.localised_description = { "entity-description." .. s.name, table.unpack(s.desc) } end
  data:extend { p, item_for(s.name, s.base, s.tint, s.order, s.icons and s.icons(), s.desc) }
end

local function elec(drain, pollution)
  local e = { type = "electric", usage_priority = "secondary-input", drain = drain }
  if pollution then e.emissions_per_minute = { pollution = pollution } end
  return e
end
local VOID = { type = "void" }

local cond, hr, cn = C.conditioner, C.heat_recovery, C.condenser
-- A crafting machine needs every fluid box to hold 3 crafts of the LARGEST amount in its recipe.
local cond_vol = vol(math.max(cond.petroleum_gas_per_second, cond.fuel_gas_per_second))
local cn_vol   = vol(math.max(cn.exhaust_steam_per_second, cn.water_per_second))
local hr_vol   = vol(math.max(hr.hot_exhaust_per_second, hr.water_per_second, hr.steam_per_second, hr.flue_gas_per_second), 2000)
local max_vent = 0
for _, v in pairs(C.stack.vent_per_second) do max_vent = math.max(max_vent, v) end

local mach = {
  { name = "ipp-air-condenser", base = "chemical-plant", size = cn.size, tint = U.color(0.70, 0.88, 1.00), order = "d",
    categories = { "ipp-condensing" }, fixed_recipe = "ipp-condensation", health = cn.health,
    energy_source = elec(unit(cn.idle_drain_kw, "kW")), energy_usage = unit(cn.power_kw, "kW"),
    desc = { D.fmt(cn.exhaust_steam_per_second), D.fmt(cn.water_per_second) },
    fluid_boxes = { { kind = "input",  dir = "north", lat = 0, volume = cn_vol },
                    { kind = "output", dir = "south", lat = 0, volume = cn_vol } } },

  { name = D.STACK, base = "assembling-machine-1", size = C.stack.size, tint = U.color(0.50, 0.50, 0.55), order = "e",
    categories = { "ipp-venting" }, energy_source = VOID, energy_usage = "1kW", health = C.stack.health,
    fluid_boxes = { { kind = "input", dir = "north", lat = 0, volume = vol(max_vent, 2000) } } },

  -- Tier 2: the conditioner is the compressor train (chemical-stager art, 5x5 by default). It needs grid power, so a
  -- dead grid cannot restart the gas turbines (startup requirement); its emissions stand in for
  -- combustion pollution.
  { name = "ipp-fuel-gas-conditioner", base = "chemical-plant", size = cond.size, order = "g",
    graphics = stager_graphics, icons = stager_icons, health = cond.health, drawing_extension = 0.7 * cond.size / STAGER_NATIVE_SIZE,
    categories = { "ipp-gas-conditioning" }, fixed_recipe = "ipp-fuel-gas-conditioning",
    energy_source = elec(unit(cond.idle_drain_kw, "kW"), cond.pollution_per_minute),
    energy_usage = unit(cond.power_mw, "MW"),
    desc = { D.fmt(cond.petroleum_gas_per_second), D.fmt(cond.fuel_gas_per_second), D.fmt(cond.power_mw) },
    fluid_boxes = { { kind = "input",  dir = "north", lat = 0, volume = cond_vol },
                    { kind = "output", dir = "south", lat = 0, volume = cond_vol } } },

  -- 5x5 by default: the vanilla chemical-plant art is scaled by size/3. Two inputs on the north face, two outputs on the south.
  { name = "ipp-heat-recovery-steam-generator", base = "chemical-plant", size = hr.size, tint = U.color(1.00, 0.78, 0.55), order = "i",
    categories = { "ipp-heat-recovery" }, fixed_recipe = "ipp-heat-recovery", health = hr.health,
    energy_source = elec(unit(hr.idle_drain_kw, "kW")), energy_usage = unit(hr.power_kw, "kW"),
    desc = { D.fmt(hr.hot_exhaust_per_second), D.fmt(hr.water_per_second), D.fmt(hr.steam_per_second), D.fmt(hr.flue_gas_per_second) },
    fluid_boxes = { { kind = "input",  dir = "north", lat = -1, volume = hr_vol },
                    { kind = "input",  dir = "north", lat = 1,  volume = hr_vol },
                    { kind = "output", dir = "south", lat = -1, volume = hr_vol },
                    { kind = "output", dir = "south", lat = 1,  volume = hr_vol } } },
}
for _, m in ipairs(mach) do build_machine(m) end

--------------------------------------------------------------------------------------------------
-- Native turbine-generators (fusion-generator prototype).
-- Pipe layout, size and graphics are the vanilla fusion generator's; only fluids, rating and tint change.
--------------------------------------------------------------------------------------------------
local FG = data.raw["fusion-generator"] and data.raw["fusion-generator"]["fusion-generator"]
assert(FG, "industrial-power-plants: vanilla fusion-generator prototype not found (Space Age required)")

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
  p.max_health = g.health
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
  local desc = { D.fmt(g.per_second), D.fmt(g.power_mw) }
  p.localised_description = { "entity-description." .. name, table.unpack(desc) }
  data:extend { p, item_for(name, "fusion-generator", g.tint, g.order, nil, desc) }
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
  acc.max_health = C.startup_bank.health
  local bank = C.startup_bank
  -- Vanilla accumulator is 2x2: grow/shrink to bank.size (default 3x3), collision box 0.1 smaller per side.
  local f = bank.size / 2
  local half = bank.size / 2
  acc.collision_box = { { -half + 0.1, -half + 0.1 }, { half - 0.1, half - 0.1 } }
  acc.selection_box = { { -half, -half }, { half, half } }
  if acc.circuit_connector then U.scale_connector_positions(acc.circuit_connector, f) end
  if acc.alert_icon_shift then acc.alert_icon_shift = { acc.alert_icon_shift[1] * f, acc.alert_icon_shift[2] * f } end
  if acc.drawing_box_vertical_extension then acc.drawing_box_vertical_extension = acc.drawing_box_vertical_extension * f end
  acc.energy_source = { type = "electric", buffer_capacity = unit(bank.capacity_mj, "MJ"), usage_priority = "tertiary",
                        input_flow_limit = unit(bank.charge_mw, "MW"), output_flow_limit = unit(bank.discharge_mw, "MW") }
  acc.localised_description = { "entity-description.ipp-startup-bank", D.fmt(bank.capacity_mj) }
  U.restyle(acc.chargable_graphics, f, tint)
  if acc.water_reflection then U.restyle(acc.water_reflection, f) end
  data:extend { acc, item_for("ipp-startup-bank", "accumulator", tint, "k", nil, { D.fmt(bank.capacity_mj) }) }
end

--------------------------------------------------------------------------------------------------
-- Process recipes (amounts from config.lua). No fluid temperatures are stamped: steam keeps its default temperature and carries its
-- energy as a fuel value (STEAM_KJ per unit), so every pipe and port can connect.
--------------------------------------------------------------------------------------------------
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
process("ipp-condensation", { "ipp-condensing" }, 1, { { "fluid", "ipp-exhaust-steam", cn.exhaust_steam_per_second } },
  { { "fluid", "water", cn.water_per_second } }, U.icons_of_fluid("water"))
process("ipp-fuel-gas-conditioning", { "ipp-gas-conditioning" }, 1, { { "fluid", "petroleum-gas", cond.petroleum_gas_per_second } },
  { { "fluid", "ipp-fuel-gas", cond.fuel_gas_per_second } }, fl("ipp-fuel-gas"))
process("ipp-heat-recovery", { "ipp-heat-recovery" }, 1,
  { { "fluid", "ipp-hot-exhaust", hr.hot_exhaust_per_second }, { "fluid", "water", hr.water_per_second } },
  { { "fluid", "ipp-industrial-steam", hr.steam_per_second }, { "fluid", "ipp-flue-gas", hr.flue_gas_per_second } },
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

--------------------------------------------------------------------------------------------------
-- Building recipes
--------------------------------------------------------------------------------------------------
local function building(name, time, ings)
  data:extend { {
    type = "recipe", name = name, enabled = false, energy_required = time,
    ingredients = U.stacks(ings), results = { { type = "item", name = name, amount = 1 } },
  } }
end
local F, M, R = "ipp-structural-frame", "ipp-electric-motor", "ipp-refractory-lining"
building("ipp-air-condenser", 8, { {"item",F,2}, {"item","ipp-heat-exchanger-panel",8}, {"item",M,2}, {"item","pipe",10} })
building("ipp-exhaust-stack", 5, { {"item",F,1}, {"item","pipe",10}, {"item",R,2} })
building("ipp-fuel-gas-conditioner", 10, { {"item",F,3}, {"item","ipp-pressure-vessel",2}, {"item","ipp-high-speed-rotor",2}, {"item","ipp-seal-pack",2}, {"item","ipp-control-cabinet",1} })
building("ipp-gas-turbine-generator", 15, { {"item",F,5}, {"item","ipp-high-speed-rotor",3}, {"item","ipp-generator-winding",6}, {"item","ipp-heat-resistant-alloy",20}, {"item","ipp-control-cabinet",3} })
building("ipp-heat-recovery-steam-generator", 12, { {"item",F,3}, {"item","ipp-pressure-vessel",3}, {"item","ipp-heat-exchanger-panel",12}, {"item","pipe",20}, {"item","ipp-pump-assembly",2} })
building("ipp-large-steam-turbine-generator", 15, { {"item",F,4}, {"item","ipp-turbine-rotor",4}, {"item","ipp-high-speed-rotor",2}, {"item","ipp-generator-winding",4}, {"item","ipp-pressure-vessel",2}, {"item","ipp-control-cabinet",1} })
building("ipp-startup-bank", 10, { {"item",F,2}, {"item","ipp-turbine-rotor",2}, {"item","ipp-generator-winding",4}, {"item","battery",30} })
