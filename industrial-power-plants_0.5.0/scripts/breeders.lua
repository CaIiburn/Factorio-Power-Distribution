-- Blanket irradiation: a blanket channel is bred at the speed of the fast-breeder core it touches.
--
-- A vanilla reactor burns one item at a time, so it cannot irradiate a second kind of assembly itself. The channel is a
-- crafting machine (blanket assembly -> bred blanket assembly, config blanket_channel.channel_time_s at full flux) that this
-- script switches on and off every tick (disabled_by_script, error-diffusion duty cycle, like the reactor cores):
--
--     duty = channel_time_s x core fission power / (loaded channels x irradiation energy per blanket), at most 1
--
-- * Core fission power is the core's ACTUAL average output (rod duty x rated power x (1 + neighbour bonus)); a core that is
--   scrammed, locked out or out of fuel irradiates nothing.
-- * The channels touching one core share its neutron budget equally, so building more channels does not breed more fissile
--   material per unit of core energy; it only lets a stronger core (neighbour bonus) keep up.
-- * A channel belongs to the nearest breeder core whose edge is within blanket_channel.reach_tiles of its own.
local defs = require("shared.defs")
local reactors = require("scripts.reactors")
local B = defs.breeder

local M = {}
local ASSIGN_TICKS = 30
local EPS = 1e-9

local function channels()
  storage.ipp_channels = storage.ipp_channels or {}
  return storage.ipp_channels
end

local function core_entries()
  storage.ipp_reactors = storage.ipp_reactors or {}
  return storage.ipp_reactors
end

local function box_gap(a, b)   -- distance between two axis-aligned boxes (0 = touching), Chebyshev like the grid
  local gx = math.max(a.left_top.x - b.right_bottom.x, b.left_top.x - a.right_bottom.x)
  local gy = math.max(a.left_top.y - b.right_bottom.y, b.left_top.y - a.right_bottom.y)
  return math.max(gx, gy)
end

-- Nearest breeder core in reach: its unit number or nil.
function M.find_core(ch)
  local best, best_gap = nil, B.reach + EPS
  for unit, entry in pairs(core_entries()) do
    local c = entry.entity
    if c.valid and c.name == defs.FBR and c.surface == ch.surface then
      local gap = box_gap(ch.selection_box, c.selection_box)
      if gap <= best_gap then best, best_gap = unit, gap end
    end
  end
  return best
end

-- A channel counts as loaded when a blanket is waiting in it or one is being irradiated.
function M.loaded(ch)
  if (ch.crafting_progress or 0) > 0 then return true end
  local inv = ch.get_inventory(defines.inventory.crafter_input)
  return inv ~= nil and not inv.is_empty()
end

-- Average fission power of a core in watts.
function M.core_power(entry)
  local c = entry.entity
  if not (c.valid and reactors.has_fuel(c)) then return 0 end
  return (entry.duty or 0) * B.rated_w * (1 + (c.neighbour_bonus or 0))
end

local function set_status(entry, diode, label)
  entry.entity.custom_status = { diode = diode, label = label }
end

-- Every ASSIGN_TICKS: re-assign channels to cores, share each core's flux among its loaded channels, set the duties.
function M.assign()
  local list = channels()
  local loaded_by_core, any = {}, false
  for unit, entry in pairs(list) do
    if not entry.entity.valid then
      list[unit] = nil
    else
      entry.core = M.find_core(entry.entity)
      if entry.core and M.loaded(entry.entity) then
        loaded_by_core[entry.core] = (loaded_by_core[entry.core] or 0) + 1
      end
      any = true
    end
  end
  if not any then return end
  local diode = defines.entity_status_diode
  for _, entry in pairs(list) do
    local core = entry.core and core_entries()[entry.core]
    if not core then
      entry.duty = 0
      set_status(entry, diode.red, { "ipp.channel-no-core" })
    else
      local power = M.core_power(core)
      local n = math.max(1, loaded_by_core[entry.core] or 0)
      entry.duty = math.min(1, B.channel_time_s * power / (n * B.irradiation_j))
      if power <= 0 then
        set_status(entry, diode.yellow, { "ipp.channel-core-idle" })
      else
        local pct = string.format("%.0f", entry.duty * 100)
        local starved = (B.channel_time_s * power / (n * B.irradiation_j)) > 1 + 1e-6
        set_status(entry, starved and diode.yellow or diode.green,
          { starved and "ipp.channel-flux-surplus" or "ipp.channel-flux", pct, tostring(n) })
      end
    end
  end
end

-- Error-diffusion duty cycle, every tick (same scheme as the reactor cores).
function M.pwm(entry)
  local acc = entry.acc + (entry.duty or 0)
  local on = acc >= 1 - EPS
  if on then acc = math.max(0, acc - 1) end
  entry.acc = acc
  if on ~= entry.on then
    entry.on = on
    entry.entity.disabled_by_script = not on
  end
end

function M.on_tick(event)
  local list = channels()
  if next(list) == nil then return end
  if event.tick % ASSIGN_TICKS == 0 then M.assign() end
  for unit, entry in pairs(list) do
    if entry.entity.valid then M.pwm(entry) else list[unit] = nil end
  end
end

function M.register(e)
  if not (e and e.valid and e.name == defs.CHANNEL and e.unit_number) then return end
  local list = channels()
  if list[e.unit_number] then list[e.unit_number].entity = e; return end
  list[e.unit_number] = { entity = e, duty = 0, acc = 0, on = false, core = nil }
  e.disabled_by_script = true
  set_status(list[e.unit_number], defines.entity_status_diode.red, { "ipp.channel-no-core" })
end

function M.unregister(unit) channels()[unit] = nil end

function M.rescan()
  for _, surface in pairs(game.surfaces) do
    for _, e in pairs(surface.find_entities_filtered { name = defs.CHANNEL }) do M.register(e) end
  end
end

function M.debug_lines()
  local lines = {}
  for _, entry in pairs(channels()) do
    local e = entry.entity
    if e.valid then
      local core = entry.core and core_entries()[entry.core]
      lines[#lines + 1] = string.format("%s  duty %.3f  core %s  core power %.0f MW  loaded %s  progress %.2f",
        e.gps_tag, entry.duty or 0, entry.core and tostring(entry.core) or "none",
        core and M.core_power(core) / 1e6 or 0, tostring(M.loaded(e)), e.crafting_progress or 0)
    end
  end
  if #lines == 0 then lines[1] = "no blanket channels" end
  return lines
end

-- Build / clone / remove events are registered once for all scripts (scripts/events.lua).
M.lifecycle = {
  names = { [defs.CHANNEL] = true },
  built = function(e) M.register(e) end,
  removed = function(unit) M.unregister(unit) end,
}

function M.register_events()
  -- Factorio allows one on_tick handler: ride on the reactor script's (it calls every hook after its own work)
  reactors.hooks[#reactors.hooks + 1] = M.on_tick
end

return M
