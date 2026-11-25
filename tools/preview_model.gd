extends Node3D
## Ferramenta de desenvolvimento: renderiza um modelo 3D de vários ângulos.
## Uso: godot --path . res://tools/preview_model.tscn -- <res://caminho.glb> <prefixo> [animação]

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var path := args[0] if args.size() > 0 else "res://assets/models/survivor/survivor.glb"
	var prefix := args[1] if args.size() > 1 else "model"
	var anim_name := args[2] if args.size() > 2 else ""
	_close = args.size() > 3 and args[3] == "close"

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.32, 0.34, 0.33)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.57, 0.6)
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, 30, 0)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-15, -150, 0)
	fill.light_energy = 0.35
	add_child(fill)

	var model := (load(path) as PackedScene).instantiate() as Node3D
	add_child(model)
	var player := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if player:
		print("animações: ", player.get_animation_list())
	if player and not anim_name.is_empty():
		await _anim_sheet(model, player, anim_name, prefix)
		get_tree().quit()
		return

	var cam := Camera3D.new()
	cam.fov = 32
	add_child(cam)
	cam.make_current()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build/screenshots"))

	var views := [["front", 0.0, 1.0, 5.2], ["side", 90.0, 1.0, 5.2], ["back", 180.0, 1.0, 5.2],
		["face", 20.0, 1.62, 1.3], ["three_quarter", 35.0, 1.0, 4.6]]
	for v in views:
		var yaw := deg_to_rad(v[1])
		var target := Vector3(0, v[2], 0)
		cam.position = target + Vector3(sin(yaw), 0.05, cos(yaw)) * v[3]
		cam.look_at(target)
		for i in 8:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("res://build/screenshots/%s_%s.png" % [prefix, v[0]])
	print("preview ok")
	get_tree().quit()


var _close := false


## Captura 6 quadros da animação, de lado e de frente.
func _anim_sheet(model: Node3D, player: AnimationPlayer, anim_name: String, prefix: String) -> void:
	var cam := Camera3D.new()
	cam.fov = 32
	add_child(cam)
	cam.make_current()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build/screenshots"))
	player.play(anim_name)
	player.pause()
	var length := player.current_animation_length
	if _close:
		# garrafa de teste na mão direita (eixo +Y = polegar), para conferir a orientação
		var hand := model.find_child("Socket_Hand_R", true, false) as Node3D
		if hand:
			var bottle := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.02
			cyl.bottom_radius = 0.035
			cyl.height = 0.22
			bottle.mesh = cyl
			var m := StandardMaterial3D.new()
			m.albedo_color = Color(0.3, 0.6, 0.95)
			bottle.material_override = m
			hand.add_child(bottle)
	var views := [["side", 90.0], ["front", 20.0]]
	if _close:
		views = [["side", 90.0], ["front", 10.0], ["right", -60.0]]
	for view in views:
		var yaw := deg_to_rad(view[1])
		if _close:
			cam.position = Vector3(0, 1.35, 0) + Vector3(sin(yaw), 0.05, cos(yaw)) * 2.2
			cam.look_at(Vector3(0, 1.3, 0))
		else:
			cam.position = Vector3(0, 0.95, 0) + Vector3(sin(yaw), 0.08, cos(yaw)) * 5.0
			cam.look_at(Vector3(0, 0.85, 0))
		for i in 6:
			player.seek(length * i / 6.0, true)
			for k in 4:
				await get_tree().process_frame
			get_viewport().get_texture().get_image().save_png(
				"res://build/screenshots/%s_%s_%s_%d.png" % [prefix, anim_name, view[0], i])
	print("anim ok ", anim_name, " ", length)
