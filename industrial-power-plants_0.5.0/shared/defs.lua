-- Shared balance constants, derived from config.lua (the file to edit when tuning).
-- Pure data (no stage-specific globals).
--
-- Energy conventions (see docs/ENERGY_ACCOUNTING.md):
--   * Industrial steam and pressurised fuel gas are consumed by the turbines as FUEL: every generator uses
--     burns_fluid = true, so output = units x fuel_value x effectivity and never depends on fluid temperature.
--     (A temperature-based generator needs steam at a specific temperature, which locks fluid boxes and
--     blocks pipe connections under 2.1's fluid-mixing rules - do not stamp temperatures on recipes.)
local C = require("config")
local D = { config = C }

D.STEAM_KJ    = C.fluids.industrial_steam_kj
D.FUEL_GAS_MJ = C.fluids.fuel_gas_mj
D.HP_STEAM_KJ = C.fluids.hp_steam_kj
D.SCO2_HOT_MJ = C.fluids.sco2_hot_mj
D.SCO2_PREHEAT_MJ = C.fluids.sco2_recuperated_mj

-- Prototype / signal names shared by the data and control stages.
D.REACTOR       = "ipp-pwr-reactor-core"
D.FBR           = "ipp-fast-breeder-reactor"      -- Tier 4 core (same rods / SCRAM script as D.REACTOR)
D.CHANNEL       = "ipp-blanket-channel"
D.HEATER        = "ipp-sodium-co2-heater"
D.SIGNAL_ROD    = "ipp-rod-withdrawal"
D.SIGNAL_SCRAM  = "ipp-scram"

-- Short number format for locale parameters: 22.16 -> "22.2", 450 -> "450".
function D.fmt(n)
  local s = string.format("%.1f", n)
  return (s:gsub("%.0$", ""))
end

local function positive(v, path)
  if type(v) ~= "number" or v <= 0 then
    error("industrial-power-plants config.lua: " .. path .. " must be a number above 0 (got " .. tostring(v) .. ")")
  end
  return v
end

-- Native turbine-generators (fusion-generator prototype).
--   per_second  : fluid units consumed per second at full load (= max_fluid_usage x 60)
--   effectivity : fraction of the input fluid's energy delivered as electricity
--   power_mw    : full-load electric output
--   flow_mw     : electric output limit (config value, or full-load output rounded up to 0.1 MW)
--   scale       : footprint multiplier on the vanilla fusion generator (config size_multiplier; whole number)
local function whole(v, min, path, odd)
  if type(v) ~= "number" or v ~= math.floor(v) or v < min or (odd and v % 2 == 0) then
    error("industrial-power-plants config.lua: " .. path .. " must be a whole " .. (odd and "odd " or "")
          .. "number >= " .. min .. " (got " .. tostring(v) .. ")")
  end
  return v
end

local function generator(key, input, output, unit_mj, tint, order)
  local t = C.turbines[key]
  local path = "turbines." .. key
  positive(t.fluid_per_second, path .. ".fluid_per_second")
  positive(t.effectivity, path .. ".effectivity")
  if t.effectivity > 1 then
    error("industrial-power-plants config.lua: " .. path .. ".effectivity may not exceed 1 (got " .. t.effectivity .. ")")
  end
  local power = t.fluid_per_second * unit_mj * t.effectivity
  local flow = t.output_limit_mw
  if flow == nil then flow = math.ceil(power * 10 - 1e-9) / 10 end
  positive(flow, path .. ".output_limit_mw")
  local scale = whole(t.size_multiplier, 1, path .. ".size_multiplier")
  return {
    input = input, output = output,
    per_second = t.fluid_per_second, effectivity = t.effectivity, burns = true,
    power_mw = power, flow_mw = flow, health = t.health or 1800,
    scale = scale, tint = tint, order = order,
  }
end

D.generators = {
  ["ipp-large-steam-turbine-generator"] = generator("large_steam", "ipp-industrial-steam", "ipp-exhaust-steam",
    D.STEAM_KJ / 1000, { r = 0.55, g = 0.65, b = 0.95 }, "j"),
  ["ipp-hp-turbine-generator"] = generator("hp", "ipp-hp-steam", "ipp-exhaust-steam",
    D.HP_STEAM_KJ / 1000, { r = 0.70, g = 0.80, b = 1.00 }, "l"),
  ["ipp-gas-turbine-generator"] = generator("gas", "ipp-fuel-gas", "ipp-hot-exhaust",
    D.FUEL_GAS_MJ, { r = 0.80, g = 0.90, b = 0.70 }, "h"),
  -- Tier 4: burns hot supercritical CO2 as fuel (like every other turbine here), returns turbine exhaust CO2
  ["ipp-sco2-turbine-generator"] = generator("sco2", "ipp-sco2-hot", "ipp-sco2-exhaust",
    C.fluids.sco2_hot_mj, { r = 1.00, g = 0.85, b = 0.65 }, "n"),
}

-- Validate every other number once, so a typo fails at load time with the key name.
local function check(tname, keys)
  for _, k in ipairs(keys) do positive(C[tname][k], tname .. "." .. k) end
end
positive(D.STEAM_KJ, "fluids.industrial_steam_kj")
positive(D.FUEL_GAS_MJ, "fluids.fuel_gas_mj")
check("conditioner", { "petroleum_gas_per_second", "fuel_gas_per_second", "power_mw", "idle_drain_kw", "health" })
check("heat_recovery", { "hot_exhaust_per_second", "water_per_second", "steam_per_second",
  "flue_gas_per_second", "power_kw", "idle_drain_kw", "health" })
check("condenser", { "exhaust_steam_per_second", "water_per_second", "power_kw", "idle_drain_kw", "health" })
check("startup_bank", { "capacity_mj", "charge_mw", "discharge_mw", "health" })
whole(C.conditioner.size, 1, "conditioner.size", true)
whole(C.heat_recovery.size, 3, "heat_recovery.size", true)   -- two ports per face at -1 / +1
whole(C.condenser.size, 1, "condenser.size", true)
whole(C.stack.size, 1, "stack.size", true)
whole(C.startup_bank.size, 1, "startup_bank.size")
for k, v in pairs(C.stack.vent_per_second) do positive(v, "stack.vent_per_second." .. k) end
for k, v in pairs(C.research) do positive(v.count, "research." .. k .. ".count"); positive(v.time, "research." .. k .. ".time") end


-- ---- Tier 3 ----
positive(D.HP_STEAM_KJ, "fluids.hp_steam_kj")
do
  local fa, rc, pu = C.fuel_assembly, C.reactor, C.primary_unit
  positive(fa.energy_gj, "fuel_assembly.energy_gj"); whole(fa.cells, 1, "fuel_assembly.cells"); whole(fa.claddings, 1, "fuel_assembly.claddings")
  for _, k in ipairs { "power_mw", "specific_heat_mj", "max_temperature_c", "health", "rod_speed_pct_per_second",
      "scram_speed_pct_per_second", "rod_exponent", "decay_rise_s", "decay_fall_s", "warning_temperature_c",
      "meltdown_temperature_c", "meltdown_grace_s" } do positive(rc[k], "reactor." .. k) end
  whole(rc.fuel_slots, 1, "reactor.fuel_slots"); whole(rc.spent_slots, 1, "reactor.spent_slots")
  if type(rc.scram_lockout_s) ~= "number" or rc.scram_lockout_s < 0 then
    error("industrial-power-plants config.lua: reactor.scram_lockout_s must be a number >= 0 (got " .. tostring(rc.scram_lockout_s) .. ")")
  end
  if type(rc.neighbour_bonus) ~= "number" or rc.neighbour_bonus < 0 then
    error("industrial-power-plants config.lua: reactor.neighbour_bonus must be a number >= 0 (got " .. tostring(rc.neighbour_bonus) .. ")")
  end
  if type(rc.decay_fraction) ~= "number" or rc.decay_fraction < 0 or rc.decay_fraction > 1 then
    error("industrial-power-plants config.lua: reactor.decay_fraction must be between 0 and 1 (got " .. tostring(rc.decay_fraction) .. ")")
  end
  if rc.rod_speed_pct_per_second > rc.scram_speed_pct_per_second then
    error("industrial-power-plants config.lua: reactor.scram_speed_pct_per_second must not be below rod_speed_pct_per_second")
  end
  if not (rc.warning_temperature_c < rc.meltdown_temperature_c and rc.meltdown_temperature_c <= rc.max_temperature_c) then
    error("industrial-power-plants config.lua: reactor temperatures must satisfy warning < meltdown <= max")
  end
  -- The vanilla meltdown explosion only fires when the core dies ABOVE 90 % of its maximum temperature.
  if rc.meltdown_temperature_c <= 0.9 * rc.max_temperature_c then
    error("industrial-power-plants config.lua: reactor.meltdown_temperature_c must be above 90 % of max_temperature_c (the explosion only happens above that)")
  end
  check("primary_unit", { "power_mw", "target_c", "min_working_c", "hot_fluid_max_c", "health" })
  if pu.target_c <= 15 then error("industrial-power-plants config.lua: primary_unit.target_c must be above 15 degC") end
  if pu.hot_fluid_max_c < pu.target_c then error("industrial-power-plants config.lua: primary_unit.hot_fluid_max_c must be >= target_c") end
end
check("steam_generator", { "hot_primary_per_second", "cool_primary_per_second", "water_per_second", "steam_per_second",
  "power_mw", "idle_drain_kw", "health" })
check("surface_condenser", { "exhaust_steam_per_second", "cooling_water_per_second", "water_per_second", "power_kw", "idle_drain_kw", "health" })
check("cooling_tower", { "warm_per_second", "makeup_per_second", "power_kw", "idle_drain_kw", "health" })
check("dry_cooler", { "warm_per_second", "power_mw", "idle_drain_kw", "health" })
check("water_treatment", { "primary_per_second", "secondary_per_second", "cooling_per_second", "power_kw", "idle_drain_kw", "health" })
check("spent_fuel_pool", { "cooling_time_s", "water_per_assembly", "power_kw", "idle_drain_kw", "health" })
check("dry_cask", { "inventory_slots", "health" })
check("reprocessing", { "time_s", "acid", "solvent", "uranium_238", "uranium_235", "plutonium", "residue", "power_mw", "idle_drain_kw", "health" })
check("vitrifier", { "time_s", "residue", "frit", "power_mw", "idle_drain_kw", "health" })
if C.reprocessing.uranium_235_chance <= 0 or C.reprocessing.uranium_235_chance > 1 then
  error("industrial-power-plants config.lua: reprocessing.uranium_235_chance must be above 0 and at most 1")
end
whole(C.steam_generator.size, 3, "steam_generator.size", true)
whole(C.surface_condenser.size, 3, "surface_condenser.size", true)
whole(C.cooling_tower.size, 3, "cooling_tower.size", true)
whole(C.dry_cooler.size, 3, "dry_cooler.size", true)
whole(C.water_treatment.size, 2, "water_treatment.size")   -- any whole size: odd = port on the centre tile, even = half a tile left of it
whole(C.spent_fuel_pool.size, 3, "spent_fuel_pool.size", true)
whole(C.dry_cask.size, 1, "dry_cask.size")
whole(C.dry_cask.inventory_slots, 1, "dry_cask.inventory_slots")
whole(C.reprocessing.size, 3, "reprocessing.size", true)
whole(C.vitrifier.size, 3, "vitrifier.size", true)

-- ---- Tier 4 ----
do
  local fb, su = C.fast_breeder, C.sodium_unit
  for _, k in ipairs { "power_mw", "specific_heat_mj", "max_temperature_c", "health", "rod_speed_pct_per_second",
      "scram_speed_pct_per_second", "rod_exponent", "decay_rise_s", "decay_fall_s", "warning_temperature_c",
      "meltdown_temperature_c", "meltdown_grace_s" } do positive(fb[k], "fast_breeder." .. k) end
  whole(fb.fuel_slots, 1, "fast_breeder.fuel_slots"); whole(fb.spent_slots, 1, "fast_breeder.spent_slots")
  if type(fb.scram_lockout_s) ~= "number" or fb.scram_lockout_s < 0 then
    error("industrial-power-plants config.lua: fast_breeder.scram_lockout_s must be a number >= 0")
  end
  if type(fb.neighbour_bonus) ~= "number" or fb.neighbour_bonus < 0 then
    error("industrial-power-plants config.lua: fast_breeder.neighbour_bonus must be a number >= 0")
  end
  if type(fb.decay_fraction) ~= "number" or fb.decay_fraction < 0 or fb.decay_fraction > 1 then
    error("industrial-power-plants config.lua: fast_breeder.decay_fraction must be between 0 and 1")
  end
  if fb.rod_speed_pct_per_second > fb.scram_speed_pct_per_second then
    error("industrial-power-plants config.lua: fast_breeder.scram_speed_pct_per_second must not be below rod_speed_pct_per_second")
  end
  if not (fb.warning_temperature_c < fb.meltdown_temperature_c and fb.meltdown_temperature_c <= fb.max_temperature_c) then
    error("industrial-power-plants config.lua: fast_breeder temperatures must satisfy warning < meltdown <= max")
  end
  if fb.meltdown_temperature_c <= 0.9 * fb.max_temperature_c then
    error("industrial-power-plants config.lua: fast_breeder.meltdown_temperature_c must be above 90 % of max_temperature_c")
  end
  check("sodium_unit", { "power_mw", "target_c", "min_working_c", "hot_fluid_max_c", "health" })
  if su.target_c <= 15 then error("industrial-power-plants config.lua: sodium_unit.target_c must be above 15 degC") end
  if su.hot_fluid_max_c < su.target_c then error("industrial-power-plants config.lua: sodium_unit.hot_fluid_max_c must be >= target_c") end
end
check("heat_pipe_2", { "max_temperature_c", "health" })
check("sodium_exchanger", { "hot_primary_per_second", "cool_primary_per_second", "secondary_per_second", "power_mw", "idle_drain_kw", "health" })
check("co2_heater", { "sodium_per_second", "recuperated_co2_per_second", "direct_co2_per_second", "power_kw", "idle_drain_kw", "health" })
check("sco2_compressor", { "co2_per_second", "power_mw", "idle_drain_kw", "health" })
check("recuperator", { "co2_per_second", "power_kw", "idle_drain_kw", "health" })
check("sco2_cooler", { "exhaust_per_second", "power_mw", "idle_drain_kw", "health" })
check("hot_tank", { "capacity", "health" })
check("fuel_fabricator", { "power_mw", "idle_drain_kw", "health" })
check("blanket_channel", { "channel_time_s", "reach_tiles", "health" })
check("electrolyzer", { "time_s", "salt", "sodium", "chlorine", "power_mw", "idle_drain_kw", "health" })
for k, v in pairs(C.sodium_chemistry) do positive(v, "sodium_chemistry." .. k) end
for _, k in ipairs { "mox", "starter", "blanket", "core_reprocessing", "blanket_reprocessing" } do
  for kk, v in pairs(C.breeder_fuel[k]) do positive(v, "breeder_fuel." .. k .. "." .. kk) end
end
positive(C.breeder_fuel.gj_per_fissile, "breeder_fuel.gj_per_fissile"); positive(C.breeder_fuel.fabrication_time_s, "breeder_fuel.fabrication_time_s")
positive(C.fluids.sco2_hot_mj, "fluids.sco2_hot_mj"); positive(C.fluids.sco2_recuperated_mj, "fluids.sco2_recuperated_mj")
if C.fluids.sco2_recuperated_mj >= C.fluids.sco2_hot_mj then
  error("industrial-power-plants config.lua: fluids.sco2_recuperated_mj must be below sco2_hot_mj (the heater has to add something)")
end
whole(C.sodium_exchanger.size, 3, "sodium_exchanger.size", true)
whole(C.co2_heater.size, 3, "co2_heater.size", true)
whole(C.sco2_compressor.size, 1, "sco2_compressor.size", true)
whole(C.recuperator.size, 3, "recuperator.size", true)
whole(C.sco2_cooler.size, 1, "sco2_cooler.size", true)
whole(C.fuel_fabricator.size, 3, "fuel_fabricator.size", true)
whole(C.blanket_channel.size, 1, "blanket_channel.size", true)
whole(C.electrolyzer.size, 3, "electrolyzer.size", true)

-- Derived Tier 4 numbers.
D.SODIUM_UNIT_KJ = C.sodium_unit.target_c - 15                              -- kJ per unit of hot primary / secondary sodium
D.SODIUM_FLOW    = C.sodium_unit.power_mw * 1000 / D.SODIUM_UNIT_KJ         -- units/s one circulation unit moves at full power
local bf = C.breeder_fuel
D.breeder = {
  rated_w        = C.fast_breeder.power_mw * 1e6,
  channel_time_s = C.blanket_channel.channel_time_s,
  irradiation_j  = bf.blanket.irradiation_gj * 1e9,
  reach          = C.blanket_channel.reach_tiles,
}
-- Fuel cycle numbers (all per assembly): energy, breeding ratio and the heavy-metal balance.
D.fuel = {
  mox_gj        = bf.mox.burnt_fissile * bf.gj_per_fissile,
  starter_gj    = bf.starter.burnt_fissile * bf.gj_per_fissile,
  blankets_per_mox = bf.mox.burnt_fissile * bf.gj_per_fissile / bf.blanket.irradiation_gj,
}
D.fuel.fissile_out = bf.core_reprocessing.pbm + D.fuel.blankets_per_mox * bf.blanket_reprocessing.pbm
D.fuel.breeding_ratio = (D.fuel.fissile_out - bf.mox.pbm + bf.mox.burnt_fissile) / bf.mox.burnt_fissile
D.fuel.core_only_ratio = (bf.core_reprocessing.pbm - bf.mox.pbm + bf.mox.burnt_fissile) / bf.mox.burnt_fissile

-- Derived primary-loop numbers: one unit of primary water carries 1 kJ per degC (heat capacity of both primary fluids).
D.PRIMARY_UNIT_KJ = C.primary_unit.target_c - 15                       -- kJ per unit of hot primary water
D.PRIMARY_FLOW    = C.primary_unit.power_mw * 1000 / D.PRIMARY_UNIT_KJ -- units/s one circulation unit moves at full power

-- Reactor constants for the control script (watts, seconds, degC). One table per core type; D.reactor is the Tier 3 core.
local function reactor_params(rc)
  return {
    rated_w         = rc.power_mw * 1e6,
    specific_heat_j = rc.specific_heat_mj * 1e6,
    neighbour_bonus = rc.neighbour_bonus,
    rod_speed       = rc.rod_speed_pct_per_second,
    scram_speed     = rc.scram_speed_pct_per_second,
    scram_lockout_s = rc.scram_lockout_s,
    rod_exponent    = rc.rod_exponent,
    decay_fraction  = rc.decay_fraction,
    decay_rise_s    = rc.decay_rise_s,
    decay_fall_s    = rc.decay_fall_s,
    warning_c       = rc.warning_temperature_c,
    meltdown_c      = rc.meltdown_temperature_c,
    grace_s         = rc.meltdown_grace_s,
    max_c           = rc.max_temperature_c,
  }
end
D.reactor = reactor_params(C.reactor)
D.reactors = { [D.REACTOR] = D.reactor, [D.FBR] = reactor_params(C.fast_breeder) }

-- Soft balance checks (data stage only: `log` does not exist in the control stage).
if log then
  local gas, large = D.generators["ipp-gas-turbine-generator"], D.generators["ipp-large-steam-turbine-generator"]
  local function warn(msg) log("industrial-power-plants config.lua: " .. msg) end
  if C.conditioner.fuel_gas_per_second ~= gas.per_second then
    warn("conditioner.fuel_gas_per_second (" .. C.conditioner.fuel_gas_per_second .. ") differs from the gas turbine intake (" .. gas.per_second .. ")")
  end
  if C.heat_recovery.hot_exhaust_per_second ~= gas.per_second then
    warn("heat_recovery.hot_exhaust_per_second differs from the gas turbine exhaust (" .. gas.per_second .. ")")
  end
  if C.heat_recovery.steam_per_second ~= large.per_second then
    warn("heat_recovery.steam_per_second differs from the large steam turbine intake (" .. large.per_second .. ")")
  end
  local steam_mj = C.heat_recovery.steam_per_second * D.STEAM_KJ / 1000
  local exhaust_heat = C.heat_recovery.hot_exhaust_per_second * D.FUEL_GAS_MJ - gas.power_mw * C.heat_recovery.hot_exhaust_per_second / gas.per_second
  if steam_mj > exhaust_heat + 1e-9 then
    warn(string.format("heat recovery makes %.1f MJ of steam per second but the hot exhaust only holds %.1f MJ (energy created from nothing)", steam_mj, exhaust_heat))
  end

  -- Tier 3 chain
  local hp = D.generators["ipp-hp-turbine-generator"]
  local sg, sc = C.steam_generator, C.surface_condenser
  if math.abs(D.PRIMARY_FLOW - sg.hot_primary_per_second) > 1e-6 then
    warn(string.format("primary circulation unit moves %.1f primary water/s at full power but the steam generator takes %s (steam_generator.hot_primary_per_second)", D.PRIMARY_FLOW, sg.hot_primary_per_second))
  end
  if sg.cool_primary_per_second ~= sg.hot_primary_per_second then
    warn("steam_generator.cool_primary_per_second differs from hot_primary_per_second (the primary loop is closed: it would gain or lose fluid)")
  end
  if sg.steam_per_second ~= hp.per_second then warn("steam_generator.steam_per_second differs from the high-pressure turbine intake (" .. hp.per_second .. ")") end
  if sc.exhaust_steam_per_second ~= hp.per_second then warn("surface_condenser.exhaust_steam_per_second differs from the high-pressure turbine exhaust (" .. hp.per_second .. ")") end
  if sc.water_per_second ~= sg.water_per_second then warn("surface_condenser.water_per_second differs from steam_generator.water_per_second (secondary loop would gain or lose water)") end
  local heat_in_mw = sg.hot_primary_per_second * D.PRIMARY_UNIT_KJ / 1000
  local steam_out_mw = sg.steam_per_second * D.HP_STEAM_KJ / 1000
  if steam_out_mw > heat_in_mw + 1e-9 then
    warn(string.format("steam generator makes %.1f MW of steam energy from only %.1f MW of primary heat (energy created from nothing)", steam_out_mw, heat_in_mw))
  end
  if math.abs(C.fuel_assembly.energy_gj - C.fuel_assembly.cells * 8) > 1e-9 then
    warn("fuel_assembly.energy_gj differs from cells x 8 GJ (the uranium fuel cells that go into the recipe)")
  end
  -- Tier 4 chain
  local tb = D.generators["ipp-sco2-turbine-generator"]
  local se, ch, cp, rc_, cl = C.sodium_exchanger, C.co2_heater, C.sco2_compressor, C.recuperator, C.sco2_cooler
  local fb = C.breeder_fuel
  if se.hot_primary_per_second ~= se.cool_primary_per_second then warn("sodium_exchanger: primary loop would gain or lose sodium (hot_primary != cool_primary)") end
  if ch.sodium_per_second ~= se.secondary_per_second then warn("co2_heater.sodium_per_second differs from sodium_exchanger.secondary_per_second (secondary loop would gain or lose sodium)") end
  if math.abs(se.hot_primary_per_second - 3 * D.SODIUM_FLOW) > 1e-6 and math.abs(se.hot_primary_per_second % D.SODIUM_FLOW) > 1e-6 then
    warn(string.format("sodium_exchanger takes %s hot primary sodium/s, not a whole number of circulation units (one moves %.1f/s)", se.hot_primary_per_second, D.SODIUM_FLOW))
  end
  if ch.recuperated_co2_per_second ~= tb.per_second then warn("co2_heater.recuperated_co2_per_second differs from the CO2 turbine intake (" .. tb.per_second .. ")") end
  for _, pair in ipairs { { "sco2_compressor.co2_per_second", cp.co2_per_second }, { "recuperator.co2_per_second", rc_.co2_per_second }, { "sco2_cooler.exhaust_per_second", cl.exhaust_per_second } } do
    if pair[2] ~= tb.per_second then warn(pair[1] .. " differs from the CO2 turbine flow (" .. tb.per_second .. ")") end
  end
  local heat_in = se.secondary_per_second * D.SODIUM_UNIT_KJ / 1000
  local heat_rec = ch.recuperated_co2_per_second * (D.SCO2_HOT_MJ - D.SCO2_PREHEAT_MJ)
  local heat_dir = ch.direct_co2_per_second * D.SCO2_HOT_MJ
  if heat_rec > heat_in + 1e-9 then warn(string.format("heater makes hot CO2 worth %.1f MW from %.1f MW of sodium heat (energy created from nothing)", heat_rec, heat_in)) end
  if heat_dir > heat_in + 1e-9 then warn(string.format("heater (direct feed) makes hot CO2 worth %.1f MW from %.1f MW of sodium heat", heat_dir, heat_in)) end
  if math.abs(heat_rec - heat_dir) > 1e-6 then warn("the heater's two recipes do not carry the same heat (recuperated " .. heat_rec .. " MW, direct " .. heat_dir .. " MW)") end
  local exhaust_heat = rc_.co2_per_second * (1 - tb.effectivity) * D.SCO2_HOT_MJ
  if rc_.co2_per_second * D.SCO2_PREHEAT_MJ > exhaust_heat + 1e-9 then
    warn(string.format("recuperator returns %.1f MW but the turbine exhaust only holds %.1f MW (energy created from nothing)", rc_.co2_per_second * D.SCO2_PREHEAT_MJ, exhaust_heat))
  end
  if C.heat_pipe_2.max_temperature_c >= C.fast_breeder.warning_temperature_c then
    warn("heat_pipe_2.max_temperature_c should stay below the breeder core's warning temperature")
  end
  if C.heat_pipe_2.max_temperature_c <= 1000 then warn("heat_pipe_2.max_temperature_c is not above the vanilla heat pipe (1000 degC)") end
  if D.fuel.breeding_ratio <= 1 or D.fuel.breeding_ratio > 1.5 then warn(string.format("breeding ratio is %.2f; the design wants it modestly above 1 (up to 1.5)", D.fuel.breeding_ratio)) end
  for _, k in ipairs { "core_reprocessing", "blanket_reprocessing" } do
    local out = fb[k].pbm + fb[k].du + fb[k].residue
    local inp = (k == "core_reprocessing") and (fb.mox.pbm + fb.mox.du) or fb.blanket.du
    if out > inp + 1e-9 then warn("breeder_fuel." .. k .. " returns more heavy metal than it was given (matter created)") end
  end
end

-- Exhaust stack venting list. Single source of truth: vent recipes are generated from `allowed`, the
-- stack script reads both tables, and docs/VENTING.md mirrors them. Rates come from config.lua.
--   allowed : fluid -> { recipe, rate (units/s) }
--   denied  : fluid -> reason code (valuable | fuel | hazard); anything not listed is refused as "unlisted"
D.STACK = "ipp-exhaust-stack"
D.vent = {
  allowed = {
    ["ipp-exhaust-steam"] = { recipe = "ipp-vent-exhaust-steam", rate = C.stack.vent_per_second.exhaust_steam },
    ["ipp-flue-gas"]      = { recipe = "ipp-vent-flue-gas",      rate = C.stack.vent_per_second.flue_gas },
    ["ipp-hot-exhaust"]   = { recipe = "ipp-vent-hot-exhaust",   rate = C.stack.vent_per_second.hot_exhaust },
    ["ipp-co2"]        = { recipe = "ipp-vent-co2",           rate = C.stack.vent_per_second.co2    },   -- kiln surplus
  },
  denied = {
    ["ipp-industrial-steam"] = "valuable",  -- send it to a turbine
    ["steam"]                = "valuable",
    ["water"]                = "valuable",
    ["ipp-fuel-gas"]         = "fuel",      -- burn it in a gas turbine
    ["petroleum-gas"]        = "fuel",
    ["light-oil"]            = "fuel",
    ["heavy-oil"]            = "fuel",
    ["crude-oil"]            = "fuel",
    ["lubricant"]            = "hazard",
    ["sulfuric-acid"]        = "hazard",
    ["ipp-hp-steam"]         = "valuable",  -- send it to a turbine
    ["ipp-cooling-water"]    = "valuable",
    ["ipp-cooling-water-warm"] = "valuable", -- send it to a cooling tower or dry cooler
    ["ipp-primary-water"]    = "hazard",    -- radioactive primary coolant
    ["ipp-primary-water-hot"] = "hazard",
    ["ipp-secondary-water"] = "valuable",  -- closed secondary loop: it is never lost, so it is never vented
    ["ipp-solvent"]          = "hazard",
    -- Tier 4: sodium is hazardous (primary sodium is also radioactive), chlorine is poisonous, the working CO2 stays in its loop
    ["ipp-primary-sodium"]       = "hazard",
    ["ipp-primary-sodium-hot"]   = "hazard",
    ["ipp-secondary-sodium"]     = "hazard",
    ["ipp-secondary-sodium-hot"] = "hazard",
    ["ipp-chlorine"]             = "hazard",
    ["ipp-brine"]                = "valuable",
    ["ipp-sco2"]                 = "valuable",
    ["ipp-sco2-warm"]            = "valuable",
    ["ipp-sco2-hot"]             = "valuable",
    ["ipp-sco2-exhaust"]         = "valuable",
  },
}

return D
