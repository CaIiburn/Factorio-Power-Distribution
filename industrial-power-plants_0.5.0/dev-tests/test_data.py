import lupa, sys, os
from lupa import LuaRuntime
MOD = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(r'''
package.path = "%s/?.lua;" .. package.path
local function deepcopy(o, seen)
  seen = seen or {}
  if type(o) ~= "table" then return o end
  if seen[o] then return seen[o] end
  local c = {}; seen[o] = c
  for k, v in pairs(o) do c[deepcopy(k, seen)] = deepcopy(v, seen) end
  return c
end
package.preload["__core__.lualib.util"] = function() return { table = { deepcopy = deepcopy } } end
LOGS = {}
function log(m) LOGS[#LOGS+1] = m end
serpent = { line = function(t) if type(t) == 'table' then return '{' .. table.concat(t, ',') .. '}' end return tostring(t) end }
defines = { direction = { north=0, east=4, south=8, west=12 } }
local raw = {}
data = { raw = raw }
DUP = {}
function data:extend(list)
  for _, p in ipairs(list) do
    raw[p.type] = raw[p.type] or {}
    if raw[p.type][p.name] then DUP[#DUP+1] = p.type .. ":" .. p.name end
    raw[p.type][p.name] = p
  end
end
local function sprite(f) return { filename = f, width = 10, height = 10, shift = {1, 1} } end
local shared = sprite("shared.png")
local function am(name, sz)
  local box = { filename = "x" }
  return { type = "assembling-machine", name = name, crafting_categories = {"crafting"}, crafting_speed = 1,
    energy_source = {type="electric"}, energy_usage = "100kW", fast_replaceable_group = "am", next_upgrade = "z",
    minable = {result = name}, collision_box = {{-sz/2+0.3,-sz/2+0.3},{sz/2-0.3,sz/2-0.3}}, selection_box = {{-sz/2,-sz/2},{sz/2,sz/2}},
    effect_receiver = { base_effect = { productivity = 0.5 } },
    fluid_boxes = { { production_type = "input", volume = 1000, pipe_covers = {}, pipe_picture = {}, secondary_draw_orders = {north=-1},
        pipe_connections = {{flow_direction="input", direction=0, position={0,-2}}} } },
    graphics_set = { animation = { layers = { sprite(name .. ".png"), shared, { filename = "sh.png", draw_as_shadow = true, shift = {2, 2} } } },
                     working_visualisations = { { animation = sprite("w.png") } } },
    circuit_connector = { { points = { wire = { red = {0.9, 1.2} }, shadow = { red = {1.0, 1.3} } }, sprites = { connector_main = { filename = "cc.png", shift = {0.9, 1.2} } } } },
    water_reflection = { pictures = { filename = "wr.png", width = 10, height = 10, scale = 1, shift = {0, 0} } },
    icon = "__base__/graphics/icons/" .. name .. ".png", icon_size = 64 }
end
raw["assembling-machine"] = {}
for n, sz in pairs{["assembling-machine-1"]=3,["assembling-machine-2"]=3,["assembling-machine-3"]=3,["chemical-plant"]=3,["centrifuge"]=3,["foundry"]=5,["electromagnetic-plant"]=4,["oil-refinery"]=5} do
  raw["assembling-machine"][n] = am(n, sz)
end
raw["fusion-generator"] = { ["fusion-generator"] = { type="fusion-generator", name="fusion-generator",
  energy_source = {type="electric", usage_priority="primary-output", output_flow_limit="50MW"},
  -- layout copied from the vanilla space-age fusion-generator: 2 real inputs on the south face, 5 pass-through
  -- "output" connections on the input box (north + both sides), 2 outputs on the north face
  input_fluid_box = { production_type="input", volume=10, filter="fusion-plasma", pipe_connections={
    {flow_direction="input",  direction=8,  position={-1, 2},  connection_category={"fusion-reactor","fusion-generator"}},
    {flow_direction="input",  direction=8,  position={1, 2},   connection_category={"fusion-reactor","fusion-generator"}},
    {flow_direction="output", direction=0,  position={0, -2},  connection_category={"fusion-generator"}},
    {flow_direction="output", direction=12, position={-1, 0},  connection_category={"fusion-generator"}},
    {flow_direction="output", direction=4,  position={1, 0},   connection_category={"fusion-generator"}},
    {flow_direction="output", direction=12, position={-1, -1}, connection_category={"fusion-generator"}},
    {flow_direction="output", direction=4,  position={1, -1},  connection_category={"fusion-generator"}} } },
  output_fluid_box = { production_type="output", volume=100, filter="fluoroketone-hot", pipe_connections={
    {flow_direction="output", direction=0, position={-1, -2}}, {flow_direction="output", direction=0, position={1, -2}} } },
  max_fluid_usage = 1, burns_fluid = false, effectivity = 1, minimum_input_temperature = 1000,
  minable = {result="fusion-generator"}, fast_replaceable_group="fg", next_upgrade="x",
  graphics_set = { animation = { layers = { sprite("fg.png"), shared } }, working_visualisations = { { name = "warm-up", animation = sprite("w.png") } },
                   states = { { name = "warm-up" }, { name = "on" } },
                   -- vanilla: one fluid_input_graphics entry per input-box connection (7 = 2 sprites + 5 empty)
                   north_graphics_set = { animation = sprite("gn.png"), fluid_input_graphics = { { sprite = sprite("n1.png") }, { sprite = sprite("n2.png") }, {}, {}, {}, {}, {} } },
                   east_graphics_set  = { animation = sprite("ge.png"), fluid_input_graphics = { { sprite = sprite("e1.png") }, { sprite = sprite("e2.png") }, {}, {}, {}, {}, {} } },
                   south_graphics_set = { animation = sprite("gs.png"), fluid_input_graphics = { { sprite = sprite("s1.png") }, { sprite = sprite("s2.png") }, {}, {}, {}, {}, {} } },
                   west_graphics_set  = { animation = sprite("gw.png"), fluid_input_graphics = { { sprite = sprite("w1.png") }, { sprite = sprite("w2.png") }, {}, {}, {}, {}, {} } } },
  collision_box={{-1.4,-2.4},{1.4,2.4}}, selection_box={{-1.5,-2.5},{1.5,2.5}} } }
raw.accumulator = { accumulator = { type="accumulator", name="accumulator", energy_source={}, collision_box={{-.9,-.9},{.9,.9}},
  chargable_graphics = { picture = sprite("acc.png"), charge_animation = sprite("c.png") }, water_reflection = { pictures = sprite("r.png") } } }
raw.item, raw.fluid, raw.technology, raw.recipe = {}, {}, {}, {}
for _, n in ipairs{"fusion-generator","steel-chest","electric-engine-unit","pump","copper-cable","iron-gear-wheel","heat-pipe","stone-brick","steel-plate","storage-tank","plastic-bar","advanced-circuit","engine-unit","coal","stone","accumulator","iron-plate","copper-plate","pipe","electronic-circuit","sulfur","battery","iron-ore","concrete","nuclear-reactor","heat-exchanger","uranium-fuel-cell","depleted-uranium-fuel-cell","uranium-235","uranium-238","barrel","processing-unit","iron-stick"} do
  raw.item[n] = { type="item", name=n, icon="__base__/graphics/icons/"..n..".png", icon_size=64 }
end
VANILLA_ITEMS = {}; for k in pairs(raw.item) do VANILLA_ITEMS[k] = true end

for _, n in ipairs{"steam","petroleum-gas","water","lubricant","light-oil","sulfuric-acid"} do raw.fluid[n] = { type="fluid", name=n, icon="f.png", icon_size=64 } end
for _, n in ipairs{"steel-processing","oil-processing","battery","logistic-science-pack","chemical-science-pack","plastics","nuclear-power","nuclear-fuel-reprocessing","sulfur-processing","kovarex-enrichment-process"} do
  raw.technology[n] = { type="technology", name=n, icon="t.png", icon_size=256 } end

local function conn(d, x, y) return { location = { position = {x, y}, direction = d }, category = "nuclear-reactor", neighbour_category = {"nuclear-reactor"} } end
raw.reactor = { ["nuclear-reactor"] = { type="reactor", name="nuclear-reactor", flags={}, minable={result="nuclear-reactor"}, fast_replaceable_group="reactor",
  max_health=500, consumption="40MW", neighbour_bonus=1, dying_explosion="nuclear-reactor-explosion", corpse="nuclear-reactor-remnants",
  neighbour_connectable = { connections = { conn(0,0,-2.5), conn(4,2.5,0), conn(8,0,2.5), conn(12,-2.5,0) } },
  energy_source = { type="burner", fuel_categories={"nuclear"}, effectivity=1, fuel_inventory_size=1, burnt_inventory_size=1 },
  collision_box={{-2.2,-2.2},{2.2,2.2}}, selection_box={{-2.5,-2.5},{2.5,2.5}}, temperature_to_suppress_energy_icons=800,
  lower_layer_picture = sprite("pipes.png"), picture = { layers = { sprite("r.png"), { filename="s.png", width=10, height=10, draw_as_shadow=true } } },
  heat_buffer = { max_temperature=1000, specific_heat="10MJ", max_transfer="10GW", connections={} },
  meltdown_action = { type="direct", action_delivery={ type="instant" } }, default_temperature_signal={type="virtual",name="signal-T"},
  circuit_connector = { { points = { wire = { red = {0.9, 1.2} } } } } } }
raw.boiler = { ["heat-exchanger"] = { type="boiler", name="heat-exchanger", mode="output-to-separate-pipe", target_temperature=500,
  minable={result="heat-exchanger"}, fast_replaceable_group="heat-exchanger", max_health=200,
  fluid_box = { volume=200, filter="water", production_type="input", pipe_connections={{flow_direction="input-output",direction=12,position={-1,0.5}}} },
  output_fluid_box = { volume=200, filter="steam", production_type="output", pipe_connections={{flow_direction="output",direction=0,position={0,-0.5}}} },
  energy_consumption="10MW", energy_source={type="heat", max_temperature=1000, specific_heat="1MJ", max_transfer="2GW", min_working_temperature=500, connections={}},
  pictures = { north = { structure = { layers = { sprite("hx.png") } } } } } }
raw.container = { ["steel-chest"] = { type="container", name="steel-chest", minable={result="steel-chest"}, fast_replaceable_group="container", max_health=350,
  inventory_size=48, collision_box={{-0.35,-0.35},{0.35,0.35}}, selection_box={{-0.5,-0.5},{0.5,0.5}},
  picture = { layers = { sprite("c.png"), { filename="cs.png", width=10, height=10, draw_as_shadow=true } } },
  circuit_connector = { { points = { wire = { red = {0.4, 0.1} }, shadow = { red = {0.5, 0.2} } }, sprites = { connector_main = { filename = "cc.png", shift = {0.4, 0.1} } } } } } }
raw["storage-tank"] = { ["storage-tank"] = { type="storage-tank", name="storage-tank", minable={result="storage-tank"}, fast_replaceable_group="storage-tank", max_health=500,
  fluid_box = { volume=25000, pipe_connections={{direction=0,position={-1,-1}},{direction=4,position={1,1}}} }, flow_length_in_ticks=360,
  collision_box={{-1.35,-1.35},{1.35,1.35}}, selection_box={{-1.5,-1.5},{1.5,1.5}},
  pictures = { picture = { sheets = { sprite("tank.png"), { filename="tank-s.png", width=10, height=10, draw_as_shadow=true } } }, window_background = sprite("wb.png") } } }
raw["heat-pipe"] = { ["heat-pipe"] = { type="heat-pipe", name="heat-pipe", minable={result="heat-pipe"}, fast_replaceable_group="heat-pipe", max_health=200,
  heat_buffer = { max_temperature=1000, specific_heat="1MJ", max_transfer="1GW", connections={{position={0,0},direction=0}} },
  connection_sprites = { single = { sprite("hp.png") } }, heat_glow_sprites = { single = { sprite("hpg.png") } } } }
raw["virtual-signal"], raw["fuel-category"] = {}, {}
raw.technology["nuclear-power"].effects = {
  { type="unlock-recipe", recipe="nuclear-reactor" }, { type="unlock-recipe", recipe="heat-exchanger" }, { type="unlock-recipe", recipe="heat-pipe" },
  { type="unlock-recipe", recipe="steam-turbine" }, { type="unlock-recipe", recipe="uranium-fuel-cell" } }
for _, n in ipairs{"heat-pipe", "uranium-fuel-cell"} do
  raw.recipe[n] = { type="recipe", name=n, enabled=false, ingredients={}, results={} }
end
dofile("%s/data.lua")
''' % (MOD, MOD))
g = lua.globals()
raw = g.data.raw
def tolist(t): return [t[k] for k in sorted(t.keys(), key=lambda x: str(x))]
errs = []
def rcats(r):
    return ['crafting'] if r.categories is None else [r.categories[i] for i in range(1, len(r.categories)+1)]
if len(g.DUP): errs.append("duplicate prototypes: %s" % [g.DUP[i] for i in range(1, len(g.DUP)+1)])
items = set(raw.item.keys()); fluids = set(raw.fluid.keys())
recipes = raw.recipe
unlocked = {}
for tname in raw.technology.keys():
    t = raw.technology[tname]
    if not t.effects: continue
    for i in range(1, len(t.effects)+1):
        r = t.effects[i].recipe
        unlocked.setdefault(r, []).append(tname)
for rname in recipes.keys():
    r = recipes[rname]
    if r.category is not None: errs.append(rname + ": legacy 'category' (2.1 needs categories)")
    if r.categories is not None and len(r.categories) < 1: errs.append(rname + ": empty categories")
    for i in range(1, len(r.ingredients)+1):
        ing = r.ingredients[i]
        pool = items if ing.type == "item" else fluids
        if ing.name not in pool: errs.append("%s: unknown %s %s" % (rname, ing.type, ing.name))
    if r.results:
        for i in range(1, len(r.results)+1):
            res = r.results[i]
            pool = items if res.type == "item" else fluids
            if res.name not in pool: errs.append("%s: unknown result %s" % (rname, res.name))
    if r.enabled is False and rname not in unlocked and rname != "concrete": errs.append(rname + ": never unlocked")
    if rname in unlocked and len(unlocked[rname]) > 1: errs.append(rname + ": unlocked twice")
for tname in raw.technology.keys():
    t = raw.technology[tname]
    for i in range(1, (len(t.prerequisites) if t.prerequisites else 0)+1):
        if t.prerequisites[i] not in raw.technology.keys(): errs.append("tech %s: bad prereq %s" % (tname, t.prerequisites[i]))
    if t.effects:
        for i in range(1, len(t.effects)+1):
            if t.effects[i].recipe not in recipes.keys(): errs.append("tech %s: unknown recipe %s" % (tname, t.effects[i].recipe))
# machines
for mname in raw["assembling-machine"].keys():
    if not mname.startswith("ipp-"): continue
    m = raw["assembling-machine"][mname]
    if mname not in items: errs.append(mname + ": no item")
    if m.effect_receiver.base_effect.productivity is not None: errs.append(mname + ": inherited productivity")
    if m.fast_replaceable_group is not None: errs.append(mname + ": fast_replaceable_group kept")
    if m.graphics_set.working_visualisations is None: errs.append(mname + ": working visualisations must be kept intact")
    cats = [m.crafting_categories[i] for i in range(1, len(m.crafting_categories)+1)]
    if m.fixed_recipe:
        r = recipes[m.fixed_recipe]
        if r is None: errs.append(mname + ": fixed recipe missing"); continue
        if not any(c in cats for c in rcats(r)): errs.append(mname + ": category mismatch")
    # fluid port count
    nin = sum(1 for i in range(1, len(m.fluid_boxes)+1) if m.fluid_boxes[i].production_type == "input") if m.fluid_boxes else 0
    nout = sum(1 for i in range(1, len(m.fluid_boxes)+1) if m.fluid_boxes[i].production_type == "output") if m.fluid_boxes else 0
    for rname in recipes.keys():
        r = recipes[rname]
        if not any(c in cats for c in rcats(r)): continue
        fi = sum(1 for i in range(1, len(r.ingredients)+1) if r.ingredients[i].type == "fluid")
        fo = sum(1 for i in range(1, len(r.results)+1) if r.results[i].type == "fluid") if r.results else 0
        if fi > nin or fo > nout: errs.append("%s/%s: fluid ports %d/%d need %d/%d" % (mname, rname, nin, nout, fi, fo))
# 2.1 rule: connection position must be inside the collision box, on the edge tile, matching its direction
for mname in raw["assembling-machine"].keys():
    if not mname.startswith("ipp-"): continue
    m = raw["assembling-machine"][mname]
    if not m.fluid_boxes: continue
    cb = m.collision_box; sb = m.selection_box
    half = max(abs(sb[1][1]), abs(sb[2][1])); size = round(half*2)
    for i in range(1, len(m.fluid_boxes)+1):
        pc = m.fluid_boxes[i].pipe_connections[1]
        x, y = pc.position[1], pc.position[2]
        if not (cb[1][1] <= x <= cb[2][1] and cb[1][2] <= y <= cb[2][2]):
            errs.append("%s: pipe %d position (%s,%s) outside collision box" % (mname, i, x, y))
        d = pc.direction; edge = size/2 - 0.5
        on_edge = {0: y == -edge, 8: y == edge, 4: x == edge, 12: x == -edge}[d]
        lat = x if d in (0, 8) else y
        parity_ok = (lat % 1 == 0) if size % 2 == 1 else (lat % 1 == 0.5)
        if not on_edge: errs.append("%s: pipe %d not on edge tile for dir %s" % (mname, i, d))
        if not parity_ok: errs.append("%s: pipe %d lateral %s not a tile centre for size %d" % (mname, i, lat, size))
# scaled generators: footprint, edge-tile connections, collision containment
D_GEN = g.require('shared.defs').generators
for tn in D_GEN.keys():
    e = raw["fusion-generator"][tn]
    sb, cb = e.selection_box, e.collision_box
    w = round(sb[2][1] - sb[1][1]); h = round(sb[2][2] - sb[1][2])
    sc = D_GEN[tn].scale
    if (w, h) != (3*sc, 5*sc): errs.append("%s: footprint %dx%d != %dx%d" % (tn, w, h, 3*sc, 5*sc))
    print("%-38s footprint %dx%d (x%d)" % (tn, w, h, sc))
    # the engine requires one fluid_input_graphics entry per INPUT connection in every direction's graphics set
    for dn in ("north_graphics_set", "east_graphics_set", "south_graphics_set", "west_graphics_set"):
        fig = e.graphics_set[dn].fluid_input_graphics
        n_in = len(e.input_fluid_box.pipe_connections)
        if fig is None or len(fig) != n_in: errs.append("%s.%s: fluid_input_graphics has %s entries, the input box has %d connections" % (tn, dn, None if fig is None else len(fig), n_in))
        elif any(fig[i].sprite is None for i in range(1, n_in+1)): errs.append("%s.%s: a surviving input connection lost its sprite entry" % (tn, dn))
    for boxname in ("input_fluid_box", "output_fluid_box"):
        box = e[boxname]
        for i in range(1, len(box.pipe_connections)+1):
            pc = box.pipe_connections[i]; x, y = pc.position[1], pc.position[2]
            if not (cb[1][1] <= x <= cb[2][1] and cb[1][2] <= y <= cb[2][2]): errs.append("%s.%s: (%s,%s) outside collision box" % (tn, boxname, x, y))
            d = pc.direction
            edge = (h/2 - 0.5) if d in (0, 8) else (w/2 - 0.5)
            on_edge = {0: y == -edge, 8: y == edge, 4: x == edge, 12: x == -edge}[d]
            lat = x if d in (0, 8) else y; size = w if d in (0, 8) else h
            ok_par = (lat % 1 == 0) if size % 2 == 1 else (lat % 1 == 0.5)
            if not on_edge or not ok_par: errs.append("%s.%s: connection not on a valid edge tile (%s,%s)" % (tn, boxname, x, y))
        # exactly two connections per box: inputs on the south face, exhaust outputs on the north face
        want_flow, want_dir = ("input", 8) if boxname == "input_fluid_box" else ("output", 0)
        n_ = len(box.pipe_connections)
        if n_ != 2: errs.append("%s.%s has %d connections, want exactly 2" % (tn, boxname, n_))
        for i in range(1, n_+1):
            pc = box.pipe_connections[i]
            if pc.flow_direction != want_flow: errs.append("%s.%s connection %d is %s, want %s only" % (tn, boxname, i, pc.flow_direction, want_flow))
            if pc.direction != want_dir: errs.append("%s.%s connection %d faces %s, want %s" % (tn, boxname, i, pc.direction, want_dir))
        xs_ = sorted(box.pipe_connections[i].position[1] for i in range(1, n_+1))
        if n_ == 2 and (xs_[0] != -xs_[1] or xs_[0] >= 0): errs.append("%s.%s ports not symmetric about the centre: %s" % (tn, boxname, xs_))
        for i in range(1, len(box.pipe_connections)+1):
            extra = [k for k in box.pipe_connections[i].keys() if k not in ("flow_direction", "direction", "position")]
            if extra: errs.append("%s.%s connection %d keeps inherited fields %s (e.g. connection_category blocks normal pipes)" % (tn, boxname, i, extra))
        if len(box.pipe_connections) != 2: errs.append("%s.%s: port count %d != 2 (two inputs, two exhaust outputs, no pass-through)" % (tn, boxname, len(box.pipe_connections)))
        if box.minimum_temperature is not None or box.maximum_temperature is not None:
            errs.append("%s.%s: removed fluid-box temperature keys present" % (tn, boxname))
# vent list consistency
V = g.require("shared.defs").vent
allowed = list(V.allowed.keys()); denied = list(V.denied.keys())
for f in allowed:
    if f not in fluids: errs.append("vent allowed: unknown fluid " + f)
    r = recipes[V.allowed[f].recipe]
    if r is None or r.results is None or len(r.results) != 0: errs.append("vent recipe for %s missing or has products" % f)
    elif r.categories[1] != "ipp-venting": errs.append("vent recipe category")
if set(allowed) & set(denied): errs.append("fluid both allowed and denied: %s" % (set(allowed) & set(denied)))
for f, why in V.denied.items():
    if why not in ("valuable", "fuel", "hazard"): errs.append("unknown deny reason " + why)
vent_recipes = [rn for rn in recipes.keys() if rn.startswith("ipp-vent-")]
if sorted(vent_recipes) != sorted(V.allowed[f].recipe for f in allowed): errs.append("vent recipes %s != allowed list" % vent_recipes)
for f in ("ipp-industrial-steam", "ipp-fuel-gas", "water"):
    if f in allowed: errs.append(f + " must never be ventable")
print("generator port fields dropped (as logged):", len(g.LOGS), "entries; e.g.", g.LOGS[1])
print("vent allowed:", sorted(allowed)); print("vent denied :", sorted(denied))
stk = raw["assembling-machine"]["ipp-exhaust-stack"]
if stk.fixed_recipe is not None: errs.append("stack must not have a fixed recipe")
# sprite double-scaling guard: shared sprite must be scaled exactly once (scale 1 -> 1, no factor) ; check bank scale = size/2
D = g.require("shared.defs")
bank = raw.accumulator["ipp-startup-bank"]
sc = bank.chargable_graphics.picture.scale
if abs(sc - D.config.startup_bank.size / 2) > 1e-9: errs.append("bank sprite scale %s != size/2" % sc)
# energy accounting for native generators
D_GEN = g.require('shared.defs').generators
def amt(r, kind, name):
    arr = r.ingredients if kind == 'in' else r.results
    for i in range(1, len(arr)+1):
        if arr[i].name == name: return arr[i].amount
D = g.require("shared.defs")
STEAM_UNIT_KJ = D.STEAM_KJ
fg_items = raw["fusion-generator"]
print("== native generators ==")
for tn in D.generators.keys():
    d = D.generators[tn]
    e = fg_items[tn]
    if e is None: errs.append(tn + ": generator prototype missing"); continue
    if tn not in items: errs.append(tn + ": no item")
    if e.input_fluid_box.filter != d.input or e.output_fluid_box.filter != d.output: errs.append(tn + ": filters")
    for f in (d.input, d.output):
        if f not in fluids: errs.append("%s: unknown fluid %s" % (tn, f))
    if abs(e.max_fluid_usage*60 - d.per_second) > 1e-6: errs.append(tn + ": max_fluid_usage mismatch")
    if e.fast_replaceable_group is not None: errs.append(tn + ": fast replaceable group kept")
    inf = raw.fluid[d.input]
    if not d.burns: errs.append(tn + ": must burn its fluid (temperature-based generators lock fluid boxes)")
    if not e.burns_fluid: errs.append(tn + ": prototype burns_fluid not set")
    fv = str(inf.fuel_value)
    unit_mj = float(fv.replace("kJ", "")) / 1000.0 if fv.endswith("kJ") else float(fv.replace("MJ", ""))
    power = d.per_second * unit_mj * d.effectivity
    flow = float(e.energy_source.output_flow_limit.replace("MW", ""))
    print("%-38s %6.0f units/s x %.3f MJ x eff %.3f = %6.2f MW  (limit %.1f MW)" % (tn, d.per_second, unit_mj, d.effectivity, power, flow))
    if power > flow + 1e-9: errs.append("%s: power %.2f exceeds flow limit %.1f" % (tn, power, flow))
    if d.effectivity > 1: errs.append(tn + ": efficiency > 100%")
    if d.input == "ipp-industrial-steam" and abs(unit_mj*1000 - D.STEAM_KJ) > 1e-6: errs.append(tn + ": steam unit energy != STEAM_KJ")
    if e.minimum_input_temperature is not None or e.maximum_input_temperature is not None: errs.append(tn + ": temperature limits must not be set")
    for bx in ("input_fluid_box", "output_fluid_box"):
        if e[bx].volume < d.per_second * 3 - 1e-6: errs.append("%s.%s: volume %s < 3 s of flow" % (tn, bx, e[bx].volume))
    if e.graphics_set.working_visualisations is None: errs.append(tn + ": working vis dropped")
# nothing may stamp a temperature (locks fluid boxes -> pipes refuse to connect under 2.1 mixing rules)
for rn in recipes.keys():
    r = recipes[rn]
    for key in ("ingredients", "results"):
        arr = r[key]
        if arr is None: continue
        for i in range(1, len(arr)+1):
            if arr[i].temperature is not None or arr[i].minimum_temperature is not None or arr[i].maximum_temperature is not None:
                errs.append("%s: %s %s carries a temperature" % (rn, key, arr[i].name))
for fname in ("ipp-industrial-steam", "ipp-exhaust-steam", "ipp-fuel-gas", "ipp-hot-exhaust", "ipp-flue-gas"):
    f = raw.fluid[fname]
    if f.max_temperature is not None and f.max_temperature != f.default_temperature: errs.append(fname + ": temperature range present")
# crafting-machine fluid boxes must hold >= 3x the largest per-craft amount of the fluids they carry (fluidbox_multiplier 3)
for mname in raw["assembling-machine"].keys():
    if not mname.startswith("ipp-"): continue
    m = raw["assembling-machine"][mname]
    if not m.fluid_boxes: continue
    need = 0
    for rname in recipes.keys():
        r = recipes[rname]
        if not any(c in [m.crafting_categories[i] for i in range(1, len(m.crafting_categories)+1)] for c in rcats(r)): continue
        if m.fixed_recipe and rname != m.fixed_recipe: continue
        for arr in (r.ingredients, r.results):
            if arr is None: continue
            for i in range(1, len(arr)+1):
                if arr[i].type == "fluid": need = max(need, arr[i].amount * 3)
    for i in range(1, len(m.fluid_boxes)+1):
        if m.fluid_boxes[i].volume < need - 1e-6: errs.append("%s: fluid box %d volume %s < %s needed" % (mname, i, m.fluid_boxes[i].volume, need))
# no turbine recipes / hidden buffers left over
for rn in recipes.keys():
    if "turbine-cycle" in rn: errs.append("stale recipe " + rn)
if raw["electric-energy-interface"] is not None: errs.append("hidden EEI prototypes should be gone")
hr = recipes["ipp-heat-recovery"]
steam_mj = amt(hr,'out','ipp-industrial-steam')*STEAM_UNIT_KJ/1000
gt = D.generators["ipp-gas-turbine-generator"]; gt_elec = gt.per_second*gt.effectivity
print("HRSG: %.0f hot exhaust + %.0f water -> %.0f steam (%.1f MJ) + %.0f flue ; exhaust heat available %.1f MJ" % (amt(hr,'in','ipp-hot-exhaust'), amt(hr,'in','water'), amt(hr,'out','ipp-industrial-steam'), steam_mj, amt(hr,'out','ipp-flue-gas'), gt.per_second-gt_elec))
if steam_mj > gt.per_second - gt_elec: errs.append("HRSG recovers more heat than the exhaust holds")
if amt(hr,'in','ipp-hot-exhaust') != gt.per_second: errs.append("HRSG exhaust != gas turbine output (1:1 conversion assumed)")
print("conditioner: 105 PG -> %.0f fuel gas" % amt(recipes["ipp-fuel-gas-conditioning"],'out','ipp-fuel-gas'))

# ---- tier 1 coal plant is gone ----
for rn in ("ipp-coal-charge", "ipp-ash-compaction", "ipp-boiler-cycle", "ipp-ash-concrete", "ipp-coal-mill",
           "ipp-industrial-boiler", "ipp-steam-turbine-generator", "ipp-waste-compactor"):
    if recipes[rn] is not None: errs.append("tier 1 recipe still present: " + rn)
for iname in ("ipp-coal-charge", "ipp-ash", "ipp-ash-block", "ipp-coal-mill", "ipp-industrial-boiler",
              "ipp-steam-turbine-generator", "ipp-waste-compactor"):
    if iname in items: errs.append("tier 1 item still present: " + iname)
for mname in ("ipp-coal-mill", "ipp-industrial-boiler", "ipp-waste-compactor"):
    if raw["assembling-machine"][mname] is not None: errs.append("tier 1 machine still present: " + mname)
if raw["fusion-generator"]["ipp-steam-turbine-generator"] is not None: errs.append("tier 1 turbine still present")
if raw["fuel-category"] is not None and raw["fuel-category"]["ipp-graded-coal"] is not None: errs.append("graded coal fuel category still present")
for tname in raw.technology.keys():
    t = raw.technology[tname]
    if t.effects:
        for i in range(1, len(t.effects)+1):
            if t.effects[i].recipe in ("ipp-coal-mill", "ipp-industrial-boiler", "ipp-steam-turbine-generator", "ipp-waste-compactor"):
                errs.append("tech %s still unlocks tier 1 recipe" % tname)
# ---- 5x5 footprints and sprites ----
for mname in ("ipp-fuel-gas-conditioner", "ipp-heat-recovery-steam-generator"):
    m = raw["assembling-machine"][mname]
    sb, cb = m.selection_box, m.collision_box
    w, h = round(sb[2][1] - sb[1][1]), round(sb[2][2] - sb[1][2])
    want = D.config.conditioner.size if mname == "ipp-fuel-gas-conditioner" else D.config.heat_recovery.size
    if (w, h) != (want, want): errs.append("%s: footprint %dx%d != configured %dx%d" % (mname, w, h, want, want))
    margin = 0.3 if want == 3 else 0.1   # at the chemical plant's own 3x3 the vanilla boxes are kept
    if abs(cb[2][1] - (want / 2 - margin)) > 1e-9 or abs(cb[1][2] + (want / 2 - margin)) > 1e-9: errs.append("%s: collision box %s,%s" % (mname, cb[1][1], cb[2][2]))
    print("%-38s footprint %dx%d" % (mname, w, h))
cond = raw["assembling-machine"]["ipp-fuel-gas-conditioner"]
layers = cond.graphics_set.animation.layers
if not str(layers[1].filename).endswith("chemical-stager/chemical-stager-hr-animation-1.png"): errs.append("conditioner: not using the chemical-stager animation")
if not str(layers[1].filename).startswith("__industrial-power-plants__/graphics/"): errs.append("conditioner: sprite path must be inside the mod")
if layers[1].frame_count != 60 or layers[1].line_length != 8 or layers[1].width != 400: errs.append("conditioner: sprite sheet layout mismatch")
if layers[2].draw_as_shadow is not True or layers[2].repeat_count != 60: errs.append("conditioner: shadow layer")
if cond.graphics_set.working_visualisations[1].animation.draw_as_glow is not True: errs.append("conditioner: emission layer")
for lay in (layers[1], layers[2], cond.graphics_set.working_visualisations[1].animation):
    p_ = os.path.join(MOD, str(lay.filename).replace("__industrial-power-plants__/", ""))
    if not os.path.exists(p_): errs.append("missing sprite file " + p_)
    else:
        from PIL import Image
        w_, h_ = Image.open(p_).size
        need_w = lay.line_length * lay.width if lay.line_length else lay.width
        if lay.width > w_ or lay.height > h_: errs.append("sprite %s smaller than a frame" % p_)
        if lay.line_length and (lay.line_length * lay.width > w_ or -(-lay.frame_count // lay.line_length) * lay.height > h_):
            errs.append("sprite %s too small for %d frames x %d columns" % (p_, lay.frame_count, lay.line_length))
icon = cond.icons[1].icon
if not os.path.exists(os.path.join(MOD, str(icon).replace("__industrial-power-plants__/", ""))): errs.append("missing icon " + str(icon))
hrsg = raw["assembling-machine"]["ipp-heat-recovery-steam-generator"]
hf = D.config.heat_recovery.size / 3
hs = hrsg.graphics_set.animation.layers[1].scale or 1   # nil = 1 (restyle leaves an unscaled sprite untouched)
if abs(hs - hf) > 1e-9: errs.append("hrsg sprite not scaled %s: %s" % (hf, hs))
if abs(hrsg.circuit_connector[1].points.wire.red[1] - 0.9*hf) > 1e-9: errs.append("hrsg circuit connector not scaled")
if abs(layers[1].scale - 0.5 * D.config.conditioner.size / 5) > 1e-9: errs.append("conditioner sprite scale does not follow size")
# ---- configured sizes reach every custom entity ----
def side(box): return round(box[2][1] - box[1][1]), round(box[2][2] - box[1][2])
am = raw["assembling-machine"]
for ent, want in (("ipp-air-condenser", D.config.condenser.size), (D.STACK, D.config.stack.size)):
    if side(am[ent].selection_box) != (want, want): errs.append("%s footprint %s != configured %d" % (ent, side(am[ent].selection_box), want))
    pc = am[ent].fluid_boxes[1].pipe_connections[1].position
    if abs(abs(pc[2]) - (want - 1) / 2) > 1e-9: errs.append("%s pipe tile %s not on the edge of a %d footprint" % (ent, pc[2], want))
if side(raw.accumulator["ipp-startup-bank"].selection_box) != (D.config.startup_bank.size,) * 2: errs.append("bank footprint != configured")
for tn, key in (("ipp-large-steam-turbine-generator", "large_steam"), ("ipp-gas-turbine-generator", "gas")):
    if side(raw["fusion-generator"][tn].selection_box) != (3 * D.config.turbines[key].size_multiplier, 5 * D.config.turbines[key].size_multiplier): errs.append(tn + ": footprint != 3x5 x size_multiplier")
# every fluid port sits on the edge tile of its (resized) building
for ent in ("ipp-fuel-gas-conditioner", "ipp-heat-recovery-steam-generator"):
    half = side(am[ent].selection_box)[1] / 2
    for fbx in range(1, len(am[ent].fluid_boxes) + 1):
        pc = am[ent].fluid_boxes[fbx].pipe_connections[1].position
        if abs(abs(pc[2]) - (half - 0.5)) > 1e-9: errs.append("%s: port %d not on edge tile" % (ent, fbx))
# ---- every config rate reaches the prototypes ----
CF = D.config
cs = raw.recipe["ipp-fuel-gas-conditioning"]
if amt(cs, 'in', 'petroleum-gas') != CF.conditioner.petroleum_gas_per_second or amt(cs, 'out', 'ipp-fuel-gas') != CF.conditioner.fuel_gas_per_second: errs.append("conditioner recipe != config")
if str(cond.energy_usage) != "%.6gMW" % CF.conditioner.power_mw: errs.append("conditioner energy usage %s != config" % cond.energy_usage)
if cond.energy_source.emissions_per_minute.pollution != CF.conditioner.pollution_per_minute: errs.append("conditioner pollution != config")
cd = raw.recipe["ipp-condensation"]
if amt(cd, 'in', 'ipp-exhaust-steam') != CF.condenser.exhaust_steam_per_second or amt(cd, 'out', 'water') != CF.condenser.water_per_second: errs.append("condensation recipe != config")
if str(raw["assembling-machine"]["ipp-air-condenser"].energy_usage) != "%.6gkW" % CF.condenser.power_kw: errs.append("condenser power != config")
if str(hrsg.energy_usage) != "%.6gkW" % CF.heat_recovery.power_kw: errs.append("hrsg power != config")
if amt(hr, 'in', 'water') != CF.heat_recovery.water_per_second or amt(hr, 'out', 'ipp-flue-gas') != CF.heat_recovery.flue_gas_per_second: errs.append("hrsg recipe != config")
bank = raw.accumulator["ipp-startup-bank"]
if str(bank.energy_source.buffer_capacity) != "%.6gMJ" % CF.startup_bank.capacity_mj: errs.append("bank capacity != config")
for tn, key in (("ipp-industrial-steam-power", "industrial_steam_power"), ("ipp-combined-cycle-power", "combined_cycle_power"), ("ipp-startup-energy-storage", "startup_energy_storage")):
    u = raw.technology[tn].unit
    if u.count != CF.research[key].count or u.time != CF.research[key].time: errs.append(tn + ": research cost != config")
for tn, key in (("ipp-large-steam-turbine-generator", "large_steam"), ("ipp-gas-turbine-generator", "gas")):
    if raw["fusion-generator"][tn].max_health != CF.turbines[key].health: errs.append(tn + ": health != config")

# ---- Tier 3: pressurized-water nuclear ----
RC, PU, SGc, SCc = CF.reactor, CF.primary_unit, CF.steam_generator, CF.surface_condenser
def mw(v):
    v = str(v)
    return float(v[:-2]) if v.endswith("MW") else float(v[:-2]) / 1000 if v.endswith("kW") else float(v[:-2]) * 1000 if v.endswith("GW") else float("nan")
core = raw.reactor[D.REACTOR]
if core is None: errs.append("reactor core prototype missing")
else:
    if abs(mw(core.consumption) - RC.power_mw) > 1e-9: errs.append("core consumption != config")
    if core.neighbour_bonus != RC.neighbour_bonus: errs.append("core neighbour bonus != config")
    nc = core.neighbour_connectable.connections
    for i in range(1, len(nc) + 1):
        if nc[i].category != "ipp-pwr-reactor" or nc[i].neighbour_category[1] != "ipp-pwr-reactor": errs.append("core neighbour category not private")
    if core.energy_source.fuel_categories[1] != "ipp-fuel-assembly" or len(core.energy_source.fuel_categories) != 1: errs.append("core must burn only fuel assemblies")
    if core.energy_source.fuel_inventory_size != RC.fuel_slots or core.energy_source.burnt_inventory_size != RC.spent_slots: errs.append("core slots != config")
    if core.heat_buffer.max_temperature != RC.max_temperature_c or str(core.heat_buffer.specific_heat) != "%.6gMJ" % RC.specific_heat_mj: errs.append("core heat buffer != config")
    if core.meltdown_action is None: errs.append("core lost the vanilla meltdown action")
    if core.dying_explosion is None: errs.append("core lost the vanilla dying explosion")
    if core.circuit_connector is None: errs.append("core lost its circuit connector")
    if core.fast_replaceable_group is not None: errs.append("core keeps vanilla fast_replaceable_group")
    if core.max_health != RC.health: errs.append("core health != config")
    if core.minable.result != D.REACTOR or D.REACTOR not in items: errs.append("core item/minable")
    if RC.meltdown_temperature_c <= 0.9 * RC.max_temperature_c: errs.append("meltdown temperature must be above 90 percent of max")
    print("core: %.0f MW, %.0f MJ/C, window at 3x output from 500 C: %.0f s" % (RC.power_mw, RC.specific_heat_mj, RC.specific_heat_mj * (RC.meltdown_temperature_c - 500) / (RC.power_mw * 3)))
hx = raw.boiler["ipp-primary-circulation-unit"]
if hx is None: errs.append("circulation unit prototype missing")
else:
    if hx.fluid_box.filter != "ipp-primary-water" or hx.output_fluid_box.filter != "ipp-primary-water-hot": errs.append("circulation unit filters")
    if hx.target_temperature != PU.target_c or abs(mw(hx.energy_consumption) - PU.power_mw) > 1e-9: errs.append("circulation unit != config")
    if hx.energy_source.min_working_temperature != PU.min_working_c: errs.append("circulation unit min working temperature")
    if hx.mode != "output-to-separate-pipe": errs.append("circulation unit mode")
    if hx.pictures.north.structure.layers[1].tint is None: errs.append("circulation unit sprites are not tinted (vanilla keeps them in `pictures`)")
    if hx.fluid_box.volume < D.PRIMARY_FLOW * 3 - 1e-6 or hx.output_fluid_box.volume < D.PRIMARY_FLOW * 3 - 1e-6: errs.append("circulation unit volume < 3 s of flow")
    if hx.fast_replaceable_group is not None: errs.append("circulation unit keeps vanilla fast_replaceable_group")
for f in ("ipp-primary-water", "ipp-primary-water-hot"):
    if str(raw.fluid[f].heat_capacity) != "1kJ": errs.append(f + ": heat capacity must be 1kJ (the energy accounting assumes it)")
if raw.fluid["ipp-primary-water-hot"].max_temperature < PU.target_c: errs.append("hot primary water max temperature below the circulation unit target")
if raw.fluid["ipp-primary-water"].max_temperature is not None and raw.fluid["ipp-primary-water"].max_temperature != raw.fluid["ipp-primary-water"].default_temperature: errs.append("cool primary water must have no temperature range")
# energy accounting across the loop
sgr = recipes["ipp-nuclear-steam-generation"]
heat_mw = amt(sgr, 'in', 'ipp-primary-water-hot') * D.PRIMARY_UNIT_KJ / 1000
steam_mw = amt(sgr, 'out', 'ipp-hp-steam') * D.HP_STEAM_KJ / 1000
hpg = D.generators["ipp-hp-turbine-generator"]
print("steam generator: %.1f MW of primary heat -> %.1f MW of steam energy; turbine train %.1f MW; condenser rejects %.1f MW" % (heat_mw, steam_mw, hpg.per_second * hpg.effectivity * D.HP_STEAM_KJ / 1000, heat_mw - steam_mw))
if steam_mw > heat_mw + 1e-9: errs.append("steam generator creates energy")
if abs(D.PRIMARY_FLOW - amt(sgr, 'in', 'ipp-primary-water-hot')) > 1e-6: errs.append("one circulation unit does not feed one steam generator")
if amt(sgr, 'in', 'ipp-primary-water-hot') != amt(sgr, 'out', 'ipp-primary-water'): errs.append("primary loop is not closed")
if amt(sgr, 'in', 'ipp-secondary-water') != amt(recipes["ipp-surface-condensation"], 'out', 'ipp-secondary-water'): errs.append("secondary loop is not closed")
for rn_ in ("ipp-nuclear-steam-generation", "ipp-surface-condensation"):
    for kind_ in ('in', 'out'):
        if amt(recipes[rn_], kind_, 'water') is not None: errs.append("%s still uses vanilla water (the middle loop runs on secondary water)" % rn_)
if amt(sgr, 'out', 'ipp-hp-steam') != hpg.per_second: errs.append("steam generator output != turbine intake")
sc_r = recipes["ipp-surface-condensation"]
if amt(sc_r, 'in', 'ipp-exhaust-steam') != hpg.per_second: errs.append("condenser intake != turbine exhaust")
if amt(sc_r, 'in', 'ipp-cooling-water') != amt(sc_r, 'out', 'ipp-cooling-water-warm'): errs.append("cooling loop gains/loses water at the condenser")
tw = recipes["ipp-cooling-tower-cycle"]
if amt(tw, 'in', 'water') != CF.cooling_tower.makeup_per_second: errs.append("tower makeup water != config")
if CF.cooling_tower.makeup_per_second != 600: errs.append("cooling tower makeup is meant to be 600 vanilla water/s (forces building near water)")
if amt(tw, 'in', 'ipp-secondary-water') is not None or amt(tw, 'in', 'ipp-primary-water') is not None: errs.append("tower makeup must be vanilla water")
if amt(tw, 'in', 'ipp-cooling-water-warm') != amt(tw, 'out', 'ipp-cooling-water'): errs.append("tower should return all cooling water (makeup is the loss)")
# fuel chain
fa = raw.item["ipp-fuel-assembly"]
gj = float(str(fa.fuel_value).replace("GJ", ""))
if abs(gj - CF.fuel_assembly.cells * 8) > 1e-9: errs.append("assembly energy != cells x 8 GJ")
if fa.burnt_result != "ipp-spent-fuel-assembly" or fa.fuel_categories[1] != "ipp-fuel-assembly": errs.append("assembly fuel category / burnt result")
if raw["fuel-category"]["ipp-fuel-assembly"] is None: errs.append("fuel category missing")
if amt(recipes["ipp-fuel-assembly"], 'in', 'uranium-fuel-cell') != CF.fuel_assembly.cells: errs.append("assembly recipe cells != config")
if raw.item["ipp-spent-fuel-assembly"].fuel_value is not None: errs.append("spent fuel must not burn")
if amt(recipes["ipp-spent-fuel-cooling"], 'in', 'ipp-spent-fuel-assembly') != 1 or amt(recipes["ipp-spent-fuel-cooling"], 'out', 'ipp-spent-fuel-assembly-cooled') != 1: errs.append("cooling pool recipe")
if recipes["ipp-spent-fuel-cooling"].energy_required != CF.spent_fuel_pool.cooling_time_s: errs.append("cooling time must be the fixed config time")
if amt(recipes["ipp-spent-fuel-reprocessing"], 'in', 'ipp-spent-fuel-assembly-cooled') != 1: errs.append("reprocessing must take COOLED fuel only")
res = recipes["ipp-spent-fuel-reprocessing"].results
if not any(res[i].name == "uranium-235" and res[i].independent_probability == CF.reprocessing.uranium_235_chance for i in range(1, len(res)+1)): errs.append("uranium-235 recovery chance")
if amt(recipes["ipp-vitrification"], 'in', 'ipp-radioactive-residue') != CF.vitrifier.residue: errs.append("vitrifier residue != config")
# every part in the plan table can be crafted and is unlocked by exactly one of the two researches
for b in ("ipp-pwr-reactor-core", "ipp-primary-circulation-unit", "ipp-nuclear-steam-generator", "ipp-hp-turbine-generator", "ipp-surface-condenser",
          "ipp-cooling-tower", "ipp-dry-cooler", "ipp-spent-fuel-pool", "ipp-dry-cask-storage", "ipp-reprocessing-plant", "ipp-waste-vitrifier"):
    if b not in items or recipes[b] is None: errs.append(b + ": no item or recipe")
    elif b not in unlocked: errs.append(b + ": not unlocked")
t3 = {r: unlocked[r][0] for r in unlocked if unlocked[r][0] in ("ipp-pressurized-water-power", "ipp-nuclear-reprocessing")}
for b in ("ipp-reprocessing-plant", "ipp-waste-vitrifier", "ipp-vitrification", "ipp-spent-fuel-reprocessing"):
    if t3.get(b) != "ipp-nuclear-reprocessing": errs.append(b + " belongs to the optional reprocessing research")
for b in ("ipp-pwr-reactor-core", "ipp-spent-fuel-pool", "ipp-dry-cask-storage", "ipp-fuel-assembly"):
    if t3.get(b) != "ipp-pressurized-water-power": errs.append(b + " belongs to the base tier 3 research")
for tn, key in (("ipp-pressurized-water-power", "pressurized_water_power"), ("ipp-nuclear-reprocessing", "nuclear_reprocessing")):
    u = raw.technology[tn].unit
    if u.count != CF.research[key].count or u.time != CF.research[key].time: errs.append(tn + ": research cost != config")
# components named in the plan table
for c in ("ipp-nuclear-shielding", "ipp-control-rod-assembly", "ipp-radhard-controller", "ipp-reinforced-pipe", "ipp-chemical-resistant-pipe"):
    if c not in items: errs.append("missing component " + c)
# control-rod signals
for sg_name in (D.SIGNAL_ROD, D.SIGNAL_SCRAM):
    if raw["virtual-signal"][sg_name] is None: errs.append("virtual signal missing: " + sg_name)
# ---- water treatment plant + the two closed-loop fluids ----
wtc = CF.water_treatment
wp = am["ipp-water-treatment-plant"]
if wp is None: errs.append("water treatment plant missing")
else:
    if side(wp.selection_box) != (4, 4) or wtc.size != 4: errs.append("water treatment plant must be 4x4 (config %s, box %s)" % (wtc.size, side(wp.selection_box)))
    for i_ in (1, 2):
        pc_ = wp.fluid_boxes[i_].pipe_connections[1].position
        if pc_[1] != -0.5 or abs(pc_[2]) != 1.5: errs.append("water treatment port %d at (%s,%s): a 4x4 needs x = -0.5 and y = +-1.5" % (i_, pc_[1], pc_[2]))
    if wp.fixed_recipe is not None: errs.append("water treatment plant needs a recipe selection (two recipes)")
    if "ipp-water-treatment-plant" not in items or "ipp-water-treatment-plant" not in unlocked: errs.append("water treatment plant item / unlock missing")
    if str(wp.energy_usage) != "%.6gkW" % wtc.power_kw: errs.append("water treatment power != config")
    if wp.max_health != wtc.health: errs.append("water treatment health != config")
    nin_ = sum(1 for i in range(1, len(wp.fluid_boxes)+1) if wp.fluid_boxes[i].production_type == "input")
    nout_ = sum(1 for i in range(1, len(wp.fluid_boxes)+1) if wp.fluid_boxes[i].production_type == "output")
    if (nin_, nout_) != (1, 1): errs.append("water treatment fluid ports %d/%d != 1/1" % (nin_, nout_))
    wl = wp.graphics_set.animation.layers
    if not str(wl[1].filename).endswith("oxidizer/oxidizer-hr-animation-1.png"): errs.append("water treatment plant: not using the oxidizer art")
    if not str(wl[1].filename).startswith("__industrial-power-plants__/graphics/"): errs.append("water treatment plant: sprite path must be inside the mod")
    if (wl[1].width, wl[1].height, wl[1].frame_count, wl[1].line_length) != (280, 320, 60, 8): errs.append("water treatment plant: sprite sheet layout mismatch")
    if wl[2].draw_as_shadow is not True or wl[2].repeat_count != 60 or (wl[2].width, wl[2].height) != (700, 500): errs.append("water treatment plant: shadow layer")
    if wp.graphics_set.working_visualisations[1].animation.draw_as_glow is not True: errs.append("water treatment plant: emission layer")
    if abs(wl[1].scale - 0.5 * wtc.size / 4) > 1e-9 or abs(wl[2].scale - wl[1].scale) > 1e-9: errs.append("water treatment plant: sprite scale does not follow size")
    from PIL import Image
    for lay in (wl[1], wl[2], wp.graphics_set.working_visualisations[1].animation):
        p_ = os.path.join(MOD, str(lay.filename).replace("__industrial-power-plants__/", ""))
        if not os.path.exists(p_): errs.append("missing sprite file " + p_); continue
        w_, h_ = Image.open(p_).size
        if lay.line_length and (lay.line_length * lay.width != w_ or -(-lay.frame_count // lay.line_length) * lay.height != h_):
            errs.append("sprite %s is %dx%d, expected %dx%d for the declared frames" % (p_, w_, h_, lay.line_length * lay.width, -(-lay.frame_count // lay.line_length) * lay.height))
        if not lay.line_length and (lay.width, lay.height) != (w_, h_): errs.append("shadow %s is %dx%d, declared %dx%d" % (p_, w_, h_, lay.width, lay.height))
    if not os.path.exists(os.path.join(MOD, str(wp.icons[1].icon).replace("__industrial-power-plants__/", ""))): errs.append("missing water treatment icon")
wtp, wts, wtcool = recipes["ipp-primary-water-treatment"], recipes["ipp-secondary-water-treatment"], recipes["ipp-cooling-water-treatment"]
if wtp is None or wts is None or wtcool is None: errs.append("water treatment recipes missing")
else:
    for rr, out_name, want in ((wtp, "ipp-primary-water", wtc.primary_per_second), (wts, "ipp-secondary-water", wtc.secondary_per_second), (wtcool, "ipp-cooling-water", wtc.cooling_per_second)):
        if rcats(rr) != ["ipp-water-treatment"]: errs.append(rr.name + ": category")
        if len(rr.ingredients) != 1 or rr.ingredients[1].name != "water" or rr.ingredients[1].type != "fluid" or rr.ingredients[1].amount != want: errs.append(rr.name + ": must take exactly the configured vanilla water")
        if len(rr.results) != 1 or rr.results[1].name != out_name or rr.results[1].amount != want: errs.append(rr.name + ": must make exactly the configured amount of " + out_name)
        if unlocked.get(rr.name, [None])[0] != "ipp-pressurized-water-power": errs.append(rr.name + ": belongs to the base tier 3 research")
for f_ in ("ipp-secondary-water", "ipp-primary-water", "ipp-cooling-water"):
    if f_ not in fluids: errs.append("missing fluid " + f_)
sw = raw.fluid["ipp-secondary-water"]
if sw.max_temperature is not None and sw.max_temperature != sw.default_temperature: errs.append("secondary water must have no temperature range")
if sw.fuel_value is not None: errs.append("secondary water is not a fuel")
if V.denied["ipp-secondary-water"] != "valuable" or "ipp-secondary-water" in allowed: errs.append("secondary water must be refused by the exhaust stack")
# nothing but the pool, the tower and the plant may still take vanilla water in tier 3
for rn_ in recipes.keys():
    if not any(c in ("ipp-steam-generation", "ipp-surface-condensing", "ipp-evaporative-cooling", "ipp-dry-cooling", "ipp-fuel-cooling", "ipp-water-treatment") for c in rcats(recipes[rn_])): continue
    if amt(recipes[rn_], 'in', 'water') is not None and rn_ not in ("ipp-cooling-tower-cycle", "ipp-spent-fuel-cooling", "ipp-spent-core-cooling", "ipp-primary-water-treatment", "ipp-secondary-water-treatment", "ipp-cooling-water-treatment"):
        errs.append(rn_ + ": unexpected vanilla water input")
print("water treatment: %.0f water/s -> primary water, %.0f -> secondary water, %.0f -> cooling water; tower evaporates %.0f water/s" % (wtc.primary_per_second, wtc.secondary_per_second, wtc.cooling_per_second, CF.cooling_tower.makeup_per_second))
# vanilla replacement
ne = raw.technology["nuclear-power"].effects
left = [ne[i].recipe for i in range(1, len(ne)+1)]
if CF.replace_vanilla_nuclear:
    for dropped in ("nuclear-reactor", "heat-exchanger", "steam-turbine"):
        if dropped in left: errs.append("vanilla nuclear-power still unlocks " + dropped)
    for kept in ("heat-pipe", "uranium-fuel-cell"):
        if kept not in left: errs.append("vanilla nuclear-power lost " + kept)
# 2.1 fluid rule: a boiler pipe connection and every new machine port sit on valid edge tiles (generic check above covers machines)
# new machines: footprints follow config
for ent, want in (("ipp-nuclear-steam-generator", SGc.size), ("ipp-surface-condenser", SCc.size), ("ipp-cooling-tower", CF.cooling_tower.size),
                  ("ipp-dry-cooler", CF.dry_cooler.size), ("ipp-spent-fuel-pool", CF.spent_fuel_pool.size),
                  ("ipp-reprocessing-plant", CF.reprocessing.size), ("ipp-waste-vitrifier", CF.vitrifier.size)):
    if side(am[ent].selection_box) != (want, want): errs.append("%s footprint %s != configured %d" % (ent, side(am[ent].selection_box), want))
cask = raw.container["ipp-dry-cask-storage"]
if side(cask.selection_box) != (CF.dry_cask.size,) * 2 or cask.inventory_size != CF.dry_cask.inventory_slots: errs.append("dry cask != config")
if abs(cask.picture.layers[1].scale - CF.dry_cask.size) > 1e-9: errs.append("dry cask sprite not scaled once to its size")
if str(am["ipp-nuclear-steam-generator"].energy_usage) != "%.6gMW" % SGc.power_mw: errs.append("steam generator power != config")
if am["ipp-nuclear-steam-generator"].energy_source.drain is None: errs.append("steam generator must idle on a drain, it must not be free")
for tn in ("ipp-hp-turbine-generator",):
    if raw["fusion-generator"][tn].max_health != CF.turbines.hp.health: errs.append(tn + ": health != config")
# 2.1 renamed product 'probability' to 'independent_probability' (the old name stops the mod from loading)
for rn in recipes.keys():
    for key in ("ingredients", "results"):
        arr = recipes[rn][key]
        if arr is None: continue
        for i in range(1, len(arr)+1):
            if arr[i].probability is not None: errs.append("%s: %s %s uses the removed 'probability' field" % (rn, key, arr[i].name))


# =====================================================================================================================
# TIER 4: fast breeder with supercritical CO2 generation
# =====================================================================================================================
print("== tier 4 ==")
T4 = ("ipp-sodium-coolant-production", "ipp-fast-breeder-power")
FBc, SUc, SEc, CHc, CPc, RCc, CLc = CF.fast_breeder, CF.sodium_unit, CF.sodium_exchanger, CF.co2_heater, CF.sco2_compressor, CF.recuperator, CF.sco2_cooler
BFc, ELc, SCc4 = CF.breeder_fuel, CF.electrolyzer, CF.sodium_chemistry
H_MJ, R_MJ = CF.fluids.sco2_hot_mj, CF.fluids.sco2_recuperated_mj
tb = raw["fusion-generator"]["ipp-sco2-turbine-generator"]

# --- buildings in the plan table exist, are researched, and are the right kind of prototype
for b in ("ipp-fast-breeder-reactor", "ipp-intermediate-sodium-exchanger", "ipp-sodium-co2-heater", "ipp-sco2-compressor", "ipp-sco2-turbine-generator",
          "ipp-recuperator", "ipp-sco2-cooler", "ipp-shielded-fuel-fabricator", "ipp-sodium-electrolyzer", "ipp-hot-fluid-tank",
          "ipp-sodium-circulation-unit", "ipp-blanket-channel"):
    if b not in items: errs.append(b + ": no item")
    elif b not in unlocked or unlocked[b][0] not in T4: errs.append(b + ": not unlocked by a tier 4 research")
    if b not in recipes or recipes[b].ingredients is None: errs.append(b + ": no building recipe")
# the plan's crafting components, per building
plan = {
  "ipp-fast-breeder-reactor": ["ipp-structural-frame", "ipp-refractory-alloy", "ipp-nuclear-shielding", "ipp-control-rod-assembly", "ipp-radhard-controller"],
  "ipp-intermediate-sodium-exchanger": ["ipp-refractory-alloy", "ipp-heat-exchanger-panel", "ipp-ceramic-seal", "ipp-nuclear-shielding"],
  "ipp-sodium-co2-heater": ["ipp-pressure-vessel", "ipp-refractory-alloy", "ipp-heat-exchanger-panel", "ipp-ceramic-seal"],
  "ipp-sco2-compressor": ["ipp-precision-rotor", "ipp-pressure-vessel", "ipp-electric-motor", "ipp-seal-pack", "processing-unit"],
  "ipp-sco2-turbine-generator": ["ipp-refractory-rotor", "ipp-generator-winding", "ipp-pressure-housing", "processing-unit"],
  "ipp-recuperator": ["ipp-recuperator-matrix", "ipp-pressure-vessel", "ipp-ceramic-seal"],
  "ipp-sco2-cooler": ["ipp-heat-exchanger-panel", "ipp-pressure-vessel", "ipp-pump-assembly"],
  "ipp-shielded-fuel-fabricator": ["ipp-nuclear-shielding", "ipp-handling-machinery", "ipp-refractory-alloy", "ipp-radhard-controller"],
  "ipp-sodium-electrolyzer": ["ipp-refractory-lining", "ipp-electrode-assembly", "ipp-pressure-vessel", "ipp-control-cabinet"],
  "ipp-hot-fluid-tank": ["ipp-pressure-vessel", "ipp-refractory-lining", "ipp-thermal-insulation", "ipp-pump-assembly"],
}
for b, comps in plan.items():
    for c in comps:
        if amt(recipes[b], 'in', c) is None: errs.append("%s: plan component %s missing from its recipe" % (b, c))
for c in ("ipp-refractory-alloy", "ipp-ceramic-seal", "ipp-precision-rotor", "ipp-refractory-rotor", "ipp-pressure-housing", "ipp-recuperator-matrix",
          "ipp-handling-machinery", "ipp-electrode-assembly", "ipp-thermal-insulation"):
    if c not in items or c not in recipes: errs.append(c + ": new component missing")
# every plan component is made from something that exists (no recipe loop): refractory alloy / rotors build on tier 3 parts
for c in ("ipp-refractory-rotor", "ipp-pressure-housing", "ipp-recuperator-matrix"):
    if amt(recipes[c], 'in', "ipp-refractory-alloy") is None: errs.append(c + ": should use refractory alloy")

# --- reactor core: vanilla reactor prototype, own fuel + neighbour category, config numbers
fbr = raw.reactor["ipp-fast-breeder-reactor"]
if str(fbr.consumption) != "%.6gMW" % FBc.power_mw: errs.append("breeder core power != config")
if fbr.neighbour_bonus != FBc.neighbour_bonus: errs.append("breeder neighbour bonus != config")
if fbr.neighbour_bonus != 1 or raw.reactor["nuclear-reactor"].neighbour_bonus != 1: errs.append("neighbour bonus must be like vanilla nuclear (1)")
if fbr.energy_source.fuel_categories[1] != "ipp-fast-fuel" or len(fbr.energy_source.fuel_categories) != 1: errs.append("breeder core must burn only the fast-fuel category")
if raw.reactor["ipp-pwr-reactor-core"].energy_source.fuel_categories[1] == "ipp-fast-fuel": errs.append("the tier 3 core must not burn fast fuel")
if fbr.energy_source.fuel_inventory_size != FBc.fuel_slots or fbr.energy_source.burnt_inventory_size != FBc.spent_slots: errs.append("breeder core slots != config")
for i in range(1, len(fbr.neighbour_connectable.connections) + 1):
    c = fbr.neighbour_connectable.connections[i]
    if c.category != "ipp-fbr-reactor" or c.neighbour_category[1] != "ipp-fbr-reactor" or len(c.neighbour_category) != 1: errs.append("breeder core neighbour category must be its own")
if fbr.heat_buffer.max_temperature != FBc.max_temperature_c or str(fbr.heat_buffer.specific_heat) != "%.6gMJ" % FBc.specific_heat_mj: errs.append("breeder core heat buffer != config")
if fbr.max_health != FBc.health: errs.append("breeder core health != config")
core_heat_mw = FBc.power_mw
print("breeder core: %.0f MW, %.0f MJ/C, +%.0f%% per neighbouring core" % (FBc.power_mw, FBc.specific_heat_mj, FBc.neighbour_bonus * 100))
for k in ("ipp-mox-assembly", "ipp-starter-assembly"):
    it_ = raw.item[k]
    if it_.fuel_categories[1] != "ipp-fast-fuel" or it_.burnt_result != "ipp-spent-core-assembly": errs.append(k + ": fuel category / burnt result")
    if abs(float(str(it_.fuel_value).replace("GJ", "")) - D.fuel.mox_gj) > 1e-9: errs.append(k + ": fuel value != burnt fissile x GJ per fissile")
for k in ("ipp-blanket-assembly", "ipp-bred-blanket-assembly", "ipp-spent-core-assembly", "ipp-spent-core-assembly-cooled"):
    if raw.item[k].fuel_value is not None or raw.item[k].fuel_categories is not None: errs.append(k + " must not be burnable")
if raw.item["ipp-spent-core-assembly"].burnt_result is not None: errs.append("spent core assembly must not burn on")

# --- Heat pipe II and the breeder core's temperature limits
hp2, hp1 = raw["heat-pipe"]["ipp-heat-pipe-2"], raw["heat-pipe"]["heat-pipe"]
HPc = CF.heat_pipe_2
if hp2.heat_buffer.max_temperature != HPc.max_temperature_c or HPc.max_temperature_c != 2000: errs.append("heat pipe II must withstand 2000 C")
if hp1.heat_buffer.max_temperature != 1000: errs.append("the vanilla heat pipe must stay untouched")
if hp2.heat_buffer.specific_heat != hp1.heat_buffer.specific_heat or hp2.heat_buffer.max_transfer != hp1.heat_buffer.max_transfer: errs.append("heat pipe II conducts like the vanilla pipe")
if hp2.fast_replaceable_group != hp1.fast_replaceable_group: errs.append("heat pipe II must be fast-replaceable with the vanilla pipe")
if raw.item["ipp-heat-pipe-2"].place_result != "ipp-heat-pipe-2": errs.append("heat pipe II item")
if amt(recipes["ipp-heat-pipe-2"], 'in', "heat-pipe") != 1: errs.append("heat pipe II is an upgrade of the vanilla pipe")
if FBc.warning_temperature_c != 2100 or FBc.meltdown_temperature_c != 2500: errs.append("breeder core warning / explosion must be 2100 / 2500")
if not HPc.max_temperature_c < FBc.warning_temperature_c < FBc.meltdown_temperature_c <= FBc.max_temperature_c: errs.append("pipe limit < warning < explosion <= core buffer")
if raw.boiler["ipp-sodium-circulation-unit"].energy_source.max_temperature != HPc.max_temperature_c: errs.append("the circulation unit would cap a heat pipe II network")

# --- sodium circulation unit (primary loop heat exchanger)
cu = raw.boiler["ipp-sodium-circulation-unit"]
if cu.target_temperature != SUc.target_c or str(cu.energy_consumption) != "%.6gMW" % SUc.power_mw or cu.energy_source.min_working_temperature != SUc.min_working_c: errs.append("circulation unit != config")
if cu.fluid_box.filter != "ipp-primary-sodium" or cu.output_fluid_box.filter != "ipp-primary-sodium-hot": errs.append("circulation unit fluids")
if raw.fluid["ipp-primary-sodium-hot"].max_temperature < SUc.target_c: errs.append("hot primary sodium cannot reach the target temperature")
for f in ("ipp-primary-sodium", "ipp-primary-sodium-hot"):
    if raw.fluid[f].heat_capacity != "1kJ": errs.append(f + ": heat capacity must be 1 kJ (a unit carries target - 15 kJ)")
for f in ("ipp-secondary-sodium", "ipp-secondary-sodium-hot", "ipp-co2", "ipp-sco2", "ipp-sco2-warm", "ipp-sco2-exhaust", "ipp-chlorine", "ipp-brine"):
    if raw.fluid[f].max_temperature is not None and raw.fluid[f].max_temperature != raw.fluid[f].default_temperature: errs.append(f + ": must have no temperature range (only the circulation unit stamps one)")
if raw.fluid["ipp-sco2-hot"].fuel_value is None or abs(float(str(raw.fluid["ipp-sco2-hot"].fuel_value).replace("MJ", "")) - H_MJ) > 1e-9: errs.append("hot CO2 fuel value != config")
for f in ("ipp-co2", "ipp-sco2", "ipp-sco2-warm", "ipp-sco2-exhaust", "ipp-primary-sodium", "ipp-secondary-sodium"):
    if raw.fluid[f].fuel_value is not None: errs.append(f + " must not be a fuel")

# --- energy accounting of the two sodium loops and the CO2 loop (MW)
ex = recipes["ipp-sodium-heat-exchange"]
if amt(ex, 'in', "ipp-primary-sodium-hot") != amt(ex, 'out', "ipp-primary-sodium"): errs.append("exchanger: primary loop gains or loses sodium")
if amt(ex, 'in', "ipp-secondary-sodium") != amt(ex, 'out', "ipp-secondary-sodium-hot"): errs.append("exchanger: secondary loop gains or loses sodium")
heat_primary = amt(ex, 'in', "ipp-primary-sodium-hot") * D.SODIUM_UNIT_KJ / 1000
heat_secondary = amt(ex, 'out', "ipp-secondary-sodium-hot") * D.SODIUM_UNIT_KJ / 1000
if heat_secondary > heat_primary + 1e-9: errs.append("exchanger creates heat")
if abs(heat_primary - FBc.power_mw) > 1e-9: errs.append("one exchanger must carry the heat of one core (%.1f vs %.1f MW)" % (heat_primary, FBc.power_mw))
if abs(SEc.hot_primary_per_second - 3 * D.SODIUM_FLOW) > 1e-9: errs.append("one exchanger != three circulation units")
hw, hd = recipes["ipp-co2-heating-recuperated"], recipes["ipp-co2-heating-direct"]
for r_, feed in ((hw, "ipp-sco2-warm"), (hd, "ipp-sco2")):
    if amt(r_, 'in', "ipp-secondary-sodium-hot") != amt(r_, 'out', "ipp-secondary-sodium"): errs.append(r_.name + ": secondary loop gains or loses sodium")
    if amt(r_, 'in', feed) != amt(r_, 'out', "ipp-sco2-hot"): errs.append(r_.name + ": CO2 gained or lost")
    if amt(r_, 'in', "ipp-secondary-sodium-hot") != amt(ex, 'in', "ipp-secondary-sodium"): errs.append(r_.name + ": sodium flow != exchanger flow")
heat_in = amt(hw, 'in', "ipp-secondary-sodium-hot") * D.SODIUM_UNIT_KJ / 1000
added_w = amt(hw, 'out', "ipp-sco2-hot") * (H_MJ - R_MJ)
added_d = amt(hd, 'out', "ipp-sco2-hot") * H_MJ
if added_w > heat_in + 1e-9 or added_d > heat_in + 1e-9: errs.append("heater makes more hot CO2 energy than the sodium brings")
if abs(added_w - added_d) > 1e-9: errs.append("the heater's two recipes must use the same heat")
if amt(hw, 'out', "ipp-sco2-hot") != tb.max_fluid_usage * 60 and abs(amt(hw, 'out', "ipp-sco2-hot") - CF.turbines.sco2.fluid_per_second) > 1e-9: errs.append("recuperated heater output != turbine intake")
if amt(hd, 'out', "ipp-sco2-hot") >= amt(hw, 'out', "ipp-sco2-hot"): errs.append("direct feed must yield less hot CO2")
turb_mw = CF.turbines.sco2.fluid_per_second * H_MJ * CF.turbines.sco2.effectivity
turb_mw_direct = amt(hd, 'out', "ipp-sco2-hot") * H_MJ * CF.turbines.sco2.effectivity
comp_mw, cool_mw = CPc.power_mw, CLc.power_mw
net = turb_mw - comp_mw - cool_mw - SEc.power_mw - CHc.power_kw / 1000 - RCc.power_kw / 1000
eff_w, eff_d = turb_mw / added_w, turb_mw_direct / added_d
print("CO2 plant: %.0f MW of sodium heat -> %.0f MW gross (%.0f%% with recuperator), %.0f MW gross without (%.0f%%); heat per electric MW x%.2f without; own use %.1f MW, net %.1f MW" %
      (added_w, turb_mw, eff_w * 100, turb_mw_direct, eff_d * 100, eff_w / eff_d, comp_mw + cool_mw + SEc.power_mw + CHc.power_kw / 1000 + RCc.power_kw / 1000, net))
if eff_w / eff_d < 1.5: errs.append("removing the recuperator must substantially increase the heat demand (x%.2f)" % (eff_w / eff_d))
if not 0.4 <= eff_w <= 0.6: errs.append("rated efficiency should be around 50%%, is %.0f%%" % (eff_w * 100))
t3_eff = steam_mw / heat_mw   # tier 3: steam energy per primary heat (the turbine train then converts it 1:1)
if eff_w <= t3_eff: errs.append("tier 4 must beat the tier 3 cycle efficiency (%.0f%% vs %.0f%%)" % (eff_w * 100, t3_eff * 100))
rcp = recipes["ipp-sco2-recuperation"]
if amt(rcp, 'in', "ipp-sco2-exhaust") != amt(rcp, 'out', "ipp-sco2-exhaust") or amt(rcp, 'in', "ipp-sco2") != amt(rcp, 'out', "ipp-sco2-warm"): errs.append("recuperator gains or loses CO2")
returned = amt(rcp, 'out', "ipp-sco2-warm") * R_MJ
exhaust_heat = amt(rcp, 'in', "ipp-sco2-exhaust") * (1 - CF.turbines.sco2.effectivity) * H_MJ
if returned > exhaust_heat + 1e-9: errs.append("recuperator returns %.1f MW, the exhaust only holds %.1f MW" % (returned, exhaust_heat))
for rn_, a, b in (("ipp-sco2-compression", "ipp-co2", "ipp-sco2"), ("ipp-sco2-cooling", "ipp-sco2-exhaust", "ipp-co2")):
    if amt(recipes[rn_], 'in', a) != amt(recipes[rn_], 'out', b) or amt(recipes[rn_], 'in', a) != CF.turbines.sco2.fluid_per_second: errs.append(rn_ + ": CO2 flow != turbine flow")
print("recuperator: returns %.0f of the %.0f MW the exhaust holds (%.0f%%)" % (returned, exhaust_heat, returned / exhaust_heat * 100))
if tb.max_fluid_usage is not None and abs(tb.max_fluid_usage * 60 - CF.turbines.sco2.fluid_per_second) > 1e-6: errs.append("turbine max fluid usage != config")
if tb.burns_fluid is not True: errs.append("CO2 turbine must burn hot CO2 as fuel")
if tb.input_fluid_box.filter != "ipp-sco2-hot" or tb.output_fluid_box.filter != "ipp-sco2-exhaust": errs.append("CO2 turbine fluids")
# machine volumes hold the flow, the heater has no fixed recipe (the script picks it), the others do
for n_, rn_ in (("ipp-intermediate-sodium-exchanger", "ipp-sodium-heat-exchange"), ("ipp-sco2-compressor", "ipp-sco2-compression"),
               ("ipp-recuperator", "ipp-sco2-recuperation"), ("ipp-sco2-cooler", "ipp-sco2-cooling"), ("ipp-blanket-channel", "ipp-blanket-irradiation")):
    if am[n_].fixed_recipe != rn_: errs.append(n_ + ": fixed recipe")
if am["ipp-sodium-co2-heater"].fixed_recipe is not None: errs.append("the heater must not have a fixed recipe (its script picks one)")
if am["ipp-sodium-electrolyzer"].fixed_recipe is not None or am["ipp-shielded-fuel-fabricator"].fixed_recipe is not None: errs.append("electrolyzer / fabricator pick their recipe by hand")
if am["ipp-spent-fuel-pool"].fixed_recipe is not None or am["ipp-reprocessing-plant"].fixed_recipe is not None: errs.append("the shared tier 3 pool / reprocessing plant must take tier 4 recipes")
for n_, want in (("ipp-intermediate-sodium-exchanger", SEc.size), ("ipp-sodium-co2-heater", CHc.size), ("ipp-sco2-compressor", CPc.size), ("ipp-recuperator", RCc.size),
                 ("ipp-sco2-cooler", CLc.size), ("ipp-shielded-fuel-fabricator", CF.fuel_fabricator.size), ("ipp-sodium-electrolyzer", ELc.size), ("ipp-blanket-channel", CF.blanket_channel.size)):
    if side(am[n_].selection_box) != (want, want): errs.append("%s footprint != configured %d" % (n_, want))
if am["ipp-blanket-channel"].energy_source.type != "void": errs.append("blanket channel needs no power")
if raw["storage-tank"]["ipp-hot-fluid-tank"].fluid_box.volume != CF.hot_tank.capacity or raw["storage-tank"]["ipp-hot-fluid-tank"].fluid_box.filter is not None: errs.append("hot-fluid tank != config")
# the exchanger / heater / cooler / compressor need grid power: the loop stops without it (decay heat then needs the startup bank)
for n_ in ("ipp-intermediate-sodium-exchanger", "ipp-sodium-co2-heater", "ipp-sco2-compressor", "ipp-recuperator", "ipp-sco2-cooler", "ipp-sodium-electrolyzer", "ipp-shielded-fuel-fabricator"):
    if am[n_].energy_source.type != "electric" or am[n_].energy_source.drain is None: errs.append(n_ + ": needs an electric source with an idle drain")

# --- sodium: two loops that cannot be mixed up; coolant manufacture; chlorine has a way out the moment sodium unlocks
for e_ in ("ipp-primary-sodium-electrolysis", "ipp-secondary-sodium-electrolysis"):
    r_ = recipes[e_]
    if amt(r_, 'in', "ipp-dry-sodium-salt") != ELc.salt or amt(r_, 'out', "ipp-chlorine") != ELc.chlorine: errs.append(e_ + " != config")
    if r_.energy_required != ELc.time_s: errs.append(e_ + ": time != config")
if amt(recipes["ipp-primary-sodium-electrolysis"], 'out', "ipp-primary-sodium") != ELc.sodium or amt(recipes["ipp-secondary-sodium-electrolysis"], 'out', "ipp-secondary-sodium") != ELc.sodium: errs.append("electrolysis sodium amount")
# fluid isolation: primary sodium is only in the primary loop machines, its electrolysis recipe and nowhere else
for f in ("ipp-primary-sodium", "ipp-primary-sodium-hot"):
    for rn_ in recipes.keys():
        if (amt(recipes[rn_], 'in', f) is not None or amt(recipes[rn_], 'out', f) is not None) and rn_ not in ("ipp-sodium-heat-exchange", "ipp-primary-sodium-electrolysis"): errs.append("%s appears in %s" % (f, rn_))
for f in ("ipp-secondary-sodium", "ipp-secondary-sodium-hot"):
    for rn_ in recipes.keys():
        if (amt(recipes[rn_], 'in', f) is not None or amt(recipes[rn_], 'out', f) is not None) and rn_ not in ("ipp-sodium-heat-exchange", "ipp-secondary-sodium-electrolysis", "ipp-co2-heating-recuperated", "ipp-co2-heating-direct"): errs.append("%s appears in %s" % (f, rn_))
# chain: water + stone -> brine -> dry salt -> sodium + chlorine ; stone -> lime + CO2
chain = (("ipp-brine-preparation", "ipp-brine"), ("ipp-sodium-salt-drying", "ipp-dry-sodium-salt"), ("ipp-lime-kiln", "ipp-lime"))
for rn_, out_ in chain:
    if rn_ not in recipes or amt(recipes[rn_], 'out', out_) is None: errs.append(rn_ + ": missing or wrong product")
    elif "chemistry" not in rcats(recipes[rn_]): errs.append(rn_ + ": vanilla chemical plant recipe")
if amt(recipes["ipp-sodium-salt-drying"], 'in', "ipp-brine") is None or amt(recipes["ipp-brine-preparation"], 'in', "stone") is None: errs.append("brine chain inputs")
if amt(recipes["ipp-lime-kiln"], 'out', "ipp-co2") is None: errs.append("the kiln must make the working CO2")
# chlorine: neutralisation and a chemical use, both unlocked together with the electrolysis
chl_users = [rn_ for rn_ in recipes.keys() if amt(recipes[rn_], 'in', "ipp-chlorine") is not None]
if sorted(chl_users) != ["ipp-chlorinated-plastic", "ipp-chlorine-neutralization"]: errs.append("chlorine routes: %s" % chl_users)
nz = recipes["ipp-chlorine-neutralization"]
if nz.results is not None and len(nz.results) > 0: errs.append("neutralisation leaves nothing behind")
if amt(nz, 'in', "ipp-lime") is None: errs.append("neutralisation uses lime")
if amt(recipes["ipp-chlorinated-plastic"], 'out', "plastic-bar") <= 2 * amt(recipes["ipp-chlorinated-plastic"], 'in', "coal"): errs.append("chlorinated plastic should beat plain plastic")
for rn_ in chl_users + ["ipp-primary-sodium-electrolysis", "ipp-secondary-sodium-electrolysis"]:
    if unlocked[rn_][0] != "ipp-sodium-coolant-production": errs.append(rn_ + ": chlorine routes and sodium production must unlock together")
if "ipp-lime-concrete" not in recipes or amt(recipes["ipp-lime-concrete"], 'in', "ipp-lime") is None or amt(recipes["ipp-lime-concrete"], 'out', "concrete") is None: errs.append("lime concrete")
# chlorine / sodium cannot be vented, surplus CO2 can
for f in ("ipp-chlorine", "ipp-primary-sodium", "ipp-primary-sodium-hot", "ipp-secondary-sodium", "ipp-secondary-sodium-hot"):
    if V.denied[f] != "hazard" or f in allowed: errs.append(f + ": must be refused as a hazard")
if "ipp-co2" not in allowed or "ipp-sco2" in allowed or "ipp-sco2-hot" in allowed: errs.append("only CO2 can be vented")
if unlocked["ipp-vent-co2"][0] != "ipp-sodium-coolant-production": errs.append("CO2 vent unlocked with the kiln")
# initial coolant filling: what it takes to fill the plant once (nothing is consumed afterwards: every sodium loop recipe is a closed loop)
loops_fill = 3 * (3 * D.SODIUM_FLOW * 2) + 2 * 3 * SEc.hot_primary_per_second * 2   # circulation boxes + exchanger boxes, rough lower bound
fill_salt = loops_fill / ELc.sodium * ELc.salt
print("sodium: filling the machines alone takes >= %.0f units = %.0f dry salt = %.0f brine; one electrolyzer makes %.0f sodium/s" % (loops_fill, fill_salt, fill_salt / SCc4.salt_out * SCc4.salt_brine, ELc.sodium / ELc.time_s))
if any(amt(recipes[r_], 'in', f_) != amt(recipes[r_], 'out', f2_) for r_, f_, f2_ in (("ipp-sodium-heat-exchange", "ipp-primary-sodium-hot", "ipp-primary-sodium"), ("ipp-co2-heating-direct", "ipp-secondary-sodium-hot", "ipp-secondary-sodium"))): errs.append("routine coolant consumption must be zero")

# --- fuel cycle recipes follow config, nothing can be bred out of nothing
fab = {"ipp-mox-assembly-fabrication": ("ipp-mox-assembly", {"ipp-plutonium-bearing-material": BFc.mox.pbm, "uranium-238": BFc.mox.du, "ipp-fuel-cladding": BFc.mox.claddings}),
       "ipp-starter-assembly-fabrication": ("ipp-starter-assembly", {"uranium-235": BFc.starter.u235, "uranium-238": BFc.starter.du, "ipp-fuel-cladding": BFc.starter.claddings}),
       "ipp-blanket-assembly-fabrication": ("ipp-blanket-assembly", {"uranium-238": BFc.blanket.du, "ipp-fuel-cladding": BFc.blanket.claddings})}
for rn_, (out_, ins_) in fab.items():
    r_ = recipes[rn_]
    if amt(r_, 'out', out_) != 1: errs.append(rn_ + ": product")
    for k_, v_ in ins_.items():
        if amt(r_, 'in', k_) != v_: errs.append("%s: %s != config" % (rn_, k_))
    if "ipp-fuel-fabrication" not in rcats(r_): errs.append(rn_ + ": category")
# the normal fuel needs recovered plutonium AND depleted uranium; the bootstrap fuel needs enriched uranium and no breeder output
if amt(recipes["ipp-mox-assembly-fabrication"], 'in', "uranium-235") is not None: errs.append("MOX must not need enriched uranium")
if amt(recipes["ipp-starter-assembly-fabrication"], 'in', "ipp-plutonium-bearing-material") is not None: errs.append("the starter assembly must not need plutonium (the first breeder needs no working breeder)")
irr = recipes["ipp-blanket-irradiation"]
if amt(irr, 'in', "ipp-blanket-assembly") != 1 or amt(irr, 'out', "ipp-bred-blanket-assembly") != 1 or irr.energy_required != CF.blanket_channel.channel_time_s: errs.append("irradiation recipe")
rcore, rbl = recipes["ipp-spent-core-reprocessing"], recipes["ipp-bred-blanket-reprocessing"]
for r_, c_, src in ((rcore, BFc.core_reprocessing, "ipp-spent-core-assembly-cooled"), (rbl, BFc.blanket_reprocessing, "ipp-bred-blanket-assembly")):
    if amt(r_, 'in', src) != 1 or amt(r_, 'out', "ipp-plutonium-bearing-material") != c_.pbm or amt(r_, 'out', "uranium-238") != c_.du or amt(r_, 'out', "ipp-radioactive-residue") != c_.residue: errs.append(r_.name + " != config")
    if amt(r_, 'out', "uranium-235") is not None: errs.append(r_.name + ": reprocessing must not hand out enriched uranium")
    if amt(r_, 'in', "sulfuric-acid") != CF.reprocessing.acid or amt(r_, 'in', "ipp-solvent") != CF.reprocessing.solvent or r_.energy_required != CF.reprocessing.time_s: errs.append(r_.name + ": acid / solvent / time must match the tier 3 plant")
    if "ipp-reprocessing" not in rcats(r_): errs.append(r_.name + ": category")
if amt(recipes["ipp-spent-core-cooling"], 'in', "ipp-spent-core-assembly") != 1 or amt(recipes["ipp-spent-core-cooling"], 'out', "ipp-spent-core-assembly-cooled") != 1: errs.append("spent core cooling")
if recipes["ipp-spent-core-cooling"].energy_required != CF.spent_fuel_pool.cooling_time_s: errs.append("spent core cooling time must match the pool")
if amt(recipes["ipp-spent-core-reprocessing"], 'in', "ipp-spent-core-assembly") is not None: errs.append("hot spent core fuel must cool before reprocessing")
# closed-loop check on the recipe amounts: one MOX assembly burnt + the blankets bred during it
burnt = BFc.mox.burnt_fissile
pbm_back = amt(rcore, 'out', "ipp-plutonium-bearing-material") + D.fuel.blankets_per_mox * amt(rbl, 'out', "ipp-plutonium-bearing-material")
du_net = (BFc.mox.du - amt(rcore, 'out', "uranium-238")) + D.fuel.blankets_per_mox * (BFc.blanket.du - amt(rbl, 'out', "uranium-238"))
waste = amt(rcore, 'out', "ipp-radioactive-residue") + D.fuel.blankets_per_mox * amt(rbl, 'out', "ipp-radioactive-residue")
ratio = (pbm_back - BFc.mox.pbm + burnt) / burnt
print("fuel cycle per MOX assembly (%.0f GJ): %.1f PBM back for %d in, %.1f depleted uranium eaten, %.1f residue made, breeding ratio %.2f" % (D.fuel.mox_gj, pbm_back, BFc.mox.pbm, du_net, waste, ratio))
if not 1.0 < ratio <= 1.3: errs.append("breeding ratio %.2f is not modestly above one" % ratio)
if du_net <= 0: errs.append("the cycle must consume depleted uranium")
if waste <= 0: errs.append("the cycle must make waste")
if pbm_back - BFc.mox.pbm > burnt: errs.append("more fissile gained than burnt: that is not breeding any more")
# a loop without blankets must shrink, a loop with the blankets of that burn must grow only modestly
if amt(rcore, 'out', "ipp-plutonium-bearing-material") >= BFc.mox.pbm: errs.append("the bare core must return less fissile material than it was loaded with")
# a blanket assembly cannot be loaded into a core, a MOX assembly cannot be irradiated
if "ipp-fast-fuel" in (raw.item["ipp-blanket-assembly"].fuel_categories or {}): errs.append("blanket assemblies cannot burn")
print("tier 4 checks done")


# ---- locale: every ipp-* prototype has a name (and the tier 4 ones a description where the tooltip needs one) ----
import re as _re
_loc, _sec = {}, None
for _line in open(MOD + "/locale/en/locale.cfg", encoding="utf-8").read().splitlines():
    _m = _re.match(r"^\[(.+)\]$", _line)
    if _m: _sec = _m.group(1); continue
    if "=" in _line and _sec and not _line.startswith("#"):
        _k, _v = _line.split("=", 1)
        if (_sec, _k) in _loc: errs.append("locale: duplicate key %s.%s" % (_sec, _k))
        _loc[(_sec, _k)] = _v
def _has(sec, name): return (sec, name) in _loc
for _n in raw.item.keys():
    if _n.startswith("ipp-") and raw.item[_n].localised_name is None and not _has("item-name", _n) and not _has("entity-name", _n): errs.append("locale: item-name.%s missing" % _n)
for _n in raw.fluid.keys():
    if _n.startswith("ipp-") and not _has("fluid-name", _n): errs.append("locale: fluid-name.%s missing" % _n)
    if _n.startswith("ipp-") and not _has("fluid-description", _n): errs.append("locale: fluid-description.%s missing" % _n)
for _n in recipes.keys():
    if _n.startswith("ipp-") and not (_has("recipe-name", _n) or _has("item-name", _n) or _has("entity-name", _n) or _has("fluid-name", _n)): errs.append("locale: recipe-name.%s missing" % _n)
for _t in raw.technology.keys():
    if _t.startswith("ipp-") and not (_has("technology-name", _t) and _has("technology-description", _t)): errs.append("locale: technology name/description %s missing" % _t)
for _c in raw["recipe-category"].keys():
    if _c.startswith("ipp-") and not _has("recipe-category-name", _c): errs.append("locale: recipe-category-name.%s missing" % _c)
for _c in raw["fuel-category"].keys():
    if _c.startswith("ipp-") and not _has("fuel-category-name", _c): errs.append("locale: fuel-category-name.%s missing" % _c)
for _typ in ("assembling-machine", "reactor", "boiler", "fusion-generator", "storage-tank"):
    for _n in raw[_typ].keys():
        if _n.startswith("ipp-"):
            if not _has("entity-name", _n): errs.append("locale: entity-name.%s missing" % _n)
            if not _has("entity-description", _n) and raw[_typ][_n].localised_description is not None: errs.append("locale: entity-description.%s missing" % _n)
# parameters: the highest __N__ of a description must not exceed what the prototype passes
def _params(s_): return max([int(x) for x in _re.findall(r"__(\d+)__", s_)] or [0])
def _npar(ld): return 0 if ld is None else len([k for k in ld.keys() if isinstance(k, int)]) - 1
for _typ in ("assembling-machine", "reactor", "boiler", "fusion-generator", "storage-tank"):
    for _n in raw[_typ].keys():
        if _n.startswith("ipp-") and _has("entity-description", _n) and raw[_typ][_n].localised_description is not None:
            if _params(_loc[("entity-description", _n)]) > _npar(raw[_typ][_n].localised_description): errs.append("locale: entity-description.%s uses more parameters than the tooltip passes" % _n)
for _n in ("ipp-mox-assembly", "ipp-starter-assembly"):
    if _params(_loc[("item-description", _n)]) > _npar(raw.item[_n].localised_description): errs.append("locale: item-description.%s parameters" % _n)
if _params(_loc[("fluid-description", "ipp-sco2-hot")]) > _npar(raw.fluid["ipp-sco2-hot"].localised_description): errs.append("locale: fluid-description.ipp-sco2-hot parameters")
print("locale checked: %d keys" % len(_loc))

# ---- every property name must exist in the 2.1 prototype API (skipped when prototype-api.json is not next to the mod) ----
import json
API = os.path.join(os.path.dirname(MOD), "prototype-api.json")
if os.path.exists(API):
    api = json.load(open(API))
    defs_by_name = {x["name"]: x for x in api["prototypes"] + api["types"]}
    by_typename = {x["typename"]: x["name"] for x in api["prototypes"] if x.get("typename")}
    def props_of(tname):
        out, seen = set(), set()
        while tname and tname in defs_by_name and tname not in seen:
            seen.add(tname); d = defs_by_name[tname]
            out |= {pr["name"] for pr in d.get("properties", [])}
            tname = d.get("parent")
        return out
    def keys(t):
        return [k for k in t.keys() if isinstance(k, str)]
    skipped = set()
    for ptype in list(raw.keys()):
        for pname in list(raw[ptype].keys()):
            if not str(pname).startswith("ipp-"): continue
            proto = raw[ptype][pname]
            if ptype not in by_typename: skipped.add(ptype); continue
            ok = props_of(by_typename[ptype]) | {"type", "name"}
            for k in keys(proto):
                if k not in ok: errs.append("%s %s: property '%s' does not exist in the 2.1 API" % (ptype, pname, k))

            def nested(t, tname, where):
                if t is None or tname not in defs_by_name: return
                allowed = props_of(tname) | {"type"}
                for k in keys(t):
                    if k not in allowed: errs.append("%s %s %s: '%s' does not exist in %s" % (ptype, pname, where, k, tname))
            if proto["icons"] is not None:
                for i in range(1, len(proto["icons"]) + 1): nested(proto["icons"][i], "IconData", "icons[%d]" % i)
            if ptype == "technology":
                nested(proto.unit, "TechnologyUnit", "unit")
                if proto.effects:
                    for i in range(1, len(proto.effects) + 1): nested(proto.effects[i], "UnlockRecipeModifier", "effects[%d]" % i)
            if ptype == "boiler":
                nested(proto.fluid_box, "FluidBox", "fluid_box"); nested(proto.output_fluid_box, "FluidBox", "output_fluid_box")
                for bx in ("fluid_box", "output_fluid_box"):
                    for i in range(1, len(proto[bx].pipe_connections) + 1): nested(proto[bx].pipe_connections[i], "PipeConnectionDefinition", bx + ".pipe_connections")
                nested(proto.energy_source, "HeatEnergySource", "energy_source")
            if ptype == "reactor":
                nested(proto.heat_buffer, "HeatBuffer", "heat_buffer")
                nested(proto.energy_source, "BurnerEnergySource", "energy_source")
            if ptype == "assembling-machine" and proto.fluid_boxes:
                for i in range(1, len(proto.fluid_boxes) + 1):
                    nested(proto.fluid_boxes[i], "FluidBox", "fluid_boxes[%d]" % i)
                    for j in range(1, len(proto.fluid_boxes[i].pipe_connections) + 1): nested(proto.fluid_boxes[i].pipe_connections[j], "PipeConnectionDefinition", "fluid_boxes[%d].pipe_connections" % i)
            if ptype == "recipe":
                for arr_name, base in (("ingredients", "Ingredient"), ("results", "Product")):
                    arr = proto[arr_name]
                    if arr is None: continue
                    for i in range(1, len(arr) + 1):
                        e = arr[i]; kind = "Item" if e.type == "item" else "Fluid"
                        allowed = props_of(kind + base + "Prototype") | {"type"}
                        for k in keys(e):
                            if k not in allowed: errs.append("recipe %s %s[%d]: '%s' is not a %s%sPrototype property" % (pname, arr_name, i, k, kind, base))
    if skipped: print("API name check: no API entry for", sorted(skipped))
    print("API name check done")
print("PROBLEMS:" if errs else "ALL CHECKS PASSED")
for e in errs: print(" -", e)
sys.exit(1 if errs else 0)
