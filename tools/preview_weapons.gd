extends Node3D
## Ferramenta de desenvolvimento: confere armas presas no corpo e nas mãos.
## Uso: godot --path . res://tools/preview_weapons.tscn

const SURVIVOR := "res://assets/models/survivor/survivor.glb"


func _ready() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.32, 0.34, 0.33)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.6, 0.62)
	env.ambient_light_energy = 0.7
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, 30, 0)
	sun.light_energy = 1.3
	add_child(sun)
	var cam := Camera3D.new()
	cam.fov = 30
	add_child(cam)
	cam.make_current()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build/screenshots"))

	var model := (load(SURVIVOR) as PackedScene).instantiate() as Node3D
	add_child(model)
	var player := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	model.find_child("Jacket", true, false).visible = true
	model.find_child("Backpack", true, false).visible = false

	var bat := _weapon("baseball_bat", model, "Socket_Back")
	var pistol := _weapon("pistol", model, "Socket_Holster")

	# 1) armas guardadas (costas e coldre)
	await _shot(player, "idle", 0.0, cam, 200.0, 1.3, 3.2, "w_back")
	await _shot(player, "idle", 0.0, cam, 60.0, 1.0, 3.6, "w_side")
	# 2) taco na mão
	_move(bat, model, "Socket_Hand_R")
	await _shot(player, "hold_melee", 0.0, cam, 30.0, 1.1, 3.4, "w_melee")
	await _shot(player, "hold_melee", 0.0, cam, 0.0, 1.0, 1.1, "w_hands_front")
	await _shot(player, "hold_melee", 0.0, cam, 60.0, 1.0, 1.1, "w_hands_side")
	await _shot(player, "hold_melee", 0.0, cam, -40.0, 1.0, 1.1, "w_hands_left")
	for i in 5:
		await _shot(player, "attack_melee", 0.8 * i / 5.0, cam, 20.0, 1.1, 3.6, "w_attack_%d" % i)
	# 3) pistola
	_move(bat, model, "Socket_Back")
	_move(pistol, model, "Socket_Hand_R")
	await _shot(player, "hold_pistol", 0.0, cam, 90.0, 1.3, 3.0, "w_pistol_side")
	await _shot(player, "hold_pistol", 0.0, cam, 15.0, 1.3, 3.0, "w_pistol_front")
	await _shot(player, "reload_pistol", 0.5, cam, 40.0, 1.2, 3.0, "w_reload")
	print("weapons ok")
	get_tree().quit()


func _weapon(id: String, model: Node, socket: String) -> Node3D:
	var w := (load("res://assets/models/weapons/%s.glb" % id) as PackedScene).instantiate() as Node3D
	model.find_child(socket, true, false).add_child(w)
	return w


func _move(w: Node3D, model: Node, socket: String) -> void:
	w.reparent(model.find_child(socket, true, false), false)
	w.transform = Transform3D.IDENTITY


func _shot(player: AnimationPlayer, anim: String, t: float, cam: Camera3D, yaw_deg: float, h: float, dist: float, file: String) -> void:
	player.play(anim)
	player.seek(t, true)
	player.pause()
	var yaw := deg_to_rad(yaw_deg)
	cam.position = Vector3(sin(yaw) * dist, h + 0.2, cos(yaw) * dist)
	cam.look_at(Vector3(0, h, 0))
	for i in 5:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("res://build/screenshots/%s.png" % file)
