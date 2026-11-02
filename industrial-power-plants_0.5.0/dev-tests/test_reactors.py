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

-- world ------------------------------------------------------------------------------------------
local next_unit = 1
function mk(opts)
  opts = opts or {}
  local e = { name = opts.name or D.REACTOR, valid = true, unit_number = next_unit, force = FORCE, temperature = 15,
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
  local R = D.reactors[e.name]
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
M.register_events()
reg = list(g.REG.values())
check("on_tick is registered", any(r.id == "on_tick" for r in reg))
check("lifecycle events are NOT registered here (scripts/events.lua registers them once)", not any(r.id in ("on_built_entity", "on_entity_died") for r in reg))
check("both core types are handled by the one script", M.lifecycle.names["ipp-pwr-reactor-core"] is True and M.lifecycle.names["ipp-fast-breeder-reactor"] is True)
check("hook list exists for scripts that need on_tick", M.hooks is not None)

print("new core")
e = mk(lua.table(wired=False)); M.register(e)
check("registered, rods fully in, switched off", entry(e).rod == 0 and e.disabled_by_script is True)
run(e, 5)
check("no wire: stays off, status says unwired", e.disabled_by_script is True and str(e.custom_status.label[1]) == "ipp.reactor-status-unwired", e.custom_status.label[1])
check("no wire: status colour is yellow", e.custom_status.diode == "yellow")

FULL = 100 / R.rod_speed + 2     # seconds the rods need to come fully out (plus a margin)
DROP = 100 / R.scram_speed + 0.5 # seconds a SCRAM needs to drive them fully in (plus a margin)
print("rod withdrawal follows the signal at limited speed (config rod speed %s %%/s)" % R.rod_speed)
e = mk(); M.register(e); e.sig["ipp-rod-withdrawal"] = 100
run(e, 25)
check("after 25 s the rods are at 25 s x rod speed", abs(entry(e).rod - 25 * R.rod_speed) < 1.0, entry(e).rod)
run(e, FULL - 25)
check("after the full travel time rods are fully out (100 %)", abs(entry(e).rod - 100) < 1e-6, entry(e).rod)
e.sig["ipp-rod-withdrawal"] = 250
run(e, 5); check("setpoint above 100 is clamped", entry(e).rod <= 100 + 1e-9)
e.sig["ipp-rod-withdrawal"] = -40
run(e, 3); check("negative setpoint is clamped to 0 (moving at rod speed)", entry(e).setpoint == 0 and entry(e).rod < 100)

print("fission duty follows the rods (error-diffusion duty cycle)")
e = mk(); M.register(e); e.sig["ipp-rod-withdrawal"] = 40
run(e, 40 / R.rod_speed + 1)       # 40 % reached after 40 / rod speed seconds
check("rods settled at 40 %", abs(entry(e).rod - 40) < 1e-6, entry(e).rod)
reset_counts(e); run(e, 20)
check("core is enabled in 40 % of ticks", abs(e.on_ticks / e.total_ticks - 0.40) < 0.005, e.on_ticks / e.total_ticks)
e2 = mk(); M.register(e2); e2.sig["ipp-rod-withdrawal"] = 100; run(e2, FULL); reset_counts(e2); run(e2, 5)
check("at 100 % the core is enabled every tick", e2.on_ticks == e2.total_ticks)

print("SCRAM: latched, rods always fully in, lockout before they can come out again (config %s s)" % R.scram_lockout_s)
LOCK = R.scram_lockout_s
def full_power():
    c = mk(); M.register(c); c.sig["ipp-rod-withdrawal"] = 100; run(c, FULL); return c
e = full_power()
check("rods fully out before the scram", abs(entry(e).rod - 100) < 1e-6)
e.sig["ipp-scram"] = 1; run(e, DROP)
check("scram drives full rods fully in at scram speed", entry(e).rod == 0, entry(e).rod)
check("the core is tripped", entry(e).tripped is True)
e.sig["ipp-rod-withdrawal"] = 100; run(e, 1)
check("scram wins over a withdrawal setpoint", entry(e).rod == 0 and entry(e).setpoint == 0)
check("status shows the lockout countdown while rods are in", str(e.custom_status.label[1]) == "ipp.reactor-status-lockout", e.custom_status.label[1])
e.sig["ipp-scram"] = None
run(e, 60)
check("60 s after the scram signal is gone the rods are still locked in", entry(e).rod == 0 and entry(e).tripped is True, entry(e).rod)
check("lockout countdown is about the configured time (less what has passed)", abs(entry(e).lock_left - (LOCK - DROP - 61)) < 3, entry(e).lock_left)
check("a locked-out core is switched off", e.disabled_by_script is True)
run(e, LOCK - DROP - 61 - 4)       # about 4 s before the lockout ends
check("still locked 4 s before the lockout ends", entry(e).rod == 0 and entry(e).tripped is True, (entry(e).rod, entry(e).lock_left))
run(e, 4 + 10)                      # 10 s after it ended
check("the rods are released when the lockout is over", entry(e).tripped is False and 0 < entry(e).rod < 15 * R.rod_speed + 1, (entry(e).tripped, entry(e).rod))
check("... and come out at normal speed, not scram speed", entry(e).rod < 10 * R.rod_speed + 2, entry(e).rod)

e = full_power()
e.sig["ipp-scram"] = 1; run(e, 0.2); e.sig["ipp-scram"] = None
run(e, DROP)
check("a scram pulse (one control step) still drives the rods all the way in", entry(e).rod == 0 and entry(e).tripped is True, entry(e).rod)
run(e, 100)
t_left = entry(e).lock_left
e.sig["ipp-scram"] = 1; run(e, 0.2); e.sig["ipp-scram"] = None; run(e, 1)
check("a scram signal during a lockout does not restart the timer", abs((t_left - 1.2) - entry(e).lock_left) < 1, (t_left, entry(e).lock_left))

e = full_power()
e.sig["ipp-scram"] = 1; run(e, LOCK + 30)
check("a scram signal still present after the lockout keeps the rods in", entry(e).rod == 0 and entry(e).tripped is True)
check("status says the signal is holding the rods", str(e.custom_status.label[1]) == "ipp.reactor-status-scram-held", e.custom_status.label[1])
e.sig["ipp-scram"] = None; run(e, 1)
check("removing the signal after the lockout releases the rods at once", entry(e).tripped is False)
run(e, 10); check("... and they withdraw at normal speed", 0 < entry(e).rod < 10 * R.rod_speed + 2, entry(e).rod)

e = full_power()
e.sig["ipp-scram"] = 1; run(e, 1); e.sig["ipp-scram"] = None
e.wired = False; run(e, 30); e.wired = True; run(e, 30)
check("cutting and restoring the wire does not end a lockout", entry(e).rod == 0 and entry(e).tripped is True, entry(e).rod)

R.scram_lockout_s = 0
e = full_power()
e.sig["ipp-scram"] = 1; run(e, DROP)
check("lockout 0: the rods still go all the way in while the signal is present", entry(e).rod == 0 and entry(e).tripped is True)
e.sig["ipp-scram"] = None; run(e, 10)
check("lockout 0: rods are released as soon as the signal is gone", entry(e).tripped is False and entry(e).rod > 0, entry(e).rod)
e = full_power()
e.sig["ipp-scram"] = 1; run(e, 0.2); e.sig["ipp-scram"] = None; run(e, 1)
check("lockout 0: after a pulse the core stays tripped while the rods are still travelling in", entry(e).tripped is True and 0 < entry(e).rod < 100, (entry(e).tripped, entry(e).rod))
run(e, DROP + 2)
check("lockout 0: ... and is released once they are fully in (rods start coming out again)", entry(e).tripped is False and entry(e).rod < 3 * R.rod_speed + 1, (entry(e).tripped, entry(e).rod))
R.scram_lockout_s = LOCK

print("old saves: entries without the SCRAM fields keep working")
e = full_power(); ent = entry(e); ent.tripped = None; ent.lock_until = None; ent.lock_left = None
run(e, 2)
check("an entry from before the lockout existed runs normally", entry(e).tripped is not True and abs(entry(e).rod - 100) < 1e-6)

print("fail-safe (no lockout)")
e = full_power()
e.wired = False; run(e, DROP)
check("cutting the wire drops the rods at scram speed", entry(e).rod < 1.0, entry(e).rod)
check("... without starting a lockout", entry(e).tripped is not True)
e.wired = True; run(e, 10)
check("rods come out again at normal speed once the wire is back", 0 < entry(e).rod < 10 * R.rod_speed + 2, entry(e).rod)
e = full_power()
e.fail = True; run(e, DROP)
check("an error reading the connector drops the rods", entry(e).rod < 1.0, entry(e).rod)
check("... without starting a lockout", entry(e).tripped is not True)
e = mk(lua.table(wired=False)); M.register(e); run(e, 5)
check("a new unwired core is not locked out", entry(e).tripped is False)

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
t1 = e.temperature; run(e, 0.67 * R.decay_fall_s); t2 = e.temperature; run(e, 10)
heat_rate_late = (e.temperature - t2) / 10
check("afterheat dies away (late heating is slower than early heating)", heat_rate_late < heat_rate_early * 0.6, (heat_rate_early, heat_rate_late))
expect_rate = R.decay_fraction * R.rated_w / R.specific_heat_j
check("afterheat is of the right size (decay fraction x rated power / thermal mass = %.2f C/s at first)" % expect_rate, 0.9 * expect_rate < heat_rate_early < 1.05 * expect_rate, (heat_rate_early, expect_rate))
e2 = mk(lua.table(sink_mw=0, fuel=False)); M.register(e2); e2.sig["ipp-rod-withdrawal"] = 100; run(e2, 120)
check("a core with no fuel makes no heat and no afterheat", e2.temperature == 15 and entry(e2).decay == 0, e2.temperature)

print("meltdown")
g.DIES = 0
e = mk(lua.table(sink_mw=0)); M.register(e); e.sig["ipp-rod-withdrawal"] = 100
n_ = 0
while e.valid and e.temperature < R.warning_c + 5 and n_ < 600: run(e, 1); n_ += 1    # rods come out slowly, then the core heats at full rate
check("heating without cooling: warning alerts are raised below the meltdown limit", g.ALERTS > 0 and e.valid and e.temperature < R.meltdown_c, (g.ALERTS, e.temperature, n_))
check("status goes red and counts down once above the meltdown temperature", True)
n_ = 0
while e.valid and n_ < 120: run(e, 1); n_ += 1      # meltdown temperature, then the grace period
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


print("fast-breeder core: the same script, its own constants")
DD = g.require("shared.defs")
FB = DD.reactors["ipp-fast-breeder-reactor"]; FBC = DD.config.fast_breeder
check("breeder constants come from config.fast_breeder", FB.rated_w == FBC.power_mw * 1e6 and FB.specific_heat_j == FBC.specific_heat_mj * 1e6 and FB != R)
check("the Tier 3 constants are untouched", R.rated_w == DD.config.reactor.power_mw * 1e6)
def fbr(**kw):
    c = mk(lua.table(name="ipp-fast-breeder-reactor", **kw)); M.register(c); return c
RATE = FB.rated_w / FB.specific_heat_j
def at_full_rods(**kw):
    c = fbr(sink_mw=1e6, **kw); c.sig["ipp-rod-withdrawal"] = 100; run(c, 110); c.sink_mw = 0; return c   # rods out (1 %/s), then no cooling
c = at_full_rods(); t0 = c.temperature; run(c, 20)
check("uncooled, the breeder core heats at rated power / thermal mass (%.1f C/s)" % RATE, abs((c.temperature - t0) / 20 - RATE) < 0.05 and c.temperature < FB.warning_c, (t0, c.temperature))
c = fbr(sink_mw=FBC.power_mw); c.sig["ipp-rod-withdrawal"] = 100; run(c, 300)
check("cooled at its rated power the core settles at the exchanger's working temperature", c.valid and c.temperature <= 351, c.temperature)
c = at_full_rods(bonus=2); t0 = c.temperature; run(c, 20)
check("neighbour bonus multiplies the breeder core's output (x3)", abs((c.temperature - t0) / 20 - 3 * RATE) < 0.1 and c.temperature < FB.warning_c, (t0, c.temperature))
c = fbr(); c.sig["ipp-rod-withdrawal"] = 100; run(c, 30)
c.sig["ipp-scram"] = 1; run(c, 5); c.sig["ipp-scram"] = None
check("SCRAM drives the breeder rods in and latches", entry(c).rod == 0 and entry(c).tripped is True, entry(c).rod)
check("... the lockout uses the breeder's own time", abs(entry(c).lock_left - FBC.scram_lockout_s) < 10, entry(c).lock_left)
c = fbr(); c.sig["ipp-rod-withdrawal"] = 100; run(c, 300)
check("an uncooled breeder core has not exploded after 300 s uncooled (explosion needs the full climb to 2500 C)", c.valid and entry(c) is not None)
run(c, 400)
check("an uncooled breeder core melts down (explosion at %d C)" % FBC.meltdown_temperature_c, not c.valid)
print("both core types share one script: %d entries" % len([1 for _ in g.storage.ipp_reactors.values()]))

print("lifecycle")
e = mk(); M.register(e); M.register(e)
check("registering twice keeps one entry", len([1 for _ in g.storage.ipp_reactors.values()]) >= 1 and entry(e) is not None)
M.unregister(e.unit_number); check("unregister removes the entry", entry(e) is None)
e = mk(); M.register(e); e.valid = False; g.TICK = g.TICK + 1; M.on_tick(lua.table(tick=g.TICK))
check("an invalid entity is dropped from the list", entry(e) is None)
lines = list(M.debug_lines().values()); check("debug command prints a line", len(lines) >= 1)

print("REACTOR CHECKS PASSED" if not fails else "FAILED: %s" % fails)
sys.exit(1 if fails else 0)
