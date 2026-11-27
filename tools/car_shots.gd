extends Node
## Ferramenta de desenvolvimento: capturas do carro (entrar, dirigir, curva, sair).
## Uso: godot --path . res://tools/car_shots.tscn  (precisa de tela/GPU)


func _ready() -> void:
	var world := (load("res://scenes/world/test_sandbox.tscn") as PackedScene).instantiate()
	add_child(world)
	var player := world.get_node("Player") as PlayerController
	var rig := world.get_node("CameraRig") as CameraRig
	var car := world.get_node("Car") as Vehicle
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build/screenshots"))
	await _wait(20)
	world.get_node("ZombieSpawner").process_mode = Node.PROCESS_MODE_DISABLED
	for z in get_tree().get_nodes_in_group("zombies"):
		z.free()
	await get_tree().create_timer(1.0).timeout
	player.global_position = car.exit_position() + Vector3(0, 0.05, 0.6)
	player.reset_physics_interpolation()
	rig.set("_yaw_deg", -60.0)
	rig.set("_pitch_deg", -8.0)
	await _wait(20)
	_save("car_0_near.png")
	player.enter_vehicle(car)
	for i in 4:
		await get_tree().create_timer(0.45).timeout
		_save("car_1_enter_%d.png" % i)
	await get_tree().create_timer(0.6).timeout
	_save("car_2_seated.png")
	Input.action_press("car_gas")
	await get_tree().create_timer(2.0).timeout
	_save("car_3_driving.png")
	Input.action_press("move_left", 1.0)
	await get_tree().create_timer(0.8).timeout
	_save("car_4_turn.png")
	Input.action_release("move_left")
	Input.action_release("car_gas")
	Input.action_press("jump")
	await get_tree().create_timer(2.5).timeout
	Input.action_release("jump")
	player.exit_vehicle()
	await get_tree().create_timer(0.9).timeout
	_save("car_5_exit.png")
	await get_tree().create_timer(1.5).timeout
	_save("car_6_out.png")
	get_tree().quit()


func _save(file: String) -> void:
	get_viewport().get_texture().get_image().save_png("res://build/screenshots/" + file)
	print("salvo ", file)


func _wait(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame
