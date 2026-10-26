-- Shared between data stage and control stage. Pure data, no game API.
-- Table returned to whoever requires this file.
local C = {}

C.mod_name = "pylon-transformers"

C.kinds = {"up", "down"}
C.half_offset = 1.8
C.half_box = 0.1

-- Ports: one hidden pole on each end of the shell, at the same spot as the electric half of that
-- end. They are the link between a transformer and the outside grid. Each port belongs to a pole
-- class (see C.pole below), so only poles of that class can be wired to it:
--   step-up:   input = feeder port,  output = pylon port
--   step-down: input = pylon port,   output = distribution port
-- The player wires them by hand with copper wire (they are selectable, but cannot be mined or
-- blueprinted), and new poles of the right class wire to them like to any other pole.
--   * port_supply: the supply area is just big enough to cover the half at the port's end. It stays
--     inside the shell's end, so it never touches a neighbouring entity and never reaches the half
--     of a transformer that is built end to end with this one,
--   * port_reach: wire reach. A pole's supply area may not touch a transformer, so a pole has to
--     stand at least its supply half-width away from the shell. The widest half-width of any pole
--     is 15 (large distribution, tier 6), so 16 lets every pole tier connect,
--   * the ports never wire themselves to anything when they are created (auto_connect_up_to_n_wires
--     is 0), so the two ports of one transformer start out unconnected,
--   * the selection box is a small square around the port, drawn above the shell's own.
C.port_supply = 0.15   -- supply_area_distance
C.port_reach = 16      -- maximum_wire_distance
C.port_select = 0.3    -- half size of the selection box
C.port_priority = 80   -- selection priority, above the shell (50)

-- Port prototype name of each end of a transformer kind.
C.ports = {
  up   = { input = "pc-port-feeder-in",  output = "pc-port-pylon-out" },
  down = { input = "pc-port-pylon-in",   output = "pc-port-distribution-out" },
}

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

-- Radiator: a 2x2 building that takes heat out of heat pipes and out of the heat-tier transformers
-- next to it and gives it to nobody. It is a heat interface (the engine's "infinity heat pipe"),
-- set at runtime to "at most ambient", so it is always at ambient. The engine alone does the rest:
-- every tick it equalises the temperature of two connected heat buffers, and since the radiator is
-- put back to ambient, what it takes is
--     heat per tick = (T - ambient) * specific_heat of the radiator       (a small specific heat)
-- That is a cooler with a conductance (W per degree C) like the passive cooling of a transformer,
-- and the specific heat of the radiator sets it: conductance = 60 * specific_heat * exchange_factor.
-- A transformer's heat pipe connects to it directly, ordinary heat pipes connect to it as well.
--
-- The one number to set is how many radiators the hungriest heat transformer needs at full load. The
-- specific heat of the radiator follows from it (see below), and so does the number of radiators
-- every other transformer needs, which the tooltips show.
C.radiator = {
  name = "pt-radiator",
  full_load_count = 4,        -- radiators the transformer that needs the most cooling needs at full load
  hold_frac = C.heat.warn_frac, -- "enough" means: full load settles at this fraction of the way from
                              -- ambient to the explosion temperature. The default is the alert
                              -- temperature, so no alert and no explosion. 1 = right at the explosion.
  exchange_factor = 1,        -- the fraction of the temperature difference the engine equalises per
                              -- tick between two buffers (1 = all of it). Calibrate this if the
                              -- measured cooling of a radiator is off by a constant factor.
  max_temperature = 1000,
  max_health = 300,
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

-- Radiator numbers that follow from C.radiator.
--   A transformer at full load settles where its losses equal its cooling:
--       full_w = (cooling + radiators * conductance) * (T - ambient)
--   It holds the hold temperature when radiators * conductance >= need_k, with
--       need_k = full_w / (hold - ambient) - cooling       (W per degree C, 0 if passive cooling is enough)
-- conductance is chosen so that the transformer with the largest need_k needs exactly
-- full_load_count radiators; the radiator's specific heat gives that conductance to the engine.
do
  local R = C.radiator
  assert(R.full_load_count >= 1, "C.radiator.full_load_count must be at least 1")
  assert(R.hold_frac > 0 and R.hold_frac <= 1, "C.radiator.hold_frac must be in (0, 1]")
  assert(R.exchange_factor > 0 and R.exchange_factor <= 1, "C.radiator.exchange_factor must be in (0, 1]")
  local ambient = C.heat.ambient
  local worst = 0
  for _, row in pairs(C.tiers) do
    for _, entry in pairs(row) do
      local h = entry.heat
      if h then
        h.hold_c = ambient + R.hold_frac * (h.explode_c - ambient)
        h.need_k = math.max(0, entry.full_w / (h.hold_c - ambient) - h.cooling)
        worst = math.max(worst, h.need_k)
      end
    end
  end
  R.conductance = worst / R.full_load_count                  -- W per degree C, per radiator
  R.specific_heat = R.conductance / 60 / R.exchange_factor   -- J per degree C: what the engine is given
  for _, row in pairs(C.tiers) do
    for _, entry in pairs(row) do
      local h = entry.heat
      if h then h.radiators = math.ceil(h.need_k / R.conductance - 1e-9) end
    end
  end
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
-- east/west (long side horizontal) and one for north/south (long side vertical).
function C.heat_name(kind, tier, size, vertical)
  return C.shell_name(kind, tier, size) .. (vertical and "-heat-v" or "-heat-h")
end

---------------------------------------------------------------------------------------------------
-- Pole classes
---------------------------------------------------------------------------------------------------
--
-- Replaces the four vanilla poles with pole classes. Poles only wire to poles of their own class;
-- the transformer ports above bridge the classes. Pure data plus a few helpers, shared by the data
-- stage and the control stage. The only global it touches is `settings` (startup settings), lazily.
local P = {}
C.pole = P

P.TIER_COUNT = 6
P.PREFIX = "pc-"

-- Pole classes. Poles only wire to poles of their own class.
P.CLASSES = { "feeder", "pylon", "distribution", "aux" }

-- Pole families. `area` is the FULL side length of the supply area in tiles
-- (supply_area_distance = side / 2, measured from the pole centre).
-- Pylons have no meaningful supply area: see PYLON_SUPPLY_DISTANCE.
-- `reach` is the maximum wire distance in tiles.
--
-- Large distribution: reach == area, scaling 10 -> 30.
-- Small distribution: reach == area + 2.
P.FAMILIES = {
  {
    id = "feeder", class = "feeder", size = 2, base = "big-electric-pole",
    color = { 1.0, 0.62, 0.2 }, stack = 50, order = "a",
    area = { 6, 8, 10, 12, 14, 16 },
    reach = { 16, 20, 24, 28, 32, 36 },
  },
  {
    id = "pylon", class = "pylon", size = 1, base = "medium-electric-pole",
    color = { 0.55, 0.75, 1.0 }, stack = 50, order = "b",
    area = nil,
    reach = { 40, 45, 50, 55, 60, 64 },
  },
  {
    id = "distribution-large", class = "distribution", size = 2, base = "substation",
    color = { 0.5, 1.0, 0.55 }, stack = 50, order = "c",
    area = { 10, 14, 18, 22, 26, 30 },
    reach = { 10, 14, 18, 22, 26, 30 },
  },
  {
    id = "distribution-small", class = "distribution", size = 1, base = "small-electric-pole",
    color = { 0.35, 0.9, 0.85 }, stack = 100, order = "d",
    area = { 5, 7, 9, 11, 13, 15 },
    reach = { 7, 9, 11, 13, 15, 17 },
  },
  {
    id = "aux", class = "aux", size = 1, base = "small-electric-pole",
    color = { 0.8, 0.55, 1.0 }, stack = 100, order = "e",
    area = { 3, 3, 5, 5, 7, 7 },
    reach = { 6, 8, 10, 12, 14, 16 },
  },
}

-- Pylons "have no supply area". The engine may or may not accept 0, so the
-- smallest value that cannot cover any other entity is used: half a tile
-- covers exactly the pylon's own tile. Set to 0 if your build accepts it.
P.PYLON_SUPPLY_DISTANCE = 0.5

-- Hidden "port" poles that live inside transformers (see C.ports). One per (class, role).
-- role "in"  = power flows from the network into the transformer
-- role "out" = the transformer injects power into the network
-- step-up   transformer: feeder-in  + pylon-out
-- step-down transformer: pylon-in   + distribution-out
P.PORTS = {
  { name = C.ports.up.input,    class = "feeder",       role = "in"  },
  { name = C.ports.up.output,   class = "pylon",        role = "out" },
  { name = C.ports.down.input,  class = "pylon",        role = "in"  },
  { name = C.ports.down.output, class = "distribution", role = "out" },
}
P.PORT_NAMES = {}
for _, port in ipairs(P.PORTS) do P.PORT_NAMES[#P.PORT_NAMES + 1] = port.name end
P.PORT_SUPPLY_DISTANCE = C.port_supply
P.PORT_REACH = C.port_reach

-- Maximum number of transformer OUTPUT ports per network. Inputs are unlimited.
-- Feeder networks never receive transformer outputs.
P.OUTPUT_LIMIT = { feeder = 0, pylon = 2, distribution = 2, aux = 0 }

-- Pole-count cap per network, by tier. A network is limited by its weakest pole.
-- Pylon lines have no gameplay cap (transformer outputs limit them); the
-- number here is only a performance guard for graph walks.
P.NETWORK_CAP = {
  feeder       = { 16, 24, 36, 52, 72, 96 },
  distribution = { 24, 36, 52, 72, 96, 128 },
  aux          = { 8, 12, 16, 24, 32, 48 },
  pylon        = { 400, 400, 400, 400, 400, 400 },
}

-- Wires per pole. MAX_DEGREE is the hard limit for any wire (manual or auto);
-- AUTO_DEGREE is how full a pole may be to still accept an automatic wire;
-- AUTO_CONNECTIONS is how many wires a freshly built pole makes by itself.
P.MAX_DEGREE       = { feeder = 6, pylon = 4, distribution = 6, aux = 6 }
P.AUTO_DEGREE      = { feeder = 2, pylon = 2, distribution = 3, aux = 2 }
P.AUTO_CONNECTIONS = { feeder = 1, pylon = 1, distribution = 2, aux = 1 }

function P.name(family_id, tier)
  return P.PREFIX .. family_id .. "-" .. tier
end

-- Flat list of every pole definition, in a stable order.
P.POLES = {}
P.FAMILY_BY_ID = {}
for _, fam in ipairs(P.FAMILIES) do
  P.FAMILY_BY_ID[fam.id] = fam
  for tier = 1, P.TIER_COUNT do
    local area = fam.area and fam.area[tier]
    P.POLES[#P.POLES + 1] = {
      name = P.name(fam.id, tier),
      family = fam.id,
      class = fam.class,
      tier = tier,
      size = fam.size,
      area = area,                                       -- full side, nil for pylons
      distance = area and (area / 2) or P.PYLON_SUPPLY_DISTANCE,
      reach = fam.reach[tier],
      has_area = fam.class ~= "pylon",
    }
  end
end

local cap_multiplier
local function multiplier()
  if cap_multiplier then return cap_multiplier end
  cap_multiplier = 1
  if settings and settings.startup and settings.startup["pc-network-cap-multiplier"] then
    cap_multiplier = settings.startup["pc-network-cap-multiplier"].value
  end
  return cap_multiplier
end

-- Pole-count cap of one pole of this class and tier, after the startup multiplier.
function P.cap(class, tier)
  local base = P.NETWORK_CAP[class][tier]
  return math.max(2, math.floor(base * multiplier() + 0.5))
end

function P.max_cap(class)
  return P.cap(class, P.TIER_COUNT)
end

-- Used by tests that change the settings between runs.
function P.reset_cache()
  cap_multiplier = nil
end

return C
