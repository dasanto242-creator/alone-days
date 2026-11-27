extends Node
## Ferramenta de desenvolvimento: capturas de porta-malas, fogueira e mira.
## Uso: godot --path . res://tools/feature_shots.tscn  (precisa de tela/GPU)


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
	# --- porta-malas
	for item in [[&"can_beans", 2], [&"water_bottle", 1], [&"bandage", 2], [&"firewood", 2]]:
		player.inventory.add_item(item[0], item[1])
	car.trunk.add_item(&"soda_can", 3)
	player.global_position = car.global_transform * Vector3(0, 0.05, 2.9)
	player.reset_physics_interpolation()
	rig.set("_yaw_deg", 150.0)
	rig.set("_pitch_deg", -14.0)
	await _wait(20)
	player.use_trunk(car, true)
	await get_tree().create_timer(0.7).timeout
	_save("feat_0_trunk_opening.png")
	await get_tree().create_timer(1.6).timeout
	_save("feat_1_trunk_screen.png")
	(world.find_child("ContainerScreen", true, false) as ContainerScreen).close()
	rig.set("_yaw_deg", 205.0)
	await get_tree().create_timer(0.8).timeout
	_save("feat_2_trunk_open.png")
	car.set_trunk_open(false)
	# --- fogueira (no fim da tarde, para o fogo aparecer)
	var env := world.find_child("WorldEnvironment", true, false) as WorldEnvironment
	var sun := world.find_child("Sun", true, false) as DirectionalLight3D
	player.global_position = Vector3(4.0, 0.05, 24.0)
	player.reset_physics_interpolation()
	(player.get_node("Visual") as Node3D).rotation.y = 0.0
	player.inventory.add_item(&"firewood", 3)
	await _wait(10)
	rig.set("_yaw_deg", 70.0)
	rig.set("_pitch_deg", -10.0)
	player.build_campfire()
	await get_tree().create_timer(1.2).timeout
	_save("feat_3_build_fire.png")
	await get_tree().create_timer(5.0).timeout
	if sun:
		sun.light_energy = 0.04
	if env and env.environment:
		env.environment.background_energy_multiplier = 0.08
		env.environment.ambient_light_energy = 0.08
	rig.set("_yaw_deg", 25.0)
	rig.set("_pitch_deg", -8.0)
	await get_tree().create_timer(1.5).timeout
	_save("feat_4_fire_night.png")
	player.global_position = Vector3(5.3, 0.05, 24.2)
	player.reset_physics_interpolation()
	(player.get_node("Visual") as Node3D).rotation.y = deg_to_rad(40.0)
	rig.set("_yaw_deg", 10.0)
	rig.set("_pitch_deg", -14.0)
	await get_tree().create_timer(1.5).timeout
	_save("feat_5_fire_close.png")
	if sun:
		sun.light_energy = 1.0
	if env and env.environment:
		env.environment.background_energy_multiplier = 1.0
		env.environment.ambient_light_energy = 1.0
	# --- mira
	var weapons := player.get_node("Weapons") as WeaponHandler
	player.global_position = Vector3(0.0, 0.05, 8.0)
	player.reset_physics_interpolation()
	player.inventory.add_item(&"pistol", 1)
	player.inventory.add_item(&"ammo_9mm", 30)
	player.inventory.equip(player.inventory.index_of(&"pistol"))
	await _wait(5)
	weapons.set_wielded(ItemData.Slot.SIDEARM)
	rig.set("_yaw_deg", 0.0)
	rig.set("_pitch_deg", -4.0)
	await get_tree().create_timer(1.0).timeout
	_save("feat_6_pistol_hip.png")
	weapons.set_aiming(true)
	await get_tree().create_timer(1.0).timeout
	_save("feat_7_pistol_aim.png")
	get_tree().quit()


func _save(file: String) -> void:
	get_viewport().get_texture().get_image().save_png("res://build/screenshots/" + file)
	print("salvo ", file)


func _wait(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame
