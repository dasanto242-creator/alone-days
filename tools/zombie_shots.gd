extends Node
## Ferramenta de desenvolvimento: capturas do zumbi e das ações (beber, pegar).
## Uso: godot --path . res://tools/zombie_shots.tscn  (precisa de tela/GPU)


func _ready() -> void:
	var world := (load("res://scenes/world/test_sandbox.tscn") as PackedScene).instantiate()
	add_child(world)
	var player := world.get_node("Player") as PlayerController
	var rig := world.get_node("CameraRig") as CameraRig
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build/screenshots"))
	await _wait(20)
	world.get_node("ZombieSpawner").process_mode = Node.PROCESS_MODE_DISABLED
	for z in get_tree().get_nodes_in_group("zombies"):
		z.free()
	player.global_position = Vector3(0, 0.05, 30)
	player.reset_physics_interpolation()
	rig.set("_yaw_deg", 200.0)
	rig.set("_pitch_deg", -8.0)
	var zs: Array[Zombie] = []
	for p in [Vector3(-1.2, 0.05, 35.5), Vector3(1.8, 0.05, 37.5)]:
		var z := (load("res://scenes/characters/zombie.tscn") as PackedScene).instantiate() as Zombie
		world.add_child(z)
		z.global_position = p
		zs.append(z)
	await _wait(10)
	for z in zs:
		z.apply_damage(1.0, player, z.global_position + Vector3.UP)  # acorda e persegue
	rig.set("_yaw_deg", 160.0)
	await get_tree().create_timer(2.5).timeout
	_save("shot_zombie_chase.png")
	await get_tree().create_timer(4.0).timeout
	_save("shot_zombie_chase2.png")
	for z in zs:
		z.queue_free()
	# beber
	player.global_position = Vector3(-4, 0.05, 14)
	player.reset_physics_interpolation()
	rig.set("_yaw_deg", -150.0)
	rig.set("_pitch_deg", -6.0)
	player.inventory.add_item(&"water_bottle")
	await _wait(20)
	player.use_item(player.inventory.index_of(&"water_bottle"))
	await get_tree().create_timer(0.75).timeout
	_save("shot_drink.png")
	await _wait(60)
	# pegar do chão
	ItemPickup.spawn(world, &"can_beans", 1, 100.0, Vector3(-4, 0.2, 13.2))
	await _wait(40)
	player._visual.rotation.y = 0.0
	player.begin_pickup(world.get_children().back())
	await get_tree().create_timer(0.45).timeout
	_save("shot_pickup.png")
	await _wait(40)
	await _parkour_shots(world, player, rig)
	get_tree().quit()


func _parkour_shots(world: Node, player: PlayerController, rig: CameraRig) -> void:
	var visual := player.get_node("Visual") as Node3D
	# salto sobre a cerca, visto de lado
	player.global_position = Vector3(5.9, 0.05, 12.0)
	player.reset_physics_interpolation()
	visual.rotation.y = -PI / 2
	rig.set("_yaw_deg", -20.0)
	rig.set("_pitch_deg", -8.0)
	await _wait(20)
	Input.action_press("jump")
	await _wait(2)
	Input.action_release("jump")
	for i in 3:
		await get_tree().create_timer(0.22).timeout
		_save("shot_vault_%d.png" % i)
	await get_tree().create_timer(1.0).timeout
	# escalada da plataforma
	player.global_position = Vector3(12.0, 0.05, -7.0)
	player.reset_physics_interpolation()
	visual.rotation.y = PI
	rig.set("_yaw_deg", 120.0)
	rig.set("_pitch_deg", -5.0)
	await _wait(20)
	Input.action_press("jump")
	await _wait(2)
	Input.action_release("jump")
	for i in 4:
		await get_tree().create_timer(0.3).timeout
		_save("shot_climb_%d.png" % i)
	await get_tree().create_timer(1.0).timeout
	# machado e árvore
	var inv := player.inventory
	inv.add_item(&"axe")
	player.auto_equip(&"axe")
	inv.add_item(&"pistol")
	player.auto_equip(&"pistol")
	inv.add_item(&"baseball_bat")
	var weapons := player.get_node("Weapons") as WeaponHandler
	weapons.select_entry(0)
	player.global_position = Vector3(-17, 0.05, 11.0)
	player.reset_physics_interpolation()
	visual.rotation.y = 0.0
	rig.set("_yaw_deg", 35.0)
	rig.set("_pitch_deg", -4.0)
	await _wait(20)
	_save("shot_axe.png")
	var tree := world.get_node("Grove/ChopTree0") as ChoppableTree
	for i in tree.hits_to_fell:
		player.stats.stamina = 100.0
		Input.action_press("attack")
		await _wait(2)
		Input.action_release("attack")
		await get_tree().create_timer(1.1).timeout
	await get_tree().create_timer(1.0).timeout
	_save("shot_tree_fall_0.png")
	await get_tree().create_timer(1.2).timeout
	_save("shot_tree_fall_1.png")
	# pegar ou guardar
	weapons.set_wielded(-1)
	ItemPickup.spawn(world, &"water_bottle", 1, 100.0, Vector3(-4, 0.3, 21.2))
	player.global_position = Vector3(-4, 0.05, 22.0)
	player.reset_physics_interpolation()
	rig.set("_yaw_deg", -30.0)
	rig.set("_pitch_deg", -10.0)
	await get_tree().create_timer(1.0).timeout
	_save("shot_pick_or_store.png")
	Input.action_press("interact")
	await _wait(2)
	Input.action_release("interact")
	await get_tree().create_timer(1.4).timeout
	_save("shot_holding.png")


func _save(file: String) -> void:
	get_viewport().get_texture().get_image().save_png("res://build/screenshots/" + file)
	print("salvo ", file)


func _wait(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame
