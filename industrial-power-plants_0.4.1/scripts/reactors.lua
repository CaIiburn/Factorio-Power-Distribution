-- Pressurized-water reactor core: control rods, decay heat and meltdown.
--
-- The core is a vanilla `reactor` prototype, so its heat buffer, temperature, neighbour bonus and the heat taken
-- away by the primary circulation units are all native. This script adds three things:
--
--   1. CONTROL RODS. Every CTRL_TICKS the core reads two virtual signals from its circuit connector (red + green):
--        ipp-rod-withdrawal  0..100 %  how far the rods are pulled out (0 = fully in = no fission)
--        ipp-scram           non-zero  drop the rods at scram speed
--      A core with no wire attached SCRAMs by itself (fail-safe). The real rod position moves toward the
--      setpoint at a limited speed. Fission power = (position/100)^rod_exponent x rated power x (1 + neighbour
--      bonus). Native consumption cannot be changed at runtime, so the core is switched off and on every tick in
--      exactly that proportion (`disabled_by_script`, error-diffusion accumulator): average fuel burn and heat
--      follow the rods.
--   2. DECAY HEAT. After power falls, afterheat (a fraction of the earlier power) keeps heating the core and dies
--      away slowly, so the primary loop must keep running after a shutdown.
--   3. MELTDOWN. If the core makes more heat than the steam side removes, its native temperature climbs. At or
--      above meltdown_temperature_c for meltdown_grace_s (or at the maximum at once) the core is killed; the vanilla
--      meltdown_action then produces the standard reactor explosion (it fires above 90 % of max temperature).
local defs = require("shared.defs")
local R = defs.reactor

local M = {}
local CTRL_TICKS  = 6            -- control update period per core (staggered by unit number)
local ALERT_TICKS = 60           -- alert refresh period while overheating
local DT          = CTRL_TICKS / 60
local EPS         = 1e-9

local ROD   = { type = "virtual", name = defs.SIGNAL_ROD }
local SCRAM = { type = "virtual", name = defs.SIGNAL_SCRAM }

local function reactors()
  storage.ipp_reactors = storage.ipp_reactors or {}
  return storage.ipp_reactors
end

local function clamp(v, lo, hi)
  if v < lo then return lo elseif v > hi then return hi end
  return v
end

local function f0(v) return string.format("%.0f", v) end
local function f2(v) return string.format("%.2f", v) end

-- What the circuit network tells the core: setpoint (0..100), scram (bool), wired (bool).
-- No wire at all counts as a SCRAM (fail-safe); so does an error reading the connector.
function M.read_signals(e)
  local red, green = defines.wire_connector_id.circuit_red, defines.wire_connector_id.circuit_green
  local ok, wired = pcall(function()
    return e.get_circuit_network(red) ~= nil or e.get_circuit_network(green) ~= nil
  end)
  if not ok or not wired then return 0, true, false end
  local ok2, set, scram = pcall(function()
    return e.get_signal(ROD, red, green), e.get_signal(SCRAM, red, green)
  end)
  if not ok2 then return 0, true, false end
  return clamp(set or 0, 0, 100), (scram or 0) ~= 0, true
end

local function has_fuel(e)
  local b = e.burner
  if not b then return false end
  if b.currently_burning then return true end
  local inv = b.inventory
  return inv ~= nil and not inv.is_empty()
end

local function neighbour_multiplier(e)
  return 1 + (e.neighbour_bonus or 0)
end

local function set_status(entry, fueled)
  local e = entry.entity
  local diode = defines.entity_status_diode
  local T = entry.temp or 0
  local mult = neighbour_multiplier(e)
  local fuel_label = fueled and { "ipp.reactor-fuel-yes" } or { "ipp.reactor-fuel-no" }
  local color, label
  if T >= R.meltdown_c then
    color = diode.red
    label = { "ipp.reactor-status-critical", f0(T), f0(math.max(0, R.grace_s - entry.hot_ticks / 60)) }
  elseif entry.scram then
    color = diode.yellow
    label = { entry.wired and "ipp.reactor-status-scram" or "ipp.reactor-status-unwired", f0(entry.rod), f0(T), f2(mult), fuel_label }
  else
    color = (T >= R.warning_c) and diode.yellow or diode.green
    label = { "ipp.reactor-status", f0(entry.rod), f0(entry.setpoint), f0(T), f2(mult), fuel_label }
  end
  e.custom_status = { diode = color, label = label }
end

local function alert(e)
  for _, player in pairs(e.force.players) do
    player.add_custom_alert(e, SCRAM, { "ipp.reactor-alert-hot", f0(e.temperature or 0) }, true)
  end
end

function M.meltdown(entry)
  local e = entry.entity
  local force, tag = e.force, e.gps_tag
  reactors()[e.unit_number] = nil
  force.print({ "ipp.reactor-meltdown", tag }, { color = { 1, 0.3, 0.2 } })
  e.die()      -- vanilla meltdown_action: the standard reactor explosion (core is above 90 % of max temperature)
end

-- One control step (every CTRL_TICKS): read signals, move the rods, add afterheat, watch the temperature.
function M.control(entry, tick)
  local e = entry.entity
  local set, scram, wired = M.read_signals(e)
  entry.wired, entry.scram = wired, scram
  local target = scram and 0 or set
  entry.setpoint = target

  -- rod drive: limited speed; dropping because of a SCRAM (or cut wires) uses the fast scram speed
  local step = (scram and R.scram_speed or R.rod_speed) * DT
  if entry.rod < target then
    entry.rod = math.min(target, entry.rod + R.rod_speed * DT)
  elseif entry.rod > target then
    entry.rod = math.max(target, entry.rod - step)
  end
  entry.duty = (entry.rod / 100) ^ R.rod_exponent

  -- decay heat: builds up while the core runs on fuel, dies away slowly; only what exceeds the fission power
  -- that is already being produced is added (no double counting)
  local fueled = has_fuel(e)
  local target_decay = fueled and (R.decay_fraction * entry.duty) or 0
  local tau = (target_decay > entry.decay) and R.decay_rise_s or R.decay_fall_s
  entry.decay = entry.decay + (target_decay - entry.decay) * (1 - math.exp(-DT / tau))
  local residual = entry.decay - R.decay_fraction * entry.duty
  local T = e.temperature or 0
  if residual > 1e-4 then
    T = math.min(R.max_c, T + residual * R.rated_w * neighbour_multiplier(e) * DT / R.specific_heat_j)
    e.temperature = T
  end
  entry.temp = T

  -- meltdown: more heat made than carried away
  if T >= R.meltdown_c then
    entry.hot_ticks = entry.hot_ticks + CTRL_TICKS
    if entry.hot_ticks >= R.grace_s * 60 or T >= R.max_c - 0.5 then
      return M.meltdown(entry)
    end
  else
    entry.hot_ticks = 0
  end
  if T >= R.warning_c and (tick + entry.offset) % ALERT_TICKS < CTRL_TICKS then alert(e) end
  set_status(entry, fueled)
end

-- Error-diffusion duty cycle, every tick: the core works in `duty` of all ticks, evenly spread.
function M.pwm(entry)
  local acc = entry.acc + entry.duty
  local on = acc >= 1 - EPS
  if on then acc = math.max(0, acc - 1) end
  entry.acc = acc
  if on ~= entry.on then
    entry.on = on
    entry.entity.disabled_by_script = not on
  end
end

function M.on_tick(event)
  local list = reactors()
  if next(list) == nil then return end
  local tick = event.tick
  for unit, entry in pairs(list) do
    if not entry.entity.valid then
      list[unit] = nil
    else
      if (tick + entry.offset) % CTRL_TICKS == 0 then M.control(entry, tick) end
      if list[unit] then M.pwm(entry) end   -- the control step may have destroyed the core
    end
  end
end

-- A new (or cloned, or revived) core starts with its rods fully inserted.
function M.register(e)
  if not (e and e.valid and e.name == defs.REACTOR and e.unit_number) then return end
  local list = reactors()
  local entry = list[e.unit_number]
  if entry then entry.entity = e; return end
  entry = {
    entity = e, rod = 0, setpoint = 0, duty = 0, acc = 0, decay = 0, hot_ticks = 0,
    offset = e.unit_number % CTRL_TICKS, temp = e.temperature or 0, scram = true, wired = false, on = false,
  }
  list[e.unit_number] = entry
  e.disabled_by_script = true
  set_status(entry, false)
end

function M.unregister(unit)
  reactors()[unit] = nil
end

function M.rescan()
  for _, surface in pairs(game.surfaces) do
    for _, e in pairs(surface.find_entities_filtered { name = defs.REACTOR }) do M.register(e) end
  end
end

-- Lines for /ipp-reactor-debug: everything needed to check the assumptions made about the engine.
function M.debug_lines()
  local lines = {}
  for _, entry in pairs(reactors()) do
    local e = entry.entity
    if e.valid then
      lines[#lines + 1] = string.format(
        "%s  rods %.1f%% (set %.0f%%)  duty %.3f  T %.1f C  neighbour_bonus %s  decay %.4f  active %s  wired %s  scram %s  fuel %s",
        e.gps_tag, entry.rod, entry.setpoint, entry.duty, e.temperature or -1, tostring(e.neighbour_bonus),
        entry.decay, tostring(e.active), tostring(entry.wired), tostring(entry.scram), tostring(has_fuel(e)))
    end
  end
  if #lines == 0 then lines[1] = "no pressurized-water reactor cores" end
  return lines
end

function M.register_events()
  local filters = { { filter = "name", name = defs.REACTOR } }
  local ev = defines.events
  -- Event filters can only be attached when registering ONE event at a time (not an array).
  local function on(events, handler)
    for _, id in ipairs(events) do script.on_event(id, handler, filters) end
  end
  on({ ev.on_built_entity, ev.on_robot_built_entity, ev.on_space_platform_built_entity,
       ev.script_raised_built, ev.script_raised_revive },
    function(e) M.register(e.entity) end)
  on({ ev.on_entity_cloned }, function(e) M.register(e.destination) end)
  on({ ev.on_player_mined_entity, ev.on_robot_mined_entity, ev.on_space_platform_mined_entity,
       ev.on_entity_died, ev.script_raised_destroy },
    function(e) if e.entity and e.entity.unit_number then M.unregister(e.entity.unit_number) end end)
  script.on_event(ev.on_tick, M.on_tick)
end

return M
