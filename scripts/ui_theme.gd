extends RefCounted
## Thème d'interface commun : gros boutons arrondis, lisibles au pouce.

static func make() -> Theme:
	var t := Theme.new()
	t.default_font_size = 24
	var normal := _box(Color(0.96, 0.93, 0.85))
	var hover := _box(Color(1.0, 0.97, 0.9))
	var pressed := _box(Color(1.0, 0.78, 0.35))
	var disabled := _box(Color(0.6, 0.6, 0.62, 0.6))
	for state in [["normal", normal], ["hover", hover], ["pressed", pressed], ["hover_pressed", pressed], ["disabled", disabled], ["focus", StyleBoxEmpty.new()]]:
		t.set_stylebox(state[0], "Button", state[1])
	t.set_color("font_color", "Button", Color(0.15, 0.2, 0.3))
	t.set_color("font_hover_color", "Button", Color(0.15, 0.2, 0.3))
	t.set_color("font_pressed_color", "Button", Color(0.2, 0.12, 0.05))
	t.set_color("font_hover_pressed_color", "Button", Color(0.2, 0.12, 0.05))
	t.set_color("font_disabled_color", "Button", Color(0.3, 0.3, 0.35))
	t.set_color("font_color", "Label", Color(1, 1, 1))
	t.set_color("font_outline_color", "Label", Color(0.05, 0.1, 0.2))
	t.set_constant("outline_size", "Label", 6)
	return t


static func _box(c: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.set_corner_radius_all(14)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	return sb
