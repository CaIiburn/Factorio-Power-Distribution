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
local C = require("__pylon-transformers__.config")
local shared = C.pole

local EMPTY = { filename = "__core__/graphics/empty.png", priority = "extra-high", width = 1, height = 1 }

local ports = {}
for _, def in ipairs(shared.PORTS) do
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
    selection_box = { { -C.port_select, -C.port_select }, { C.port_select, C.port_select } },
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
    connection_points = { { shadow = { copper = { 0, 0 } }, wire = { copper = { 0, 0 } } } },
  }
end
data:extend(ports)
