extends Control
class_name DepthMeterUI

## Total metres of depth visible in the scrolling bar at once.
@export var view_range: float = 80.0

# ── private state ────────────────────────────────────────────────────────────
var _depth: float = 0.0

# ── layout constants ─────────────────────────────────────────────────────────
const BAR_X := 12.0
const BAR_W := 20.0
const BAR_TOP := 72.0
const LABEL_X := 40.0
const FONT_SM := 14
const FONT_MD := 17
const FONT_LG := 30

# ── colours ───────────────────────────────────────────────────────────────────
const COL_BG       := Color(0.03, 0.07, 0.13, 0.90)
const COL_BAR_BG   := Color(0.02, 0.04, 0.09, 1.00)
const COL_SURFACE  := Color(0.40, 1.00, 0.55, 0.90)
const COL_TICK     := Color(0.30, 0.50, 0.70, 0.25)
const COL_TICK_MAJ := Color(0.40, 0.60, 0.80, 0.40)
const COL_LABEL    := Color(0.70, 0.88, 1.00, 0.75)
const COL_CURRENT  := Color(0.95, 0.95, 0.95, 1.00)

# ── public API ────────────────────────────────────────────────────────────────

func update_depth(depth: float) -> void:
	_depth = depth
	queue_redraw()

# ── drawing ───────────────────────────────────────────────────────────────────

func _draw() -> void:
	var w := size.x
	var h := size.y
	var bar_h := h - BAR_TOP - 22.0
	var font := ThemeDB.fallback_font

	var view_top := _depth - view_range * 0.5
	var view_bot := _depth + view_range * 0.5

	# Panel background
	draw_rect(Rect2(0.0, 0.0, w, h), COL_BG)

	# ── Header ───────────────────────────────────────────────────────────────
	draw_string(font, Vector2(BAR_X, 18.0),
			"DEPTH", HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_MD, COL_LABEL)

	draw_string(font, Vector2(BAR_X, 56.0),
			"%.1f m" % _depth, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_LG, COL_CURRENT)

	draw_line(Vector2(0.0, 63.0), Vector2(w, 63.0),
			Color(0.3, 0.5, 0.7, 0.35), 1.0)

	# ── Bar background ───────────────────────────────────────────────────────
	draw_rect(Rect2(BAR_X, BAR_TOP, BAR_W, bar_h), COL_BAR_BG)

	# ── Tick marks ───────────────────────────────────────────────────────────
	var tick := ceilf(view_top / 10.0) * 10.0
	while tick <= view_bot:
		if absf(tick - _depth) > 1.5:
			var ty := _bar_y(tick, view_top, bar_h)
			var is_major := (int(roundf(tick)) % 50) == 0
			if is_major:
				draw_line(
						Vector2(BAR_X, ty),
						Vector2(BAR_X + BAR_W + 8.0, ty),
						COL_TICK_MAJ, 1.0)
				draw_string(font, Vector2(LABEL_X + 8.0, ty + 4.0),
						"%d m" % int(roundf(tick)),
						HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SM, COL_TICK_MAJ)
			else:
				draw_line(
						Vector2(BAR_X + BAR_W, ty),
						Vector2(BAR_X + BAR_W + 4.0, ty),
						COL_TICK, 1.0)
		tick += 10.0

	# ── Surface line ─────────────────────────────────────────────────────────
	if 0.0 >= view_top and 0.0 <= view_bot:
		var sy := _bar_y(0.0, view_top, bar_h)
		draw_line(Vector2(BAR_X - 3.0, sy), Vector2(BAR_X + BAR_W + 3.0, sy),
				COL_SURFACE, 2.0)
		draw_string(font, Vector2(LABEL_X, sy + 4.0),
				"SURFACE  0 m", HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SM, COL_SURFACE)
	else:
		var at_top := 0.0 < view_top
		var ey := BAR_TOP + (0.0 if at_top else bar_h)
		draw_string(font, Vector2(LABEL_X, ey + 4.0),
				"↑ SURF  %.0f m" % _depth if at_top else "↓ SURF",
				HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SM, COL_SURFACE.darkened(0.3))

	# ── Current depth marker (always centred in bar) ─────────────────────────
	var mid_y := BAR_TOP + bar_h * 0.5
	draw_line(Vector2(BAR_X - 8.0, mid_y), Vector2(BAR_X + BAR_W + 8.0, mid_y),
			COL_CURRENT, 3.0)
	draw_colored_polygon(
		PackedVector2Array([
			Vector2(BAR_X - 9.0, mid_y - 7.0),
			Vector2(BAR_X - 9.0, mid_y + 7.0),
			Vector2(BAR_X + 2.0, mid_y),
		]),
		COL_CURRENT
	)

	# ── Bar border ───────────────────────────────────────────────────────────
	draw_rect(Rect2(BAR_X, BAR_TOP, BAR_W, bar_h),
			Color(0.3, 0.5, 0.7, 0.20), false)

# ── helpers ───────────────────────────────────────────────────────────────────

## Converts a depth value to a Y pixel coordinate within the scrolling bar.
## Current depth (_depth) always maps to the vertical centre of the bar.
func _bar_y(depth_val: float, view_top: float, bar_h: float) -> float:
	return BAR_TOP + (depth_val - view_top) / view_range * bar_h
