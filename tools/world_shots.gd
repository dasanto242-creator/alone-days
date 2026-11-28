extends Node
## Ferramenta de desenvolvimento: capturas do cenário de vários pontos de vista.

func _ready() -> void:
	var world := (load("res://scenes/world/test_sandbox.tscn") as PackedScene).instantiate()
	add_child(world)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build/screenshots"))
	await _wait(5)
	world.get_node("ZombieSpawner").process_mode = Node.PROCESS_MODE_DISABLED
	var hud := world.find_child("HUD", true, false) as CanvasLayer
	if hud:
		hud.visible = false
	var q := int(OS.get_cmdline_user_args()[0]) if OS.get_cmdline_user_args().size() > 0 else 1
	GameSettings.set_quality(q)
	var cam := Camera3D.new()
	cam.fov = 70
	add_child(cam)
	cam.make_current()
	var views := [
		["w_house", Vector3(9, 2.2, 1), Vector3(0, 2.0, -14)],
		["w_street", Vector3(-9.5, 1.7, 22), Vector3(-12, 1.0, -10)],
		["w_grass", Vector3(4, 1.0, 14), Vector3(10, 0.4, 30)],
		["w_dragon", Vector3(20, 3.0, 16), Vector3(30, 2.0, 4)],
		["w_hills", Vector3(40, 6, 40), Vector3(140, 20, 160)],
		["w_air", Vector3(-60, 90, 120), Vector3(40, 0, -60)],
		["w_mountain", Vector3(0, 60, 150), Vector3(0, 60, 450)],
	]
	for v in views:
		cam.position = v[1]
		cam.look_at(v[2])
		await _wait(12)
		get_viewport().get_texture().get_image().save_png("res://build/screenshots/%s.png" % v[0])
		print("%s  tris %dk  draw calls %d" % [v[0], RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME) / 1000,
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)])
	get_tree().quit()


func _wait(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame
