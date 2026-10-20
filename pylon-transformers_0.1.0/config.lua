-- Shared between data stage and control stage. Pure data, no game API.
-- Table returned to whoever requires this file.
local C = {}

C.mod_name = "pylon-transformers"

-- Half positions relative to shell centre. Left half = input, right half = output.
-- Distance (tiles) from the shell centre to each hidden half; also the half collision size.
C.half_offset = 1.8
C.half_box = 0.1

-- Input flow limit = this * rated output (worst case "work case").
-- Input flow limit as a multiple of rated output (the worst-case input).
C.input_limit_factor = 3
-- Cap on (1 + conversion + line) so that rated * multiplier + idle always fits
-- inside the input flow limit.
-- Highest allowed input/output ratio (1 + conversion + line).
C.max_input_multiplier = 2.5

-- Buffers must carry a transformer between two script updates, with a safety factor.
-- Buffer capacity multiplier over what is needed between two script updates.
C.buffer_safety = 2

-- The two transformer kinds.
C.kinds = { "up", "down" }

-- rated_w          : maximum output power (W), shown in tooltip
-- idle_w           : constant loss (W), drawn from the input network at all times
-- conversion       : loss as a fraction of output power
-- line_per_tile    : (step-down only) loss as a fraction of output power, per tile of wire
--                    between this step-down and the nearest step-up
C.tiers = {
  [1] = { rated_w = 1e6,   idle_w = 10e3,  conversion = 0.020, line_per_tile = 0.0005 },
  [2] = { rated_w = 10e6,  idle_w = 50e3,  conversion = 0.015, line_per_tile = 0.0002 },
  [3] = { rated_w = 100e6, idle_w = 300e3, conversion = 0.010, line_per_tile = 0.0001 },
}

-- Wires connected or cut by hand with the copper wire tool raise no game event. The control script
-- therefore watches each player's wire drag state (see poll_wire_drag in control.lua).
-- How often (ticks) that state is polled. 1 is cheap (one property read per connected player) and
-- cannot miss a fast click-drag. Must not be 15 (that tick interval is used by the debounce timer).
C.wire_poll_ticks = 1

-- Safety net: re-evaluate every step-down's line distance at least this often (ticks), even when
-- no event announced a change. It catches wire changes nothing can detect, such as a blueprint
-- pasted over existing poles that only adds wires, or another mod calling connect_to.
-- 0 disables it.
C.safety_recompute_ticks = 600

-- Prototype name helpers, so both stages build identical names.
function C.shell_name(kind, tier) return "pt-" .. kind .. "-" .. tier end
function C.in_name(kind, tier)    return "pt-in-" .. kind .. "-" .. tier end
function C.out_name(kind, tier)   return "pt-out-" .. kind .. "-" .. tier end

return C
