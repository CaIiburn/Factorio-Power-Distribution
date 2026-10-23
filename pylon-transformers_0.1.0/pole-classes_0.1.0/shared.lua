-- shared.lua
-- Constants shared by the data stage and the control stage.
-- Pure Lua: the only global it touches is `settings` (startup settings), lazily.

local M = {}

M.TIER_COUNT = 6
M.PREFIX = "pc-"

-- Pole classes. Poles only wire to poles of their own class.
M.CLASSES = { "feeder", "pylon", "distribution", "aux" }

-- Pole families. `area` is the FULL side length of the supply area in tiles
-- (supply_area_distance = side / 2, measured from the pole centre).
-- Pylons have no meaningful supply area: see PYLON_SUPPLY_DISTANCE.
-- `reach` is the maximum wire distance in tiles.
--
-- Large distribution: reach == area, scaling 10 -> 30.
-- Small distribution: reach == area + 2.
M.FAMILIES = {
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
M.PYLON_SUPPLY_DISTANCE = 0.5

-- Hidden "port" poles that live inside transformers. One per (class, role).
-- role "in"  = power flows from the network into the transformer
-- role "out" = the transformer injects power into the network
-- step-up   transformer: feeder-in  + pylon-out
-- step-down transformer: pylon-in   + distribution-out
M.PORTS = {
  { name = "pc-port-feeder-in",         class = "feeder",       role = "in"  },
  { name = "pc-port-pylon-out",         class = "pylon",        role = "out" },
  { name = "pc-port-pylon-in",          class = "pylon",        role = "in"  },
  { name = "pc-port-distribution-out",  class = "distribution", role = "out" },
}
M.PORT_SUPPLY_DISTANCE = 1.5
M.PORT_REACH = 64

-- Maximum number of transformer OUTPUT ports per network. Inputs are unlimited.
-- Feeder networks never receive transformer outputs.
M.OUTPUT_LIMIT = { feeder = 0, pylon = 2, distribution = 2, aux = 0 }

-- Pole-count cap per network, by tier. A network is limited by its weakest pole.
-- Pylon lines have no gameplay cap (transformer outputs limit them); the
-- number here is only a performance guard for graph walks.
M.NETWORK_CAP = {
  feeder       = { 16, 24, 36, 52, 72, 96 },
  distribution = { 24, 36, 52, 72, 96, 128 },
  aux          = { 8, 12, 16, 24, 32, 48 },
  pylon        = { 400, 400, 400, 400, 400, 400 },
}

-- Wires per pole. MAX_DEGREE is the hard limit for any wire (manual or auto);
-- AUTO_DEGREE is how full a pole may be to still accept an automatic wire;
-- AUTO_CONNECTIONS is how many wires a freshly built pole makes by itself.
M.MAX_DEGREE       = { feeder = 6, pylon = 4, distribution = 6, aux = 6 }
M.AUTO_DEGREE      = { feeder = 2, pylon = 2, distribution = 3, aux = 2 }
M.AUTO_CONNECTIONS = { feeder = 1, pylon = 1, distribution = 2, aux = 1 }

function M.name(family_id, tier)
  return M.PREFIX .. family_id .. "-" .. tier
end

-- Flat list of every pole definition, in a stable order.
M.POLES = {}
M.FAMILY_BY_ID = {}
for _, fam in ipairs(M.FAMILIES) do
  M.FAMILY_BY_ID[fam.id] = fam
  for tier = 1, M.TIER_COUNT do
    local area = fam.area and fam.area[tier]
    M.POLES[#M.POLES + 1] = {
      name = M.name(fam.id, tier),
      family = fam.id,
      class = fam.class,
      tier = tier,
      size = fam.size,
      area = area,                                       -- full side, nil for pylons
      distance = area and (area / 2) or M.PYLON_SUPPLY_DISTANCE,
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
function M.cap(class, tier)
  local base = M.NETWORK_CAP[class][tier]
  return math.max(2, math.floor(base * multiplier() + 0.5))
end

function M.max_cap(class)
  return M.cap(class, M.TIER_COUNT)
end

-- Used by tests that change the settings between runs.
function M.reset_cache()
  cap_multiplier = nil
end

return M
