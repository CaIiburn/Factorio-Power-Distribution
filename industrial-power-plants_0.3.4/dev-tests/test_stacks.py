# Mock-world test of scripts/stacks.lua: automatic recipe choice, refusals, rotation, research gating.
import sys
from lupa import LuaRuntime
MOD = "/home/claude/ipp/industrial-power-plants_0.3.4"
lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(r'''
package.path = "@MOD@/?.lua;" .. package.path
defines = { direction = {north=0, east=4, south=8, west=12}, entity_status_diode = {green="green", yellow="yellow", red="red"},
            events = setmetatable({}, {__index = function(t,k) return k end}) }
storage = {}
prototypes = { fluid = setmetatable({}, {__index = function(t,k) return {localised_name = "LN:" .. k} end}) }
ENABLED = { ["ipp-vent-exhaust-steam"] = true, ["ipp-vent-flue-gas"] = true, ["ipp-vent-hot-exhaust"] = false }
FORCE = { recipes = setmetatable({}, {__index = function(t,k) return { enabled = ENABLED[k] } end}) }
SURF = { ents = {} }
function SURF.find_entities_filtered(f)
  local out = {}
  for _, e in ipairs(SURF.ents) do
    if f.position then local dx, dy = e.position.x - f.position.x, e.position.y - f.position.y
      if dx*dx + dy*dy <= f.radius*f.radius then out[#out+1] = e end
    elseif f.name == e.name then out[#out+1] = e end
  end
  return out
end
SETS = 0
function mk_stack(x, y, dir)
  local s = { name = "ipp-exhaust-stack", valid = true, unit_number = 1, position = {x=x, y=y}, direction = dir, surface = SURF, force = FORCE, type = "assembling-machine" }
  function s.get_recipe() return s.recipe and { name = s.recipe } or nil end
  function s.set_recipe(r) s.recipe = r; SETS = SETS + 1 end
  return s
end
function mk_pipe(x, y, contents) local p = { name = "pipe", type = "pipe", valid = true, position = {x=x, y=y}, contents = contents }
  function p.get_fluid_contents() return p.contents end; table.insert(SURF.ents, p); return p end
REG = {}
script = {
  on_event = function(id, fn, filters)
    if filters ~= nil and type(id) == "table" then error("Filters can only be used when registering single non custom-input events.") end
    REG[#REG+1] = { id = id, filters = filters, fn = fn }
  end,
  on_nth_tick = function(n, fn) REG[#REG+1] = { nth = n, fn = fn } end,
}
S = require("scripts.stacks")
''' .replace('@MOD@', MOD))
g = lua.globals()
fails = []
def check(cond, msg):
    print(("  ok   " if cond else "  FAIL ") + msg)
    if not cond: fails.append(msg)
def setup(direction=0, px=0, py=-2, contents=None):
    lua.execute("SURF.ents = {}; SETS = 0")
    st = g.mk_stack(10, 10, direction)
    pipe = g.mk_pipe(10 + px, 10 + py, lua.table_from(contents or {}))
    g.table.insert(g.SURF.ents, st)
    return st, pipe
def poll(st): g.S.update(st)

print("exhaust steam arrives")
st, pipe = setup(contents={"ipp-exhaust-steam": 100.0})
poll(st); check(st.recipe == "ipp-vent-exhaust-steam", "recipe auto-set to steam vent"); check(st.custom_status.diode == "green", "status green")
print("same fluid again: no churn")
n = g.SETS; poll(st); check(g.SETS == n, "recipe not re-set")
print("pipe now carries flue gas")
pipe.contents = lua.table_from({"ipp-flue-gas": 50.0}); poll(st); check(st.recipe == "ipp-vent-flue-gas", "switched to flue gas vent")
print("pipe empties: keep recipe")
pipe.contents = lua.table_from({}); poll(st); check(st.recipe == "ipp-vent-flue-gas", "recipe kept while pipe empty")
print("denied fluids")
for fluid, reason in (("ipp-industrial-steam", "valuable"), ("ipp-fuel-gas", "fuel"), ("sulfuric-acid", "hazard"), ("water", "valuable"), ("some-mod-fluid", "unlisted")):
    pipe.contents = lua.table_from({fluid: 10.0}); poll(st)
    lbl = st.custom_status.label
    check(st.recipe is None and st.custom_status.diode == "red" and lbl[3][1] == "ipp.vent-denied-" + reason, "%s refused (%s), recipe cleared" % (fluid, reason))
print("mixed pipe: ventable wins over denied")
pipe.contents = lua.table_from({"water": 500.0, "ipp-flue-gas": 20.0}); poll(st); check(st.recipe == "ipp-vent-flue-gas", "flue gas picked from mixed contents")
print("research gating")
pipe.contents = lua.table_from({"ipp-hot-exhaust": 30.0}); poll(st)
check(st.recipe is None and st.custom_status.diode == "yellow" and st.custom_status.label[1] == "ipp.status-research", "hot exhaust waits for research")
g.ENABLED["ipp-vent-hot-exhaust"] = True; poll(st); check(st.recipe == "ipp-vent-hot-exhaust", "recipe set after research")
print("no pipe at all")
st2, _ = setup(contents={}); lua.execute("SURF.ents = {}"); poll(st2); check(st2.recipe is None and st2.custom_status.label[1] == "ipp.status-waiting", "waiting status")
print("rotation: inlet follows direction")
for d, (px, py) in {4: (2, 0), 8: (0, 2), 12: (-2, 0)}.items():
    st3, _ = setup(direction=d, px=px, py=py, contents={"ipp-exhaust-steam": 5.0}); poll(st3)
    check(st3.recipe == "ipp-vent-exhaust-steam", "direction %d inlet found at (%d,%d)" % (d, px, py))
print("pipe on the wrong side is ignored")
st4, _ = setup(direction=0, px=0, py=2, contents={"ipp-exhaust-steam": 5.0}); poll(st4); check(st4.recipe is None, "outlet side not read")
print("vent list lines")
lines = g.S.vent_list_lines(); check(len(lines) >= 10, "list has %d lines" % len(lines))
print("event registration (engine rules)")
try:
    g.S.register_events(); ids = [g.REG[i].id for i in range(1, len(g.REG)+1) if g.REG[i].id]
    check(True, "register_events ran with strict filter rule, %d registrations" % len(g.REG))
    needed = {"on_built_entity","on_robot_built_entity","on_space_platform_built_entity","script_raised_built","script_raised_revive","on_entity_cloned","on_player_mined_entity","on_robot_mined_entity","on_space_platform_mined_entity","on_entity_died","script_raised_destroy","on_research_finished"}
    check(needed <= set(ids), "all lifecycle events registered individually")
    lua.execute("""
      local n = 0
      for _, r in ipairs(REG) do if r.filters and #r.filters ~= 1 then n = n + 1 end end
      BAD_FILTERS = n""")
    check(g.BAD_FILTERS == 0, "every filtered registration has the stack-name filter")
except Exception as ex:
    check(False, "register_events raised: %s" % ex)
print("FAILURES" if fails else "STACK CHECKS PASSED")
sys.exit(1 if fails else 0)
