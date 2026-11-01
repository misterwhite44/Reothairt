extends Node3D
## Une partie : scène 3D + interface portrait. Émet `finished` à la défaite.

signal finished(result: Dictionary)
signal quit_requested

const Island = preload("res://scripts/island.gd")
const BoardView = preload("res://scripts/board_view.gd")
const B = Island.Building
const E = Island.Event

const WARM_SKY := Color(0.99, 0.84, 0.62)
const COLD_SKY := Color(0.33, 0.40, 0.55)

var island: Island
var board: BoardView
var camera: Camera3D
var sun: DirectionalLight3D
var env: Environment
var daily := false

const MODE_NONE := -1
const MODE_HARVEST := 100
const MODE_MOVE := 101

var mode: int = MODE_NONE       # MODE_HARVEST, MODE_MOVE ou un Building
var move_from := -1
var busy := false

# Interface
var _top_label: Label
var _res_label: Label
var _event_label: Label
var _msg_label: Label
var _actions_label: Label
var _buttons := {}
var _end_button: Button


func start(p_seed: int, p_daily: bool, unlocks: Dictionary) -> void:
	daily = p_daily
	island = Island.new()
	island.setup(p_seed, unlocks)
	_build_scene()
	_build_hud()
	_set_message("Les cases bleues seront englouties à la fin du tour. Tu as %d actions." % island.actions_per_turn)
	_update_all()


# --- Scène ---------------------------------------------------------------------
func _build_scene() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = WARM_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.85, 0.85, 0.9)
	env.ambient_light_energy = 0.55
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -30, 0)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	add_child(sun)

	board = BoardView.new()
	add_child(board)
	board.setup(island)

	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	camera.size = 17.5
	add_child(camera)
	camera.look_at_from_position(Vector3(14, 15, 14), Vector3.ZERO)
	camera.v_offset = -4.2
	camera.current = true


# --- Interface -----------------------------------------------------------------
func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = preload("res://scripts/ui_theme.gd").make()
	layer.add_child(root)

	# Bandeau du haut
	var top := PanelContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.add_theme_stylebox_override("panel", _panel_style(Color(0, 0, 0, 0.25)))
	root.add_child(top)
	var top_box := VBoxContainer.new()
	top.add_child(top_box)
	var row := HBoxContainer.new()
	top_box.add_child(row)
	_top_label = Label.new()
	_top_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_top_label)
	var quit := Button.new()
	quit.text = "Abandonner"
	quit.pressed.connect(_on_give_up)
	row.add_child(quit)
	_res_label = Label.new()
	top_box.add_child(_res_label)
	_event_label = Label.new()
	_event_label.add_theme_color_override("font_color", Color(1, 0.95, 0.7))
	top_box.add_child(_event_label)

	# Panneau du bas, à portée de pouce
	var bottom := PanelContainer.new()
	bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bottom.add_theme_stylebox_override("panel", _panel_style(Color(0.08, 0.12, 0.2, 0.85)))
	root.add_child(bottom)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	bottom.add_child(box)

	_msg_label = Label.new()
	_msg_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_msg_label.custom_minimum_size = Vector2(0, 64)
	box.add_child(_msg_label)
	_actions_label = Label.new()
	_actions_label.add_theme_font_size_override("font_size", 28)
	box.add_child(_actions_label)

	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	box.add_child(grid)
	_add_mode_button(grid, MODE_HARVEST, "Récolter")
	_add_mode_button(grid, MODE_MOVE, "Déplacer")
	for b in [B.DIKE_WOOD, B.DIKE_STONE, B.FIELD, B.BRIDGE, B.RAFT, B.LIGHTHOUSE, B.STILTS, B.MILL]:
		if island.is_building_available(b):
			_add_mode_button(grid, b, Island.BUILDING_NAMES[b])

	_end_button = Button.new()
	_end_button.text = "Fin du tour : la marée monte"
	_end_button.custom_minimum_size = Vector2(0, 88)
	_end_button.add_theme_font_size_override("font_size", 30)
	_end_button.pressed.connect(_on_end_turn)
	box.add_child(_end_button)


func _panel_style(c: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.content_margin_left = 20
	sb.content_margin_right = 20
	sb.content_margin_top = 16
	sb.content_margin_bottom = 24
	return sb


func _add_mode_button(parent: Control, key: int, title: String) -> void:
	var btn := Button.new()
	btn.toggle_mode = true
	btn.custom_minimum_size = Vector2(0, 76)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.set_meta("title", title)
	btn.pressed.connect(_on_mode_pressed.bind(key))
	parent.add_child(btn)
	_buttons[key] = btn


func _cost_text(cost: Dictionary) -> String:
	var parts: Array[String] = []
	if cost.get("wood", 0) > 0:
		parts.append("%d bois" % cost.wood)
	if cost.get("stone", 0) > 0:
		parts.append("%d pierre" % cost.stone)
	return ", ".join(parts)


func _update_all() -> void:
	var tag := "Défi du jour" if daily else "Île #%d" % (abs(island.seed_value) % 100000)
	_top_label.text = "Tour %d  ·  Mer niv. %d  ·  %s" % [island.turn, island.sea, tag]
	var income := island.food_income()
	var pop := island.population()
	_res_label.text = "Nourriture %d (%+d/tour)   Bois %d   Pierre %d   Habitants %d" % [
		island.food, income - pop, island.wood, island.stone, pop]
	if island.event_known():
		var ev: int = island.next_event
		_event_label.text = "Phare : prochain tour, %s !" % Island.EVENT_NAMES[ev].to_lower()
	else:
		_event_label.text = "Dernier événement : %s" % Island.EVENT_NAMES[island.last_event].to_lower()
	_actions_label.text = "Actions : " + "●".repeat(island.actions_left) + "○".repeat(island.actions_per_turn - island.actions_left)
	for key in _buttons:
		var btn: Button = _buttons[key]
		btn.button_pressed = (mode == key)
		if key == MODE_HARVEST or key == MODE_MOVE:
			btn.text = btn.get_meta("title")
		else:
			btn.text = "%s\n%s" % [btn.get_meta("title"), _cost_text(island.build_cost(key))]
			btn.add_theme_font_size_override("font_size", 20)
		btn.disabled = busy or island.actions_left <= 0
	_end_button.disabled = busy
	_update_overlays()
	var t := island.tension()
	env.background_color = WARM_SKY.lerp(COLD_SKY, t)
	sun.light_color = Color(1.0, 0.95, 0.85).lerp(Color(0.75, 0.82, 1.0), t)
	board.set_tension(t)


func _update_overlays() -> void:
	var targets: Array[int] = []
	if mode != MODE_NONE and not busy:
		for i in Island.N:
			if _is_valid_target(i):
				targets.append(i)
	var f2: Array[int] = []
	if island.has_unlock("prevision"):
		f2 = island.forecast_second()
	board.show_overlays(island.forecast(), f2, targets, move_from)


func _is_valid_target(i: int) -> bool:
	if mode == MODE_HARVEST:
		return island.can_harvest(i) == ""
	if mode == MODE_MOVE:
		if move_from < 0:
			return island.colonists[i] > 0
		return island.can_move(move_from, i) == ""
	return island.can_build(mode, i) == ""


func _set_message(text: String) -> void:
	_msg_label.text = text


# --- Entrées -------------------------------------------------------------------
func _on_mode_pressed(key: int) -> void:
	if mode == key:
		mode = MODE_NONE
	else:
		mode = key
	move_from = -1
	if mode == MODE_HARVEST:
		_set_message("Touche une case : forêt = bois, colline = pierre, rivage = pêche, ailleurs = cueillette.")
	elif mode == MODE_MOVE:
		_set_message("Touche un groupe d'habitants, puis sa destination.")
	elif mode != MODE_NONE:
		_set_message("%s : touche une case en surbrillance." % Island.BUILDING_NAMES[mode])
	_update_all()


func _unhandled_input(event: InputEvent) -> void:
	if busy or island.game_over:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var i := board.pick(camera, event.position)
		if i >= 0:
			_on_tile(i)


func _on_tile(i: int) -> void:
	if mode == MODE_NONE:
		_describe(i)
		return
	var err := ""
	if mode == MODE_HARVEST:
		var gain := island.harvest_preview(i)
		err = island.harvest(i)
		if err == "":
			_set_message("Récolte : +%s." % _gain_text(gain))
	elif mode == MODE_MOVE:
		if move_from < 0:
			if island.colonists[i] > 0:
				move_from = i
				_set_message("Où emmener ces %d habitants ?" % island.colonists[i])
			else:
				err = "Touche d'abord une case avec des habitants."
		else:
			var saved_before := island.castaways_saved
			err = island.move(move_from, i)
			if err == "":
				var saved := island.castaways_saved - saved_before
				_set_message("Habitants déplacés." + (" %d naufragés recueillis !" % saved if saved > 0 else ""))
				move_from = -1
	else:
		var b := mode
		err = island.build(b, i)
		if err == "":
			_set_message("%s construit." % Island.BUILDING_NAMES[b])
	if err != "":
		_set_message(err)
	elif island.actions_left <= 0:
		mode = MODE_NONE
		move_from = -1
		_set_message(_msg_label.text + " Plus d'action : termine le tour.")
	board.refresh()
	_update_all()


func _gain_text(gain: Dictionary) -> String:
	var parts: Array[String] = []
	for k in gain:
		parts.append("%d %s" % [gain[k], {"food": "nourriture", "wood": "bois", "stone": "pierre"}[k]])
	return ", ".join(parts)


func _describe(i: int) -> void:
	var names := {0: "Plage", 1: "Prairie", 2: "Forêt", 3: "Colline"}
	var parts: Array[String] = []
	parts.append("%s, altitude %d" % [names[island.terrain[i]], island.heights[i]])
	if island.flooded[i] == 1:
		parts[0] = "Case engloutie"
	if island.building[i] != B.NONE:
		var t: String = Island.BUILDING_NAMES[island.building[i]]
		if island.building[i] == B.DIKE_WOOD:
			t += " (%d tours)" % island.dike_turns[i]
		parts.append(t)
	if island.colonists[i] > 0:
		parts.append("%d habitants" % island.colonists[i])
	if island.castaways[i] > 0:
		parts.append("%d naufragés à recueillir" % island.castaways[i])
	if island.is_below_sea(i) and island.flooded[i] == 0:
		parts.append("sous le niveau de la mer")
	_set_message(" · ".join(parts))


func _on_end_turn() -> void:
	if busy:
		return
	busy = true
	mode = MODE_NONE
	move_from = -1
	_update_all()
	var report := island.end_turn()
	await board.animate_tide()
	_set_message(_report_text(report))
	if island.game_over:
		_update_all()
		await get_tree().create_timer(1.5).timeout
		finished.emit(_result())
		return
	busy = false
	_update_all()


func _report_text(r: Dictionary) -> String:
	var parts: Array[String] = []
	match r.event:
		E.STORM:
			parts.append("Tempête ! La mer monte de 2 niveaux.")
		E.LOW_TIDE:
			parts.append("Marée basse : un tour de répit.")
		E.CASTAWAYS:
			parts.append("Des naufragés attendent sur le rivage (en violet) : va les chercher !" if r.new_castaways >= 0 else "Un radeau de naufragés n'a pas trouvé de rivage.")
		_:
			parts.append("La mer monte d'un niveau.")
	if r.flooded.size() > 0:
		parts.append("%d cases englouties." % r.flooded.size())
	if r.drowned > 0:
		parts.append("%d habitants noyés." % r.drowned)
	if r.starved > 0:
		parts.append("%d habitants partis, faute de nourriture." % r.starved)
	if r.lost_castaways > 0:
		parts.append("%d naufragés perdus." % r.lost_castaways)
	if r.dikes_broken > 0:
		parts.append("%d digues cédées." % r.dikes_broken)
	return " ".join(parts)


func _on_give_up() -> void:
	if busy:
		return
	island.game_over = true
	finished.emit(_result())


func _result() -> Dictionary:
	return {
		"seed": island.seed_value,
		"daily": daily,
		"turns": island.turns_survived(),
		"peak_population": island.peak_population,
		"castaways_saved": island.castaways_saved,
		"score": island.score(),
		"souvenirs": island.souvenirs_earned(daily),
	}
