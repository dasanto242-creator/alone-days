class_name UiTheme
extends RefCounted
## Tema visual da interface: tons escuros, cinza e verde militar, cantos discretos.

const BG := Color(0.05, 0.06, 0.05, 0.92)
const PANEL := Color(0.09, 0.1, 0.09, 0.95)
const SLOT := Color(0.13, 0.14, 0.12, 1.0)
const SLOT_SELECTED := Color(0.22, 0.26, 0.15, 1.0)
const ACCENT := Color(0.55, 0.62, 0.32)
const TEXT := Color(0.86, 0.86, 0.8)
const TEXT_DIM := Color(0.58, 0.6, 0.55)
const WARNING := Color(0.85, 0.62, 0.22)
const DANGER := Color(0.82, 0.25, 0.2)

static var _theme: Theme


static func get_theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font_size = 17
	t.set_color("font_color", "Label", TEXT)

	t.set_stylebox("normal", "Button", box(Color(0.14, 0.15, 0.13), 6, ACCENT * Color(1, 1, 1, 0.35)))
	t.set_stylebox("hover", "Button", box(Color(0.17, 0.19, 0.15), 6, ACCENT * Color(1, 1, 1, 0.5)))
	t.set_stylebox("pressed", "Button", box(Color(0.24, 0.29, 0.16), 6, ACCENT))
	t.set_stylebox("disabled", "Button", box(Color(0.1, 0.1, 0.1), 6, Color(1, 1, 1, 0.06)))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_pressed_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", TEXT)
	t.set_color("font_disabled_color", "Button", TEXT_DIM * Color(1, 1, 1, 0.6))
	t.set_stylebox("panel", "PanelContainer", box(PANEL, 8))
	t.set_stylebox("panel", "Panel", box(PANEL, 8))
	_theme = t
	return t


static func box(color: Color, radius := 6, border := Color.TRANSPARENT, margin := 10.0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(margin)
	if border.a > 0.0:
		s.border_color = border
		s.set_border_width_all(2)
	return s
