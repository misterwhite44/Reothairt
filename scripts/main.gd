extends Node
## Point d'entrée : menu, déblocages, partie, écran de défaite.

const Game = preload("res://scripts/game.gd")
const UiTheme = preload("res://scripts/ui_theme.gd")

var _game: Node = null
var _ui: CanvasLayer
var _last_seed := 0
var _last_daily := false


func _ready() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 10
	add_child(_ui)
	show_menu()
	if "--capture" in OS.get_cmdline_user_args():
		add_child.call_deferred(load("res://tests/screenshot.gd").new())


func _clear_ui() -> Control:
	for ch in _ui.get_children():
		ch.queue_free()
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = UiTheme.make()
	_ui.add_child(root)
	return root


func _background(root: Control, c: Color) -> void:
	var bg := ColorRect.new()
	bg.color = c
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)


func _column(root: Control) -> VBoxContainer:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 48)
	root.add_child(margin)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 18)
	margin.add_child(col)
	return col


func _label(parent: Control, text: String, size: int = 26) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", size)
	parent.add_child(l)
	return l


func _button(parent: Control, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 92)
	b.add_theme_font_size_override("font_size", 30)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


# --- Menu -------------------------------------------------------------------------
func show_menu() -> void:
	_end_game()
	var root := _clear_ui()
	_background(root, Color(0.2, 0.55, 0.72))
	var col := _column(root)
	_label(col, "Marée Montante", 64)
	_label(col, "Protège ton île de la marée le plus longtemps possible,\net reviens plus fort à chaque naufrage.", 24)
	col.add_child(HSeparator.new())
	_label(col, "Souvenirs : %d" % Save.souvenirs, 30)
	_label(col, "Record : %d points (%d tours)" % [Save.best_score, Save.best_turns], 24)
	_button(col, "Nouvelle partie", func(): start_game(randi(), false))
	var daily_best: Array = Save.daily_ranking()
	var daily_txt := "Défi du jour" + ("  (meilleur : %d)" % daily_best[0] if not daily_best.is_empty() else "")
	_button(col, daily_txt, func(): start_game(Save.daily_seed(), true))
	_button(col, "Déblocages", show_unlocks)


func show_unlocks() -> void:
	var root := _clear_ui()
	_background(root, Color(0.16, 0.3, 0.45))
	var col := _column(root)
	_label(col, "Déblocages", 52)
	_label(col, "Souvenirs : %d" % Save.souvenirs, 30)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 12)
	scroll.add_child(list)
	for u in Save.UNLOCKS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		list.add_child(row)
		var info := Label.new()
		info.text = "%s\n%s" % [u.name, u.desc]
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_theme_font_size_override("font_size", 22)
		row.add_child(info)
		var b := Button.new()
		b.custom_minimum_size = Vector2(170, 80)
		if Save.is_unlocked(u.id):
			b.text = "Acquis"
			b.disabled = true
		else:
			b.text = "%d Souv." % u.cost
			b.disabled = Save.souvenirs < u.cost
			b.pressed.connect(func():
				Save.buy(u.id)
				show_unlocks())
		row.add_child(b)
	_button(col, "Retour", show_menu)


# --- Partie -----------------------------------------------------------------------
func start_game(p_seed: int, daily: bool) -> void:
	_end_game()
	_clear_ui()
	_last_seed = p_seed
	_last_daily = daily
	_game = Game.new()
	add_child(_game)
	_game.start(p_seed, daily, Save.unlocks.duplicate())
	_game.finished.connect(_on_game_finished)


func _end_game() -> void:
	if _game:
		_game.queue_free()
		_game = null


func _on_game_finished(result: Dictionary) -> void:
	var is_record := Save.record_game(result.score, result.turns, result.souvenirs, result.daily)
	show_game_over(result, is_record)


func show_game_over(r: Dictionary, is_record: bool) -> void:
	var root := _clear_ui()
	_background(root, Color(0.05, 0.1, 0.2, 0.82))
	var col := _column(root)
	_label(col, "L'île a sombré", 56)
	_label(col, "%d tours survécus" % r.turns, 40)
	_label(col, "Population max : %d   ·   Naufragés sauvés : %d" % [r.peak_population, r.castaways_saved], 24)
	_label(col, "Score : %d" % r.score, 44)
	if is_record:
		_label(col, "Nouveau record !", 34).add_theme_color_override("font_color", Color(1, 0.85, 0.3))
	else:
		_label(col, "Record personnel : %d" % Save.best_score, 26)
	_label(col, "+%d Souvenirs%s  (total : %d)" % [r.souvenirs, " (bonus défi ×1,5)" if r.daily else "", Save.souvenirs], 30)
	if r.daily:
		var ranking: Array = Save.daily_ranking()
		var lines: Array[String] = []
		for k in ranking.size():
			lines.append("%d. %d pts" % [k + 1, ranking[k]])
		_label(col, "Classement local du jour\n" + "\n".join(lines), 24)
	var next := _cheapest_locked()
	if not next.is_empty():
		_label(col, "Prochain déblocage : %s (%d Souvenirs)" % [next.name, next.cost], 22)
	_button(col, "Rejouer (nouvelle île)", func(): start_game(randi(), false))
	_button(col, "Rejouer cette île", func(): start_game(_last_seed, _last_daily))
	_button(col, "Menu", show_menu)


func _cheapest_locked() -> Dictionary:
	for u in Save.UNLOCKS:
		if not Save.is_unlocked(u.id):
			return u
	return {}
