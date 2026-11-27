extends Node
## Ferramenta de desenvolvimento: dirige o carro sozinha e imprime velocidade, marcha, rotação,
## inclinação e posição para ajustar a física. Uso: godot --headless --path . res://tools/car_check.tscn


func _ready() -> void:
	var world := (load("res://scenes/world/test_sandbox.tscn") as PackedScene).instantiate()
	add_child(world)
	var player := world.get_node("Player") as PlayerController
	var car := world.get_node("Car") as Vehicle
	await _frames(10)
	for z in get_tree().get_nodes_in_group("zombies"):
		z.free()
	world.get_node("ZombieSpawner").process_mode = Node.PROCESS_MODE_DISABLED
	await get_tree().create_timer(1.5).timeout
	_log("assentado", car)
	player.global_position = car.exit_position()
	await _frames(5)
	player.enter_vehicle(car)
	await get_tree().create_timer(2.4).timeout
	print("dirigindo? ", player.in_vehicle(), " etapa ", player.get("_vehicle_stage"))
	Input.action_press("car_gas")
	for i in 8:
		await get_tree().create_timer(0.5).timeout
		_log("acelerando", car)
	Input.action_press("move_right", 1.0)
	for i in 4:
		await get_tree().create_timer(0.5).timeout
		_log("curva", car)
	Input.action_release("move_right")
	Input.action_release("car_gas")
	Input.action_press("car_brake")
	for i in 6:
		await get_tree().create_timer(0.5).timeout
		_log("freando", car)
	await get_tree().create_timer(1.0).timeout
	_log("ré", car)
	Input.action_release("car_brake")
	Input.action_press("jump")
	await get_tree().create_timer(2.5).timeout
	_log("freio mão", car)
	Input.action_release("jump")
	Input.action_press("interact")
	await get_tree().create_timer(0.15).timeout
	Input.action_release("interact")
	await get_tree().create_timer(2.2).timeout
	print("saiu? ", not player.in_vehicle(), " jogador ", player.global_position, " chão ", player.is_on_floor())
	get_tree().quit()


func _log(tag: String, car: Vehicle) -> void:
	var up := car.global_basis.y
	print("%-10s v=%5.1f km/h marcha=%d rpm=%4.0f inclinação=%4.1f° pos=%s yaw=%.0f" % [tag, car.speed_kmh, car.gear,
		car.rpm, rad_to_deg(up.angle_to(Vector3.UP)), car.global_position.snapped(Vector3.ONE * 0.1),
		rad_to_deg(car.global_rotation.y)])


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
