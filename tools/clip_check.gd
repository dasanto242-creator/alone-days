extends Node
## Ferramenta de desenvolvimento: mede se o corpo do personagem entra nos obstáculos durante
## os movimentos de parkour. Para cada quadro, testa as juntas do esqueleto (exceto mãos/dedos)
## contra a colisão do mundo e informa o pior caso.
## Uso: godot --headless --path . res://tools/clip_check.tscn

const BONES := ["pelvis", "spine03", "spine01", "neck01", "head", "upperleg01.L", "upperleg01.R",
	"lowerleg01.L", "lowerleg01.R", "foot.L", "foot.R", "upperarm01.L", "upperarm01.R", "lowerarm01.L",
	"lowerarm01.R", "clavicle.L", "clavicle.R"]

var results := {}


func _ready() -> void:
	var world := (load("res://scenes/world/test_sandbox.tscn") as PackedScene).instantiate()
	add_child(world)
	var player := world.get_node("Player") as PlayerController
	await _frames(15)
	for z in get_tree().get_nodes_in_group("zombies"):
		z.free()
	world.get_node("ZombieSpawner").process_mode = Node.PROCESS_MODE_DISABLED
	var cases := [
		["vault (cerca 1,2 m)", Vector3(5.9, 0.05, 12.0), -PI / 2],
		["mantle (bloco 0,8 m)", Vector3(16.5, 0.05, -10.6), PI],
		["climb (plataforma 1,5 m)", Vector3(12.0, 0.05, -7.0), PI],
		["climb_high (muro 2,2 m)", Vector3(16.5, 0.05, 5.4), 0.0],
		["climb_high perto (0,25 m)", Vector3(16.5, 0.05, 4.8), 0.0],
		["climb perto", Vector3(12.0, 0.05, -6.35), PI],
	]
	var total_bad := 0
	for c in cases:
		var bad := await _run_case(player, c[0], c[1], c[2])
		total_bad += bad
	print("CLIP_TOTAL ", total_bad)
	get_tree().quit()


func _run_case(player: PlayerController, label: String, pos: Vector3, yaw: float) -> int:
	player.global_position = pos
	player.velocity = Vector3.ZERO
	(player.get_node("Visual") as Node3D).rotation.y = yaw
	player.stats.stamina = 100.0
	await _frames(10)
	if not player.parkour.try_start():
		print("CLIP ", label, ": NÃO INICIOU")
		return 1
	var sk := player.find_child("Skeleton3D", true, false) as Skeleton3D
	var space := player.get_world_3d().direct_space_state
	var worst := 0.0
	var worst_bone := ""
	var bad_frames := 0
	var frame := 0
	while player.parkour.is_active():
		await get_tree().physics_frame
		await get_tree().process_frame
		frame += 1
		var any := false
		for b in BONES:
			var idx := sk.find_bone(b)
			if idx < 0:
				continue
			var p := sk.global_transform * sk.get_bone_global_pose(idx).origin
			var depth := _depth(space, p, player)
			if depth > 0.0:
				any = true
				if depth > worst:
					worst = depth
					worst_bone = "%s q%d" % [b, frame]
		if any:
			bad_frames += 1
	print("CLIP %s: quadros com junta dentro = %d / %d, pior %.2f m (%s)" % [label, bad_frames, frame, worst, worst_bone])
	await _frames(20)
	return bad_frames


## Profundidade aproximada: testa o ponto e pontos recuados até 20 cm em 6 direções.
func _depth(space: PhysicsDirectSpaceState3D, p: Vector3, player: Node) -> float:
	var q := PhysicsPointQueryParameters3D.new()
	q.collision_mask = 1
	q.exclude = [player.get_rid()]
	q.position = p
	if space.intersect_point(q, 1).is_empty():
		return 0.0
	var d := 0.02
	while d <= 0.3:
		for dir in [Vector3.UP, Vector3.DOWN, Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK]:
			q.position = p + dir * d
			if space.intersect_point(q, 1).is_empty():
				return d
		d += 0.02
	return 0.3


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
