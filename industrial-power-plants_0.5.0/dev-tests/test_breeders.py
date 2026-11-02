# Mock-world tests of the Tier 4 scripts: scripts/events.lua + control.lua (one registration per event for the whole mod),
# scripts/heaters.lua (recipe follows the fluid at the CO2 inlet) and scripts/breeders.lua (blanket channels follow the
# fission power of the core they touch).
import os, sys
from lupa import LuaRuntime
MOD = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(r'''
package.path = "@MOD@/?.lua;" .. package.path
function log(m) end
defines = { direction = {north=0, east=4, south=8, west=12},
  wire_connector_id = { circuit_red = "red", circuit_green = "green" },
  entity_status_diode = { green = "green", yellow = "yellow", red = "red" },
  inventory = { crafter_input = "crafter_input" },
  events = setmetatable({}, {__index = function(t, k) return k end}) }
storage = {}
game = { surfaces = {}, get_player = function() return nil end, print = function() end }
commands = { add_command = function() end }
prototypes = { fluid = setmetatable({}, {__index = function(t,k) return {localised_name = "LN:" .. k} end}) }

-- registration log: every script.on_event / on_nth_tick call of a full control.lua load
EVENT_COUNT, NTH_COUNT, TICK_FN = {}, {}, nil
script = {
  on_event = function(id, fn, filters)
    if filters ~= nil and type(id) == "table" then error("Filters can only be used when registering single non custom-input events.") end
    EVENT_COUNT[id] = (EVENT_COUNT[id] or 0) + 1
    if id == "on_tick" then TICK_FN = fn end
    LAST_FILTERS = LAST_FILTERS or {}; LAST_FILTERS[id] = filters; HANDLERS = HANDLERS or {}; HANDLERS[id] = fn
  end,
  on_nth_tick = function(n, fn) NTH_COUNT[n] = (NTH_COUNT[n] or 0) + 1 end,
  on_init = function() end, on_configuration_changed = function() end,
}
dofile("@MOD@/control.lua")

D = require("shared.defs")
HEAT = require("scripts.heaters")
BRD = require("scripts.breeders")
REA = require("scripts.reactors")

-- ---- heater world ----
ENABLED = { ["ipp-co2-heating-recuperated"] = true, ["ipp-co2-heating-direct"] = true }
FORCE = { recipes = setmetatable({}, {__index = function(t,k) return { enabled = ENABLED[k] } end}) }
SURF = { ents = {} }
function SURF.find_entities_filtered(f)
  local out = {}
  for _, e in ipairs(SURF.ents) do
    if f.position then local dx, dy = e.position.x - f.position.x, e.position.y - f.position.y
      if dx*dx + dy*dy <= f.radius*f.radius then out[#out+1] = e end end
  end
  return out
end
function mk_heater(x, y, dir)
  local h = { name = D.HEATER, valid = true, unit_number = 7, position = {x=x, y=y}, direction = dir, surface = SURF, force = FORCE, type = "assembling-machine" }
  function h.get_recipe() return h.recipe and { name = h.recipe } or nil end
  function h.set_recipe(r) h.recipe = r end
  return h
end
function mk_pipe(x, y, contents)
  local p = { name = "pipe", type = "pipe", valid = true, position = {x=x, y=y}, contents = contents }
  function p.get_fluid_contents() return p.contents end
  table.insert(SURF.ents, p); return p
end

-- ---- breeder world ----
CORE_SEQ = 100
function mk_core(x, y, opts)
  opts = opts or {}
  CORE_SEQ = CORE_SEQ + 1
  local c = { name = D.FBR, valid = true, unit_number = CORE_SEQ, surface = SURF, neighbour_bonus = opts.bonus or 0,
    position = {x=x, y=y}, selection_box = { left_top = {x=x-2.5, y=y-2.5}, right_bottom = {x=x+2.5, y=y+2.5} },
    burner = { currently_burning = (opts.fuel ~= false) and true or nil, inventory = { is_empty = function() return opts.fuel == false end } } }
  storage.ipp_reactors = storage.ipp_reactors or {}
  storage.ipp_reactors[c.unit_number] = { entity = c, duty = opts.duty or 1.0 }
  return c
end
CH_SEQ = 200
function mk_channel(x, y, loaded)
  CH_SEQ = CH_SEQ + 1
  local c = { name = D.CHANNEL, valid = true, unit_number = CH_SEQ, surface = SURF, position = {x=x, y=y}, crafting_progress = 0,
    selection_box = { left_top = {x=x-1.5, y=y-1.5}, right_bottom = {x=x+1.5, y=y+1.5} }, gps_tag = "[gps]" }
  c.inp = { is_empty = function() return not c.has end }
  c.has = (loaded ~= false)
  function c.get_inventory() return c.inp end
  BRD.register(c)
  return c
end
function ch_entry(c) return storage.ipp_channels[c.unit_number] end
function run_ticks(n)
  for t = 1, n do TICK = (TICK or 0) + 1; BRD.on_tick({ tick = TICK }) end
end
''' .replace("@MOD@", MOD))
g = lua.globals()
fails = []
def check(name, cond, extra=""):
    print(("  ok   " if cond else "  FAIL ") + name + (("  [" + str(extra) + "]") if extra != "" else ""))
    if not cond: fails.append(name)
D = g.D
ch_entry = g.ch_entry
CF = D.config

print("event registration: the whole mod, once per event (the engine keeps one handler per event)")
dups = {k: v for k, v in g.EVENT_COUNT.items() if v > 1}
check("no event is registered twice (a second script.on_event replaces the first, even with other filters)", not dups, dups)
nth_dups = {k: v for k, v in g.NTH_COUNT.items() if v > 1}
check("no nth-tick value is registered twice", not nth_dups, nth_dups)
for ev in ("on_built_entity", "on_robot_built_entity", "on_space_platform_built_entity", "script_raised_built", "script_raised_revive",
           "on_entity_cloned", "on_player_mined_entity", "on_robot_mined_entity", "on_space_platform_mined_entity", "on_entity_died",
           "script_raised_destroy", "on_tick", "on_research_finished"):
    check("%s registered" % ev, g.EVENT_COUNT[ev] == 1)
names = sorted(g.LAST_FILTERS["on_built_entity"][i].name for i in range(1, len(g.LAST_FILTERS["on_built_entity"]) + 1))
check("the combined filter names every script-managed entity", names == sorted(["ipp-exhaust-stack", D.REACTOR, D.FBR, D.HEATER, D.CHANNEL]), names)
check("nth ticks 60 (stacks) and 59 (heaters)", g.NTH_COUNT[60] == 1 and g.NTH_COUNT[59] == 1)

print("dispatch: an entity reaches only the script that owns its name")
h0 = g.mk_heater(0, 0, 0); h0.unit_number = 31
g.HANDLERS["on_built_entity"](lua.table(entity=h0))
check("a built heater is registered", g.storage.ipp_heaters[31] is not None)
g.HANDLERS["on_entity_died"](lua.table(entity=h0))
check("a destroyed heater is forgotten", g.storage.ipp_heaters[31] is None)
core = g.mk_core(0, 0)
ch0 = g.mk_channel(10, 0)
g.HANDLERS["on_entity_cloned"](lua.table(destination=ch0))
check("a cloned channel is registered", g.storage.ipp_channels[ch0.unit_number] is not None)
g.HANDLERS["script_raised_destroy"](lua.table(entity=ch0))
check("a destroyed channel is forgotten", g.storage.ipp_channels[ch0.unit_number] is None)

print("heater: recipe follows the fluid at the CO2 inlet")
OFF = (CF.co2_heater.size + 1) // 2
def setup(direction=0, px=1, py=None, contents=None, recipe=None):
    py = -OFF if py is None else py
    lua.execute("SURF.ents = {}")
    h = g.mk_heater(10, 10, direction); h.recipe = recipe
    g.table.insert(g.SURF.ents, h)
    p = g.mk_pipe(10 + px, 10 + py, lua.table_from(contents or {}))
    return h, p
WARM, DIRECT = "ipp-co2-heating-recuperated", "ipp-co2-heating-direct"
h, p = setup(contents={"ipp-sco2-warm": 50.0}); g.HEAT.update(h)
check("preheated CO2 at the inlet -> recuperated recipe", h.recipe == WARM and h.custom_status.diode == "green", h.recipe)
h, p = setup(contents={"ipp-sco2": 50.0}); g.HEAT.update(h)
check("cold compressed CO2 at the inlet (no recuperator) -> direct recipe", h.recipe == DIRECT and h.custom_status.diode == "yellow", h.recipe)
check("the direct status says how much more heat it needs", str(h.custom_status.label[1]) == "ipp.heater-direct" and str(h.custom_status.label[2]) == "67", list(h.custom_status.label.values()))
p.contents = lua.table_from({"ipp-sco2-warm": 20.0}); g.HEAT.update(h)
check("the recuperator is added later: the heater switches over by itself", h.recipe == WARM)
p.contents = lua.table_from({"ipp-sco2": 20.0}); g.HEAT.update(h)
check("the recuperator is removed: the heater switches back and keeps working", h.recipe == DIRECT)
h, p = setup(contents={}, recipe=None); g.HEAT.update(h)
check("nothing connected yet: starts on the rated (recuperated) recipe", h.recipe == WARM)
h, p = setup(contents={}, recipe=DIRECT); g.HEAT.update(h)
check("an empty pipe never changes a working recipe", h.recipe == DIRECT)
h, p = setup(contents={"ipp-sco2-hot": 90.0}, recipe=DIRECT); g.HEAT.update(h)
check("an unrelated fluid at the inlet changes nothing", h.recipe == DIRECT)
h, p = setup(contents={"ipp-sco2": 10.0, "ipp-sco2-warm": 90.0}); g.HEAT.update(h)
check("a mixed pipe: the more plentiful feed wins", h.recipe == WARM)
g.ENABLED[DIRECT] = False
h, p = setup(contents={"ipp-sco2": 50.0}, recipe=WARM); g.HEAT.update(h)
check("a recipe that is not researched is never set", h.recipe == WARM)
g.ENABLED[DIRECT] = True
g.ENABLED[WARM] = False
h, p = setup(contents={}, recipe=None); g.HEAT.update(h)
check("nothing researched: no recipe, red status", h.recipe is None and h.custom_status.diode == "red")
g.ENABLED[WARM] = True
print("heater: the inlet follows the rotation (right-hand port of the north face when unrotated)")
for d, (px, py) in {4: (OFF, 1), 8: (-1, OFF), 12: (-OFF, -1)}.items():
    h, p = setup(direction=d, px=px, py=py, contents={"ipp-sco2": 5.0}); g.HEAT.update(h)
    check("direction %d inlet found at (%d,%d)" % (d, px, py), h.recipe == DIRECT)
h, p = setup(direction=0, px=-1, py=-OFF, contents={"ipp-sco2": 5.0}); g.HEAT.update(h)
check("the sodium port (left-hand) is not read", h.recipe is None or h.recipe == WARM)

print("blanket channels: speed follows the actual power of the core they touch")
B = D.breeder
T, E = B.channel_time_s, B.irradiation_j
def duty_of(c): return ch_entry(c).duty
lua.execute("SURF.ents = {}; storage.ipp_reactors = {}; storage.ipp_channels = {}")
core = g.mk_core(0, 0, lua.table(duty=1.0, bonus=0))
c1 = g.mk_channel(4, 0)          # touches the core's east edge (gap 0.0)
g.BRD.assign()
want = T * B.rated_w / E
check("one channel on a full-power core: duty = channel time x power / irradiation energy", abs(duty_of(c1) - want) < 1e-9 and 0 < want < 1, (duty_of(c1), want))
check("status is green with the duty shown", c1.custom_status.diode == "green" and str(c1.custom_status.label[1]) == "ipp.channel-flux")
c2 = g.mk_channel(-4, 0); c3 = g.mk_channel(0, 4)
g.BRD.assign()
check("three loaded channels share the flux equally", all(abs(duty_of(c) - want / 3) < 1e-9 for c in (c1, c2, c3)), [duty_of(c) for c in (c1, c2, c3)])
check("... so the core's total breeding rate does not depend on the number of channels",
      abs(sum(duty_of(c) for c in (c1, c2, c3)) - want) < 1e-9)
c3.has = False
g.BRD.assign()
check("an empty channel takes no share", abs(duty_of(c1) - want / 2) < 1e-9 and abs(duty_of(c2) - want / 2) < 1e-9)
c3.has = True
core_e = g.storage.ipp_reactors[core.unit_number]
core_e.duty = 0.5; g.BRD.assign()
check("a core at half rods breeds at half speed", abs(duty_of(c1) - want / 3 / 2) < 1e-9)
core_e.duty = 0.0; g.BRD.assign()
check("a shut-down core irradiates nothing", duty_of(c1) == 0 and c1.custom_status.diode == "yellow" and str(c1.custom_status.label[1]) == "ipp.channel-core-idle")
core_e.duty = 1.0
core.burner = lua.table(currently_burning=None, inventory=lua.table(is_empty=lambda *a: True))
g.BRD.assign()
check("a core without fuel irradiates nothing", duty_of(c1) == 0)
core.burner = lua.table(currently_burning=True, inventory=lua.table(is_empty=lambda *a: False))

print("blanket channels: a strong core outruns its channels (neighbour bonus), more channels fix it")
lua.execute("SURF.ents = {}; storage.ipp_reactors = {}; storage.ipp_channels = {}")
core = g.mk_core(0, 0, lua.table(duty=1.0, bonus=2))
c1 = g.mk_channel(4, 0)
g.BRD.assign()
check("x3 core and one channel: duty capped at 1 (flux wasted), status warns", duty_of(c1) == 1 and c1.custom_status.diode == "yellow" and str(c1.custom_status.label[1]) == "ipp.channel-flux-surplus")
cs = [c1, g.mk_channel(-4, 0), g.mk_channel(0, 4)]
g.BRD.assign()
check("x3 core and three channels: all below the cap", all(duty_of(c) < 1 for c in cs), [duty_of(c) for c in cs])
check("... and together they use the full flux", abs(sum(duty_of(c) for c in cs) - T * 3 * B.rated_w / E) < 1e-9)

print("blanket channels: which core a channel belongs to")
lua.execute("SURF.ents = {}; storage.ipp_reactors = {}; storage.ipp_channels = {}")
a = g.mk_core(0, 0, lua.table(duty=1.0)); b = g.mk_core(30, 0, lua.table(duty=0.5))
near_a = g.mk_channel(4, 0); near_b = g.mk_channel(26, 0); far = g.mk_channel(15, 0)
g.BRD.assign()
check("each channel takes the core it touches", ch_entry(near_a).core == a.unit_number and ch_entry(near_b).core == b.unit_number)
check("a channel out of reach has no core, duty 0, red status", ch_entry(far).core is None and duty_of(far) == 0 and far.custom_status.diode == "red")
lua.execute("storage.ipp_reactors = {}")
g.BRD.assign()
check("without any core every channel idles", all(duty_of(c) == 0 for c in (near_a, near_b)))
pwr = g.mk_core(0, 0, lua.table(duty=1.0))
other = g.mk_core(50, 50, lua.table(duty=1.0)); other.name = D.REACTOR
g.storage.ipp_reactors[other.unit_number].entity = other
g.BRD.assign()
check("a pressurized-water core is never a breeder core", ch_entry(near_b).core is None)

print("blanket channels: the on/off duty cycle averages to the duty")
lua.execute("SURF.ents = {}; storage.ipp_reactors = {}; storage.ipp_channels = {}; TICK = 0")
core = g.mk_core(0, 0, lua.table(duty=1.0, bonus=0)); c1 = g.mk_channel(4, 0)
check("a new channel starts switched off", c1.disabled_by_script is True)
g.BRD.assign()
g.CHANNEL_UNDER_TEST = c1
lua.execute("""
  ON_TICKS = 0
  for _ = 1, 6000 do run_ticks(1); if not CHANNEL_UNDER_TEST.disabled_by_script then ON_TICKS = ON_TICKS + 1 end end""")
check("enabled in a share of ticks equal to the duty", abs(g.ON_TICKS / 6000 - ch_entry(c1).duty) < 0.005, (g.ON_TICKS / 6000, ch_entry(c1).duty))
check("the blanket's irradiation takes the energy it should: time = irradiation energy / (power) at one channel",
      abs(T / ch_entry(c1).duty - E / B.rated_w) < 1e-6, (T / ch_entry(c1).duty, E / B.rated_w))

print("fuel cycle numbers (no closed recipe may breed fissile material out of nothing)")
BF = CF.breeder_fuel
fuel = D.fuel
check("breeding ratio is modestly above one", 1 < fuel.breeding_ratio <= 1.3, fuel.breeding_ratio)
check("a core without blankets cannot sustain itself (ratio below one)", fuel.core_only_ratio < 1, fuel.core_only_ratio)
core_out = BF.core_reprocessing; bl_out = BF.blanket_reprocessing
check("core reprocessing returns no more heavy metal than went in (the rest was fissioned or lost)",
      core_out.pbm + core_out.du + core_out.residue <= BF.mox.pbm + BF.mox.du + 1e-9)
check("blanket reprocessing returns no more heavy metal than went in", bl_out.pbm + bl_out.du + bl_out.residue <= BF.blanket.du + 1e-9)
check("fission and losses end up as waste: the core's residue covers at least the fissioned fissile material", core_out.residue >= BF.mox.burnt_fissile)
fissile_in = BF.mox.pbm; left_after_burn = fissile_in - BF.mox.burnt_fissile
bred_in_core = core_out.pbm - left_after_burn
check("the core cannot return more fissile than it was given plus what it bred from fertile material (bred >= 0, <= burnt)", 0 <= bred_in_core <= BF.mox.burnt_fissile, bred_in_core)
du_net = (BF.mox.du - core_out.du) + fuel.blankets_per_mox * (BF.blanket.du - bl_out.du)
check("every MOX assembly burnt eats depleted uranium (net > 0)", du_net > 0, du_net)
check("... and the PBM-only loop always needs depleted uranium input: no MOX without it", BF.mox.du > 0 and BF.blanket.du > 0)
check("a starter assembly holds as much fissile material as a MOX assembly (fresh enriched uranium replaces the plutonium)", BF.starter.u235 == BF.mox.pbm)
check("MOX and starter assembly energy follow the fissile material burnt", abs(fuel.mox_gj - BF.mox.burnt_fissile * BF.gj_per_fissile) < 1e-9 and fuel.mox_gj == fuel.starter_gj)
check("fuel assembly energy per fissile unit matches the Tier 3 assembly (40 GJ per 0.5 U-235)", BF.gj_per_fissile == CF.fuel_assembly.energy_gj / (CF.fuel_assembly.cells * 0.1))
print("   breeding ratio %.3f with blankets, %.3f without; %.2f blankets per MOX assembly; net depleted uranium %.2f per assembly; %.0f GJ per assembly" %
      (fuel.breeding_ratio, fuel.core_only_ratio, fuel.blankets_per_mox, du_net, fuel.mox_gj))

print("BREEDER CHECKS PASSED" if not fails else "FAILED: %s" % fails)
sys.exit(1 if fails else 0)
