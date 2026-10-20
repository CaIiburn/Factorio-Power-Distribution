-- Prototype generator. For every kind (up/down) and tier it creates:
--   1 visible shell entity  - what the player places, blueprints and upgrades
--   2 hidden energy halves  - input (buffered consumer) and output (buffered producer)
--   1 item and 1 recipe
-- plus one technology per tier at the end of the file.
local C = require("__pylon-transformers__.config")

-- Update interval from settings.lua; used to size buffers.
local N = settings.startup["pt-update-interval"].value
local interval_s = N / 60

-- Number to Factorio energy strings: power in W, buffer size in J.
local function W(x) return string.format("%.0fW", x) end
local function J(x) return string.format("%.0fJ", x) end

-- Human readable text for the tooltip fields.
local function fmt_power(w)
  if w >= 1e6 then return string.format("%g MW", w / 1e6) end
  if w >= 1e3 then return string.format("%g kW", w / 1e3) end
  return string.format("%g W", w)
end
local function fmt_pct(f) return string.format("%g %%", f * 100) end

-- Ingredients per tier (same cost for step-up and step-down).
local recipes = {
  [1] = { {type="item", name="iron-plate", amount=20}, {type="item", name="copper-plate", amount=30},
          {type="item", name="electronic-circuit", amount=10} },
  [2] = { {type="item", name="steel-plate", amount=20}, {type="item", name="copper-plate", amount=60},
          {type="item", name="advanced-circuit", amount=10} },
  [3] = { {type="item", name="steel-plate", amount=50}, {type="item", name="copper-plate", amount=150},
          {type="item", name="processing-unit", amount=10} },
}

-- Icons and sprites are generated placeholders under graphics/.
local function icon_path(name) return "__pylon-transformers__/graphics/icons/" .. name .. ".png" end

-- Prototype list, passed to data:extend once at the end of the loop.
local out = {}

for _, kind in ipairs(C.kinds) do
  for tier, t in ipairs(C.tiers) do
    local shell = C.shell_name(kind, tier)
    local icon = icon_path(shell)
    -- Rated output power. The input flow limit is a multiple of it (worst case).
    local rated = t.rated_w
    local in_limit = rated * C.input_limit_factor

    -- Lines shown in the entity tooltip. `order` must be an integer.
    local fields = {
      { name = {"pt-tooltip.max-output"},  value = fmt_power(rated),   order = 1 },
      { name = {"pt-tooltip.idle-loss"},   value = fmt_power(t.idle_w), order = 2 },
      { name = {"pt-tooltip.conv-loss"},   value = fmt_pct(t.conversion), order = 3 },
    }
    if kind == "down" then
      fields[#fields + 1] = { name = {"pt-tooltip.line-loss"},
                              value = fmt_pct(t.line_per_tile * 1000), order = 4 }
    end

    -- Fast replace and upgrade planner work through fast_replaceable_group and next_upgrade.
    -- Visible shell: the only thing the player ever sees / blueprints / upgrades.
    out[#out + 1] = {
      type = "simple-entity-with-owner",
      name = shell,
      icon = icon, icon_size = 64,
      flags = { "placeable-neutral", "player-creation", "not-rotatable" },
      minable = { mining_time = 0.3, result = shell },
      max_health = 250,
      collision_box = { { -1.85, -0.85 }, { 1.85, 0.85 } },
      selection_box = { { -2, -1 }, { 2, 1 } },
      picture = {
        filename = "__pylon-transformers__/graphics/entity/" .. shell .. ".png",
        width = 256, height = 128, scale = 0.5,
      },
      fast_replaceable_group = "pt-" .. kind,
      next_upgrade = (C.tiers[tier + 1] and C.shell_name(kind, tier + 1)) or nil,
      custom_tooltip_fields = fields,
      localised_description = {"entity-description.pt-" .. kind},
    }

    -- Settings shared by both hidden halves. They sit at the shell ends, have a tiny collision box and
    -- an empty collision mask (they never block building), and are hidden, unselectable and
    -- not blueprintable. Poles connect to them by supply-area overlap with the collision box.
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

    -- (The drain below is the constant idle loss, drawn from the connected network by the engine.)
    -- Input half: buffered consumer. Native engine drain = idle loss.
    local inp = table.deepcopy(half_common)
    inp.name = C.in_name(kind, tier)
    inp.energy_source = {
      type = "electric",
      usage_priority = "primary-input",
      buffer_capacity = J(in_limit * interval_s * C.buffer_safety),
      input_flow_limit = W(in_limit),
      output_flow_limit = "0W",
      drain = W(t.idle_w),
    }
    out[#out + 1] = inp

    -- (output_flow_limit is the hard cap on delivered power, i.e. the rated output in the tooltip.)
    -- Output half: buffered producer. output_flow_limit is the hard rated-power cap.
    local outp = table.deepcopy(half_common)
    outp.name = C.out_name(kind, tier)
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
      order = "e[pt]-" .. (kind == "up" and "a" or "b") .. "[" .. kind .. "]-" .. tier,
      place_result = shell,
      stack_size = 20,
    }

    out[#out + 1] = {
      type = "recipe",
      name = shell,
      enabled = false,
      energy_required = 5,
      ingredients = recipes[tier],
      results = { { type = "item", name = shell, amount = 1 } },
    }
  end
end

-- Register everything generated above.
data:extend(out)

-- (Recipes of both kinds in a tier are unlocked together; tiers chain through prerequisites.)
-- Technologies: one per tier, unlocks step-up and step-down recipes together.
local function unlocks(tier)
  return {
    { type = "unlock-recipe", recipe = C.shell_name("up", tier) },
    { type = "unlock-recipe", recipe = C.shell_name("down", tier) },
  }
end
local tech_icon = "__pylon-transformers__/graphics/technology/transformers.png"
data:extend({
  {
    type = "technology", name = "pt-transformers-1", icon = tech_icon, icon_size = 256,
    effects = unlocks(1), prerequisites = { "electric-energy-distribution-1" },
    unit = { count = 100, time = 30, ingredients = {
      { "automation-science-pack", 1 }, { "logistic-science-pack", 1 } } },
  },
  {
    type = "technology", name = "pt-transformers-2", icon = tech_icon, icon_size = 256,
    effects = unlocks(2), prerequisites = { "pt-transformers-1", "electric-energy-distribution-2" },
    unit = { count = 200, time = 30, ingredients = {
      { "automation-science-pack", 1 }, { "logistic-science-pack", 1 }, { "chemical-science-pack", 1 } } },
  },
  {
    type = "technology", name = "pt-transformers-3", icon = tech_icon, icon_size = 256,
    effects = unlocks(3), prerequisites = { "pt-transformers-2", "utility-science-pack" },
    unit = { count = 300, time = 30, ingredients = {
      { "automation-science-pack", 1 }, { "logistic-science-pack", 1 },
      { "chemical-science-pack", 1 }, { "utility-science-pack", 1 } } },
  },
})
