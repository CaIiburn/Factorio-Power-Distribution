-- Shared between data stage and control stage. Pure data, no game API.
-- Table returned to whoever requires this file.
local C = {}

C.mod_name = "pylon-transformers"

C.kinds = {"up", "down"}
C.half_offset = 1.8
C.half_box = 0.1

-- Connection poles, one on each end of the shell, at the same spot as the electric halves.
-- They are the only link between a transformer and the outside grid, and the player wires them
-- by hand with copper wire (they are selectable, but cannot be mined or blueprinted):
--   * the supply area is just big enough to cover the half at their end (and nothing else, not
--     even the half of a transformer that is built end to end with this one),
--   * auto_connect_up_to_n_wires is 0, so a pole never wires itself to anything when it is
--     created. The two poles of one transformer therefore start out unconnected, although they
--     are well within wire reach of each other (2 * half_offset = 3.6 apart),
--   * the selection box is a small square around the pole, drawn above the shell's own.
C.pole_name = "pt-hidden-pole"
C.pole_supply = 0.25   -- supply_area_distance
C.pole_reach = 9       -- maximum_wire_distance
C.pole_select = 0.3    -- half size of the selection box

-- Half extents of the area a transformer occupies, long axis first (the halves stick out a little
-- past the shell's collision box). Used for the "not inside a pole's supply area" rule.
C.footprint = { long = C.half_offset + C.half_box, short = 0.85 }

-- Buffers must carry a transformer between two script updates, with a safety factor.
-- Buffer capacity multiplier over what is needed between two script updates.
C.buffer_safety = 1.1

local e6 = 1000000

C.sizes = {"small", "medium", "large"}

---------------------------------------------------------------------------------------------------
-- Circuit network output
---------------------------------------------------------------------------------------------------

-- Virtual signal names written to the shell (a constant combinator) every update.
--   load        delivered output power as % of rated output (0..100)
--   power       delivered output power in kW
--   temperature core temperature in degrees C (heat tiers only)
C.signal = {
  load = "pt-load",
  power = "pt-power",
  temperature = "pt-temperature",
}

-- The power signal is quantised to this fraction of rated output, so a slowly drifting load does
-- not cause a circuit write on every single update. 0.005 = steps of 0.5 % of rated output.
C.signal_power_resolution = 0.005

---------------------------------------------------------------------------------------------------
-- Heat model (only tiers listed in C.heat.tiers have a temperature)
---------------------------------------------------------------------------------------------------
--
-- A hidden heat-pipe entity owns the temperature. Per update the script applies
--     P    = idle_w (while the input is powered) + conversion loss that was actually paid / dt
--     T_eq = ambient + P / cooling
--     T'   = T_eq + (T - T_eq) * exp(-dt * cooling / specific_heat)
-- cooling (W per degree C) is passive cooling to the environment. Conduction into connected heat
-- pipes is done by the engine, not by the script.
--
-- Per tier and size the numbers are derived from that tier's own loss figures, so they follow
-- any change to the loss table below:
--   * cooling is chosen so that passive cooling alone settles exactly at the warning temperature
--     when the transformer runs at `cool_load` (fraction of rated output). Above that load a
--     transformer needs heat pipes. This is the number shown in the tooltip.
--   * specific_heat is chosen so full load without any cooling takes `time_to_explode_s` seconds
--     to go from ambient to the explosion temperature.
C.heat = {
  ambient = 15,               -- degrees C, also the heat entity's default temperature
  warn_frac = 0.7,            -- alert once 70 % of the way from ambient to the explosion temperature
  cool_load = 0.5,            -- passive cooling holds up to this fraction of rated output
  time_to_explode_s = 120,    -- full load, no cooling, from ambient
  max_margin = 50,            -- the heat buffer may go this far past the explosion temperature
  alert_interval = 300,       -- ticks between two overheating alerts of one transformer

  -- Only these tiers have the heat mechanic. 1, 2 (too small), 5 (aquilo only), 6 (superconductor)
  -- are not listed and therefore never get a temperature.
  tiers = {
    [3] = { explode_c = 300 },
    [4] = { explode_c = 400 },
  },

  -- Area damage when a transformer explodes. Damage falls off linearly to 25 % at the radius.
  blast = {
    small  = { radius = 3, damage = 150 },
    medium = { radius = 4, damage = 300 },
    large  = { radius = 5, damage = 500 },
  },
}

-- Explosion effect played when a shell dies (any cause). Names that do not exist in the loaded
-- prototypes are ignored by the data stage.
C.explosion_effect = {
  small  = "medium-explosion",
  medium = "big-explosion",
  large  = "massive-explosion",
}

---------------------------------------------------------------------------------------------------
-- Loss model
---------------------------------------------------------------------------------------------------

-- Loss model:  loss(load) = idle_w + (full_w - idle_w) * (load / capacity_w)^2
--   idle_w  is applied by the engine as the input half's drain (constant, always on).
--   The squared part is applied by control.lua on every transfer.
--   full_w  is the TOTAL loss at 100 % load (idle_w included), so full_w must be >= idle_w.
--
-- The table is generated from loss fractions of rated capacity so the efficiency curves stay
-- consistent between sizes and tiers:
--   * Capacity doubles per size step (small -> medium -> large) and is x5 per tier.
--   * Bigger sizes have a higher absolute idle loss but a lower loss at full load, so small
--     transformers are more efficient at low load and big ones under load.
--   * Each tier removes another 12.5 % of the tier-1 loss fractions (multiplier 1.0, 0.875 ... 0.375).
--
-- Tier-1 values: idle / full are fractions of that size's own rated capacity.
local size_params = {
  small  = { capacity_w = 0.625e6, idle = 0.01, full = 0.09 },  -- 1 % idle,  9 % at full load
  medium = { capacity_w = 1.25e6,  idle = 0.015, full = 0.06 },  -- 1.5 % idle,  6 % at full load
  large  = { capacity_w = 2.5e6,   idle = 0.02, full = 0.04 },  -- 2.0 % idle,  4 % at full load
}

C.tiers = {}
for tier = 1, 6 do
  local capacity_mul = 5 ^ (tier - 1)
  local loss_mul = 1 - 0.125 * (tier - 1)
  local heat_tier = C.heat.tiers[tier]
  local row = {}
  for _, size in ipairs(C.sizes) do
    local p = size_params[size]
    local capacity_w = p.capacity_w * capacity_mul
    local entry = {
      capacity_w = capacity_w,
      idle_w = capacity_w * p.idle * loss_mul,
      full_w = capacity_w * p.full * loss_mul,
    }

    if heat_tier then
      local ambient = C.heat.ambient
      local range = heat_tier.explode_c - ambient
      local warn_c = ambient + C.heat.warn_frac * range
      -- Total loss (idle + conversion) while running at cool_load.
      local loss_at_cool = entry.idle_w + (entry.full_w - entry.idle_w) * C.heat.cool_load ^ 2
      entry.heat = {
        explode_c = heat_tier.explode_c,
        warn_c = warn_c,
        max_c = heat_tier.explode_c + C.heat.max_margin,
        cooling = loss_at_cool / (warn_c - ambient),                   -- W per degree C
        specific_heat = entry.full_w * C.heat.time_to_explode_s / range, -- J per degree C
      }
    end

    row[size] = entry
  end
  C.tiers[tier] = row
end

---------------------------------------------------------------------------------------------------
-- Prototype name helpers, so both stages build identical names.
---------------------------------------------------------------------------------------------------

function C.shell_name(kind, tier, size)
  return "pt-" .. kind .. "-" .. size .. "-t" .. tier
end

function C.in_name(kind, tier, size)
  return C.shell_name(kind, tier, size) .. "-in"
end

function C.out_name(kind, tier, size)
  return C.shell_name(kind, tier, size) .. "-out"
end

-- Hidden heat entity. Heat pipes cannot rotate, so there is one variant for the shell facing
-- north/south (long side horizontal) and one for east/west (long side vertical).
function C.heat_name(kind, tier, size, vertical)
  return C.shell_name(kind, tier, size) .. (vertical and "-heat-v" or "-heat-h")
end


return C
