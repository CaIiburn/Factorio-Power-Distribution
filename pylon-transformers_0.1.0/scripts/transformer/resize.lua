-- Changing the size (small / medium / large) and / or the kind (step-up / step-down) of a placed
-- transformer. The picker (gui.lua) and copying settings between transformers (placement.lua)
-- call this.
--
-- Every size and kind is a shell prototype of its own with the same footprint, so a change swaps
-- the shell for the other one on the same spot: same direction, force, quality, health and circuit
-- wires. The record moves to the new shell, and the halves and the heat pipe, which are different
-- prototypes per size and kind, are replaced with their energy and temperature kept
-- (Helpers.change_variant). The ports and their copper wires stay when only the size changes. Another
-- kind has ports of other pole classes: they are replaced and wired like those of a newly placed
-- transformer, to the poles of their class that are in reach.
local Common = require("__pylon-transformers__.scripts.transformer.common")
local Helpers = require("__pylon-transformers__.scripts.transformer.helpers")
local Circuit = require("__pylon-transformers__.scripts.transformer.circuit")
local PortWires = require("__pylon-transformers__.scripts.transformer.port_wires")

local C, shells = Common.C, Common.shells

local Resize = {}

-- Circuit wires of an entity as { { id, target (LuaWireConnector), origin }, ... }.
local function take_wires(entity)
  local list = {}
  for id, connector in pairs(entity.get_wire_connectors(false)) do
    for _, connection in ipairs(connector.connections) do
      list[#list + 1] = { id = id, target = connection.target, origin = connection.origin }
    end
  end
  return list
end

local function put_wires(entity, list)
  for _, w in ipairs(list) do
    local mine = entity.get_wire_connector(w.id, true)
    if mine and w.target.valid then mine.connect_to(w.target, false, w.origin) end
  end
end

-- Makes a shell of `name` where `old` stands (the old one is gone by now). Returns it or nil.
local function make_shell(old_data, name)
  return old_data.surface.create_entity{
    name = name,
    position = old_data.position,
    direction = old_data.direction,
    force = old_data.force,
    quality = old_data.quality,
    create_build_effect_smoke = false,
    raise_built = false,
  }
end

-- Gives the transformer of `rec` another size and / or kind: opts = { size = "large", kind = "down" }
-- (each optional). ctx = { player_index, force, source } is used for wiring the ports of another
-- kind (ctx.no_wire: the caller wires them). Returns the new shell, or nil (the old transformer restored) when that is not possible.
function Resize.apply(rec, opts, ctx)
  local old = rec.shell
  if not (old and old.valid) then return nil end
  local info = rec.info
  local kind, size = opts.kind or info.kind, opts.size or info.size
  if info.size == size and info.kind == kind then return old end
  local new_name = C.shell_name(kind, info.tier, size)
  local new_info = shells[new_name]
  if not new_info then return nil end

  local old_unit = old.unit_number
  local data = {
    surface = old.surface, position = old.position, direction = old.direction,
    force = old.force, quality = old.quality.name,
  }
  local health_ratio = old.get_health_ratio()
  local last_user = old.last_user
  local wires = take_wires(old)
  local old_name = old.name

  -- The record is looked up by the unit number of the shell: take it off until the new one exists.
  storage.transformers[old_unit] = nil
  local bucket = storage.buckets[rec.bucket]
  if bucket then bucket[old_unit] = nil end

  old.destroy()
  local new = make_shell(data, new_name)
  local restored = false
  if not new then
    -- Put the old size back, so that a failed change loses nothing.
    new = make_shell(data, old_name)
    restored = true
  end
  if not new then
    -- Nothing can stand here any more: drop the transformer and what belongs to it.
    Helpers.destroy(rec)
    return nil
  end

  new.health = new.max_health * health_ratio
  if last_user and last_user.valid then new.last_user = last_user end
  rec.shell = new
  local new_unit = new.unit_number
  storage.transformers[new_unit] = rec
  if bucket then bucket[new_unit] = rec end
  script.register_on_object_destroyed(new)

  Circuit.init(rec)
  put_wires(new, wires)

  if not restored then
    local kind_changed = new_info.kind ~= info.kind
    if not Helpers.change_variant(rec, new_info) then return new end
    if kind_changed and not (ctx and ctx.no_wire) then
      PortWires.on_transformer_built(rec, nil, ctx or { force = new.force, source = "script" })
    end
  end
  rec.check_at = 0
  return (not restored) and new or nil
end

return Resize
