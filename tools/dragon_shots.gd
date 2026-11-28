extends Node
## Ferramenta de desenvolvimento: monta no dragão, voa, pousa e desmonta, salvando capturas.
## Uso: godot --path . res://tools/dragon_shots.tscn [-- headless]

var _shots := true
var _cam: Camera3D
var _rig_cam: Camera3D


## Foto de perto: câmera num ponto relativo ao dragão, olhando para outro ponto dele.
func _close(file: String, d: Dragon, from_local: Vector3, at_local: Vector3) -> void:
	if not _shots:
		return
	if _cam == null:
		_cam = Camera3D.new()
		_cam.fov = 55
		add_child(_cam)
	_rig_cam = get_viewport().get_camera_3d()
	_cam.global_position = d.global_transform * from_local
	_cam.look_at(d.global_transform * at_local)
	_cam.make_current()
	await get_tree().process_frame
	await get_tree().process_frame
	_save(file)
	_rig_cam.make_current()


func _ready() -> void:
	_shots = not ("headless" in OS.get_cmdline_user_args())
	var world := (load("res://scenes/world/test_sandbox.tscn") as PackedScene).instantiate()
	add_child(world)
	var player := world.get_node("Player") as PlayerController
	var rig := world.get_node("CameraRig") as CameraRig
	var d := world.get_node("Dragon") as Dragon
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build/screenshots"))
	await _wait(10)
	world.get_node("ZombieSpawner").process_mode = Node.PROCESS_MODE_DISABLED
	for z in get_tree().get_nodes_in_group("zombies"):
		z.free()
	player.global_position = d.mount_position() + d.global_transform.basis * Vector3(-2.0, 0, 0.5)
	player.reset_physics_interpolation()
	rig.set("_yaw_deg", rad_to_deg(d.global_rotation.y) - 120.0)
	rig.set("_pitch_deg", -12.0)
	await get_tree().create_timer(1.0).timeout
	_save("drg_0_lying.png")
	print("seat lying: ", d.seat_transform().origin, " ground ", d.global_position.y, " spot ", d.mount_position())
	player.mount_dragon(d)
	await get_tree().create_timer(0.9).timeout
	await _close("drg_1_mount_a.png", d, Vector3(-6.5, 2.2, -1.0), Vector3(0, 1.3, -2.2))
	await get_tree().create_timer(0.6).timeout
	await _close("drg_2_mount_b.png", d, Vector3(-6.5, 2.2, -1.0), Vector3(0, 1.6, -2.2))
	await get_tree().create_timer(0.5).timeout
	await _close("drg_2b_mount_c.png", d, Vector3(-6.5, 2.2, -1.0), Vector3(0, 1.8, -2.2))
	await get_tree().create_timer(1.6).timeout
	await _close("drg_3b_seated_close.png", d, Vector3(-4.5, 4.0, -4.5), Vector3(0, 3.0, -2.2))
	print("estado após montar: ", d.state, " rider ", player.riding_dragon())
	_save("drg_3_seated.png")
	Input.action_press("dragon_roar")
	await _wait(2)
	Input.action_release("dragon_roar")
	await get_tree().create_timer(0.8).timeout
	_save("drg_4_roar.png")
	await get_tree().create_timer(1.5).timeout
	Input.action_press("move_forward", 1.0)
	await get_tree().create_timer(1.5).timeout
	_save("drg_5_walk.png")
	Input.action_release("move_forward")
	await get_tree().create_timer(0.5).timeout
	Input.action_press("dragon_flap")
	await _wait(2)
	await get_tree().create_timer(0.6).timeout
	_save("drg_6_takeoff.png")
	await get_tree().create_timer(2.5).timeout
	await _close("drg_7b_flap_close.png", d, Vector3(-7.0, 4.5, -6.0), Vector3(0, 2.6, -1.5))
	await get_tree().create_timer(0.27).timeout
	await _close("drg_7c_flap_side.png", d, Vector3(-16.0, 1.0, -3.0), Vector3(0, 2.6, -1.0))
	print("voando: estado ", d.state, " alt %.1f vel %.1f km/h" % [d.altitude(), d.speed_kmh()])
	_save("drg_7_flap.png")
	Input.action_press("move_forward", 0.6)
	await get_tree().create_timer(2.5).timeout
	Input.action_release("move_forward")
	Input.action_release("dragon_flap")
	print("subindo: alt %.1f vel %.1f km/h" % [d.altitude(), d.speed_kmh()])
	await get_tree().create_timer(1.5).timeout
	_save("drg_8_glide.png")
	Input.action_press("move_right", 1.0)
	await get_tree().create_timer(1.6).timeout
	_save("drg_9_bank.png")
	await _close("drg_9b_bank_close.png", d, Vector3(-3.0, 9.0, 12.0), Vector3(0, 2.5, -1.5))
	await _close("drg_9c_hero.png", d, Vector3(-14.0, 3.0, -6.0), Vector3(0, 2.0, 2.0))
	print("curva: yaw %.0f roll %.0f alt %.1f" % [rad_to_deg(d.rotation.y), d.roll_deg, d.altitude()])
	await get_tree().create_timer(1.5).timeout
	Input.action_release("move_right")
	Input.action_press("move_back", 0.8)
	await get_tree().create_timer(1.8).timeout
	_save("drg_10_dive.png")
	print("mergulho: pitch %.0f vel %.1f km/h alt %.1f anim %s" % [d.pitch_deg, d.speed_kmh(), d.altitude(), d.current_anim()])
	Input.action_release("move_back")
	await get_tree().create_timer(1.0).timeout
	Input.action_press("dragon_land")
	await _wait(2)
	Input.action_release("dragon_land")
	await get_tree().create_timer(1.2).timeout
	_save("drg_11_hover.png")
	var t := 0.0
	while d.state != Dragon.State.STANDING and t < 15.0:
		await get_tree().create_timer(0.25).timeout
		t += 0.25
	print("pousou em %.1f s: estado %d alt %.2f" % [t, d.state, d.altitude()])
	_save("drg_12_landed.png")
	Input.action_press("interact")
	await _wait(2)
	Input.action_release("interact")
	await get_tree().create_timer(2.2).timeout
	_save("drg_13_dismount.png")
	await get_tree().create_timer(1.5).timeout
	print("desmontou: ", not player.riding_dragon(), " pos ", player.global_position, " dragão ", d.state)
	_save("drg_14_off.png")
	get_tree().quit()


func _save(file: String) -> void:
	if _shots:
		get_viewport().get_texture().get_image().save_png("res://build/screenshots/" + file)


func _wait(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame
