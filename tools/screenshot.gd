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
	screen.close()
	await _weapon_shots(world, player, rig)
	get_tree().quit()


func _weapon_shots(world: Node, player: PlayerController, rig: CameraRig) -> void:
	var inv := player.inventory
	var weapons := player.get_node("Weapons") as WeaponHandler
	for id in [&"baseball_bat", &"pistol"]:
		inv.add_item(id)
		player.auto_equip(id)
	inv.add_item(&"ammo_9mm", 30)
	# 1) de costas, andando, com taco preso na mochila
	player.global_position = Vector3(0, 0.05, 12)
	player.reset_physics_interpolation()
	rig.set("_yaw_deg", 0.0)
	rig.set("_pitch_deg", -10.0)
	Input.action_press("move_forward", 0.45)
	await _wait(60)
	Input.action_release("move_forward")
	_save("shot_w_back.png")
	# 2) golpe no boneco
	weapons.set_wielded(ItemData.Slot.MELEE)
	player.global_position = Vector3(3.5, 0.05, 10.7)
	player.reset_physics_interpolation()
	(player.get_node("Visual") as Node3D).rotation.y = 0.0
	rig.set("_yaw_deg", 60.0)
	rig.set("_pitch_deg", -8.0)
	await _wait(40)
	weapons.attack()
	await get_tree().create_timer(0.22).timeout
	_save("shot_w_swing.png")
	await _wait(40)
	# 3) pistola mirando na placa
	weapons.set_wielded(ItemData.Slot.SIDEARM)
	weapons.reload()
	player.global_position = Vector3(9.5, 0.05, 14.6)
	player.reset_physics_interpolation()
	var board := world.get_node("PracticeTargets/ShootingTarget") as Node3D
	for i in 10:
		var cam_pos := get_viewport().get_camera_3d().global_position
		var to_board := board.global_position + Vector3.UP * 1.35 - cam_pos
		rig.set("_yaw_deg", rad_to_deg(atan2(-to_board.x, -to_board.z)))
		rig.set("_pitch_deg", rad_to_deg(asin(to_board.y / to_board.length())))
		await _wait(12)
	await _wait(40)
	_save("shot_w_aim.png")
	weapons.attack()
	await _wait(1)
	_save("shot_w_fire.png")


func _save(file: String) -> void:
	get_viewport().get_texture().get_image().save_png("res://build/screenshots/" + file)
	print("salvo ", file)


func _wait(n: int) -> void:
	for i in n:
		await get_tree().process_frame
