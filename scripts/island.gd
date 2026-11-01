extends RefCounted
## Logique pure d'une partie de Marée Montante : grille, marée, actions, événements.
## Aucune dépendance au rendu, pour pouvoir simuler des parties en headless.

const SIZE := 12
const N := SIZE * SIZE
const MAX_LEVEL := 30
const START_SEA := 5
const START_COLONISTS := 5
const BASE_ACTIONS := 3

enum Terrain { SAND, GRASS, FOREST, ROCK }
enum Building { NONE, DIKE_WOOD, DIKE_STONE, FIELD, BRIDGE, RAFT, LIGHTHOUSE, STILTS, MILL }
enum Event { NONE, STORM, LOW_TIDE, CASTAWAYS }

const BUILDING_NAMES := {
	Building.DIKE_WOOD: "Digue en bois",
	Building.DIKE_STONE: "Digue en pierre",
	Building.FIELD: "Champ",
	Building.BRIDGE: "Pont",
	Building.RAFT: "Radeau",
	Building.LIGHTHOUSE: "Phare",
	Building.STILTS: "Pilotis",
	Building.MILL: "Moulin à marée",
}

## Bâtiments qui demandent un déblocage (id de déblocage).
const BUILDING_UNLOCK := {
	Building.LIGHTHOUSE: "phare",
	Building.STILTS: "pilotis",
	Building.MILL: "moulin",
}

const EVENT_NAMES := {
	Event.NONE: "Mer calme",
	Event.STORM: "Tempête",
	Event.LOW_TIDE: "Marée basse",
	Event.CASTAWAYS: "Naufragés",
}

# --- État de l'île ---------------------------------------------------------
var seed_value: int = 0
var rng := RandomNumberGenerator.new()
var unlocks: Dictionary = {}

var heights := PackedInt32Array()
var terrain := PackedInt32Array()
var flooded := PackedByteArray()
var building := PackedInt32Array()
var dike_turns := PackedInt32Array()
var colonists := PackedInt32Array()
var castaways := PackedInt32Array()
var forest_stock := PackedInt32Array()

var sea: int = START_SEA
var turn: int = 1
var actions_per_turn: int = BASE_ACTIONS
var actions_left: int = BASE_ACTIONS
var food: int = 10
var wood: int = 3
var stone: int = 0
var peak_population: int = 0
var castaways_saved: int = 0
var next_event: int = Event.NONE
var last_event: int = Event.NONE
var game_over := false
var start_land: int = 1


func setup(p_seed: int, p_unlocks: Dictionary = {}) -> void:
	seed_value = p_seed
	unlocks = p_unlocks
	rng.seed = p_seed
	# Les Packed*Array sont copiés à l'affectation : on les initialise un par un.
	heights = _zeros_i()
	terrain = _zeros_i()
	building = _zeros_i()
	dike_turns = _zeros_i()
	colonists = _zeros_i()
	castaways = _zeros_i()
	forest_stock = _zeros_i()
	flooded.resize(N)
	flooded.fill(0)
	_generate()
	if has_unlock("reserves"):
		food += 4
	_roll_next_event()
	actions_left = actions_per_turn
	peak_population = population()
	start_land = max(1, land_count())


static func _zeros_i() -> PackedInt32Array:
	var a := PackedInt32Array()
	a.resize(N)
	a.fill(0)
	return a


func has_unlock(id: String) -> bool:
	return unlocks.get(id, false)


# --- Génération -------------------------------------------------------------
func _generate() -> void:
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	noise.frequency = 0.16
	noise.fractal_octaves = 3
	var forest_noise := FastNoiseLite.new()
	forest_noise.seed = seed_value + 7919
	forest_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	forest_noise.frequency = 0.22

	var c := (SIZE - 1) / 2.0
	var raw := PackedFloat32Array()
	raw.resize(N)
	var top := 0.001
	for y in SIZE:
		for x in SIZE:
			var d := Vector2(x - c, y - c).length() / (SIZE * 0.5)
			var falloff := clampf(1.0 - pow(d, 2.2), 0.0, 1.0)
			var n := (noise.get_noise_2d(x, y) + 1.0) * 0.5
			var h := falloff * (0.15 + 0.85 * n * n)
			raw[idx(x, y)] = h
			top = maxf(top, h)
	# Normalisé : le sommet atteint toujours MAX_LEVEL, la durée de partie reste stable.
	for i in N:
		heights[i] = clampi(int(round(raw[i] / top * MAX_LEVEL)), 0, MAX_LEVEL)

	for i in N:
		var h := heights[i]
		var p := idx_to_pos(i)
		if h >= int(MAX_LEVEL * 0.8):
			terrain[i] = Terrain.ROCK
		elif h <= START_SEA + 2:
			terrain[i] = Terrain.SAND
		elif forest_noise.get_noise_2d(p.x, p.y) > 0.05:
			terrain[i] = Terrain.FOREST
			forest_stock[i] = 3
		else:
			terrain[i] = Terrain.GRASS

	flooded = _simulate_flood(sea, 0, false)

	# Colonie de départ : la case herbeuse (sinon émergée) la plus proche du centre.
	var best := -1
	var best_d := INF
	for i in N:
		if flooded[i] == 1:
			continue
		var p := idx_to_pos(i)
		var dd := Vector2(p.x - c, p.y - c).length() + (0.0 if terrain[i] == Terrain.GRASS else 100.0)
		if dd < best_d:
			best_d = dd
			best = i
	if best >= 0:
		colonists[best] = START_COLONISTS + (1 if has_unlock("colon") else 0)


# --- Grille -------------------------------------------------------------------
static func idx(x: int, y: int) -> int:
	return y * SIZE + x


static func idx_to_pos(i: int) -> Vector2i:
	return Vector2i(i % SIZE, i / SIZE)


func neighbors(i: int) -> Array[int]:
	var p := idx_to_pos(i)
	var out: Array[int] = []
	if p.x > 0: out.append(i - 1)
	if p.x < SIZE - 1: out.append(i + 1)
	if p.y > 0: out.append(i - SIZE)
	if p.y < SIZE - 1: out.append(i + SIZE)
	return out


func is_border(i: int) -> bool:
	var p := idx_to_pos(i)
	return p.x == 0 or p.y == 0 or p.x == SIZE - 1 or p.y == SIZE - 1


## Une case où des habitants peuvent se tenir.
func is_habitable(i: int) -> bool:
	return flooded[i] == 0 or building[i] == Building.STILTS


## Une case sur laquelle on peut marcher (habitable ou pont).
func is_walkable(i: int) -> bool:
	return is_habitable(i) or building[i] == Building.BRIDGE


## Case émergée au bord de l'eau (pêche, radeau).
func is_coastal(i: int) -> bool:
	if flooded[i] == 1:
		return false
	if is_border(i):
		return true
	for n in neighbors(i):
		if flooded[n] == 1:
			return true
	return false


func is_below_sea(i: int) -> bool:
	return heights[i] < sea


func population() -> int:
	var total := 0
	for i in N:
		total += colonists[i]
	return total


func land_count() -> int:
	var total := 0
	for i in N:
		if flooded[i] == 0:
			total += 1
	return total


func count_building(b: int) -> int:
	var total := 0
	for i in N:
		if building[i] == b:
			total += 1
	return total


# --- Marée --------------------------------------------------------------------
func _dike_holds(i: int, sea_level: int, ahead: int, storm: bool) -> bool:
	match building[i]:
		Building.DIKE_WOOD:
			return dike_turns[i] > ahead
		Building.DIKE_STONE:
			return not (storm and heights[i] < sea_level)
	return false


func _can_flood(i: int, sea_level: int, ahead: int, storm: bool) -> bool:
	return heights[i] < sea_level and not _dike_holds(i, sea_level, ahead, storm)


## Calcule l'état inondé si la mer atteint `sea_level`. L'eau entre par les bords
## de la carte et se propage aux cases plus basses que la mer, sauf à travers les digues.
## `ahead` = nombre de marées déjà passées (0 = prochaine marée) pour l'usure des digues en bois.
func _simulate_flood(sea_level: int, ahead: int, storm: bool, base: PackedByteArray = PackedByteArray()) -> PackedByteArray:
	var fl: PackedByteArray = flooded.duplicate() if base.is_empty() else base.duplicate()
	var queue: Array[int] = []
	for i in N:
		if fl[i] == 1:
			queue.append(i)
		elif is_border(i) and _can_flood(i, sea_level, ahead, storm):
			fl[i] = 1
			queue.append(i)
	while not queue.is_empty():
		var i: int = queue.pop_back()
		for n in neighbors(i):
			if fl[n] == 0 and _can_flood(n, sea_level, ahead, storm):
				fl[n] = 1
				queue.append(n)
	return fl


func expected_rise(event: int) -> int:
	match event:
		Event.STORM:
			return 2
		Event.LOW_TIDE:
			return 0
	return 1


## Le prochain événement est-il connu du joueur (phare construit) ?
func event_known() -> bool:
	return count_building(Building.LIGHTHOUSE) > 0


## Cases qui seront englouties à la prochaine marée.
func forecast() -> Array[int]:
	var ev := next_event if event_known() else Event.NONE
	var fl := _simulate_flood(sea + expected_rise(ev), 0, ev == Event.STORM)
	return _diff(flooded, fl)


## Cases englouties dans deux marées (déblocage « Longue-vue »).
func forecast_second() -> Array[int]:
	var ev := next_event if event_known() else Event.NONE
	var s1 := sea + expected_rise(ev)
	var fl1 := _simulate_flood(s1, 0, ev == Event.STORM)
	var fl2 := _simulate_flood(s1 + 1, 1, false, fl1)
	return _diff(fl1, fl2)


func _diff(a: PackedByteArray, b: PackedByteArray) -> Array[int]:
	var out: Array[int] = []
	for i in N:
		if a[i] == 0 and b[i] == 1:
			out.append(i)
	return out


func _roll_next_event() -> void:
	if turn < 3:
		next_event = Event.NONE
		return
	var r := rng.randf()
	if r < 0.15:
		next_event = Event.STORM
	elif r < 0.28:
		next_event = Event.LOW_TIDE
	elif r < 0.43:
		next_event = Event.CASTAWAYS
	else:
		next_event = Event.NONE


func food_income() -> int:
	var total := 0
	for i in N:
		if building[i] == Building.FIELD:
			total += 2
		elif building[i] == Building.MILL:
			total += 3 if is_coastal(i) else 1
	return total


## Fin du tour : production, consommation, marée, événement.
## Renvoie un rapport lisible par l'interface.
func end_turn() -> Dictionary:
	var report := {
		"event": next_event,
		"rise": 0,
		"flooded": [],
		"drowned": 0,
		"starved": 0,
		"lost_castaways": 0,
		"new_castaways": -1,
		"dikes_broken": 0,
		"food_delta": 0,
	}
	# 1. Nourriture
	var income := food_income()
	var pop := population()
	food += income - pop
	report.food_delta = income - pop
	if food < 0:
		report.starved = _remove_colonists(-food)
		food = 0

	# 2. Marée
	var ev := next_event
	last_event = ev
	var storm := ev == Event.STORM
	var rise := expected_rise(ev)
	report.rise = rise
	sea += rise
	var fl := _simulate_flood(sea, 0, storm)
	if storm:
		for i in N:
			if building[i] == Building.DIKE_STONE and heights[i] < sea:
				building[i] = Building.NONE
				report.dikes_broken += 1
	var newly := _diff(flooded, fl)
	flooded = fl
	for i in newly:
		if building[i] == Building.STILTS:
			continue
		report.drowned += colonists[i]
		report.lost_castaways += castaways[i]
		colonists[i] = 0
		castaways[i] = 0
		forest_stock[i] = 0
		if building[i] != Building.BRIDGE:
			building[i] = Building.NONE
	report.flooded = newly

	# 3. Usure des digues en bois
	for i in N:
		if building[i] == Building.DIKE_WOOD:
			dike_turns[i] -= 1
			if dike_turns[i] <= 0:
				building[i] = Building.NONE
				report.dikes_broken += 1

	# 4. Événement : naufragés
	if ev == Event.CASTAWAYS:
		report.new_castaways = _spawn_castaways()

	# 5. Fin de partie ?
	if population() == 0:
		game_over = true
	else:
		turn += 1
		actions_left = actions_per_turn
		_roll_next_event()
	peak_population = max(peak_population, population())
	return report


func _remove_colonists(count: int) -> int:
	var removed := 0
	while removed < count and population() > 0:
		var candidates: Array[int] = []
		for i in N:
			if colonists[i] > 0:
				candidates.append(i)
		var i: int = candidates[rng.randi_range(0, candidates.size() - 1)]
		colonists[i] -= 1
		removed += 1
	return removed


func _spawn_castaways() -> int:
	var candidates: Array[int] = []
	for i in N:
		if is_coastal(i) and colonists[i] == 0 and castaways[i] == 0:
			candidates.append(i)
	if candidates.is_empty():
		return -1
	var i: int = candidates[rng.randi_range(0, candidates.size() - 1)]
	castaways[i] = rng.randi_range(1, 3)
	return i


# --- Accessibilité ------------------------------------------------------------
## Composante de terre (cases praticables reliées) contenant `start`.
func component(start: int) -> PackedByteArray:
	var mask := PackedByteArray()
	mask.resize(N)
	mask.fill(0)
	if not is_walkable(start):
		return mask
	var queue: Array[int] = [start]
	mask[start] = 1
	while not queue.is_empty():
		var i: int = queue.pop_back()
		for n in neighbors(i):
			if mask[n] == 0 and is_walkable(n):
				mask[n] = 1
				queue.append(n)
	return mask


## Cases accessibles à au moins un groupe d'habitants.
func reachable_mask() -> PackedByteArray:
	var mask := PackedByteArray()
	mask.resize(N)
	mask.fill(0)
	for i in N:
		if colonists[i] > 0 and mask[i] == 0:
			var comp := component(i)
			for j in N:
				if comp[j] == 1:
					mask[j] = 1
	return mask


func _raft_in(mask: PackedByteArray) -> int:
	for i in N:
		if mask[i] == 1 and building[i] == Building.RAFT:
			return i
	return -1


# --- Actions ------------------------------------------------------------------
func harvest_preview(i: int) -> Dictionary:
	if terrain[i] == Terrain.FOREST and forest_stock[i] > 0:
		return {"wood": 3 + (1 if has_unlock("scierie") else 0)}
	if terrain[i] == Terrain.ROCK:
		return {"stone": 2 + (1 if has_unlock("carriere") else 0)}
	if is_coastal(i):
		return {"food": 3}
	return {"food": 1}


func can_harvest(i: int) -> String:
	if game_over or actions_left <= 0:
		return "Plus d'action ce tour."
	if not is_habitable(i):
		return "Cette case est sous l'eau."
	if reachable_mask()[i] == 0:
		return "Aucun habitant ne peut atteindre cette case."
	return ""


func harvest(i: int) -> String:
	var err := can_harvest(i)
	if err != "":
		return err
	var gain := harvest_preview(i)
	food += gain.get("food", 0)
	wood += gain.get("wood", 0)
	stone += gain.get("stone", 0)
	if gain.has("wood"):
		forest_stock[i] -= 1
		if forest_stock[i] <= 0:
			terrain[i] = Terrain.GRASS
	actions_left -= 1
	return ""


func build_cost(b: int) -> Dictionary:
	match b:
		Building.DIKE_WOOD: return {"wood": 2}
		Building.DIKE_STONE: return {"stone": 3}
		Building.FIELD: return {"wood": 1}
		Building.BRIDGE: return {"wood": 1 if has_unlock("pont_leger") else 2}
		Building.RAFT: return {"wood": 3}
		Building.LIGHTHOUSE: return {"wood": 2, "stone": 3}
		Building.STILTS: return {"wood": 3}
		Building.MILL: return {"wood": 2, "stone": 1}
	return {}


func is_building_available(b: int) -> bool:
	return not BUILDING_UNLOCK.has(b) or has_unlock(BUILDING_UNLOCK[b])


func can_build(b: int, i: int) -> String:
	if game_over or actions_left <= 0:
		return "Plus d'action ce tour."
	if not is_building_available(b):
		return "Bâtiment non débloqué."
	var cost := build_cost(b)
	if wood < cost.get("wood", 0) or stone < cost.get("stone", 0):
		return "Pas assez de ressources."
	if b == Building.BRIDGE:
		if flooded[i] == 0 or building[i] != Building.NONE:
			return "Un pont se pose sur une case d'eau libre."
		var reach := reachable_mask()
		for n in neighbors(i):
			if reach[n] == 1:
				return ""
		return "Le pont doit toucher une case accessible."
	if flooded[i] == 1:
		return "Cette case est sous l'eau."
	if building[i] != Building.NONE:
		return "Il y a déjà un bâtiment ici."
	if reachable_mask()[i] == 0:
		return "Aucun habitant ne peut atteindre cette case."
	match b:
		Building.FIELD:
			if terrain[i] != Terrain.SAND and terrain[i] != Terrain.GRASS:
				return "Un champ se pose sur l'herbe ou le sable."
		Building.RAFT:
			if not is_coastal(i):
				return "Le radeau se construit au bord de l'eau."
		Building.LIGHTHOUSE:
			if count_building(Building.LIGHTHOUSE) > 0:
				return "Un seul phare suffit."
	return ""


func build(b: int, i: int) -> String:
	var err := can_build(b, i)
	if err != "":
		return err
	var cost := build_cost(b)
	wood -= cost.get("wood", 0)
	stone -= cost.get("stone", 0)
	building[i] = b
	if b == Building.DIKE_WOOD:
		dike_turns[i] = 4 if has_unlock("digue_renforcee") else 3
	if b == Building.FIELD and terrain[i] == Terrain.FOREST:
		terrain[i] = Terrain.GRASS
	actions_left -= 1
	return ""


## Déplacement d'un groupe : à pied dans le même îlot (ponts compris), ou
## vers n'importe quel îlot si l'îlot de départ possède un radeau (consommé).
func can_move(from: int, to: int) -> String:
	if game_over or actions_left <= 0:
		return "Plus d'action ce tour."
	if colonists[from] <= 0:
		return "Aucun habitant sur cette case."
	if from == to:
		return "Choisis une autre case."
	if not is_habitable(to):
		return "On ne peut pas s'installer sur l'eau."
	var comp := component(from)
	if comp[to] == 1:
		return ""
	if _raft_in(comp) >= 0:
		return ""
	return "Cette case est sur un autre îlot : construis un pont ou un radeau."


func move(from: int, to: int) -> String:
	var err := can_move(from, to)
	if err != "":
		return err
	var comp := component(from)
	if comp[to] == 0:
		var raft := _raft_in(comp)
		building[raft] = Building.NONE
	colonists[to] += colonists[from]
	colonists[from] = 0
	if castaways[to] > 0:
		colonists[to] += castaways[to]
		castaways_saved += castaways[to]
		castaways[to] = 0
	peak_population = max(peak_population, population())
	actions_left -= 1
	return ""


# --- Score ----------------------------------------------------------------------
func turns_survived() -> int:
	return turn - 1 if game_over else turn


func score() -> int:
	return turns_survived() * 10 + peak_population * 5 + castaways_saved * 5


func souvenirs_earned(daily: bool) -> int:
	var base := turns_survived() + castaways_saved
	return int(round(base * (1.5 if daily else 1.0)))


## Proportion de l'île engloutie (0 = début, 1 = plus rien), pour la palette.
func tension() -> float:
	return clampf(1.0 - float(land_count()) / float(start_land), 0.0, 1.0)
