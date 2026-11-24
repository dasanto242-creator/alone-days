extends Node
## Ferramenta de desenvolvimento: abre o cenário, posiciona a câmera e salva capturas.
## Uso: godot --path . res://tools/screenshot.tscn  (precisa de tela/GPU)

const SHOTS := [
	{"pos": Vector3(0, 0.05, 6), "yaw": 0.0, "pitch": -12.0, "file": "shot_house.png"},
	{"pos": Vector3(-6, 0.05, 8), "yaw": -140.0, "pitch": -18.0, "file": "shot_road.png"},
	{"pos": Vector3(1, 0.15, -14.5), "yaw": 30.0, "pitch": -15.0, "file": "shot_indoor.png"},
	{"pos": Vector3(-10.3, 0.05, 3.3), "yaw": 0.0, "pitch": -20.0, "file": "shot_loot.png"},
	{"pos": Vector3(4, 0.05, 14), "yaw": 30.0, "pitch": -10.0, "file": "shot_walk.png", "move": 0.45},
	{"pos": Vector3(-4, 0.05, 14), "yaw": -60.0, "pitch": -8.0, "file": "shot_run.png", "move": 1.0},
]


func _ready() -> void:
	var world := (load("res://scenes/world/test_sandbox.tscn") as PackedScene).instantiate()
	add_child(world)
	var player := world.get_node("Player") as PlayerController
	var rig := world.get_node("CameraRig") as CameraRig
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build/screenshots"))
	await _wait(30)
	var img: Image
	for shot in SHOTS:
		player.global_position = shot.pos
		player.reset_physics_interpolation()
		TouchInput.add_look(Vector2(rad_to_deg(rig.get_yaw()) - shot.yaw, rig.get_pitch_degrees() - shot.pitch))
		if shot.has("move"):
			Input.action_press("move_left", shot.move)
		await _wait(90)
		Input.action_release("move_left")
		img = get_viewport().get_texture().get_image()
		img.save_png("res://build/screenshots/" + shot.file)
		print("salvo ", shot.file)
	# Inventário aberto com alguns itens
	var inv := player.inventory
	for id in [&"backpack", &"jacket"]:
		inv.add_item(id)
		player.equip_item(inv.stacks.size() - 1)
	inv.add_item(&"water_bottle", 2)
	inv.add_item(&"can_beans", 3)
	inv.add_item(&"cereal_bar", 4)
	inv.add_item(&"bandage", 2)
	inv.add_item(&"soda_can", 1)
	player.stats.food = 22.0
	player.stats.water = 64.0
	player.stats.stamina = 45.0
	player.stats.stats_changed.emit()
	await _wait(10)
	img = get_viewport().get_texture().get_image()
	img.save_png("res://build/screenshots/shot_hud.png")
	var screen := world.get_node("HUD/InventoryScreen") as InventoryScreen
	screen.open()
	await _wait(5)
	(screen.find_child("Slot1", true, false) as Button).pressed.emit()
	await _wait(10)
	img = get_viewport().get_texture().get_image()
	img.save_png("res://build/screenshots/shot_inventory.png")
	print("salvo inventário")
	get_tree().quit()


func _wait(n: int) -> void:
	for i in n:
		await get_tree().process_frame
