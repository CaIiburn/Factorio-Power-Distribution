-- recipes.lua
-- Ingredient costs scale sub-linearly with capacity to keep large/high-tier
-- transformers expensive but not absurd. Adjust multipliers to taste.

local recipes = {}

-- Base ingredient "weight" per size class, before tier scaling.
-- These represent relative material complexity at the SAME tier.
local size_weight = {
  small  = 1.0,
  medium = 2.2,
  large  = 4.5,
}

-- Per-tier cost multiplier curve. Sub-linear (power^0.6) relative to the
-- tier's "large" capacity_w, normalized so tier 1 large = baseline 1.0.
-- This keeps tier 6 from requiring literally 3125x the raw materials of tier 1.
local function tier_cost_multiplier(tier_capacity_w, base_capacity_w)
  return (tier_capacity_w / base_capacity_w) ^ 0.6
end

-- Ingredient "recipe shape" per tier — which items unlock at which tier.
-- Swap these for your mod's actual item names.
local tier_ingredient_sets = {
  { "iron-plate",         "copper-plate" },                                    -- tier 1
  { "copper-plate",       "electronic-circuit" },                              -- tier 2
  { "steel-plate",        "electronic-circuit",   "copper-cable" },            -- tier 3
  { "steel-plate",        "advanced-circuit",     "copper-cable" },            -- tier 4
  { "advanced-circuit",   "processing-unit",      "steel-plate" },             -- tier 5
  { "processing-unit",    "low-density-structure","advanced-circuit" },        -- tier 6
}

-- Base amounts per ingredient at weight=1.0, tier multiplier=1.0.
-- Index matches position in tier_ingredient_sets[tier].
local base_amounts = {
  { 4, 2 },           -- tier 1: iron, copper
  { 6, 4 },           -- tier 2: copper, circuit
  { 8, 6, 4 },        -- tier 3: steel, circuit, cable
  { 10, 8, 6 },        -- tier 4: steel, adv-circuit, cable
  { 12, 6, 10 },       -- tier 5: adv-circuit, PU, steel
  { 8, 4, 10 },        -- tier 6: PU, LDS, adv-circuit
}

function recipes.generate(C)
  local out = {}  -- out[tier][size] = { {type=..., name=..., amount=...}, ... }

  local base_capacity_w = C.tiers[1].large.capacity_w  -- normalization anchor

  for tier, tier_data in ipairs(C.tiers) do
    out[tier] = {}
    local tier_mult = tier_cost_multiplier(tier_data.large.capacity_w, base_capacity_w)
    local ing_names = tier_ingredient_sets[tier]
    local amounts = base_amounts[tier]

    for _, size in ipairs(C.sizes) do
      local sw = size_weight[size]
      local ingredients = {}

      for i, ing_name in ipairs(ing_names) do
        local amount = math.ceil(amounts[i] * sw * tier_mult)
        table.insert(ingredients, { type = "item", name = ing_name, amount = amount })
      end

      out[tier][size] = ingredients
    end
  end

  return out
end

return recipes