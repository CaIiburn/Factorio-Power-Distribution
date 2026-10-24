-- Energy transfer, per transformer, once every N ticks (N = startup setting "pt-update-interval"):
--   missing   = output buffer size - output energy
--   load      = (missing / dt_seconds) / capacity_w            (clamped to 0..1)
--   loss      = (full_w - idle_w) * load^2 * dt_seconds         (conversion loss, on top of idle drain)
--   input    -= missing + loss
--   output   += missing
-- If the input buffer cannot pay for missing + loss, both are scaled down proportionally so
-- no energy is ever created and the input never goes below zero.
--
-- Heat tiers hand the loss to heat.lua in the same update; every transformer then publishes its
-- load / power (/ temperature) through circuit.lua.
local Common = require("__pylon-transformers__.scripts.transformer.common")
local Registry = require("__pylon-transformers__.scripts.transformer.registry")
local Helpers = require("__pylon-transformers__.scripts.transformer.helpers")
local Circuit = require("__pylon-transformers__.scripts.transformer.circuit")
local Heat = require("__pylon-transformers__.scripts.transformer.heat")

local N = Common.N
local ensure_helpers = Helpers.ensure
local publish = Circuit.publish
local heat_step = Heat.step
local unregister = Registry.unregister
local rebuild_buckets = Registry.rebuild_buckets

local function update(rec, tick, unit_number)
  local dt = tick - rec.last_tick
  if dt <= 0 then return end
  rec.last_tick = tick

  local input, output, info = rec.input, rec.output, rec.info
  local dt_s = dt / 60

  local out_energy = output.energy
  local missing = rec.out_size - out_energy

  -- The input is only read when it matters: something has to be moved, or the idle heat depends
  -- on whether the input network is supplying power.
  local available = 0
  if missing > 0 or info.heat then available = input.energy end

  local transfer, loss = 0, 0
  if missing > 0 and available > 0 then
    local load = math.min(missing / dt_s / info.capacity_w, 1)
    loss = info.loss_w * load * load * dt_s

    transfer = missing
    local total = transfer + loss
    if total > available then
      -- Input cannot pay for everything: scale transfer and loss down together.
      local scale = available / total
      transfer = transfer * scale
      loss = loss * scale
      total = available
    end

    input.energy = available - total
    output.energy = out_energy + transfer
  end

  local temp_q
  if info.heat then
    temp_q = heat_step(rec, unit_number, tick, dt, dt_s, loss, available)
    if not temp_q then return end  -- the transformer exploded
  end

  local load_pct = math.min(100, math.floor(transfer / dt_s / info.capacity_w * 100 + 0.5))
  local power_kw = math.floor(transfer / dt_s / 1000 / info.power_step + 0.5) * info.power_step
  publish(rec, load_pct, power_kw, temp_q)
end

local function on_tick(event)
  -- Startup setting changed since the buckets were built.
  if storage.bucket_count ~= N then rebuild_buckets() end

  local tick = event.tick
  for unit_number, rec in pairs(storage.buckets[tick % N + 1]) do
    if not rec.shell.valid then
      unregister(unit_number)
    elseif ensure_helpers(rec) then
      update(rec, tick, unit_number)
    end
  end
end

return {
  events = {
    [defines.events.on_tick] = on_tick,
  },
}
