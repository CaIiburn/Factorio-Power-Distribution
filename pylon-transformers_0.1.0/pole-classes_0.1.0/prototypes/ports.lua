local shared = require("shared")

-- Hidden poles that live inside transformers. They are never placed by
-- players. The transformer mod creates one per side and wires external
-- poles of the matching class to it.
local ports = {}
for _, def in ipairs(shared.PORTS) do
  ports[#ports + 1] = {
    type = "electric-pole",
    name = def.name,
    localised_name = { "pc.port-name", { "pc.class-" .. def.class }, { "pc.role-" .. def.role } },
    icon = (data.raw.item["small-electric-pole"] or {}).icon,
    icon_size = (data.raw.item["small-electric-pole"] or {}).icon_size or 64,
    flags = { "placeable-neutral", "not-repairable", "not-on-map", "not-blueprintable",
              "not-deconstructable", "hide-alt-info" },
    hidden = true,
    hidden_in_factoriopedia = true,
    collision_box = { { -0.1, -0.1 }, { 0.1, 0.1 } },
    collision_mask = { layers = {} },
    selection_box = { { -0.35, -0.35 }, { 0.35, 0.35 } },
    selection_priority = 80,
    maximum_wire_distance = shared.PORT_REACH,
    supply_area_distance = shared.PORT_SUPPLY_DISTANCE,
    auto_connect_up_to_n_wires = 0,
    rewire_neighbours_when_destroying = false,
    draw_copper_wires = true,
    pictures = {
      filename = "__core__/graphics/empty.png",
      priority = "extra-high",
      width = 1, height = 1,
      direction_count = 1,
    },
    connection_points = { { shadow = { copper = { 0, 0 } }, wire = { copper = { 0, 0 } } } },
  }
end
data:extend(ports)
