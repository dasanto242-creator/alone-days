extends Node
## Ferramenta de desenvolvimento: capturas dos movimentos (escaladas, pulo, beber, andar mirando).
## Uso: godot --path . res://tools/move_shots.tscn  (precisa de tela/GPU)


func _ready() -> void:
	var world := (load("res://scenes/world/test_sandbox.tscn") as PackedScene).instantiate()
	add_child(world)
	var player := world.get_node("Player") as PlayerController
	var rig := world.get_node("CameraRig") as CameraRig
	var visual := player.get_node("Visual") as Node3D
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build/screenshots"))
	await _wait(20)
	world.get_node("ZombieSpawner").process_mode = Node.PROCESS_MODE_DISABLED
	for z in get_tree().get_nodes_in_group("zombies"):
		z.free()
	# muro alto de 2,2 m
	await _place(player, rig, Vector3(16.5, 0.05, 5.4), 0.0, 60.0, -6.0)
	_press("jump")
	for t in [0.35, 0.5, 0.5, 0.45, 0.5, 0.5]:
		await get_tree().create_timer(t).timeout
		_save("mv_climbhigh_%d.png" % int(Time.get_ticks_msec() % 100000))
	await get_tree().create_timer(1.0).timeout
	# bloco baixo
	await _place(player, rig, Vector3(16.5, 0.05, -10.6), PI, 230.0, -6.0)
	_press("jump")
	for t in [0.25, 0.25, 0.3]:
		await get_tree().create_timer(t).timeout
		_save("mv_mantle_%d.png" % int(Time.get_ticks_msec() % 100000))
	await get_tree().create_timer(1.0).timeout
	# beber, de perto
	await _place(player, rig, Vector3(-4, 0.05, 14), 0.0, -140.0, -4.0)
	rig.set("_distance", 2.0)
	player.inventory.add_item(&"water_bottle")
	await _wait(10)
	player.use_item(player.inventory.index_of(&"water_bottle"))
	await get_tree().create_timer(0.7).timeout
	_save("mv_drink.png")
	await get_tree().create_timer(1.4).timeout
	# pulo parado
	await _place(player, rig, Vector3(0, 0.05, 22), 0.0, 90.0, -4.0)
	_press("jump")
	await get_tree().create_timer(0.08).timeout
	_save("mv_jump_0.png")
	await get_tree().create_timer(0.3).timeout
	_save("mv_jump_1.png")
	await get_tree().create_timer(1.0).timeout
	get_tree().quit()


func _place(player: PlayerController, rig: CameraRig, pos: Vector3, body_yaw: float, cam_yaw: float, pitch: float) -> void:
	player.global_position = pos
	player.velocity = Vector3.ZERO
	player.reset_physics_interpolation()
	(player.get_node("Visual") as Node3D).rotation.y = body_yaw
	player.stats.stamina = 100.0
	rig.set("_yaw_deg", cam_yaw)
	rig.set("_pitch_deg", pitch)
	await _wait(25)


func _press(action: String) -> void:
	Input.action_press(action)
	await get_tree().process_frame
	await get_tree().process_frame
	Input.action_release(action)


func _save(file: String) -> void:
	get_viewport().get_texture().get_image().save_png("res://build/screenshots/" + file)
	print("salvo ", file)


func _wait(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame
