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
  ["ipp-gas-turbine-generator"] = generator("gas", "ipp-fuel-gas", "ipp-hot-exhaust",
    D.FUEL_GAS_MJ, { r = 0.80, g = 0.90, b = 0.70 }, "h"),
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
  },
}

return D
