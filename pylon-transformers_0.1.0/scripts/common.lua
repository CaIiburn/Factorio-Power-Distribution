-- Constants and lookup tables shared by every runtime module.
--
-- Everything here is derived from config.lua, which the data stage also uses, so the runtime and
-- the generated prototypes always agree.
local C = require("__pylon-transformers__.config")

-- Update interval in ticks (startup setting). Each transformer is serviced once every N ticks.
local N = math.max(1, math.floor(settings.startup["pt-update-interval"].value))

local POLE_NAME = C.pole_name

-- shell prototype name -> info (see below)
local shells = {}
-- hidden helper prototype name -> true (halves, heat pipes and the connection pole)
local hidden_names = { [POLE_NAME] = true }

for _, kind in ipairs(C.kinds) do
  for tier, tier_data in ipairs(C.tiers) do
    for _, size in ipairs(C.sizes) do
      local t = tier_data[size]
      local info = {
        in_name = C.in_name(kind, tier, size),
        out_name = C.out_name(kind, tier, size),
        capacity_w = t.capacity_w,
        idle_w = t.idle_w,
        -- Additional loss at 100 % load. full_w includes idle_w, so subtract it.
        -- Clamped at 0 so bad data can never turn the transformer into an energy source.
        loss_w = math.max(0, t.full_w - t.idle_w),
        -- Resolution of the power signal in kW.
        power_step = math.max(1, math.floor(t.capacity_w / 1000 * C.signal_power_resolution)),
      }
      hidden_names[info.in_name] = true
      hidden_names[info.out_name] = true

      local h = t.heat
      if h then
        info.heat = h
        -- exp() factor for the normal case dt == N, so the hot path needs no math.exp call.
        info.heat_decay = math.exp(-(N / 60) * h.cooling / h.specific_heat)
        info.heat_h = C.heat_name(kind, tier, size, false)
        info.heat_v = C.heat_name(kind, tier, size, true)
        info.blast = C.heat.blast[size]
        hidden_names[info.heat_h] = true
        hidden_names[info.heat_v] = true
      end

      shells[C.shell_name(kind, tier, size)] = info
    end
  end
end

local north, east, south, west =
  defines.direction.north, defines.direction.east, defines.direction.south, defines.direction.west

-- Direction of the shell -> unit vector from the shell center towards its OUTPUT end.
-- The input end is the opposite one. Turning clockwise: right -> down -> left -> up.
local OUTPUT_VECTOR = {
  [north] = {  1,  0 },
  [east]  = {  0,  1 },
  [south] = { -1,  0 },
  [west]  = {  0, -1 },
}

return {
  C = C,
  N = N,
  POLE_NAME = POLE_NAME,
  shells = shells,
  hidden_names = hidden_names,
  north = north,
  east = east,
  south = south,
  west = west,
  OUTPUT_VECTOR = OUTPUT_VECTOR,
}
