-- Power flow, per transformer, once every N ticks (N = startup setting "pt-update-interval").
--
-- The transformer does not move energy from one buffer to the other in bursts. It runs at a rate:
--   the output half PRODUCES `rate` per tick           (LuaEntity::power_production, J per tick)
--   the input half  CONSUMES `rate` + conversion loss  (LuaEntity::power_usage, J per tick)
-- and the engine does that every tick. So the input network sees a steady draw that only changes
-- when the rate is changed, and the rate is only changed when the load really changed.
--
-- The rate follows the load. Every update:
--   taken   = what the consumers took out of the output buffer since the last update
--           = rate * dt + (level then) - (level now)
--   wanted  = taken / dt + (target level - level now) / settle time        (J per tick, 0..max)
--   rate    = rate + (wanted - rate) * smoothing, and only written when it moved noticeably
--   cap     the draw (and with it the rate) never exceeds what the input buffer holds, spread over
--           the ticks until the next update. The output half produces whatever it is told to,
--           whether or not the input half got the energy, so this cap is what keeps the transformer
--           from making energy out of nothing: when the input network cannot supply it, the buffer
--           empties, the cap falls to what the network does supply, and production follows at once
--           (no smoothing on the way down).
--   usage   = rate + (full load loss - idle loss) * (rate / max rate)^2    (idle loss is the native
--             drain of the input half)
-- The output buffer carries the consumers over the time the rate needs to catch up, and the level
-- correction keeps it around its target (see C.control in config.lua).
--
-- Energy is never created: everything the output half produces up to the next update is paid by the
-- input buffer, which holds real energy from the input network. If the input network is cut, the
-- transformer delivers what is in the input buffer (at most N + 4 ticks of its largest draw) and
-- stops. If the consumers take much less than was produced, the output buffer fills and the surplus
-- is lost (at most an interval).
--
-- Heat tiers get the loss of the elapsed interval in heat.lua in the same update; every
-- transformer then publishes its load / power (/ temperature) through circuit.lua.
local Common = require("__pylon-transformers__.scripts.transformer.common")
local Registry = require("__pylon-transformers__.scripts.transformer.registry")
local Helpers = require("__pylon-transformers__.scripts.transformer.helpers")
local Circuit = require("__pylon-transformers__.scripts.transformer.circuit")
local Heat = require("__pylon-transformers__.scripts.transformer.heat")

local C, N = Common.C, Common.N
local ensure_helpers = Helpers.ensure
local publish = Circuit.publish
local heat_step = Heat.step
local unregister = Registry.unregister
local rebuild_buckets = Registry.rebuild_buckets

local SETTLE = math.max(C.control.settle_ticks, 2 * N)                 -- ticks
local SMOOTHING = 1 - math.exp(-N / C.control.smoothing_ticks)       -- per update

-- How often a transformer's helpers (ports included) are checked completely. The helpers that the
-- update needs are checked every time, cheaply.
local CHECK_INTERVAL = 600

local function update(rec, tick, unit_number)
  local dt = tick - rec.last_tick
  if dt <= 0 then return end
  rec.last_tick = tick

  local info, input, output = rec.info, rec.input, rec.output
  local prod, usage = rec.prod, rec.usage

  -- What the consumers took out of the output buffer.
  local level = output.energy
  local taken = prod * dt + rec.out_prev - level
  if taken < 0 then taken = 0 end
  rec.out_prev = level

  -- The rate that would keep the buffer at its target.
  local wanted = taken / dt + (rec.out_target - level) / SETTLE
  local max_rate = info.max_tick
  if wanted < 0 then wanted = 0 elseif wanted > max_rate then wanted = max_rate end

  -- What the input buffer can pay per tick until the next update (its own drain comes first).
  local in_energy = input.energy
  local cap = in_energy / N - info.idle_tick

  -- The loss of the elapsed interval (at the rate that was in effect), for the heat.
  local loss = (usage - prod) * dt

  -- New rate: smoothed (the smoothed value is kept apart from what the engine runs at), and only
  -- written to the engine when it has moved noticeably from that (or to stop).
  local rate = rec.vrate or prod
  rate = rate + (wanted - rate) * SMOOTHING
  if wanted == 0 and rate < info.rate_eps then rate = 0 end
  rec.vrate = rate
  -- The cap acts on the rate that is applied, not on the smoothed one, and takes effect at once.
  local load = rate / max_rate
  local need = rate + info.loss_tick * load * load
  local capped = need > cap
  if capped then
    if cap <= 0 then rate = 0 else rate = rate * (cap / need) end
  end
  local change = rate - prod
  if change < 0 then change = -change end
  if change >= info.rate_eps or (rate == 0 and prod ~= 0) or (capped and rate < prod) then
    load = rate / max_rate
    usage = rate + info.loss_tick * load * load
    rec.prod, rec.usage = rate, usage
    output.power_production = rate
    input.power_usage = usage
    prod = rate
  end

  local temp_q
  if info.heat then
    temp_q = heat_step(rec, unit_number, tick, dt, dt / 60, loss, in_energy)
    if not temp_q then return end  -- the transformer exploded
  end

  -- The signals follow the rate (steady, so they are only written when the load really changes).
  local load_pct = math.floor(prod / max_rate * 100 + 0.5)
  local power_kw = math.floor(prod * 60 / 1000 / info.power_step + 0.5) * info.power_step
  publish(rec, load_pct, power_kw, temp_q)
end

local function on_tick(event)
  -- Startup setting changed since the buckets were built.
  if storage.bucket_count ~= N then rebuild_buckets() end

  local tick = event.tick
  for unit_number, rec in pairs(storage.buckets[tick % N + 1]) do
    local shell = rec.shell
    if not shell.valid then
      unregister(unit_number)
    else
      -- Helpers only go missing when something else destroys them; then they are made again.
      local ok
      if tick >= (rec.check_at or 0) then
        rec.check_at = tick + CHECK_INTERVAL
        ok = ensure_helpers(rec)
      else
        local input, output, heat = rec.input, rec.output, rec.heat
        ok = (input and output and input.valid and output.valid
              and (not rec.info.heat or (heat and heat.valid))) or ensure_helpers(rec)
      end
      if ok then update(rec, tick, unit_number) end
    end
  end
end

return {
  events = {
    [defines.events.on_tick] = on_tick,
  },
}
