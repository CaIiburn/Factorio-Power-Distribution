-- Sodium-to-CO2 heaters choose their recipe by themselves.
--
-- The heater has two recipes that burn the same sodium: one takes PREHEATED CO2 (from a recuperator) and makes more hot CO2
-- from it, the other takes COLD compressed CO2 (straight from the compressor, no recuperator) and makes less. Once a second
-- the script reads the fluid in whatever is connected to the heater's CO2 inlet (the right-hand port of the north face when
-- unrotated, like the exhaust stack it reads the pipe, because a crafting machine only accepts the fluid of its current recipe)
-- and sets the matching recipe. So removing the recuperator never stops the heater; it only needs more heat per MW.
local defs = require("shared.defs")

local M = {}
local POLL_TICKS = 59
local WARM, DIRECT = "ipp-co2-heating-recuperated", "ipp-co2-heating-direct"
local FEED = { ["ipp-sco2-warm"] = WARM, ["ipp-sco2"] = DIRECT }

local function heaters()
  storage.ipp_heaters = storage.ipp_heaters or {}
  return storage.ipp_heaters
end

-- Tile just outside the CO2 inlet: north face, lateral +1 (right-hand port) when unrotated; rotates with the heater.
function M.inlet_offset(direction)
  local d = defines.direction
  local o = (defs.config.co2_heater.size + 1) / 2
  if direction == d.east then return o, 1
  elseif direction == d.south then return -1, o
  elseif direction == d.west then return -o, -1 end
  return 1, -o
end

-- Fluids held by whatever is connected to the CO2 inlet: { [fluid name] = amount } or nil.
function M.inlet_contents(h)
  local dx, dy = M.inlet_offset(h.direction)
  local at = { x = h.position.x + dx, y = h.position.y + dy }
  local merged, any = {}, false
  for _, e in pairs(h.surface.find_entities_filtered { position = at, radius = 0.45 }) do
    if e.valid and e ~= h and e.type ~= "entity-ghost" then
      local ok, contents = pcall(e.get_fluid_contents, e)
      if ok and type(contents) == "table" then
        for name, amount in pairs(contents) do
          if amount > 0 then merged[name] = (merged[name] or 0) + amount; any = true end
        end
      end
    end
  end
  return any and merged or nil
end

-- The recipe the contents ask for: the more plentiful of the two feeds wins. nil = nothing recognisable.
function M.wanted(contents)
  if not contents then return nil end
  local best, best_amount = nil, 0
  for fluid, recipe in pairs(FEED) do
    local a = contents[fluid] or 0
    if a > best_amount then best, best_amount = recipe, a end
  end
  return best
end

local function set_status(h, diode, label) h.custom_status = { diode = diode, label = label } end

local function usable(h, name)
  local r = h.force.recipes[name]
  return r and r.enabled
end

function M.update(h)
  local diode = defines.entity_status_diode
  local current = h.get_recipe()
  current = current and current.name or nil
  local want = M.wanted(M.inlet_contents(h))
  if want and want ~= current then
    if usable(h, want) then
      h.set_recipe(want); current = want
    end
  elseif not current and usable(h, WARM) then
    h.set_recipe(WARM); current = WARM          -- nothing connected yet: the rated (recuperated) recipe
  end
  local cfg = defs.config
  local more = math.floor((cfg.fluids.sco2_recuperated_mj / (cfg.fluids.sco2_hot_mj - cfg.fluids.sco2_recuperated_mj)) * 100 + 0.5)
  if current == WARM then
    set_status(h, diode.green, { "ipp.heater-recuperated" })
  elseif current == DIRECT then
    set_status(h, diode.yellow, { "ipp.heater-direct", tostring(more) })
  else
    set_status(h, diode.red, { "ipp.heater-research" })
  end
end

function M.register(h)
  if not (h and h.valid and h.name == defs.HEATER and h.unit_number) then return end
  heaters()[h.unit_number] = h
  M.update(h)
end

function M.unregister(unit) heaters()[unit] = nil end

function M.poll()
  for unit, h in pairs(heaters()) do
    if h.valid then M.update(h) else heaters()[unit] = nil end
  end
end

function M.rescan()
  for _, surface in pairs(game.surfaces) do
    for _, e in pairs(surface.find_entities_filtered { name = defs.HEATER }) do M.register(e) end
  end
end

-- Build / clone / remove events are registered once for all scripts (scripts/events.lua).
M.lifecycle = {
  names = { [defs.HEATER] = true },
  built = function(e) M.register(e) end,
  removed = function(unit) M.unregister(unit) end,
}

-- Own nth-tick value (59): the stacks use 60 and only one handler per value exists. A newly researched recipe is picked up
-- by the next poll, so no on_research_finished handler is needed (the stacks own that event).
function M.register_events()
  script.on_nth_tick(POLL_TICKS, M.poll)
end

return M
