extends Node3D
## Rendu 3D de l'île : un cube par case, décor en primitives, eau facettée.

const Island = preload("res://scripts/island.gd")
const T = Island.Terrain
const B = Island.Building

const STEP := 0.12          # hauteur d'un niveau de marée
const BASE_Y := -1.2        # fond des colonnes de terrain

const TERRAIN_COLORS := {
	T.SAND: Color(0.95, 0.86, 0.6),
	T.GRASS: Color(0.56, 0.80, 0.38),
	T.FOREST: Color(0.42, 0.68, 0.34),
	T.ROCK: Color(0.55, 0.53, 0.52),
}

var island: Island
var water: MeshInstance3D
var water_mat: ShaderMaterial
var water_y := 0.0

var _tiles: Array[MeshInstance3D] = []
var _decos: Array[Node3D] = []
var _overlays: Array[MeshInstance3D] = []
var _mats := {}
var _forecast_mat: StandardMaterial3D
var _forecast2_mat: StandardMaterial3D
var _target_mat: StandardMaterial3D
var _select_mat: StandardMaterial3D
var _box := BoxMesh.new()
var _time := 0.0
var _forecast: Array[int] = []


func setup(p_island: Island) -> void:
	island = p_island
	_box.size = Vector3.ONE
	_forecast_mat = _overlay_material(Color(0.15, 0.45, 1.0, 0.55))
	_forecast2_mat = _overlay_material(Color(0.4, 0.7, 1.0, 0.25))
	_target_mat = _overlay_material(Color(1.0, 1.0, 1.0, 0.9))
	_select_mat = _overlay_material(Color(1.0, 0.45, 0.1, 0.7))

	var overlay_mesh := BoxMesh.new()
	overlay_mesh.size = Vector3(0.98, 0.05, 0.98)
	for i in Island.N:
		var tile := MeshInstance3D.new()
		tile.mesh = _box
		add_child(tile)
		_tiles.append(tile)
		var deco := Node3D.new()
		add_child(deco)
		_decos.append(deco)
		var ov := MeshInstance3D.new()
		ov.mesh = overlay_mesh
		ov.visible = false
		ov.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(ov)
		_overlays.append(ov)

	var plane := PlaneMesh.new()
	plane.size = Vector2(80, 80)
	plane.subdivide_width = 80
	plane.subdivide_depth = 80
	water_mat = ShaderMaterial.new()
	water_mat.shader = preload("res://shaders/water.gdshader")
	water = MeshInstance3D.new()
	water.mesh = plane
	water.material_override = water_mat
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(water)
	water_y = sea_y(island.sea)
	water.position.y = water_y
	refresh()


func _overlay_material(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.no_depth_test = false
	m.render_priority = 1
	return m


func _mat(c: Color) -> StandardMaterial3D:
	var key := c.to_html()
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = 0.9
		_mats[key] = m
	return _mats[key]


static func sea_y(level: int) -> float:
	return level * STEP + STEP * 0.5


static func tile_pos(i: int) -> Vector3:
	var p := Island.idx_to_pos(i)
	var c := (Island.SIZE - 1) / 2.0
	return Vector3(p.x - c, 0.0, p.y - c)


## Hauteur affichée du dessus d'une case. Une case sèche sous le niveau de la mer
## (protégée par une digue) est affichée juste au-dessus de l'eau.
func tile_top(i: int) -> float:
	var real := (island.heights[i] + 1) * STEP
	if island.flooded[i] == 0:
		return maxf(real, water_y + 0.04)
	return real


func refresh() -> void:
	for i in Island.N:
		var top := tile_top(i)
		var tile := _tiles[i]
		var h := top - BASE_Y
		tile.scale = Vector3(1.0, h, 1.0)
		tile.position = tile_pos(i) + Vector3(0, BASE_Y + h * 0.5, 0)
		var col: Color = TERRAIN_COLORS[island.terrain[i]]
		if island.flooded[i] == 1:
			col = col.darkened(0.35)
		elif island.is_below_sea(i):
			col = col.lerp(Color(0.45, 0.6, 0.75), 0.25)
		tile.material_override = _mat(col)
		_rebuild_deco(i, top)
	_update_overlays_positions()


func _rebuild_deco(i: int, top: float) -> void:
	var deco := _decos[i]
	for ch in deco.get_children():
		ch.queue_free()
	deco.position = tile_pos(i) + Vector3(0, top, 0)
	deco.visible = true
	var flooded := island.flooded[i] == 1
	var stand_y := 0.0
	if flooded:
		stand_y = maxf(0.0, water_y - top + 0.12)

	if not flooded and island.terrain[i] == T.FOREST:
		var n := clampi(island.forest_stock[i], 1, 3)
		var spots := [Vector3(-0.22, 0, -0.18), Vector3(0.2, 0, 0.12), Vector3(-0.1, 0, 0.26)]
		for k in n:
			_add_cone(deco, spots[k], 0.17, 0.45, Color(0.2, 0.5, 0.26))
	if not flooded and island.terrain[i] == T.ROCK:
		_add_box(deco, Vector3(0.18, 0.08, -0.15), Vector3(0.3, 0.16, 0.28), Color(0.55, 0.52, 0.5))

	match island.building[i]:
		B.DIKE_WOOD:
			_add_box(deco, Vector3(0, 0.16, 0), Vector3(1.0, 0.32, 1.0), Color(0.6, 0.4, 0.22))
			for k in island.dike_turns[i]:
				_add_box(deco, Vector3(-0.3 + k * 0.2, 0.36, 0), Vector3(0.12, 0.08, 0.12), Color(0.95, 0.85, 0.4))
			stand_y = 0.32
		B.DIKE_STONE:
			_add_box(deco, Vector3(0, 0.18, 0), Vector3(1.0, 0.36, 1.0), Color(0.5, 0.5, 0.55))
			stand_y = 0.36
		B.FIELD:
			_add_box(deco, Vector3(0, 0.03, 0), Vector3(0.8, 0.06, 0.8), Color(0.93, 0.78, 0.25))
			for k in 3:
				_add_box(deco, Vector3(0, 0.07, -0.25 + k * 0.25), Vector3(0.7, 0.03, 0.06), Color(0.75, 0.6, 0.15))
		B.BRIDGE:
			var y := water_y - top + 0.08
			_add_box(deco, Vector3(0, y, 0), Vector3(1.02, 0.08, 0.6), Color(0.62, 0.42, 0.24))
			stand_y = y + 0.05
		B.RAFT:
			_add_box(deco, Vector3(0.2, 0.05, 0.2), Vector3(0.45, 0.08, 0.45), Color(0.7, 0.5, 0.28))
			_add_box(deco, Vector3(0.2, 0.3, 0.2), Vector3(0.04, 0.45, 0.04), Color(0.4, 0.28, 0.16))
			_add_box(deco, Vector3(0.28, 0.35, 0.2), Vector3(0.14, 0.25, 0.02), Color(0.98, 0.96, 0.9))
		B.LIGHTHOUSE:
			_add_cylinder(deco, Vector3(0, 0.4, 0), 0.16, 0.8, Color(0.96, 0.96, 0.94))
			_add_cylinder(deco, Vector3(0, 0.25, 0), 0.165, 0.12, Color(0.85, 0.2, 0.2))
			_add_cylinder(deco, Vector3(0, 0.88, 0), 0.12, 0.16, Color(1.0, 0.9, 0.4))
		B.STILTS:
			var py := maxf(0.25, water_y - top + 0.15)
			for sx in [-0.35, 0.35]:
				for sz in [-0.35, 0.35]:
					_add_box(deco, Vector3(sx, py * 0.5, sz), Vector3(0.06, py, 0.06), Color(0.45, 0.3, 0.18))
			_add_box(deco, Vector3(0, py, 0), Vector3(0.85, 0.06, 0.85), Color(0.7, 0.52, 0.3))
			stand_y = py + 0.03
		B.MILL:
			_add_box(deco, Vector3(0, 0.22, 0), Vector3(0.35, 0.44, 0.35), Color(0.9, 0.85, 0.75))
			_add_box(deco, Vector3(0, 0.38, 0.19), Vector3(0.7, 0.06, 0.02), Color(0.5, 0.35, 0.2))
			_add_box(deco, Vector3(0, 0.38, 0.19), Vector3(0.06, 0.7, 0.02), Color(0.5, 0.35, 0.2))

	_add_people(deco, island.colonists[i], stand_y, Color(1.0, 0.5, 0.2))
	_add_people(deco, island.castaways[i], stand_y, Color(0.75, 0.4, 0.95))


func _add_people(parent: Node3D, count: int, y: float, col: Color) -> void:
	if count <= 0:
		return
	var shown := mini(count, 5)
	for k in shown:
		var a := TAU * k / shown
		var r := 0.0 if shown == 1 else 0.22
		var m := MeshInstance3D.new()
		var cap := CapsuleMesh.new()
		cap.radius = 0.09
		cap.height = 0.34
		cap.radial_segments = 6
		cap.rings = 1
		m.mesh = cap
		m.material_override = _mat(col)
		m.position = Vector3(cos(a) * r, y + 0.17, sin(a) * r)
		parent.add_child(m)
	var label := Label3D.new()
	label.text = str(count)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.font_size = 96
	label.outline_size = 24
	label.pixel_size = 0.008
	label.modulate = col.lightened(0.3)
	label.position = Vector3(0, y + 0.75, 0)
	label.outline_modulate = Color(0.1, 0.1, 0.2)
	parent.add_child(label)


func _add_box(parent: Node3D, pos: Vector3, size: Vector3, col: Color) -> void:
	var m := MeshInstance3D.new()
	m.mesh = _box
	m.scale = size
	m.position = pos
	m.material_override = _mat(col)
	parent.add_child(m)


func _add_cone(parent: Node3D, pos: Vector3, radius: float, height: float, col: Color) -> void:
	var m := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = 0.0
	c.bottom_radius = radius
	c.height = height
	c.radial_segments = 6
	c.rings = 0
	m.mesh = c
	m.position = pos + Vector3(0, height * 0.5, 0)
	m.material_override = _mat(col)
	parent.add_child(m)


func _add_cylinder(parent: Node3D, pos: Vector3, radius: float, height: float, col: Color) -> void:
	var m := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = radius
	c.bottom_radius = radius
	c.height = height
	c.radial_segments = 8
	c.rings = 0
	m.mesh = c
	m.position = pos
	m.material_override = _mat(col)
	parent.add_child(m)


## Met à jour les surbrillances : prévision (bleu), prévision à 2 tours,
## cases valides pour l'action en cours (blanc) et case sélectionnée (jaune).
func show_overlays(forecast: Array[int], forecast2: Array[int], targets: Array[int], selected: int) -> void:
	_forecast = forecast
	for i in Island.N:
		var ov := _overlays[i]
		ov.visible = true
		ov.scale = Vector3.ONE
		if i == selected:
			ov.material_override = _select_mat
		elif forecast.has(i):
			ov.material_override = _forecast_mat
		elif targets.has(i):
			# Cible valide : pastille blanche au centre de la case.
			ov.material_override = _target_mat
			ov.scale = Vector3(0.32, 1.0, 0.32)
		elif forecast2.has(i):
			ov.material_override = _forecast2_mat
		else:
			ov.visible = false
	_update_overlays_positions()


func _update_overlays_positions() -> void:
	for i in Island.N:
		var y := maxf(tile_top(i), water_y + 0.02) + 0.03
		_overlays[i].position = tile_pos(i) + Vector3(0, y, 0)


func _process(delta: float) -> void:
	_time += delta
	if _forecast_mat:
		# Pulsation + légère vibration des cases menacées.
		_forecast_mat.albedo_color.a = 0.4 + 0.25 * sin(_time * 5.0)
		for i in _forecast:
			var base := tile_pos(i)
			_tiles[i].position.x = base.x + sin(_time * 38.0 + i) * 0.012


## Animation de la montée des eaux, puis rafraîchissement.
func animate_tide(duration: float = 0.9) -> void:
	for i in _forecast:
		_tiles[i].position.x = tile_pos(i).x
	_forecast = []
	for ov in _overlays:
		ov.visible = false
	var target := sea_y(island.sea)
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_method(_set_water_y, water_y, target, duration)
	await tw.finished
	refresh()


func _set_water_y(y: float) -> void:
	water_y = y
	water.position.y = y
	# Les cases noyées s'enfoncent visuellement avec la mer.
	for i in Island.N:
		if island.flooded[i] == 1 and island.building[i] != B.STILTS:
			var top := tile_top(i)
			var h := top - BASE_Y
			_tiles[i].scale.y = h
			_tiles[i].position.y = BASE_Y + h * 0.5
			_decos[i].visible = top > y - 0.05 or island.building[i] == B.BRIDGE


func set_tension(t: float) -> void:
	water_mat.set_shader_parameter("tension", t)


## Case sous le doigt (lancer de rayon contre les colonnes), ou -1.
func pick(camera: Camera3D, screen_pos: Vector2) -> int:
	var from := camera.project_ray_origin(screen_pos)
	var dir := camera.project_ray_normal(screen_pos)
	var best := -1
	var best_d := INF
	for i in Island.N:
		var top := maxf(tile_top(i), water_y)
		var p := tile_pos(i)
		var aabb := AABB(Vector3(p.x - 0.5, BASE_Y, p.z - 0.5), Vector3(1.0, top - BASE_Y, 1.0))
		var hit = aabb.intersects_ray(from, dir)
		if hit != null:
			var d := from.distance_to(hit)
			if d < best_d:
				best_d = d
				best = i
	return best
