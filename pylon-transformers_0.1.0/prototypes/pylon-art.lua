-- The pylon: a 2x2 lattice tower. Sprite, shadow, wire attachment points and boxes of the huge
-- electric pole of the Electric Grid mod (supplied for this mod; see README, "Graphics").
--
--   graphics/entity/pt-pylon.png          592 x 420: four 148 x 420 frames (the four directions)
--   graphics/entity/pt-pylon-shadow.png   1680 x 148: four 420 x 148 frames
--
-- Both are drawn at scale 0.5 (high resolution: 64 px per tile). The wire points are given in
-- high resolution pixels like util.by_pixel_hr, and written out as tile offsets here.
local Art = {}

local function hr(x, y) return { x / 64, y / 64 } end

local ENTITY = "__pylon-transformers__/graphics/entity/"

Art.icon = "__pylon-transformers__/graphics/icons/pt-pylon.png"
Art.icon_size = 128

-- 2x2 tiles, like the feeder poles.
Art.collision_box = { { -0.85, -0.85 }, { 0.85, 0.85 } }
Art.selection_box = { { -1, -1 }, { 1, 1 } }
Art.drawing_box_vertical_extension = 4

Art.pictures = {
  layers = {
    {
      filename = ENTITY .. "pt-pylon.png",
      priority = "extra-high",
      width = 592 / 4,
      height = 420,
      scale = 0.5,
      direction_count = 4,
      shift = { 0, -70 / 32 },
    },
    {
      filename = ENTITY .. "pt-pylon-shadow.png",
      priority = "extra-high",
      width = 1680 / 4,
      height = 148,
      scale = 0.5,
      direction_count = 4,
      shift = { 74 / 32, 0 },
      draw_as_shadow = true,
    },
  },
}

Art.connection_points = {
  {
    shadow = { copper = hr(320, 0), red = hr(350, 3), green = hr(280, 3) },
    wire = { copper = hr(0, -300), red = hr(54, -290), green = hr(-56, -290) },
  },
  {
    shadow = { copper = hr(300, 10), red = hr(258, 46), green = hr(340, -38) },
    wire = { copper = hr(6, -286), red = hr(42, -252), green = hr(-40, -330) },
  },
  {
    shadow = { copper = hr(306, 0), red = hr(300, 58), green = hr(300, -56) },
    wire = { copper = hr(8, -290), red = hr(0, -230), green = hr(0, -344) },
  },
  {
    shadow = { copper = hr(306, 0), red = hr(330, 38), green = hr(260, -40) },
    wire = { copper = hr(4, -290), red = hr(-38, -256), green = hr(42, -328) },
  },
}

Art.water_reflection = {
  pictures = {
    filename = "__base__/graphics/entity/big-electric-pole/big-electric-pole-reflection.png",
    priority = "extra-high",
    width = 16,
    height = 32,
    shift = { 0, 70 / 32 },
    variation_count = 1,
    scale = 8,
  },
  rotate = false,
  orientation_to_variation = false,
}

-- The art is dark metal, so the tier colour is mixed towards white to keep it visible. `tint` is
-- the tier tint of poles.lua ({ r, g, b, a }).
function Art.tint(tint)
  local keep = 0.5
  return {
    r = 1 - (1 - tint.r) * keep,
    g = 1 - (1 - tint.g) * keep,
    b = 1 - (1 - tint.b) * keep,
    a = 1,
  }
end

return Art
