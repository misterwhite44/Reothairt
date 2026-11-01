extends Node
## Captures d'écran de contrôle (nécessite un affichage, ex. xvfb-run).
## godot res://scenes/main.tscn -- --capture <dossier_sortie>

var out := "/tmp"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	out = args[args.find("--capture") + 1] if args.find("--capture") + 1 < args.size() else "/tmp"
	_run()


func _run() -> void:
	var main := get_parent()
	await _frames(10)
	await _shot(out + "/01_menu.png")
	main.start_game(424242, false)
	await _frames(10)
	await _shot(out + "/02_partie.png")
	var game = main._game
	game._on_mode_pressed(game.MODE_HARVEST)
	await _frames(5)
	await _shot(out + "/03_mode_recolte.png")
	game._on_mode_pressed(game.MODE_HARVEST)
	for t in 5:
		for a in 3:
			var mode: int = [game.MODE_HARVEST, game.Island.Building.FIELD, game.Island.Building.DIKE_WOOD][(t + a) % 3]
			if game.mode != mode:
				game._on_mode_pressed(mode)
			for i in game.Island.N:
				if game._is_valid_target(i):
					game._on_tile(i)
					break
		if t == 4:
			game._on_mode_pressed(game.MODE_MOVE)
			await _frames(5)
			await _shot(out + "/04_partie_avancee.png")
		game._on_end_turn()
		await get_tree().create_timer(1.3).timeout
	await _frames(5)
	await _shot(out + "/04b_apres_maree.png")
	game._on_give_up()
	await _frames(10)
	await _shot(out + "/05_defaite.png")
	main.show_unlocks()
	await _frames(10)
	await _shot(out + "/06_deblocages.png")
	get_tree().quit()


func _frames(n: int) -> void:
	for k in n:
		await get_tree().process_frame


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("capture : ", path)
