-- Input events, the wire audit / rewire tool and its shortcut.
local ref_item = data.raw.item["medium-electric-pole"] or data.raw.item["small-electric-pole"] or {}
local icon = ref_item.icon
local icon_size = ref_item.icon_size or 64
local tint = { r = 1, g = 0.85, b = 0.3, a = 1 }

data:extend({
  {
    type = "custom-input",
    name = "pc-break-line",
    key_sequence = "ALT + L",
    action = "lua",
    localised_name = { "pc.input-break-line" },
  },
  {
    type = "selection-tool",
    name = "pc-wire-tool",
    localised_name = { "pc.tool-name" },
    localised_description = { "pc.tool-desc" },
    icons = { { icon = icon, icon_size = icon_size, tint = tint } },
    flags = { "only-in-cursor", "spawnable", "not-stackable" },
    hidden = true,
    hidden_in_factoriopedia = true,
    subgroup = "tool",
    order = "z[pole-classes]",
    stack_size = 1,
    select = {
      border_color = { r = 0.3, g = 0.7, b = 1 },
      cursor_box_type = "entity",
      mode = { "any-entity" },
      entity_type_filters = { "electric-pole" },
    },
    alt_select = {
      border_color = { r = 1, g = 0.7, b = 0.2 },
      cursor_box_type = "entity",
      mode = { "any-entity" },
      entity_type_filters = { "electric-pole" },
    },
  },
  {
    type = "shortcut",
    name = "pc-wire-tool",
    localised_name = { "pc.tool-name" },
    order = "b[blueprints]-z[pole-classes]",
    action = "spawn-item",
    item_to_spawn = "pc-wire-tool",
    technology_to_unlock = "pc-poles-1",
    style = "blue",
    icons = { { icon = icon, icon_size = icon_size, tint = tint } },
    small_icons = { { icon = icon, icon_size = icon_size, tint = tint } },
  },
})
