extends Node
## Ferramenta de desenvolvimento: abre o cenário, posiciona a câmera e salva capturas.
## Uso: godot --path . res://tools/screenshot.tscn  (precisa de tela/GPU)

const SHOTS := [
	{"pos": Vector3(0, 0.05, 6), "yaw": 0.0, "pitch": -12.0, "file": "shot_house.png"},
	{"pos": Vector3(-6, 0.05, 8), "yaw": -140.0, "pitch": -18.0, "file": "shot_road.png"},
	{"pos": Vector3(1, 0.15, -14.5), "yaw": 30.0, "pitch": -15.0, "file": "shot_indoor.png"},
]


func _ready() -> void:
	var world := (load("res://scenes/world/test_sandbox.tscn") as PackedScene).instantiate()
	add_child(world)
	var player := world.get_node("Player") as PlayerController
	var rig := world.get_node("CameraRig") as CameraRig
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build/screenshots"))
	await _wait(30)
	for shot in SHOTS:
		player.global_position = shot.pos
		player.reset_physics_interpolation()
		TouchInput.add_look(Vector2(rad_to_deg(rig.get_yaw()) - shot.yaw, rig.get_pitch_degrees() - shot.pitch))
		await _wait(90)
		var img := get_viewport().get_texture().get_image()
		img.save_png("res://build/screenshots/" + shot.file)
		print("salvo ", shot.file)
	get_tree().quit()


func _wait(n: int) -> void:
	for i in n:
		await get_tree().process_frame
