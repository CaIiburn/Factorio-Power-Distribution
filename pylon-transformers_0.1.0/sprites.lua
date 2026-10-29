-- Entity sprites for the transformer shells.
--
-- Art ported from the "Electric Grid" mod by 0n0w1c (MIT, see THIRD_PARTY_LICENSE.txt):
-- one sheet per layer, 4 frames of 466x310 px (hi-res, scale 0.5):
--   transformer-sprites.png   body                      transformer-shadows.png   shadow
--   transformer-mask.png      three stripes, tinted per tier (additive)
--   transformer-overlay.png   plug mark (low voltage side) and bolt mark (high voltage side)
--   transformer-labels.png    tier digit and size letter, normal blend (made by tools/port_graphics.py)
--
-- Frames in the sheets: 0 and 2 are the wide views (4x2 tiles), 1 and 3 are the tall views (2x4 tiles).
--   frame 0: plug left,  bolt right (tall bushing on the right)     frame 2: bolt left, plug right
--   frame 1: plug at the bottom (bolt end on top)                   frame 3: bolt at the bottom
-- The plug is the low voltage end, the bolt is the high voltage end.
--
-- The output end is where the shell faces (the game flips blueprints on that assumption), so the
-- wide views are east (input left, output right) and west, the tall views north (output on top) and
-- south:
--   "up"   (low in, high out): east = 0, south = 3, west = 2, north = 1
--   "down" (high in, low out): east = 2, south = 1, west = 0, north = 3

local M = {}

local GFX = "__pylon-transformers__/graphics/entity/"
local FW, FH = 466, 310
local LABEL_W, LABEL_H = 64, 48

local FRAME_OF = {
  up   = { east = 0, south = 3, west = 2, north = 1 },
  down = { east = 2, south = 1, west = 0, north = 3 },
}

-- Measured from the sheets (hi-res px): cx = horizontal centre of the body, bottom = lowest body row.
-- digit / letter = where the tier digit and size letter are drawn inside the frame.
-- Wide frames sit on the stripes, tall frames on the end panel below the plug / bolt mark.
local FRAMES = {
  [0] = { cx = 132, bottom = 297, target = 68,  digit = { 113.5, 254 }, letter = { 149.5, 258 } },
  [1] = { cx = 69,  bottom = 301, target = 120, digit = { 50, 272 },    letter = { 86, 276 } },
  [2] = { cx = 137, bottom = 299, target = 68,  digit = { 119, 254 },   letter = { 155, 258 } },
  [3] = { cx = 67,  bottom = 299, target = 120, digit = { 50, 272 },    letter = { 86, 276 } },
}
-- target: where the lowest body row ends up below the entity centre (hi-res px), a little past the
-- collision box like the original (wide: 64 + 4, tall: 120 ~ 1.875 tiles).

local function frame_shift(f)
  local d = FRAMES[f]
  return { (FW / 2 - d.cx) / 64, (d.target - (d.bottom - FH / 2)) / 64 }
end

-- Where the wires attach: the top of the knob of each bushing, in hi-res px inside the frame
-- (measured on the body sheet). Wide frames have a bushing on the left and one on the right, tall
-- frames one at the top (far end) and one at the bottom (near end).
local ATTACH = {
  [0] = { left = { 50, 117 },  right  = { 218, 95 } },
  [1] = { top  = { 65, 13 },   bottom = { 68, 126 } },
  [2] = { left = { 43, 93 },   right  = { 217, 122 } },
  [3] = { top  = { 69, 40 },   bottom = { 68, 108 } },
}
-- Which bushing is the output end of a shell facing `dir` (the output end is where it faces), and
-- which one the input end.
local END_OF = {
  east  = { out = "right",  ["in"] = "left"   },
  west  = { out = "left",   ["in"] = "right"  },
  north = { out = "top",    ["in"] = "bottom" },
  south = { out = "bottom", ["in"] = "top"    },
}

-- Wire attachment point of the `role` ("in" / "out") end of a transformer of `kind` facing `dir`
-- ("north" / "east" / "south" / "west"), in tiles from the centre of the shell, on the sprite that
-- is drawn for that kind and direction.
function M.attach(kind, dir, role)
  local f = FRAME_OF[kind][dir]
  local p = ATTACH[f][END_OF[dir][role]]
  local shift = frame_shift(f)
  return { shift[1] + (p[1] - FW / 2) / 64, shift[2] + (p[2] - FH / 2) / 64 }
end

-- Tier tints (additive on the mask). Same colours as the original mod, wraps if there are more tiers.
local TIER_TINTS = {
  { r = 1.0, g = 0.0,  b = 0.0 },  -- red
  { r = 1.0, g = 0.5,  b = 0.0 },  -- orange
  { r = 1.0, g = 0.85, b = 0.2 },  -- gold
  { r = 1.0, g = 1.0,  b = 0.0 },  -- yellow
  { r = 0.0, g = 1.0,  b = 0.0 },  -- green
  { r = 0.0, g = 1.0,  b = 1.0 },  -- cyan
  { r = 0.0, g = 0.5,  b = 1.0 },  -- blue
  { r = 0.5, g = 0.0,  b = 1.0 },  -- violet
  { r = 1.0, g = 0.0,  b = 1.0 },  -- magenta
}
M.TIER_TINTS = TIER_TINTS

local OVERLAY_TINT = { r = 0.5, g = 0.5, b = 0.5, a = 1 }
local N_DIGITS = 9
local N_SIZE_LETTERS = 4  -- S, M, L, XL (rows 10 to 13 of transformer-labels.png)

local function label_layer(f, row, pos, shift)
  return {
    filename = GFX .. "transformer-labels.png",
    x = f * LABEL_W, y = row * LABEL_H,
    width = LABEL_W, height = LABEL_H,
    scale = 0.5,
    shift = { shift[1] + (pos[1] - FW / 2) / 64, shift[2] + (pos[2] - FH / 2) / 64 },
  }
end

local function direction_sprite(kind, dir, tier, size_index)
  local f = FRAME_OF[kind][dir]
  local shift = frame_shift(f)
  local function sheet(name, extra)
    local l = {
      filename = GFX .. "transformer-" .. name .. ".png",
      x = f * FW, width = FW, height = FH,
      shift = shift, scale = 0.5,
    }
    for k, v in pairs(extra or {}) do l[k] = v end
    return l
  end
  local tint = TIER_TINTS[(tier - 1) % #TIER_TINTS + 1]
  return {
    layers = {
      sheet("sprites"),
      sheet("shadows", { draw_as_shadow = true }),
      sheet("mask", { blend_mode = "additive", tint = { r = tint.r, g = tint.g, b = tint.b, a = 1 } }),
      sheet("overlay", { blend_mode = "additive", tint = OVERLAY_TINT }),
      label_layer(f, (tier - 1) % N_DIGITS, FRAMES[f].digit, shift),
      label_layer(f, N_DIGITS + math.min(size_index, N_SIZE_LETTERS) - 1, FRAMES[f].letter, shift),
    },
  }
end

-- Sprite4Way for one shell. size_index is the position of the size in C.sizes (1 = S, 2 = M, ...).
function M.shell(kind, tier, size_index)
  return {
    north = direction_sprite(kind, "north", tier, size_index),
    east  = direction_sprite(kind, "east",  tier, size_index),
    south = direction_sprite(kind, "south", tier, size_index),
    west  = direction_sprite(kind, "west",  tier, size_index),
  }
end

return M
