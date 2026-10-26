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
for n, sz in pairs{["assembling-machine-1"]=3,["assembling-machine-2"]=3,["chemical-plant"]=3,["centrifuge"]=3,["foundry"]=5,["electromagnetic-plant"]=4,["oil-refinery"]=5} do
  raw["assembling-machine"][n] = am(n, sz)
end
raw["fusion-generator"] = { ["fusion-generator"] = { type="fusion-generator", name="fusion-generator",
  energy_source = {type="electric", usage_priority="primary-output", output_flow_limit="50MW"},
  input_fluid_box = { production_type="input", volume=100, filter="fusion-plasma", pipe_connections={{flow_direction="input", direction=0, position={0,-2}, connection_category={"fusion-plasma"}, connection_type="normal", hide_connection_info=true}} },
  output_fluid_box = { production_type="output", volume=100, filter="fusion-plasma", pipe_connections={{flow_direction="output", direction=4, position={1,-1}, connection_category={"fluoroketone"}}, {flow_direction="output", direction=4, position={1,1}, alt_position={0,0}}} },
  max_fluid_usage = 1, burns_fluid = false, effectivity = 1, minimum_input_temperature = 1000,
  minable = {result="fusion-generator"}, fast_replaceable_group="fg", next_upgrade="x",
  graphics_set = { animation = { layers = { sprite("fg.png"), shared } }, working_visualisations = { { name = "warm-up", animation = sprite("w.png") } },
                   states = { { name = "warm-up" }, { name = "on" } } },
  collision_box={{-1.2,-2.2},{1.2,2.2}}, selection_box={{-1.5,-2.5},{1.5,2.5}} } }
raw.accumulator = { accumulator = { type="accumulator", name="accumulator", energy_source={}, collision_box={{-.9,-.9},{.9,.9}},
  chargable_graphics = { picture = sprite("acc.png"), charge_animation = sprite("c.png") }, water_reflection = { pictures = sprite("r.png") } } }
raw.item, raw.fluid, raw.technology, raw.recipe = {}, {}, {}, {}
for _, n in ipairs{"fusion-generator","steel-chest","electric-engine-unit","pump","copper-cable","iron-gear-wheel","heat-pipe","stone-brick","steel-plate","storage-tank","plastic-bar","advanced-circuit","engine-unit","coal","stone","accumulator","iron-plate","copper-plate","pipe","electronic-circuit","sulfur","battery","iron-ore","concrete"} do
  raw.item[n] = { type="item", name=n, icon="__base__/graphics/icons/"..n..".png", icon_size=64 }
end
VANILLA_ITEMS = {}; for k in pairs(raw.item) do VANILLA_ITEMS[k] = true end
for _, n in ipairs{"steam","petroleum-gas","water","lubricant"} do raw.fluid[n] = { type="fluid", name=n, icon="f.png", icon_size=64 } end
for _, n in ipairs{"steel-processing","oil-processing","battery","logistic-science-pack","chemical-science-pack","plastics"} do
  raw.technology[n] = { type="technology", name=n, icon="t.png", icon_size=256 } end
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
        for i in range(1, len(box.pipe_connections)+1):
            extra = [k for k in box.pipe_connections[i].keys() if k not in ("flow_direction", "direction", "position")]
            if extra: errs.append("%s.%s connection %d keeps inherited fields %s (e.g. connection_category blocks normal pipes)" % (tn, boxname, i, extra))
        if boxname == "input_fluid_box" and len(box.pipe_connections) != 1: errs.append(tn + ": input port count")
        if boxname == "output_fluid_box" and len(box.pipe_connections) != 2: errs.append(tn + ": output port count")
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
print("PROBLEMS:" if errs else "ALL CHECKS PASSED")
for e in errs: print(" -", e)
sys.exit(1 if errs else 0)
