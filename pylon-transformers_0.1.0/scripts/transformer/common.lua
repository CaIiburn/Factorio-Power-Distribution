-- Constants and lookup tables shared by every runtime module.
--
-- Everything here is derived from config.lua, which the data stage also uses, so the runtime and
-- the generated prototypes always agree.
local C = require("__pylon-transformers__.config")

-- Update interval in ticks (startup setting). Each transformer is serviced once every N ticks.
local N = math.max(1, math.floor(settings.startup["pt-update-interval"].value))

-- shell prototype name -> info (see below)
local shells = {}
-- hidden helper prototype name -> true (halves, heat pipes and the ports)
local hidden_names = {}
-- port prototype name -> true. Ports are the hidden poles on the ends of a transformer. They are
-- poles of the pole classes, so they are listed in config.lua (C.pole.PORTS).
local port_names = {}
for _, port in ipairs(C.pole.PORTS) do
  port_names[port.name] = true
  hidden_names[port.name] = true
end

for _, kind in ipairs(C.kinds) do
  for tier, tier_data in ipairs(C.tiers) do
    for _, size in ipairs(C.sizes) do
      local t = tier_data[size]
      local info = {
        in_name = C.in_name(kind, tier, size),
        out_name = C.out_name(kind, tier, size),
        -- Port poles of the two ends: step-up feeder + pylon, step-down pylon + distribution.
        in_port = C.ports[kind].input,
        out_port = C.ports[kind].output,
        capacity_w = t.capacity_w,
        idle_w = t.idle_w,
        -- Additional loss at 100 % load. full_w includes idle_w, so subtract it.
        -- Clamped at 0 so bad data can never turn the transformer into an energy source.
        loss_w = math.max(0, t.full_w - t.idle_w),
        -- Per tick (the engine's power_production / power_usage are in J per tick): the largest
        -- output rate, the conversion loss at that rate, and the smallest rate change worth writing.
        max_tick = t.capacity_w / 60,
        loss_tick = math.max(0, t.full_w - t.idle_w) / 60,
        idle_tick = t.idle_w / 60,
        rate_eps = t.capacity_w / 60 * C.control.tolerance,
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

-- Direction of the shell -> unit vector from the shell center towards its OUTPUT end: the output
-- end is where the transformer faces, the input end is the opposite one.
--
-- This has to be so (and not, say, "output on the right when facing north"): the game flips a
-- blueprint by turning the direction names as if the entity looked that way (a horizontal flip turns
-- east into west and leaves north alone, a vertical flip the other way round). Only when the
-- direction really points along the entity does a flipped transformer keep its input and output
-- at the correct ends. Up to 0.1.0 (first merged version) north meant "output on the right"; saves
-- from then are turned by registry.lua.
local OUTPUT_VECTOR = {
  [north] = {  0, -1 },
  [east]  = {  1,  0 },
  [south] = {  0,  1 },
  [west]  = { -1,  0 },
}

return {
  C = C,
  N = N,
  shells = shells,
  hidden_names = hidden_names,
  port_names = port_names,
  north = north,
  east = east,
  south = south,
  west = west,
  OUTPUT_VECTOR = OUTPUT_VECTOR,
}
