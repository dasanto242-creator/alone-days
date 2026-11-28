extends Node3D
## Ferramenta de desenvolvimento: quadros de uma animação de um modelo grande (dragão).
## Uso: godot --path . res://tools/dragon_preview.tscn -- <glb> <anim> [vistas: side,front,top,tq] [quadros]

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var path := args[0]
	var anim_name := args[1] if args.size() > 1 else ""
	var views := (args[2] if args.size() > 2 else "side,front,tq").split(",")
	var count := int(args[3]) if args.size() > 3 else 6
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.42, 0.46, 0.5)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.62, 0.66)
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0)
	sun.light_energy = 1.4
	sun.shadow_enabled = true
	add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 60)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.3, 0.33, 0.27)
	ground.material_override = gm
	add_child(ground)
	var model := (load(path) as PackedScene).instantiate() as Node3D
	add_child(model)
	var player := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	print("animações: ", player.get_animation_list())
	var cam := Camera3D.new()
	cam.fov = 40
	add_child(cam)
	cam.make_current()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build/screenshots"))
	var length := 1.0
	if anim_name != "":
		player.play(anim_name)
		player.pause()
		length = player.current_animation_length
	for v in views:
		match v:
			"side":
				cam.position = Vector3(19, 2.5, -0.5); cam.look_at(Vector3(0, 2.0, -0.5))
			"front":
				cam.position = Vector3(0, 3.0, -19); cam.look_at(Vector3(0, 2.2, 0))
			"top":
				cam.position = Vector3(0, 21, -0.6); cam.look_at(Vector3(0, 2, -0.5), Vector3(0, 0, -1))
			"tq":
				cam.position = Vector3(12, 6, -12); cam.look_at(Vector3(0, 2.2, -0.8))
			"head":
				cam.position = Vector3(3.2, 4.0, -7.2); cam.look_at(Vector3(0, 3.4, -5.0))
			"back":
				cam.position = Vector3(-7, 6.5, 9); cam.look_at(Vector3(0, 2.6, -1.5))
		for i in count:
			if anim_name != "":
				player.seek(length * float(i) / float(count), true)
			for k in 4:
				await get_tree().process_frame
			get_viewport().get_texture().get_image().save_png("res://build/screenshots/dr_%s_%s_%d.png" % [anim_name, v, i])
	get_tree().quit()
