-- Prototype generator. For every kind (up/down), tier and size it creates:
--   1 visible shell entity  - a constant combinator: what the player places, blueprints, upgrades
--                             and wires up. control.lua writes load / power / temperature to it.
--   2 hidden energy halves  - input (buffered consumer) and output (buffered producer)
--   2 hidden heat pipes     - only for heat tiers (C.heat.tiers); horizontal and vertical variant
--   1 item (hidden for the sizes other than C.item_size) and, for C.item_size only, 1 recipe
-- plus the virtual signals and one technology per tier.
--
-- The two hidden connection poles of a transformer (its ports) are shared prototypes defined in
-- prototypes/ports.lua; which port sits on which end is set by C.ports.
local C = require("__pylon-transformers__.config")
local Recipes = require("__pylon-transformers__.recipes")
local Technologies = require("__pylon-transformers__.technologies")
local Sprites = require("__pylon-transformers__.sprites")  -- ported Electric Grid art, see THIRD_PARTY_LICENSE.txt
local recipes = Recipes.generate(C)

-- Update interval from settings.lua; used to size buffers.
local N = settings.startup["pt-update-interval"].value
local interval_s = N / 60

-- Number to Factorio energy strings: power in W, buffer size in J.
local function W(x) return string.format("%.0fW", x) end
local function J(x) return string.format("%.0fJ", x) end

-- Human readable text for the tooltip fields.
local function fmt_power(w)
  if w >= 1e9 then return string.format("%.4g GW", w / 1e9) end
  if w >= 1e6 then return string.format("%.4g MW", w / 1e6) end
  if w >= 1e3 then return string.format("%.4g kW", w / 1e3) end
  return string.format("%.4g W", w)
end
local function fmt_pct(f) return string.format("%.3g %%", f * 100) end
-- "1.05 MW (5.25 %)": a power and what share of the rated output it is.
local function fmt_power_pct(w, rated) return fmt_power(w) .. " (" .. fmt_pct(w / rated) .. ")" end
local function fmt_temp(c) return string.format("%g °C", c) end

-- Icons (128 px, tinted, with tier and size badge) and sprites (see sprites.lua) are under graphics/.
local function icon_path(name) return "__pylon-transformers__/graphics/icons/" .. name .. ".png" end

-- Returns the prototype name only when that prototype exists, so a missing effect cannot stop
-- the game from loading.
local function existing(type_name, name)
  local list = data.raw[type_name]
  return (name and list and list[name]) and name or nil
end

local EMPTY = { filename = "__core__/graphics/empty.png", priority = "extra-high", width = 1, height = 1 }

local function empty_sprite_4way()
  return { north = EMPTY, east = EMPTY, south = EMPTY, west = EMPTY }
end

-- heat-pipe prototypes insist on connection and glow graphics for every neighbour layout.
local CONNECTABLE_KEYS = {
  "single", "straight_vertical", "straight_horizontal",
  "corner_right_down", "corner_left_down", "corner_right_up", "corner_left_up",
  "t_up", "t_down", "t_right", "t_left",
  "ending_up", "ending_down", "ending_right", "ending_left", "cross",
}
local function empty_connectable_graphics()
  local g = {}
  for _, key in ipairs(CONNECTABLE_KEYS) do g[key] = { EMPTY } end
  return g
end

-- Heat connections on the two LONG sides, one per tile.
--   horizontal (shell facing east/west):   4x2 tiles, connections on the top and bottom row
--   vertical   (shell facing north/south): 2x4 tiles, connections on the left and right column
-- Positions are tile centres relative to the entity centre.
local function heat_connections(vertical)
  local connections = {}
  for i = 0, 3 do
    local p = -1.5 + i
    if vertical then
      connections[#connections + 1] = { position = { -0.5, p }, direction = defines.direction.west }
      connections[#connections + 1] = { position = {  0.5, p }, direction = defines.direction.east }
    else
      connections[#connections + 1] = { position = { p, -0.5 }, direction = defines.direction.north }
      connections[#connections + 1] = { position = { p,  0.5 }, direction = defines.direction.south }
    end
  end
  return connections
end

-- Circuit wire attachment points for the four directions (north, east, south, west). Defined for
-- the 4x2 view (facing east: on the top long side, near the centre) and turned clockwise for the
-- other directions, so facing north is that view turned three times.
local function turn(p, steps)
  local x, y = p[1], p[2]
  for _ = 1, steps do x, y = -y, x end
  return { x, y }
end

local function wire_points()
  local points = {}
  for dir = 0, 3 do
    local steps = (dir - 1) % 4
    local red, green = turn({ -0.3, -0.6 }, steps), turn({ 0.3, -0.6 }, steps)
    points[dir + 1] = {
      wire = { red = red, green = green },
      shadow = {
        red   = { red[1] + 0.15,   red[2] + 0.15 },
        green = { green[1] + 0.15, green[2] + 0.15 },
      },
    }
  end
  return points
end

-- Prototype list, passed to data:extend once at the end of the loop.
local out = {}

---------------------------------------------------------------------------------------------------
-- Virtual signals (placeholder icon: the small tier-1 step-up transformer, tinted)
---------------------------------------------------------------------------------------------------

out[#out + 1] = {
  type = "item-subgroup",
  name = "pt-signals",
  group = "signals",
  order = "z[pt]",
}

local function signal(name, order, tint)
  return {
    type = "virtual-signal",
    name = name,
    icons = { { icon = icon_path(C.shell_name("up", 1, "small")), icon_size = 128, tint = tint } },
    subgroup = "pt-signals",
    order = order,
  }
end

out[#out + 1] = signal(C.signal.load,        "a[load]",        { r = 1.0, g = 0.85, b = 0.3, a = 1 })
out[#out + 1] = signal(C.signal.power,       "b[power]",       { r = 0.4, g = 0.8,  b = 1.0, a = 1 })
out[#out + 1] = signal(C.signal.temperature, "c[temperature]", { r = 1.0, g = 0.4,  b = 0.3, a = 1 })

---------------------------------------------------------------------------------------------------
-- Transformers
---------------------------------------------------------------------------------------------------

-- Hidden entities: not selectable, not blueprintable, no collision.
local hidden_flags = { "placeable-off-grid", "not-on-map", "not-blueprintable", "not-deconstructable",
                       "not-repairable", "not-rotatable", "not-flammable" }

for _, kind in ipairs(C.kinds) do
  for tier, tier_data in ipairs(C.tiers) do
    for size_index, size in ipairs(C.sizes) do
      local t = tier_data[size]  -- { capacity_w, idle_w, full_w, heat? }
      local h = t.heat           -- nil for tiers without the heat mechanic
      local shell = C.shell_name(kind, tier, size)
      local icon = icon_path(shell)

      -- Rated output power. The input flow limit is ouput + full load losses.
      local rated = t.capacity_w
      local idle_w = t.idle_w
      local in_limit = rated + t.full_w

      -- Lines shown in the entity tooltip. `order` must be an integer.
      local fields = {
        { name = {"pt-tooltip.max-output"},     value = fmt_power(rated),                   order = 1 },
        { name = {"pt-tooltip.idle-loss"},      value = fmt_power_pct(idle_w, rated),       order = 2 },
        -- full_w is the TOTAL loss at full load, idle loss included
        { name = {"pt-tooltip.full-load-loss"}, value = fmt_power_pct(t.full_w, rated),     order = 3 },
      }
      local description = { "", {"entity-description.pt-" .. kind}, "\n", {"entity-description.pt-power"},
                            "\n", {"entity-description.pt-circuit"} }
      if h then
        fields[#fields + 1] = { name = {"pt-tooltip.cool-load"},    value = fmt_pct(C.heat.cool_load), order = 4 }
        fields[#fields + 1] = { name = {"pt-tooltip.explode-temp"}, value = fmt_temp(h.explode_c),     order = 5 }
        fields[#fields + 1] = { name = {"pt-tooltip.radiators"},    value = tostring(h.radiators),     order = 6 }
        description[#description + 1] = "\n"
        description[#description + 1] = {"entity-description.pt-heat"}
      end

      -- Visible shell: the only thing the player ever sees / blueprints / upgrades / wires.
      -- It is a constant combinator because only that entity type can carry circuit wires and
      -- hold signals; control.lua owns its contents and disables the GUI (operable = false).
      --
      -- Fast replace and upgrade planner work through fast_replaceable_group and next_upgrade (see
      -- below); the size is kept by scripts/transformer/upgrades.lua.
      --
      -- Rotation: the prototype is rotatable (no "not-rotatable" flag), so the cursor, blueprints
      -- and R on a placed entity rotate it in 90 degree steps and the collision box turns with it.
      -- The base view (north) is 2x4 and the output end is where the shell faces, because that is
      -- what the game assumes when it flips a blueprint (see OUTPUT_VECTOR in common.lua).
      -- control.lua moves the hidden halves (and heat pipe) to the matching ends.
      out[#out + 1] = {
        type = "constant-combinator",
        name = shell,
        icon = icon, icon_size = 128,
        flags = { "placeable-neutral", "player-creation" },
        minable = { mining_time = 0.3, result = C.item_name(tier) },
        -- Every size is built from (and gives back) the one item: pipette, blueprints and ghosts too.
        placeable_by = { item = C.item_name(tier), count = 1 },
        max_health = 250,
        dying_explosion = existing("explosion", C.explosion_effect[size]),
        collision_box = { { -0.85, -1.85 }, { 0.85, 1.85 } },
        selection_box = { { -1, -2 }, { 1, 2 } },
        drawing_box_vertical_extension = 1.3,  -- the bushings stick out above the 2x4 footprint
        sprites = Sprites.shell(kind, tier, size_index),
        activity_led_sprites = empty_sprite_4way(),
        activity_led_light_offsets = { { 0, 0 }, { 0, 0 }, { 0, 0 }, { 0, 0 } },
        circuit_wire_connection_points = wire_points(),
        circuit_wire_max_distance = 9,
        -- All kinds and sizes are one fast replace group, and the upgrade planner always builds the
        -- small step-up transformer of the next tier (the only one that has a placing item);
        -- upgrades.lua gives it back the kind and size it had.
        fast_replaceable_group = "pt-transformer",
        next_upgrade = (C.tiers[tier + 1] and C.item_name(tier + 1)) or nil,
        custom_tooltip_fields = fields,
        localised_description = description,
      }

      -- Settings shared by both hidden halves.
      local half_common = {
        type = "electric-energy-interface",
        icon = icon, icon_size = 128,
        flags = hidden_flags,
        hidden = true,
        hidden_in_factoriopedia = true,
        selectable_in_game = false,
        collision_box = { { -C.half_box, -C.half_box }, { C.half_box, C.half_box } },
        collision_mask = { layers = {} },
        allow_copy_paste = false,
      }

      -- Input half: buffered consumer. Native engine drain = idle loss. The script sets its power
      -- usage (output rate plus conversion loss), see scripts/transformer/transfer.lua.
      local inp = table.deepcopy(half_common)
      inp.name = C.in_name(kind, tier, size)
      inp.energy_source = {
        type = "electric",
        usage_priority = "primary-input",
        buffer_capacity = J(in_limit / 60 * (N + C.control.input_extra_ticks)),
        input_flow_limit = W(in_limit),
        output_flow_limit = "0W",
        drain = W(idle_w),
      }
      out[#out + 1] = inp

      -- Output half: buffered producer. output_flow_limit is the hard rated-power cap. The script
      -- sets its power production, the buffer between the two is sized in config.lua (C.control).
      local outp = table.deepcopy(half_common)
      outp.name = C.out_name(kind, tier, size)
      outp.energy_source = {
        type = "electric",
        usage_priority = "primary-output",
        buffer_capacity = J(rated * math.max(C.control.min_buffer_ticks / 60, interval_s / C.control.target)),
        input_flow_limit = "0W",
        output_flow_limit = W(rated),
        drain = "0W",
      }
      out[#out + 1] = outp

      -- Hidden heat pipes (heat tiers only). The heat buffer holds the temperature; the engine
      -- shares heat with connected heat pipes, control.lua adds the waste heat and the passive
      -- cooling. max_temperature sits above the explosion temperature so the script can see it.
      if h then
        for _, vertical in ipairs({ false, true }) do
          local box = vertical
            and { { -0.85, -1.85 }, { 0.85, 1.85 } }
             or { { -1.85, -0.85 }, { 1.85, 0.85 } }
          out[#out + 1] = {
            type = "heat-pipe",
            name = C.heat_name(kind, tier, size, vertical),
            icon = icon, icon_size = 128,
            flags = { "not-on-map", "not-blueprintable", "not-deconstructable",
                      "not-repairable", "not-rotatable", "not-flammable" },
            hidden = true,
            hidden_in_factoriopedia = true,
            selectable_in_game = false,
            collision_box = box,
            collision_mask = { layers = {} },
            allow_copy_paste = false,
            heat_buffer = {
              max_temperature = h.max_c,
              default_temperature = C.heat.ambient,
              specific_heat = J(h.specific_heat),
              max_transfer = "1GW",
              connections = heat_connections(vertical),
            },
            connection_sprites = empty_connectable_graphics(),
            heat_glow_sprites = empty_connectable_graphics(),
          }
        end
      end

      -- The item of C.item_kind / C.item_size is the one the player sees; the others are hidden
      -- legacy items.
      local visible = (kind == C.item_kind and size == C.item_size)
      local item = {
        type = "item",
        name = shell,
        icon = icon, icon_size = 128,
        subgroup = "energy",
        order = "e[pt]-" .. (kind == "up" and "a" or "b")
                .. "[" .. kind .. "]-" .. tier .. "-" .. size,
        place_result = shell,
        stack_size = 20,
      }
      if visible then
        item.localised_name = { "pt-item-name.transformer", tostring(tier) }
        item.localised_description = { "item-description.pt-choose-size" }
      else
        item.hidden = true
        item.hidden_in_factoriopedia = true
      end
      out[#out + 1] = item

      if visible then
        out[#out + 1] = {
          type = "recipe",
          name = shell,
          localised_name = { "pt-item-name.transformer", tostring(tier) },
          enabled = false,
          energy_required = 5,
          ingredients = recipes[tier][C.recipe_size],
          results = { { type = "item", name = shell, amount = 1 } },
        }
      end
    end
  end
end

local techs = Technologies.generate(C)
for _, tech in ipairs(techs) do
  out[#out + 1] = tech
end

-- Register everything generated above.
data:extend(out)
