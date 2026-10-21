-- Shared between data stage and control stage. Pure data, no game API.
-- Table returned to whoever requires this file.
local C = {}

C.mod_name = "pylon-transformers"

C.kinds = {"up", "down"}
C.half_offset = 1.8
C.half_box = 0.1

-- Buffers must carry a transformer between two script updates, with a safety factor.
-- Buffer capacity multiplier over what is needed between two script updates.
C.buffer_safety = 1.25

local e6 = 1000000

C.sizes = {"small", "medium", "large"}

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
--     Medium beats small above ~61 % of the small's capacity,
--     large beats medium above ~63 % of the medium's capacity (same in every tier).
--   * Each tier removes another 12 % of the tier-1 loss fractions (multiplier 1.0, 0.88 ... 0.4).
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
  local row = {}
  for _, size in ipairs(C.sizes) do
    local p = size_params[size]
    local capacity_w = p.capacity_w * capacity_mul
    row[size] = {
      capacity_w = capacity_w,
      idle_w = capacity_w * p.idle * loss_mul,
      full_w = capacity_w * p.full * loss_mul,
    }
  end
  C.tiers[tier] = row
end

-- Prototype name helpers, so both stages build identical names.
function C.shell_name(kind, tier, size)
  return "pt-" .. kind .. "-" .. size .. "-t" .. tier
end

function C.in_name(kind, tier, size)
  return C.shell_name(kind, tier, size) .. "-in"
end

function C.out_name(kind, tier, size)
  return C.shell_name(kind, tier, size) .. "-out"
end


return C