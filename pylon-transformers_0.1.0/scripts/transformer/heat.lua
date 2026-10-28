-- Heating and cooling of heat-tier transformers, overheating alerts and the explosion.
--
-- Heat (heat tiers only), computed in the same update as the power flow (transfer.lua):
--   P     = idle_w (only while the input has energy) + loss actually paid / dt
--   T_eq  = ambient + P / cooling
--   T     = T_eq + (T - T_eq) * exp(-dt * cooling / specific_heat)
--   T >= explode_c  ->  the shell dies and damages everything around it.
local Common = require("__pylon-transformers__.scripts.transformer.common")
local Registry = require("__pylon-transformers__.scripts.transformer.registry")

local C, N, hidden_names = Common.C, Common.N, Common.hidden_names
local unregister = Registry.unregister

local AMBIENT = C.heat.ambient
local ALERT_INTERVAL = C.heat.alert_interval

-- Runtime setting, cached; kept current by on_runtime_mod_setting_changed.
local explosions_enabled = settings.global["pt-explosions"].value

-- Kills the shell and damages everything around it. Records the position first, because the shell
-- is gone afterwards. The transformer is only unregistered (which destroys its ports) after the
-- shell has died: while it dies, port_wires.lua reads the wires of the ports and puts them on the
-- ghost that robots rebuild the transformer from. The later on_object_destroyed finds no record and
-- does nothing.
local function explode(rec, unit_number)
  local shell = rec.shell
  local surface, pos, force = shell.surface, shell.position, shell.force
  local blast = rec.info.blast

  shell.die()
  unregister(unit_number)

  force.print({ "pt-message.exploded",
    string.format("[gps=%d,%d,%s]", pos.x, pos.y, surface.name) })

  if not blast then return end
  for _, e in pairs(surface.find_entities_filtered{ position = pos, radius = blast.radius }) do
    if e.valid and e.is_entity_with_health and not hidden_names[e.name]
       and (e.unit_number == nil or e.unit_number ~= unit_number) then
      local dx, dy = e.position.x - pos.x, e.position.y - pos.y
      local dist = math.sqrt(dx * dx + dy * dy)
      e.damage(blast.damage * (1 - 0.75 * math.min(dist / blast.radius, 1)), "neutral", "explosion")
    end
  end
end

local function raise_alert(rec, temperature, tick)
  rec.next_alert = tick + ALERT_INTERVAL
  local shell = rec.shell
  local icon = { type = "item", name = shell.name }
  local message = { "pt-message.overheating", string.format("%d", temperature) }
  for _, player in pairs(shell.force.connected_players) do
    player.add_custom_alert(shell, icon, message, true)
  end
end

-- Advances the temperature of a heat-tier transformer by dt ticks.
--   loss       conversion loss actually paid in this update (J)
--   available  energy that was in the input buffer at the start of the update (J)
-- Returns the rounded temperature for the circuit, or nil when the transformer exploded.
local function step(rec, unit_number, tick, dt, dt_s, loss, available)
  local info = rec.info
  local h = info.heat
  local heat = rec.heat
  local temperature = heat.temperature

  -- Waste heat: the conversion loss that was actually paid plus the idle drain while powered.
  local power = loss / dt_s
  if available > 0 then power = power + info.idle_w end

  local decay = info.heat_decay
  if dt ~= N then decay = math.exp(-dt_s * h.cooling / h.specific_heat) end

  local t_eq = AMBIENT + power / h.cooling
  local t_new = t_eq + (temperature - t_eq) * decay
  if math.abs(t_new - temperature) > 0.01 then
    heat.temperature = t_new
  end

  if explosions_enabled and (temperature >= h.explode_c or t_new >= h.explode_c) then
    explode(rec, unit_number)
    return nil
  end

  if t_new >= h.warn_c and tick >= rec.next_alert then
    raise_alert(rec, t_new, tick)
  end

  return math.floor(t_new + 0.5)
end

return {
  step = step,

  events = {
    [defines.events.on_runtime_mod_setting_changed] = function(event)
      if event.setting == "pt-explosions" then
        explosions_enabled = settings.global["pt-explosions"].value
      end
    end,
  },
}
