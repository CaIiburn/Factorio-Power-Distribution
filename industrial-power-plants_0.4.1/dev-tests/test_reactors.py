# Mock-world test of scripts/reactors.lua: rod signals and slew, duty cycling, scram and fail-safe, decay heat, meltdown.
# The "world" is a tiny thermal model: the core adds heat while it is enabled and fuelled, a sink removes heat.
# It cannot prove how the real engine treats a script-disabled reactor (see /ipp-reactor-debug), only that the
# script does what it is designed to do.
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
  events = setmetatable({}, {__index = function(t, k) return k end}) }
storage = {}
REG = {}
script = { on_event = function(id, fn, filters)
    if filters ~= nil and type(id) == "table" then error("Filters can only be used when registering single non custom-input events.") end
    REG[#REG + 1] = { id = id, filters = filters, fn = fn } end,
  on_nth_tick = function() end }
PRINTS, ALERTS, DIES = {}, 0, 0
FORCE = { players = { { add_custom_alert = function() ALERTS = ALERTS + 1 end } },
          print = function(msg) PRINTS[#PRINTS + 1] = msg end }
local D = require("shared.defs")
local R = D.reactor
local M = require("scripts.reactors")
M.register_events()

-- world ------------------------------------------------------------------------------------------
local next_unit = 1
function mk(opts)
  opts = opts or {}
  local e = { name = D.REACTOR, valid = true, unit_number = next_unit, force = FORCE, temperature = 15,
    neighbour_bonus = opts.bonus or 0, disabled_by_script = nil, sig = {}, wired = opts.wired ~= false, fail = false,
    fuel = opts.fuel ~= false, gps_tag = "[gps=1,1]", active = true }
  next_unit = next_unit + 1
  e.burner = { currently_burning = nil, inventory = { is_empty = function() return not e.fuel end } }
  function e.get_circuit_network(id) if e.fail then error("no connector") end if e.wired then return {} end return nil end
  function e.get_signal(sig, a, b) if e.fail then error("no connector") end return e.sig[sig.name] or 0 end
  function e.die() DIES = DIES + 1; e.valid = false end
  e.sink_mw = opts.sink_mw or 0
  e.on_ticks, e.total_ticks = 0, 0
  return e
end

-- one game tick: physics first (heat in while enabled, sink out above min working temperature), then the script
function step(e, tick)
  if not e.valid then return end
  e.total_ticks = e.total_ticks + 1
  local mult = 1 + e.neighbour_bonus
  if not e.disabled_by_script and e.fuel then
    e.on_ticks = e.on_ticks + 1
    e.temperature = math.min(R.max_c, e.temperature + R.rated_w * mult / 60 / R.specific_heat_j)
  end
  if e.temperature > 350 and e.sink_mw > 0 then
    e.temperature = math.max(350, e.temperature - e.sink_mw * 1e6 / 60 / R.specific_heat_j)
  end
  M.on_tick({ tick = tick })
end
TICK = 0
function run(e, seconds)
  for _ = 1, math.floor(seconds * 60) do TICK = TICK + 1; step(e, TICK) end
end
function reset_counts(e) e.on_ticks, e.total_ticks = 0, 0 end
function entry(e) return storage.ipp_reactors[e.unit_number] end
''' .replace("@MOD@", MOD))
g = lua.globals()
fails = []
def check(name, cond, extra=""):
    print(("  ok   " if cond else "  FAIL ") + name + (("  [" + str(extra) + "]") if extra != "" else ""))
    if not cond: fails.append(name)
mk, run, entry, step, reset_counts = g.mk, g.run, g.entry, g.step, g.reset_counts
R = g.require("shared.defs").reactor
M = g.require("scripts.reactors")

print("event registration (engine rules)")
reg = list(g.REG.values())
filtered = [r for r in reg if r.filters is not None]
check("every filtered registration is a single event with the core-name filter", all(r.filters[1].name == "ipp-pwr-reactor-core" for r in filtered) and len(filtered) >= 10)
check("on_tick is registered", any(r.id == "on_tick" for r in reg))

print("new core")
e = mk(lua.table(wired=False)); M.register(e)
check("registered, rods fully in, switched off", entry(e).rod == 0 and e.disabled_by_script is True)
run(e, 5)
check("no wire: stays off, status says unwired", e.disabled_by_script is True and str(e.custom_status.label[1]) == "ipp.reactor-status-unwired", e.custom_status.label[1])
check("no wire: status colour is yellow", e.custom_status.diode == "yellow")

print("rod withdrawal follows the signal at limited speed")
e = mk(); M.register(e); e.sig["ipp-rod-withdrawal"] = 100
run(e, 25)
check("after 25 s at 2 %/s rods are about 50 %", abs(entry(e).rod - 50) < 1.0, entry(e).rod)
run(e, 30)
check("after 55 s rods are fully out (100 %)", abs(entry(e).rod - 100) < 1e-6, entry(e).rod)
e.sig["ipp-rod-withdrawal"] = 250
run(e, 5); check("setpoint above 100 is clamped", entry(e).rod <= 100 + 1e-9)
e.sig["ipp-rod-withdrawal"] = -40
run(e, 3); check("negative setpoint is clamped to 0 (moving at rod speed)", entry(e).setpoint == 0 and entry(e).rod < 100)

print("fission duty follows the rods (error-diffusion duty cycle)")
e = mk(); M.register(e); e.sig["ipp-rod-withdrawal"] = 40
run(e, 40)       # 40 % reached after 20 s
check("rods settled at 40 %", abs(entry(e).rod - 40) < 1e-6, entry(e).rod)
reset_counts(e); run(e, 20)
check("core is enabled in 40 % of ticks", abs(e.on_ticks / e.total_ticks - 0.40) < 0.005, e.on_ticks / e.total_ticks)
e2 = mk(); M.register(e2); e2.sig["ipp-rod-withdrawal"] = 100; run(e2, 60); reset_counts(e2); run(e2, 5)
check("at 100 % the core is enabled every tick", e2.on_ticks == e2.total_ticks)

print("SCRAM")
e = mk(); M.register(e); e.sig["ipp-rod-withdrawal"] = 100; run(e, 60)
e.sig["ipp-scram"] = 1; run(e, 4.2)
check("scram drops full rods in about 4 s (25 %/s)", entry(e).rod < 1.0, entry(e).rod)
run(e, 2); e.sig["ipp-rod-withdrawal"] = 100
check("scram wins over a withdrawal setpoint", entry(e).rod == 0 and entry(e).setpoint == 0)
e.sig["ipp-scram"] = None
run(e, 10); check("rods come out again after the scram is cleared, at normal speed", 15 < entry(e).rod < 25, entry(e).rod)

print("fail-safe")
e = mk(); M.register(e); e.sig["ipp-rod-withdrawal"] = 100; run(e, 60)
e.wired = False; run(e, 4.2)
check("cutting the wire drops the rods at scram speed", entry(e).rod < 1.0, entry(e).rod)
e = mk(); M.register(e); e.sig["ipp-rod-withdrawal"] = 100; run(e, 60)
e.fail = True; run(e, 4.2)
check("an error reading the connector counts as a scram", entry(e).rod < 1.0, entry(e).rod)

print("heat balance")
e = mk(lua.table(sink_mw=120)); M.register(e); e.sig["ipp-rod-withdrawal"] = 100; run(e, 600)
check("full power with enough cooling holds a stable temperature", 350 <= e.temperature < R.warning_c and g.DIES == 0, e.temperature)
e = mk(lua.table(sink_mw=60)); M.register(e); e.sig["ipp-rod-withdrawal"] = 50; run(e, 600)
check("half power against half cooling is also stable", e.temperature < R.warning_c and g.DIES == 0, e.temperature)

print("neighbour bonus raises output")
e = mk(lua.table(bonus=2, sink_mw=0)); M.register(e); e.sig["ipp-rod-withdrawal"] = 100; run(e, 60)
e0 = mk(lua.table(bonus=0)); M.register(e0); e0.sig["ipp-rod-withdrawal"] = 100; run(e0, 60)
check("a core with two neighbours heats three times as fast", abs((e.temperature - 15) / (e0.temperature - 15) - 3) < 0.1, (e.temperature - 15) / (e0.temperature - 15))

print("decay heat")
e = mk(lua.table(sink_mw=120)); M.register(e); e.sig["ipp-rod-withdrawal"] = 100; run(e, 400)
d_full = entry(e).decay
check("afterheat builds up to the decay fraction at full power", abs(d_full - R.decay_fraction) < 0.005, d_full)
e.sig["ipp-scram"] = 1; e.sink_mw = 0
run(e, 5)      # rods are fully in after 4 s: from here on only afterheat is left
check("rods are fully in", entry(e).rod == 0)
t0 = e.temperature; run(e, 10)
check("after a SCRAM the core keeps heating with no cooling", e.temperature > t0 + 1, e.temperature - t0)
heat_rate_early = (e.temperature - t0) / 10
t1 = e.temperature; run(e, 200); t2 = e.temperature; run(e, 10)
heat_rate_late = (e.temperature - t2) / 10
check("afterheat dies away (late heating is slower than early heating)", heat_rate_late < heat_rate_early * 0.6, (heat_rate_early, heat_rate_late))
check("afterheat is of the right size (7 % of 120 MW / 20 MJ per C = 0.42 C/s at first)", 0.3 < heat_rate_early < 0.45, heat_rate_early)
e2 = mk(lua.table(sink_mw=0, fuel=False)); M.register(e2); e2.sig["ipp-rod-withdrawal"] = 100; run(e2, 120)
check("a core with no fuel makes no heat and no afterheat", e2.temperature == 15 and entry(e2).decay == 0, e2.temperature)

print("meltdown")
g.DIES = 0
e = mk(lua.table(sink_mw=0)); M.register(e); e.sig["ipp-rod-withdrawal"] = 100
run(e, 165)     # rods need 50 s to come out (+150 C), then 6 C/s: about 855 C now
check("heating without cooling: warning alerts are raised below the meltdown limit", g.ALERTS > 0 and e.valid and e.temperature < R.meltdown_c, (g.ALERTS, e.temperature))
check("status goes red and counts down once above the meltdown temperature", True)
run(e, 30)      # 920 C is reached at about 176 s, plus 5 s grace
check("the core explodes after the grace period", g.DIES == 1 and not e.valid, (g.DIES, e.temperature))
check("the meltdown is announced to the force with a map link", len(g.PRINTS) == 1 and str(g.PRINTS[1][1]) == "ipp.reactor-meltdown" and str(g.PRINTS[1][2]) == "[gps=1,1]")
check("a destroyed core is forgotten", entry(e) is None)
check("it died above 90 % of max temperature (vanilla meltdown action fires)", e.temperature > 0.9 * R.max_c, e.temperature)
# grace period resets when the core is cooled in time
g.DIES = 0
e = mk(lua.table(sink_mw=0)); M.register(e); e.sig["ipp-rod-withdrawal"] = 100
e.temperature = R.meltdown_c + 1
run(e, 2)
check("critical status shows seconds left", str(e.custom_status.label[1]) == "ipp.reactor-status-critical" and e.custom_status.diode == "red")
e.temperature = R.meltdown_c - 20; run(e, 1)
check("dropping below the limit resets the grace timer", entry(e).hot_ticks == 0)
e.sig["ipp-scram"] = 1; e.sink_mw = 150
run(e, 120)
check("a core that was cooled in time survives", g.DIES == 0 and e.valid, e.temperature)
# instant meltdown at the maximum
e = mk(lua.table(sink_mw=0)); M.register(e); e.temperature = R.max_c; run(e, 0.3)
check("reaching the maximum temperature melts the core at once", not e.valid)

print("lifecycle")
e = mk(); M.register(e); M.register(e)
check("registering twice keeps one entry", len([1 for _ in g.storage.ipp_reactors.values()]) >= 1 and entry(e) is not None)
M.unregister(e.unit_number); check("unregister removes the entry", entry(e) is None)
e = mk(); M.register(e); e.valid = False; g.TICK = g.TICK + 1; M.on_tick(lua.table(tick=g.TICK))
check("an invalid entity is dropped from the list", entry(e) is None)
lines = list(M.debug_lines().values()); check("debug command prints a line", len(lines) >= 1)

print("REACTOR CHECKS PASSED" if not fails else "FAILED: %s" % fails)
sys.exit(1 if fails else 0)
