-- The picker. Opening a transformer (E / click) shows a small window with the kind (step-up /
-- step-down) and the three sizes instead of the combinator's own GUI (the script owns the
-- signals); choosing one swaps the transformer for that variant on the spot (resize.lua).
local Common = require("__pylon-transformers__.scripts.transformer.common")
local Resize = require("__pylon-transformers__.scripts.transformer.resize")

local C, shells = Common.C, Common.shells

local FRAME = "pt-size-frame"
local TITLE = "pt-size-title"
local CLOSE = "pt-size-close"
local RADIO = "pt-size-"      -- + the size
local KIND = "pt-kind-"       -- + the kind

-- Same format as the tooltip in prototypes/transformers.lua.
local function fmt_power(w)
  if w >= 1e9 then return string.format("%.4g GW", w / 1e9) end
  if w >= 1e6 then return string.format("%.4g MW", w / 1e6) end
  if w >= 1e3 then return string.format("%.4g kW", w / 1e3) end
  return string.format("%.4g W", w)
end
local function fmt_power_pct(w, rated) return fmt_power(w) .. string.format(" (%.3g %%)", w / rated * 100) end

local function option_caption(kind, tier, size)
  local info = shells[C.shell_name(kind, tier, size)]
  local rated = info.capacity_w
  return { "pt-gui.option", { "pt-gui." .. size }, fmt_power(rated),
           fmt_power_pct(info.idle_w, rated), fmt_power_pct(info.idle_w + info.loss_w, rated) }
end

local function close(player)
  local frame = player.gui.screen[FRAME]
  if frame and frame.valid then frame.destroy() end
end

local function build(player, rec)
  close(player)
  local shell, info = rec.shell, rec.info

  local frame = player.gui.screen.add{ type = "frame", name = FRAME, direction = "vertical",
                                       tags = { unit_number = shell.unit_number } }
  frame.auto_center = true

  local bar = frame.add{ type = "flow", direction = "horizontal" }
  bar.drag_target = frame
  bar.style.horizontal_spacing = 8
  bar.add{ type = "label", name = TITLE, style = "frame_title",
           caption = { "pt-gui.title", shell.localised_name }, ignored_by_interaction = true }
  local filler = bar.add{ type = "empty-widget", style = "draggable_space_header",
                          ignored_by_interaction = true }
  filler.style.horizontally_stretchable = true
  filler.style.height = 24
  filler.style.right_margin = 4
  bar.add{ type = "sprite-button", name = CLOSE, style = "frame_action_button",
           sprite = "utility/close", hovered_sprite = "utility/close_black",
           clicked_sprite = "utility/close_black" }

  -- (a frame has no spacing of its own, the flow inside it does)
  local inner = frame.add{ type = "frame", style = "inside_shallow_frame_with_padding" }
    .add{ type = "flow", direction = "vertical" }
  inner.style.vertical_spacing = 8
  inner.add{ type = "label", style = "heading_2_label", caption = { "pt-gui.kind" } }
  for _, kind in ipairs(C.kinds) do
    inner.add{ type = "radiobutton", name = KIND .. kind, caption = { "pt-gui.kind-" .. kind },
               state = (kind == info.kind) }
  end
  inner.add{ type = "label", style = "heading_2_label", caption = { "pt-gui.choose" } }
  for _, size in ipairs(C.sizes) do
    inner.add{ type = "radiobutton", name = RADIO .. size,
               caption = option_caption(info.kind, info.tier, size), state = (size == info.size) }
  end
  return frame
end

local function on_gui_opened(event)
  local entity = event.entity
  if event.gui_type ~= defines.gui_type.entity or not (entity and entity.valid and shells[entity.name]) then
    return
  end
  local rec = storage.transformers[entity.unit_number]
  local player = game.get_player(event.player_index)
  if not (rec and player) then return end
  player.opened = build(player, rec)
end

local function on_gui_closed(event)
  local element = event.element
  if element and element.valid and element.name == FRAME then element.destroy() end
end

local function on_gui_click(event)
  local element = event.element
  if not (element and element.valid and element.name == CLOSE) then return end
  local player = game.get_player(event.player_index)
  if player then close(player) end
end

-- The window of the clicked radio button.
local function frame_of(element)
  while element and element.valid and element.name ~= FRAME do element = element.parent end
  return element
end

local function on_checked(event)
  local element = event.element
  local name = element and element.valid and element.name
  local is_size = name and name:sub(1, #RADIO) == RADIO
  local is_kind = name and name:sub(1, #KIND) == KIND
  if not (is_size or is_kind) then return end
  local frame = frame_of(element)
  local player = game.get_player(event.player_index)
  if not (frame and frame.valid and player) then return end

  local rec = frame.tags and storage.transformers[frame.tags.unit_number]
  if not (rec and rec.shell.valid) then
    frame.destroy()
    return
  end

  local opts = {}
  if is_size then opts.size = name:sub(#RADIO + 1) else opts.kind = name:sub(#KIND + 1) end
  local changed = false
  if (opts.size and opts.size ~= rec.info.size) or (opts.kind and opts.kind ~= rec.info.kind) then
    local new = Resize.apply(rec, opts,
      { player_index = event.player_index, force = rec.shell.force, source = "player" })
    changed = new ~= nil
    if changed then
      frame.tags = { unit_number = new.unit_number }
    end
  end

  -- Whatever happened, the buttons show what the transformer really is.
  if not rec.shell.valid then frame.destroy() return end
  local current_size, current_kind = rec.info.size, rec.info.kind
  for _, s in ipairs(C.sizes) do
    local radio = element.parent[RADIO .. s]
    if radio and radio.valid then radio.state = (s == current_size) end
  end
  for _, k in ipairs(C.kinds) do
    local radio = element.parent[KIND .. k]
    if radio and radio.valid then radio.state = (k == current_kind) end
  end

  local title = frame.children[1][TITLE]
  if title and title.valid then title.caption = { "pt-gui.title", rec.shell.localised_name } end
  player.create_local_flying_text{
    text = changed and { "pt-gui.changed", rec.shell.localised_name } or { "pt-gui.cannot" },
    position = rec.shell.position,
  }
end

return {
  events = {
    [defines.events.on_gui_opened] = on_gui_opened,
    [defines.events.on_gui_closed] = on_gui_closed,
    [defines.events.on_gui_click] = on_gui_click,
    [defines.events.on_gui_checked_state_changed] = on_checked,
  },
}
