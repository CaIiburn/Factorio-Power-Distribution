-- Prototype generator. For every kind (up/down) and tier it creates:
--   1 visible shell entity  - what the player places, blueprints and upgrades
--   2 hidden energy halves  - input (buffered consumer) and output (buffered producer)
--   1 item and 1 recipe
-- plus one technology per tier at the end of the file.
local C = require("config")
local Recipes = require("recipes")
local Technologies = require("technologies")
local recipes = Recipes.generate(C)

-- Update interval from settings.lua; used to size buffers.
local N = settings.startup["pt-update-interval"].value
local interval_s = N / 60

-- Number to Factorio energy strings: power in W, buffer size in J.
local function W(x) return string.format("%.0fW", x) end
local function J(x) return string.format("%.0fJ", x) end

-- Human readable text for the tooltip fields.
local function fmt_power(w)
  if w >= 1e9 then return string.format("%g GW", w / 1e6) end
  if w >= 1e6 then return string.format("%g MW", w / 1e6) end
  if w >= 1e3 then return string.format("%g kW", w / 1e3) end
  return string.format("%g W", w)
end
local function fmt_pct(f) return string.format("%g %%", f * 100) end

-- Icons and sprites are generated placeholders under graphics/.
local function icon_path(name) return "__pylon-transformers__/graphics/icons/" .. name .. ".png" end

-- One sprite per direction. north is the base image (4x2 tiles, input left, output right);
-- east/south/west are that image rotated clockwise by 90/180/270 degrees, so east and west are
-- 2x4 tiles. tools/make_rotated_graphics.py generates them from the north image.
local function entity_sprite(shell, suffix, width, height)
  return {
    filename = "__pylon-transformers__/graphics/entity/" .. shell .. suffix .. ".png",
    width = width, height = height, scale = 0.5,
  }
end

-- Prototype list, passed to data:extend once at the end of the loop.
local out = {}

for _, kind in ipairs(C.kinds) do
  for tier, tier_data in ipairs(C.tiers) do
    for _, size in ipairs(C.sizes) do
      local t = tier_data[size]  -- { capacity_w, idle_w, full_w }
      local shell = C.shell_name(kind, tier, size)
      local icon = icon_path(shell)

      -- Rated output power. The input flow limit is ouput + full load losses.
      local rated = t.capacity_w
      local idle_w = t.idle_w
      local in_limit = rated + t.full_w

      -- Conversion loss shown in tooltip: the ADDITIONAL loss on top of idle at 100% load.
      -- (full_w already includes idle_w, per the shared datatable convention.)
      local conv_loss_w = t.full_w - t.idle_w
      local conv_pct = conv_loss_w / rated * 100

      -- Lines shown in the entity tooltip. `order` must be an integer.
      local fields = {
        { name = {"pt-tooltip.max-output"},  value = fmt_power(rated),   order = 1 },
        { name = {"pt-tooltip.idle-loss"},   value = fmt_power(idle_w),  order = 2 },
        { name = {"pt-tooltip.conv-loss"},   value = fmt_pct(conv_pct),  order = 3 },
      }

      -- Fast replace and upgrade planner work through fast_replaceable_group and next_upgrade.
      -- Visible shell: the only thing the player ever sees / blueprints / upgrades.
      -- Note: fast_replaceable_group and next_upgrade are both scoped to kind+size,
      -- so upgrading only ever advances tier, never jumps size class.
      --
      -- Rotation: the prototype is rotatable (no "not-rotatable" flag), so the cursor, blueprints
      -- and R on a placed entity rotate it in 90 degree steps and the collision box turns with it.
      -- control.lua moves the hidden halves to the matching ends.
      out[#out + 1] = {
        type = "simple-entity-with-owner",
        name = shell,
        icon = icon, icon_size = 64,
        flags = { "placeable-neutral", "player-creation" },
        minable = { mining_time = 0.3, result = shell },
        max_health = 250,
        collision_box = { { -1.85, -0.85 }, { 1.85, 0.85 } },
        selection_box = { { -2, -1 }, { 2, 1 } },
        picture = {
          north = entity_sprite(shell, "",       256, 128),
          east  = entity_sprite(shell, "-east",  128, 256),
          south = entity_sprite(shell, "-south", 256, 128),
          west  = entity_sprite(shell, "-west",  128, 256),
        },
        fast_replaceable_group = "pt-" .. kind .. "-" .. size,
        next_upgrade = (C.tiers[tier + 1] and C.shell_name(kind, tier + 1, size)) or nil,
        custom_tooltip_fields = fields,
        localised_description = {"entity-description.pt-" .. kind},
      }

      -- Settings shared by both hidden halves. Unchanged from before.
      local half_common = {
        type = "electric-energy-interface",
        icon = icon, icon_size = 64,
        flags = { "placeable-off-grid", "not-on-map", "not-blueprintable", "not-deconstructable",
                  "not-repairable", "not-rotatable", "not-flammable" },
        hidden = true,
        hidden_in_factoriopedia = true,
        selectable_in_game = false,
        collision_box = { { -C.half_box, -C.half_box }, { C.half_box, C.half_box } },
        collision_mask = { layers = {} },
        allow_copy_paste = false,
      }

      -- Input half: buffered consumer. Native engine drain = idle loss.
      -- (Conversion/copper loss is NOT representable here since `drain` is constant —
      --  it must be applied by a control.lua script reading actual throughput per tick
      --  and topping up consumption beyond what drain alone covers. See note below.)
      local inp = table.deepcopy(half_common)
      inp.name = C.in_name(kind, tier, size)
      inp.energy_source = {
        type = "electric",
        usage_priority = "primary-input",
        buffer_capacity = J(in_limit * interval_s * C.buffer_safety),
        input_flow_limit = W(in_limit),
        output_flow_limit = "0W",
        drain = W(idle_w),
      }
      out[#out + 1] = inp

      -- Output half: buffered producer. output_flow_limit is the hard rated-power cap.
      local outp = table.deepcopy(half_common)
      outp.name = C.out_name(kind, tier, size)
      outp.energy_source = {
        type = "electric",
        usage_priority = "primary-output",
        buffer_capacity = J(rated * interval_s * C.buffer_safety),
        input_flow_limit = "0W",
        output_flow_limit = W(rated),
        drain = "0W",
      }
      out[#out + 1] = outp

      out[#out + 1] = {
        type = "item",
        name = shell,
        icon = icon, icon_size = 64,
        subgroup = "energy",
        order = "e[pt]-" .. (kind == "up" and "a" or "b")
                .. "[" .. kind .. "]-" .. tier .. "-" .. size,
        place_result = shell,
        stack_size = 20,
      }

      out[#out + 1] = {
        type = "recipe",
        name = shell,
        enabled = false,
        energy_required = 5,
        ingredients = recipes[tier][size],
        results = { { type = "item", name = shell, amount = 1 } },
      }
    end
  end
end

local techs = Technologies.generate(C)
for _, tech in ipairs(techs) do
  out[#out + 1] = tech
end

-- Register everything generated above.
data:extend(out)
