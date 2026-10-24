-- Circuit output: pt-load (% of rated), pt-power (kW), pt-temperature (heat tiers). A constant
-- combinator is only written when a quantised value changed, so a steady load costs nothing.
local Common = require("__pylon-transformers__.scripts.transformer.common")

local C = Common.C

-- Signal ids, created once. The engine copies them on every write.
local SIG_LOAD = { type = "virtual", name = C.signal.load, quality = "normal" }
local SIG_POWER = { type = "virtual", name = C.signal.power, quality = "normal" }
local SIG_TEMPERATURE = { type = "virtual", name = C.signal.temperature, quality = "normal" }

-- Called only when a quantised value changed. temp_c is nil for tiers without temperature.
local function write_signals(rec, load_pct, power_kw, temp_c)
  local cb = rec.shell.get_control_behavior()
  if not cb then return false end
  local section = cb.get_section(1) or cb.add_section()
  if not section then return false end

  local filters = {
    { value = SIG_LOAD,  min = load_pct },
    { value = SIG_POWER, min = power_kw },
  }
  if temp_c then
    filters[3] = { value = SIG_TEMPERATURE, min = temp_c }
  end
  section.filters = filters
  return true
end

local Circuit = {}

-- Removes every signal section (e.g. ones pasted from a blueprint) and forgets what was written,
-- so the next publish writes a correct state. Also locks the GUI: the script owns the signals.
function Circuit.init(rec)
  local shell = rec.shell
  shell.operable = false
  local cb = shell.get_control_behavior()
  if cb then
    for i = cb.sections_count, 1, -1 do cb.remove_section(i) end
  end
  rec.s_load, rec.s_power, rec.s_temp = nil, nil, nil
end

-- Writes the signals if any of the three values differs from what was written last.
function Circuit.publish(rec, load_pct, power_kw, temp_c)
  if load_pct == rec.s_load and power_kw == rec.s_power and temp_c == rec.s_temp then return end
  if write_signals(rec, load_pct, power_kw, temp_c) then
    rec.s_load, rec.s_power, rec.s_temp = load_pct, power_kw, temp_c
  end
end

return Circuit
