-- Graphics / icon helpers: every building reuses a vanilla prototype's sprites, tinted and scaled.
local util = require("__core__.lualib.util")
local U = {}

U.deepcopy = util.table.deepcopy

local function is_graphic(t)
  return t.filename ~= nil or t.filenames ~= nil or t.stripes ~= nil
end

local function scale_shift(shift, f)
  if shift[1] ~= nil then return { shift[1] * f, shift[2] * f } end
  return { x = (shift.x or 0) * f, y = (shift.y or 0) * f }
end

-- Scale and tint every sprite/animation reachable from `root`.
-- Iterative (explicit stack) on purpose: Factorio's Lua limits recursion depth to ~200 levels and the
-- vanilla graphics tables can nest deeper than that. `seen` guards against shared sub-tables
-- (deepcopy preserves sharing; without the guard a shared sprite would be scaled twice).
function U.restyle(root, factor, tint)
  if type(root) ~= "table" then return root end
  local seen = {}
  local stack, n = { root }, 1
  while n > 0 do
    local t = stack[n]
    stack[n] = nil
    n = n - 1
    if not seen[t] then
      seen[t] = true
      if is_graphic(t) then
        if factor and factor ~= 1 then
          t.scale = (t.scale or 1) * factor
          if type(t.shift) == "table" then t.shift = scale_shift(t.shift, factor) end
        end
        if tint and not (t.draw_as_shadow or t.draw_as_glow or t.draw_as_light) then
          t.tint = tint
        end
      else
        for _, v in pairs(t) do
          if type(v) == "table" and not seen[v] then
            n = n + 1
            stack[n] = v
          end
        end
      end
    end
  end
  return root
end

local function scale_xy(v, f)
  if v[1] ~= nil then return { v[1] * f, v[2] * f } end
  return { x = (v.x or 0) * f, y = (v.y or 0) * f }
end

-- Scale the positions inside a circuit-connector definition (sprite `shift`s and wire / shadow attach
-- points) so a connector stays on the edge of a building that is resized. Iterative, like restyle.
function U.scale_connector_positions(root, factor)
  if type(root) ~= "table" or factor == 1 then return root end
  local seen = {}
  local stack, n = { root }, 1
  while n > 0 do
    local t = stack[n]
    stack[n] = nil
    n = n - 1
    if not seen[t] then
      seen[t] = true
      for k, v in pairs(t) do
        if type(v) == "table" then
          if k == "shift" then
            t[k] = scale_xy(v, factor)
          elseif k == "wire" or k == "shadow" then
            for color, pos in pairs(v) do
              if type(pos) == "table" then v[color] = scale_xy(pos, factor) end
            end
          elseif not seen[v] then
            n = n + 1
            stack[n] = v
          end
        end
      end
    end
  end
  return root
end

-- IconData list copied from a vanilla prototype and tinted.
function U.icons_of(proto, tint, default_size)
  local out = {}
  if proto and proto.icons then
    for _, ic in ipairs(proto.icons) do
      local c = util.table.deepcopy(ic)
      c.icon_size = c.icon_size or proto.icon_size or default_size or 64
      if tint then c.tint = tint end
      out[#out + 1] = c
    end
  elseif proto and proto.icon then
    out[1] = { icon = proto.icon, icon_size = proto.icon_size or default_size or 64, tint = tint }
  else
    out[1] = { icon = "__base__/graphics/icons/iron-plate.png", icon_size = 64, tint = tint }
  end
  return out
end

function U.icons_of_item(name, tint)  return U.icons_of(data.raw.item[name], tint) end
function U.icons_of_fluid(name, tint) return U.icons_of(data.raw.fluid[name], tint) end
function U.tech_icons(name, tint)     return U.icons_of(data.raw.technology[name], tint, 256) end
function U.color(r, g, b) return { r = r, g = g, b = b } end

-- Shorthand {"item"|"fluid", name, amount[, temperature[, independent_probability]]} -> Ingredient/Product prototypes.
function U.stacks(list)
  local out = {}
  for _, e in ipairs(list) do
    out[#out + 1] = { type = e[1], name = e[2], amount = e[3], temperature = e[4], independent_probability = e[5] }
  end
  return out
end

return U
