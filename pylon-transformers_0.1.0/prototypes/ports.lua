-- Transformer ports: hidden poles that sit on the two ends of every transformer shell, one per
-- (class, role) pair of config.lua (C.pole.PORTS):
--   step-up:   pc-port-feeder-in (input end) + pc-port-pylon-out (output end)
--   step-down: pc-port-pylon-in  (input end) + pc-port-distribution-out (output end)
--
-- Players never place them; the transformer script creates two per shell, on the same spot as the
-- electric half of that end. They are the only link between a transformer and the outside grid:
--   * the tiny supply area reaches just the half at the port's end and stays inside the end of the
--     shell (C.port_supply), so it never touches a neighbouring entity,
--   * they never wire themselves to anything (auto_connect_up_to_n_wires = 0); the player wires
--     them by hand and new poles of the same class wire to them automatically,
--   * only poles of the port's own class may be wired to it (enforced by the wire checks),
--   * they can be selected (to wire them) but not mined, blueprinted or copied.
--
-- A pole has one set of wire attachment points and a selection box that does not turn, so every
-- port exists once per direction of the shell (name = base name .. "-north" / "-east" / ...):
--   * the wires attach to the knob of the bushing at that end of the shell's sprite
--     (sprites.lua, M.attach), given from the centre of the port: the port stands on the end of
--     the shell, 1.8 tiles from its centre along the long axis,
--   * the selection box is the end of the shell that the port belongs to, C.port_select_depth tiles
--     deep and as wide as the shell (the Electric Grid transformer uses the whole half, depth 2).
-- The ports without a direction are those of earlier versions. They stay so that saves that have
-- them load; the transformer script replaces them (registry.lua).
local C = require("__pylon-transformers__.config")
local Sprites = require("__pylon-transformers__.sprites")
local shared = C.pole

local EMPTY = { filename = "__core__/graphics/empty.png", priority = "extra-high", width = 1, height = 1 }

-- Direction -> unit vector towards the output end of the shell (north is up on the screen).
local OUTPUT_VECTOR = { north = { 0, -1 }, east = { 1, 0 }, south = { 0, 1 }, west = { -1, 0 } }

-- Offset between the copper wire point and the red / green ones (tiles).
local WIRE_OFFSET = 0.12
-- How far the shadow of a wire point lies to the right per tile of height above the ground.
local SHADOW_SLANT = 0.9

local function port_geometry(def)
  local v = OUTPUT_VECTOR[def.direction]
  local side = (def.role == "out") and 1 or -1
  local centre = { side * C.half_offset * v[1], side * C.half_offset * v[2] }   -- port, from the shell centre

  -- Wire points: from the shell's sprite, relative to the port.
  local a = Sprites.attach(def.kind, def.direction, def.role)
  local x, y = a[1] - centre[1], a[2] - centre[2]
  local height = math.max(0, -y)
  local sx, sy = x + height * SHADOW_SLANT, 0

  local function points(px, py)
    return { copper = { px, py }, red = { px + WIRE_OFFSET, py + WIRE_OFFSET }, green = { px - WIRE_OFFSET, py + WIRE_OFFSET } }
  end
  local connection_points = { { wire = points(x, y), shadow = points(sx, sy) } }

  -- Selection box: the end of the shell. `u` points from the shell centre out through this port;
  -- along u the box runs from `depth` inside the shell's end to the end (2 tiles from the centre),
  -- which relative to the port (at 1.8) is [0.2 - depth, 0.2]; across it is as wide as the shell.
  local u = { side * v[1], side * v[2] }
  local depth = C.port_select_depth
  local lo, hi = 0.2 - depth, 0.2
  local box
  if u[1] ~= 0 then
    local a1, a2 = lo * u[1], hi * u[1]
    box = { { math.min(a1, a2), -1 }, { math.max(a1, a2), 1 } }
  else
    local a1, a2 = lo * u[2], hi * u[2]
    box = { { -1, math.min(a1, a2) }, { 1, math.max(a1, a2) } }
  end
  return connection_points, box
end

local ports = {}
for _, def in ipairs(shared.PORTS) do
  local connection_points = { { shadow = { copper = { 0, 0 } }, wire = { copper = { 0, 0 } } } }
  local selection_box = { { -C.port_select, -C.port_select }, { C.port_select, C.port_select } }
  if def.direction then
    connection_points, selection_box = port_geometry(def)
  end

  ports[#ports + 1] = {
    type = "electric-pole",
    name = def.name,
    localised_name = { "pc.port-name", { "pc.class-" .. def.class }, { "pc.role-" .. def.role } },
    icon = "__pylon-transformers__/graphics/icons/" .. C.shell_name("up", 1, "small") .. ".png",
    icon_size = 128,
    flags = { "placeable-off-grid", "not-on-map", "not-blueprintable", "not-deconstructable",
              "not-repairable", "not-rotatable", "not-flammable", "hide-alt-info" },
    hidden = true,
    hidden_in_factoriopedia = true,
    max_health = 100,
    collision_box = { { -C.half_box, -C.half_box }, { C.half_box, C.half_box } },
    collision_mask = { layers = {} },
    selection_box = selection_box,
    selection_priority = C.port_priority,  -- above the shell (50), so the port can be picked at its end
    allow_copy_paste = false,
    maximum_wire_distance = shared.PORT_REACH,
    supply_area_distance = shared.PORT_SUPPLY_DISTANCE,
    auto_connect_up_to_n_wires = 0,
    rewire_neighbours_when_destroying = false,
    draw_copper_wires = true,
    draw_circuit_wires = false,
    pictures = {
      filename = EMPTY.filename,
      priority = EMPTY.priority,
      width = 1, height = 1,
      direction_count = 1,
    },
    connection_points = connection_points,
  }
end
data:extend(ports)
