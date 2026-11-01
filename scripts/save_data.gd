extends Node
## Sauvegarde locale de la méta-progression (autoload « Save »).

const PATH := "user://maree_montante.cfg"

## Les 10 déblocages du MVP, achetés avec les Souvenirs.
const UNLOCKS := [
	{"id": "colon", "name": "Colon de plus", "desc": "La colonie démarre avec 6 habitants.", "cost": 10},
	{"id": "reserves", "name": "Réserves", "desc": "+4 nourriture au départ.", "cost": 10},
	{"id": "scierie", "name": "Scierie", "desc": "+1 bois par récolte en forêt.", "cost": 15},
	{"id": "carriere", "name": "Tailleurs de pierre", "desc": "+1 pierre par récolte en colline.", "cost": 15},
	{"id": "pont_leger", "name": "Ponts légers", "desc": "Le pont ne coûte qu'1 bois.", "cost": 20},
	{"id": "digue_renforcee", "name": "Digues renforcées", "desc": "Les digues en bois tiennent 4 tours.", "cost": 25},
	{"id": "phare", "name": "Phare", "desc": "Nouveau bâtiment : annonce l'événement du prochain tour.", "cost": 30},
	{"id": "pilotis", "name": "Pilotis", "desc": "Nouveau bâtiment : la case reste habitable une fois inondée.", "cost": 40},
	{"id": "moulin", "name": "Moulin à marée", "desc": "Nouveau bâtiment : +1 nourriture, +3 au bord de l'eau.", "cost": 40},
	{"id": "prevision", "name": "Longue-vue", "desc": "Montre aussi les cases englouties dans deux tours.", "cost": 50},
]

var souvenirs: int = 0
var unlocks: Dictionary = {}
var best_score: int = 0
var best_turns: int = 0
var games_played: int = 0
## date (AAAA-MM-JJ) -> Array de scores, classement local du défi quotidien.
var daily_scores: Dictionary = {}


func _ready() -> void:
	load_data()


func load_data() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	souvenirs = cfg.get_value("meta", "souvenirs", 0)
	unlocks = cfg.get_value("meta", "unlocks", {})
	best_score = cfg.get_value("records", "best_score", 0)
	best_turns = cfg.get_value("records", "best_turns", 0)
	games_played = cfg.get_value("records", "games_played", 0)
	daily_scores = cfg.get_value("daily", "scores", {})


func save_data() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "souvenirs", souvenirs)
	cfg.set_value("meta", "unlocks", unlocks)
	cfg.set_value("records", "best_score", best_score)
	cfg.set_value("records", "best_turns", best_turns)
	cfg.set_value("records", "games_played", games_played)
	cfg.set_value("daily", "scores", daily_scores)
	cfg.save(PATH)


func is_unlocked(id: String) -> bool:
	return unlocks.get(id, false)


func buy(id: String) -> bool:
	for u in UNLOCKS:
		if u.id == id and not is_unlocked(id) and souvenirs >= u.cost:
			souvenirs -= u.cost
			unlocks[id] = true
			save_data()
			return true
	return false


static func today() -> String:
	var d := Time.get_date_dict_from_system()
	return "%04d-%02d-%02d" % [d.year, d.month, d.day]


static func daily_seed() -> int:
	return hash("maree-montante-" + today())


## Enregistre une fin de partie. Renvoie true si c'est un nouveau record.
func record_game(score: int, turns: int, earned: int, daily: bool) -> bool:
	games_played += 1
	souvenirs += earned
	var is_record := score > best_score
	best_score = max(best_score, score)
	best_turns = max(best_turns, turns)
	if daily:
		var key := today()
		var list: Array = daily_scores.get(key, [])
		list.append(score)
		list.sort()
		list.reverse()
		daily_scores[key] = list.slice(0, 5)
	save_data()
	return is_record


func daily_ranking() -> Array:
	return daily_scores.get(today(), [])
