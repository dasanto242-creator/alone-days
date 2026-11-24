extends Node
## Ferramenta de desenvolvimento: gera as cenas da Etapa 1 a partir de código.
## Uso: godot --headless --path . res://tools/build_scenes.tscn
## (roda como cena para que os autoloads Events/GameSettings/TouchInput existam)
## Depois de gerado, tudo pode ser editado normalmente no editor do Godot.

const PLAYER_SCENE := "res://scenes/player/player.tscn"
const CAMERA_SCENE := "res://scenes/player/camera_rig.tscn"
const HUD_SCENE := "res://scenes/ui/hud.tscn"
const SANDBOX_SCENE := "res://scenes/world/test_sandbox.tscn"

const LAYER_WORLD := 1
const LAYER_PLAYER := 2
const LAYER_INTERACTABLE := 4
const LAYER_TRIGGER := 8

var _materials := {}


func _ready() -> void:
	var ok := true
	ok = _save(_build_player(), PLAYER_SCENE) and ok
	ok = _save(_build_camera_rig(), CAMERA_SCENE) and ok
	ok = _save(_build_hud(), HUD_SCENE) and ok
	ok = _save(_build_sandbox(), SANDBOX_SCENE) and ok
	print("build_scenes: ", "OK" if ok else "FALHOU")
	get_tree().quit(0 if ok else 1)


# ---------------------------------------------------------------- utilidades

func _save(root: Node, path: String) -> bool:
	_assign_owner(root, root)
	var packed := PackedScene.new()
	var err := packed.pack(root)
	if err == OK:
		err = ResourceSaver.save(packed, path)
	root.free()
	if err != OK:
		push_error("Falha ao salvar %s (%d)" % [path, err])
	return err == OK


func _assign_owner(node: Node, owner_node: Node) -> void:
	for child in node.get_children():
		child.owner = owner_node
		if child.scene_file_path.is_empty():
			_assign_owner(child, owner_node)


func _node(type: Object, node_name: String, parent: Node = null, script_path := "") -> Node:
	var n: Node = type.new()
	n.name = node_name
	if not script_path.is_empty():
		n.set_script(load(script_path))
	if parent:
		parent.add_child(n)
	return n


func _mat(color: Color, roughness := 0.9) -> StandardMaterial3D:
	var key := "%s_%s" % [color.to_html(), roughness]
	if not _materials.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = roughness
		_materials[key] = m
	return _materials[key]


func _mesh(parent: Node, node_name: String, mesh: Mesh, color: Color, pos := Vector3.ZERO) -> MeshInstance3D:
	var mi := _node(MeshInstance3D, node_name, parent) as MeshInstance3D
	mi.mesh = mesh
	mi.material_override = _mat(color)
	mi.position = pos
	return mi


func _capsule(radius: float, height: float) -> CapsuleMesh:
	var m := CapsuleMesh.new()
	m.radius = radius
	m.height = height
	m.radial_segments = 12
	m.rings = 4
	return m


## Bloco sólido (visual + colisão).
func _block(parent: Node, node_name: String, size: Vector3, pos: Vector3, color: Color,
		layer := LAYER_WORLD, rot_deg := Vector3.ZERO) -> StaticBody3D:
	var body := _node(StaticBody3D, node_name, parent) as StaticBody3D
	body.position = pos
	body.rotation_degrees = rot_deg
	body.collision_layer = layer
	body.collision_mask = 0
	var shape := BoxShape3D.new()
	shape.size = size
	var col := _node(CollisionShape3D, "Collision", body) as CollisionShape3D
	col.shape = shape
	var box := BoxMesh.new()
	box.size = size
	_mesh(body, "Mesh", box, color)
	return body


# ---------------------------------------------------------------- personagem

func _build_player() -> Node:
	var player := _node(CharacterBody3D, "Player", null, "res://scripts/player/player_controller.gd") as CharacterBody3D
	player.collision_layer = LAYER_PLAYER
	player.collision_mask = LAYER_WORLD
	player.floor_max_angle = deg_to_rad(46.0)
	player.floor_snap_length = 0.35

	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.8
	var col := _node(CollisionShape3D, "CollisionShape3D", player) as CollisionShape3D
	col.shape = capsule
	col.position.y = 0.9

	# Boneco provisório (será trocado pelo modelo 3D definitivo)
	var jacket := Color(0.29, 0.33, 0.2)
	var pants := Color(0.18, 0.19, 0.19)
	var skin := Color(0.62, 0.5, 0.42)
	var gear := Color(0.24, 0.21, 0.16)

	var visual := _node(Node3D, "Visual", player, "res://scripts/player/placeholder_animator.gd")
	var body := _node(Node3D, "Body", visual)
	var hips := _node(Node3D, "Hips", body) as Node3D
	hips.position.y = 0.95
	for side in [-1.0, 1.0]:
		var leg := _node(Node3D, "LegL" if side < 0 else "LegR", hips) as Node3D
		leg.position.x = 0.12 * side
		_mesh(leg, "Mesh", _capsule(0.1, 0.92), pants, Vector3(0, -0.46, 0))
	var torso := _node(Node3D, "Torso", hips) as Node3D
	torso.position.y = 0.04
	_mesh(torso, "Chest", _capsule(0.21, 0.68), jacket, Vector3(0, 0.3, 0))
	var head := SphereMesh.new()
	head.radius = 0.13
	head.height = 0.27
	_mesh(torso, "Head", head, skin, Vector3(0, 0.8, 0))
	for side in [-1.0, 1.0]:
		var arm := _node(Node3D, "ArmL" if side < 0 else "ArmR", torso) as Node3D
		arm.position = Vector3(0.28 * side, 0.56, 0)
		_mesh(arm, "Mesh", _capsule(0.065, 0.62), jacket, Vector3(0, -0.29, 0))
	var pack := BoxMesh.new()
	pack.size = Vector3(0.36, 0.46, 0.18)
	_mesh(torso, "Backpack", pack, gear, Vector3(0, 0.35, 0.22))

	# Área à frente do personagem que detecta portas e objetos interativos
	var area := _node(Area3D, "InteractionArea", visual) as Area3D
	area.collision_layer = 0
	area.collision_mask = LAYER_INTERACTABLE
	area.monitorable = false
	var sphere := SphereShape3D.new()
	sphere.radius = 1.1
	var area_col := _node(CollisionShape3D, "Shape", area) as CollisionShape3D
	area_col.shape = sphere
	area_col.position = Vector3(0, 1.0, -0.7)
	return player


# ---------------------------------------------------------------- câmera

func _build_camera_rig() -> Node:
	var rig := _node(Node3D, "CameraRig", null, "res://scripts/player/camera_rig.gd")
	var yaw := _node(Node3D, "Yaw", rig)
	var pitch := _node(Node3D, "Pitch", yaw)
	var arm := _node(SpringArm3D, "SpringArm3D", pitch) as SpringArm3D
	arm.collision_mask = LAYER_WORLD
	arm.margin = 0.15
	var probe := SphereShape3D.new()
	probe.radius = 0.2
	arm.shape = probe
	arm.spring_length = 3.6
	var cam := _node(Camera3D, "Camera3D", arm) as Camera3D
	cam.fov = 68.0
	cam.near = 0.05
	cam.far = 350.0
	return rig


# ---------------------------------------------------------------- HUD / controles

func _build_hud() -> Node:
	var hud := _node(CanvasLayer, "HUD", null) as CanvasLayer

	var controls := _node(Control, "MobileControls", hud, "res://scripts/input/mobile_controls.gd") as Control
	controls.set_anchors_preset(Control.PRESET_FULL_RECT)
	controls.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var safe := _node(Control, "SafeArea", controls) as Control
	safe.set_anchors_preset(Control.PRESET_FULL_RECT)
	safe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	safe.unique_name_in_owner = true

	var joystick := _node(Control, "Joystick", safe, "res://scripts/input/touch_joystick.gd") as Control
	joystick.set_anchors_preset(Control.PRESET_FULL_RECT)
	joystick.unique_name_in_owner = true

	_button(safe, "JumpButton", "jump", "Pular", 50.0, Vector2(-92, -96))
	_button(safe, "CrouchButton", "crouch", "Agachar", 40.0, Vector2(-212, -70))
	_button(safe, "SprintButton", "sprint", "Correr", 40.0, Vector2(-98, -222))
	_button(safe, "InteractButton", "interact", "", 46.0, Vector2(-236, -206))

	var overlay := _node(PanelContainer, "PerformanceOverlay", hud, "res://scripts/diagnostics/performance_overlay.gd") as PanelContainer
	overlay.position = Vector2(14, 12)
	overlay.mouse_filter = Control.MOUSE_FILTER_PASS
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.05, 0.04, 0.6)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(8)
	overlay.add_theme_stylebox_override("panel", style)
	var vbox := _node(VBoxContainer, "VBox", overlay) as VBoxContainer
	var label := _node(Label, "StatsLabel", vbox) as Label
	label.unique_name_in_owner = true
	label.text = "FPS --"
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", Color(0.82, 0.84, 0.76))
	var row := _node(HBoxContainer, "Buttons", vbox)
	for info in [["QualityButton", "Gráfico"], ["FpsButton", "Limite"]]:
		var b := _node(Button, info[0], row) as Button
		b.unique_name_in_owner = true
		b.text = info[1]
		b.custom_minimum_size = Vector2(132, 36)
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 13)
	return hud


func _button(parent: Node, node_name: String, action: String, text: String, radius: float, center_from_corner: Vector2) -> void:
	var b := _node(Control, node_name, parent, "res://scripts/input/action_button.gd") as Control
	b.unique_name_in_owner = true
	b.set("action", StringName(action))
	b.set("label", text)
	b.set("radius", radius)
	b.anchor_left = 1.0
	b.anchor_top = 1.0
	b.anchor_right = 1.0
	b.anchor_bottom = 1.0
	b.offset_left = center_from_corner.x - radius
	b.offset_right = center_from_corner.x + radius
	b.offset_top = center_from_corner.y - radius
	b.offset_bottom = center_from_corner.y + radius


# ---------------------------------------------------------------- cenário de teste

func _build_sandbox() -> Node:
	var root := _node(Node3D, "TestSandbox", null)

	# Ambiente: céu nublado, névoa leve, tons frios (clima de abandono)
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.33, 0.37, 0.4)
	sky_mat.sky_horizon_color = Color(0.58, 0.6, 0.58)
	sky_mat.ground_horizon_color = Color(0.45, 0.46, 0.42)
	sky_mat.ground_bottom_color = Color(0.12, 0.12, 0.1)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.75
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color(0.56, 0.59, 0.56)
	env.fog_density = 0.007
	env.fog_sky_affect = 0.5
	var world_env := _node(WorldEnvironment, "WorldEnvironment", root) as WorldEnvironment
	world_env.environment = env

	var sun := _node(DirectionalLight3D, "Sun", root, "res://scripts/world/sun_light.gd") as DirectionalLight3D
	sun.rotation_degrees = Vector3(-48, -35, 0)
	sun.light_color = Color(1.0, 0.95, 0.86)
	sun.light_energy = 1.1
	sun.shadow_enabled = true

	_build_ground(root)
	_build_house(root, Vector3(0, 0, -14))
	_build_stairs(root, Vector3(12, 0, -4))
	_build_props(root)
	_build_trees(root)

	var player := (load(PLAYER_SCENE) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) as Node3D
	root.add_child(player)
	player.position = Vector3(0, 0.05, 6)
	player.set("camera_rig_path", NodePath("../CameraRig"))
	var rig := (load(CAMERA_SCENE) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	root.add_child(rig)
	var hud := (load(HUD_SCENE) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	root.add_child(hud)
	return root


func _build_ground(root: Node) -> void:
	var ground := _node(StaticBody3D, "Ground", root) as StaticBody3D
	ground.collision_layer = LAYER_WORLD
	ground.collision_mask = 0
	var shape := BoxShape3D.new()
	shape.size = Vector3(160, 1, 160)
	var col := _node(CollisionShape3D, "Collision", ground) as CollisionShape3D
	col.shape = shape
	col.position.y = -0.5

	# Textura de grama/terra gerada por ruído (dá referência visual de movimento)
	var noise := FastNoiseLite.new()
	noise.frequency = 0.03
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.2, 0.23, 0.16))
	ramp.set_color(1, Color(0.34, 0.34, 0.25))
	var tex := NoiseTexture2D.new()
	tex.width = 256
	tex.height = 256
	tex.seamless = true
	tex.noise = noise
	tex.color_ramp = ramp
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.roughness = 1.0
	mat.uv1_scale = Vector3(40, 40, 1)
	var plane := PlaneMesh.new()
	plane.size = Vector2(160, 160)
	var mi := _node(MeshInstance3D, "Mesh", ground) as MeshInstance3D
	mi.mesh = plane
	mi.material_override = mat

	var road := BoxMesh.new()
	road.size = Vector3(6, 0.02, 160)
	_mesh(root, "Road", road, Color(0.16, 0.16, 0.16), Vector3(-12, 0.01, 0))


func _build_house(root: Node, origin: Vector3) -> void:
	var house := _node(Node3D, "House", root) as Node3D
	house.position = origin
	var wall := Color(0.47, 0.45, 0.41)
	var dark := Color(0.25, 0.24, 0.22)
	var h := 3.0
	_block(house, "Floor", Vector3(8, 0.1, 6), Vector3(0, 0.05, 0), dark)
	_block(house, "WallBack", Vector3(8, h, 0.2), Vector3(0, h / 2, -3), wall)
	_block(house, "WallLeft", Vector3(0.2, h, 6), Vector3(-4, h / 2, 0), wall)
	_block(house, "WallRight", Vector3(0.2, h, 6), Vector3(4, h / 2, 0), wall)
	_block(house, "WallFrontL", Vector3(3.4, h, 0.2), Vector3(-2.3, h / 2, 3), wall)
	_block(house, "WallFrontR", Vector3(3.4, h, 0.2), Vector3(2.3, h / 2, 3), wall)
	_block(house, "Lintel", Vector3(1.2, 0.8, 0.2), Vector3(0, 2.6, 3), wall)
	_block(house, "Roof", Vector3(8.6, 0.2, 6.6), Vector3(0, h + 0.1, 0), dark)
	_block(house, "Table", Vector3(1.6, 0.8, 0.9), Vector3(1.8, 0.45, -1.6), Color(0.33, 0.26, 0.18))
	_block(house, "Shelf", Vector3(0.5, 1.8, 1.8), Vector3(-3.6, 0.95, -1.5), Color(0.3, 0.25, 0.19))

	# Porta: a dobradiça gira; a porta em si é o objeto interativo
	var hinge := _node(Node3D, "DoorHinge", house) as Node3D
	hinge.position = Vector3(-0.6, 0.1, 3)
	var door := _node(AnimatableBody3D, "Door", hinge, "res://scripts/world/door.gd") as AnimatableBody3D
	door.position = Vector3(0.6, 1.05, 0)
	door.collision_layer = LAYER_WORLD | LAYER_INTERACTABLE
	door.collision_mask = 0
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.16, 2.1, 0.08)
	(_node(CollisionShape3D, "Collision", door) as CollisionShape3D).shape = shape
	var mesh := BoxMesh.new()
	mesh.size = shape.size
	_mesh(door, "Mesh", mesh, Color(0.36, 0.27, 0.18))

	# Volume interno: a câmera se aproxima quando o jogador entra
	var zone := _node(Area3D, "IndoorZone", house, "res://scripts/world/indoor_zone.gd") as Area3D
	zone.collision_layer = LAYER_TRIGGER
	zone.collision_mask = LAYER_PLAYER
	zone.monitorable = false
	zone.position = Vector3(0, 1.4, 0)
	var zone_shape := BoxShape3D.new()
	zone_shape.size = Vector3(7.6, 2.8, 5.6)
	(_node(CollisionShape3D, "Shape", zone) as CollisionShape3D).shape = zone_shape


func _build_stairs(root: Node, origin: Vector3) -> void:
	var stairs := _node(Node3D, "StairsPlatform", root) as Node3D
	stairs.position = origin
	var concrete := Color(0.4, 0.4, 0.38)
	_block(stairs, "Platform", Vector3(4, 1.5, 4), Vector3(0, 0.75, 0), concrete)
	# Degraus (só visual) + rampa invisível de colisão: subida suave, sem travar
	var steps := 6
	for i in steps:
		var top := 1.5 - (i + 1) * 0.25 + 0.25
		var box := BoxMesh.new()
		box.size = Vector3(2.4, top, 0.4)
		_mesh(stairs, "Step%d" % i, box, concrete, Vector3(0, top / 2, 2.2 + i * 0.4))
	var run := steps * 0.4
	var angle := atan2(1.5, run)
	var ramp := _node(StaticBody3D, "StairsRamp", stairs) as StaticBody3D
	ramp.collision_layer = LAYER_WORLD
	ramp.collision_mask = 0
	ramp.position = Vector3(0, 0.7, 2 + run / 2)
	ramp.rotation.x = angle
	var shape := BoxShape3D.new()
	shape.size = Vector3(2.4, 0.1, sqrt(run * run + 1.5 * 1.5) + 0.1)
	(_node(CollisionShape3D, "Collision", ramp) as CollisionShape3D).shape = shape


func _build_props(root: Node) -> void:
	var props := _node(Node3D, "Props", root)
	var crate := Color(0.36, 0.3, 0.22)
	var crates := [Vector3(5, 0.5, 3), Vector3(6.1, 0.5, 3.3), Vector3(5.5, 1.5, 3.1),
			Vector3(-6, 0.5, -4), Vector3(8, 0.5, -10), Vector3(-3, 0.5, -22)]
	for i in crates.size():
		_block(props, "Crate%d" % i, Vector3.ONE, crates[i], crate, LAYER_WORLD, Vector3(0, i * 17 % 40, 0))
	_block(props, "LowWall", Vector3(3, 0.6, 0.4), Vector3(-4, 0.3, 2), Color(0.42, 0.41, 0.38))
	_block(props, "Fence", Vector3(0.15, 1.2, 10), Vector3(7, 0.6, 12), Color(0.3, 0.27, 0.22))

	# Carro abandonado na estrada
	var car := _node(Node3D, "CarWreck", props) as Node3D
	car.position = Vector3(-12, 0, 4)
	car.rotation_degrees.y = 12
	var rust := Color(0.36, 0.22, 0.15)
	_block(car, "Body", Vector3(1.9, 0.8, 4.2), Vector3(0, 0.6, 0), rust)
	_block(car, "Cabin", Vector3(1.7, 0.6, 2.2), Vector3(0, 1.3, -0.2), Color(0.28, 0.2, 0.15))


func _build_trees(root: Node) -> void:
	var trees := _node(Node3D, "Trees", root)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.16
	trunk_mesh.bottom_radius = 0.24
	trunk_mesh.height = 4.0
	trunk_mesh.radial_segments = 8
	var crown_mesh := CylinderMesh.new()
	crown_mesh.top_radius = 0.0
	crown_mesh.bottom_radius = 1.7
	crown_mesh.height = 4.5
	crown_mesh.radial_segments = 8
	var trunk_shape := CylinderShape3D.new()
	trunk_shape.radius = 0.22
	trunk_shape.height = 4.0
	var placed := 0
	while placed < 40:
		var p := Vector3(rng.randf_range(-70, 70), 0, rng.randf_range(-70, 70))
		if absf(p.x) < 18 and absf(p.z) < 24:
			continue
		if absf(p.x + 12) < 5:
			continue
		var tree := _node(StaticBody3D, "Tree%d" % placed, trees) as StaticBody3D
		tree.position = p
		tree.rotation.y = rng.randf() * TAU
		tree.scale = Vector3.ONE * rng.randf_range(0.8, 1.3)
		tree.collision_layer = LAYER_WORLD
		tree.collision_mask = 0
		var col := _node(CollisionShape3D, "Collision", tree) as CollisionShape3D
		col.shape = trunk_shape
		col.position.y = 2.0
		_mesh(tree, "Trunk", trunk_mesh, Color(0.25, 0.2, 0.15), Vector3(0, 2.0, 0))
		_mesh(tree, "Crown", crown_mesh, Color(0.15, 0.21, 0.13), Vector3(0, 5.2, 0))
		placed += 1
