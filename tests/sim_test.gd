extends SceneTree
## Simule des parties avec un joueur automatique simple, pour vérifier que la
## logique tourne sans erreur et estimer la durée des parties.
## Lancer : godot --headless --script res://tests/sim_test.gd

const Island = preload("res://scripts/island.gd")
const B = Island.Building


func _init() -> void:
	var turns: Array[int] = []
	var unlock_sets := [{}, {"phare": true, "pilotis": true, "moulin": true, "colon": true, "reserves": true}]
	for u in unlock_sets:
		turns.clear()
		for s in 200:
			var isl := Island.new()
			isl.setup(1000 + s, u)
			_play(isl)
			turns.append(isl.turns_survived())
		turns.sort()
		var total := 0
		for t in turns:
			total += t
		print("déblocages=%s  tours: min %d / médiane %d / max %d / moyenne %.1f" % [
			u.keys(), turns[0], turns[turns.size() / 2], turns[-1], float(total) / turns.size()])
	print("habitants noyés: %d, partis faute de nourriture: %d" % [drowned, starved])
	quit()


var drowned := 0
var starved := 0


func _play(isl: Island) -> void:
	var guard := 0
	while not isl.game_over and guard < 200:
		guard += 1
		var threatened: Array[int] = isl.forecast()
		# 1. Mettre à l'abri les habitants menacés : vers la case accessible la plus haute.
		for i in Island.N:
			if isl.colonists[i] > 0 and threatened.has(i) and isl.actions_left > 0:
				var best := _highest_target(isl, i)
				if best >= 0:
					isl.move(i, best)
		# 2. Recueillir des naufragés accessibles.
		for i in Island.N:
			if isl.castaways[i] > 0 and isl.actions_left > 0:
				for j in Island.N:
					if isl.colonists[j] > 0 and isl.can_move(j, i) == "":
						isl.move(j, i)
						break
		# 3. Production / protection.
		var tries := 0
		while isl.actions_left > 0 and tries < 30:
			tries += 1
			var pop: int = isl.population()
			if isl.food_income() < pop and isl.wood >= 1:
				if _try_build_anywhere(isl, B.FIELD):
					continue
			if isl.wood < 2:
				if _harvest_best(isl, "wood"):
					continue
			if isl.food < pop * 2:
				if _harvest_best(isl, "food"):
					continue
			if isl.stone >= 3 and _dike_threat(isl, B.DIKE_STONE):
				continue
			if isl.wood >= 2 and _dike_threat(isl, B.DIKE_WOOD):
				continue
			if not _harvest_best(isl, ["wood", "stone", "food"][tries % 3]):
				_harvest_best(isl, "food")
		var r: Dictionary = isl.end_turn()
		drowned += r.drowned
		starved += r.starved


func _highest_target(isl: Island, from: int) -> int:
	var best := -1
	for j in Island.N:
		if isl.can_move(from, j) == "" and (best < 0 or isl.heights[j] > isl.heights[best]):
			best = j
	return best


func _try_build_anywhere(isl: Island, b: int) -> bool:
	var best := -1
	for i in Island.N:
		if isl.can_build(b, i) == "" and (best < 0 or isl.heights[i] > isl.heights[best]):
			best = i
	if best >= 0:
		return isl.build(b, best) == ""
	return false


func _harvest_best(isl: Island, res: String) -> bool:
	for i in Island.N:
		if isl.can_harvest(i) == "" and isl.harvest_preview(i).has(res):
			return isl.harvest(i) == ""
	return false


func _dike_threat(isl: Island, b: int) -> bool:
	for i in isl.forecast():
		if isl.can_build(b, i) == "":
			return isl.build(b, i) == ""
	return false
