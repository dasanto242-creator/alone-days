extends Node
## Ferramenta de desenvolvimento: gera as cenas da Etapa 1 a partir de código.
## Uso: godot --headless --path . res://tools/build_scenes.tscn
## (roda como cena para que os autoloads Events/GameSettings/TouchInput existam)
## Depois de gerado, tudo pode ser editado normalmente no editor do Godot.

const PLAYER_SCENE := "res://scenes/player/player.tscn"
const CAMERA_SCENE := "res://scenes/player/camera_rig.tscn"
const HUD_SCENE := "res://scenes/ui/hud.tscn"
const SANDBOX_SCENE := "res://scenes/world/test_sandbox.tscn"
const PICKUP_SCENE := "res://scenes/world/item_pickup.tscn"
const SURVIVOR_MODEL := "res://assets/models/survivor/survivor.glb"
const CATALOG_PATH := "res://data/item_catalog.tres"

const LAYER_WORLD := 1
const LAYER_PLAYER := 2
const LAYER_INTERACTABLE := 4
const LAYER_TRIGGER := 8

var _materials := {}


func _ready() -> void:
	var ok := true
	ok = _build_items() and ok
	ok = _save(_build_pickup(), PICKUP_SCENE) and ok
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

	_node(Node, "Survival", player, "res://scripts/survival/survival_stats.gd")

	# Modelo 3D do sobrevivente (gerado no Blender por tools/character/build_survivor.py)
	var visual := _node(Node3D, "Visual", player, "res://scripts/player/survivor_animator.gd")
	var model := (load(SURVIVOR_MODEL) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) as Node3D
	model.name = "Model"
	model.rotation_degrees.y = 180.0  # o modelo olha para +Z; o jogo usa -Z como frente
	visual.add_child(model)

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

	# Indicadores de sobrevivência (canto superior direito)
	var stats_hud := _node(Control, "SurvivalHud", safe, "res://scripts/ui/survival_hud.gd") as Control
	stats_hud.anchor_left = 1.0
	stats_hud.anchor_right = 1.0
	stats_hud.offset_left = -140
	stats_hud.offset_right = -18
	stats_hud.offset_top = 16
	stats_hud.offset_bottom = 112

	var inv_btn := _node(Button, "InventoryButton", safe, "res://scripts/ui/inventory_button.gd") as Button
	inv_btn.unique_name_in_owner = true
	inv_btn.anchor_left = 1.0
	inv_btn.anchor_right = 1.0
	inv_btn.offset_left = -226
	inv_btn.offset_right = -158
	inv_btn.offset_top = 18
	inv_btn.offset_bottom = 86

	var notes := _node(VBoxContainer, "Notifications", hud, "res://scripts/ui/notifications.gd") as VBoxContainer
	notes.anchor_left = 0.5
	notes.anchor_right = 0.5
	notes.offset_left = -260
	notes.offset_right = 260
	notes.offset_top = 70
	notes.offset_bottom = 200

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

	var inv_screen := _node(Control, "InventoryScreen", hud, "res://scripts/ui/inventory_screen.gd") as Control
	inv_screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	inv_screen.unique_name_in_owner = true
	inv_btn.set("inventory_screen_path", NodePath("../../../InventoryScreen"))
	var death := _node(Control, "DeathScreen", hud, "res://scripts/ui/death_screen.gd") as Control
	death.set_anchors_preset(Control.PRESET_FULL_RECT)
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
	_build_loot(root)

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


# ---------------------------------------------------------------- itens

func _item(id: String, display_name: String, desc: String, category: int, weight: float,
		max_stack: int, shape: int, size: Vector3, color: Color, extra := {}) -> ItemData:
	var d := ItemData.new()
	d.id = StringName(id)
	d.display_name = display_name
	d.description = desc
	d.category = category
	d.weight = weight
	d.max_stack = max_stack
	d.world_shape = shape
	d.world_size = size
	d.world_color = color
	var icon_path := "res://assets/icons/items/%s.svg" % id
	if ResourceLoader.exists(icon_path):
		d.icon = load(icon_path)
	for key in extra:
		d.set(key, extra[key])
	return d


func _build_items() -> bool:
	var C := ItemData.Category
	var W := ItemData.WorldShape
	var items: Array[ItemData] = [
		_item("can_beans", "Lata de feijão", "Comida enlatada. Ainda está dentro da validade, ou quase.",
			C.FOOD, 0.45, 4, W.CYLINDER, Vector3(0.09, 0.12, 0.09), Color(0.6, 0.45, 0.3),
			{"use_verb": "Comer", "restore_food": 35.0, "restore_water": 5.0}),
		_item("cereal_bar", "Barra de cereal", "Leve e prática. Mata a fome por pouco tempo.",
			C.FOOD, 0.1, 6, W.BOX, Vector3(0.14, 0.03, 0.05), Color(0.72, 0.6, 0.35),
			{"use_verb": "Comer", "restore_food": 18.0}),
		_item("water_bottle", "Garrafa de água", "Água potável lacrada.",
			C.DRINK, 0.6, 3, W.CYLINDER, Vector3(0.08, 0.26, 0.08), Color(0.45, 0.62, 0.75),
			{"use_verb": "Beber", "restore_water": 40.0}),
		_item("soda_can", "Refrigerante", "Quente e sem gás, mas hidrata e dá um pouco de energia.",
			C.DRINK, 0.4, 4, W.CYLINDER, Vector3(0.07, 0.12, 0.07), Color(0.7, 0.2, 0.18),
			{"use_verb": "Beber", "restore_water": 25.0, "restore_food": 5.0, "restore_stamina": 20.0}),
		_item("bandage", "Bandagem", "Faixa limpa para ferimentos.",
			C.MEDICAL, 0.05, 6, W.BOX, Vector3(0.1, 0.05, 0.1), Color(0.85, 0.85, 0.8),
			{"use_verb": "Usar", "restore_health": 15.0}),
		_item("backpack", "Mochila de lona", "Mochila resistente. Aumenta muito o que você consegue carregar.",
			C.BACKPACK, 1.2, 1, W.BAG, Vector3(0.36, 0.46, 0.2), Color(0.3, 0.27, 0.2),
			{"equip_slot": ItemData.Slot.BACK, "capacity_bonus": 16.0, "max_durability": 100.0}),
		_item("jacket", "Jaqueta de campo", "Jaqueta verde militar com bolsos. Aquece e carrega um pouco mais.",
			C.CLOTHING, 1.5, 1, W.BOX, Vector3(0.45, 0.08, 0.35), Color(0.29, 0.33, 0.2),
			{"equip_slot": ItemData.Slot.BODY, "capacity_bonus": 4.0, "max_durability": 100.0}),
	]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://data/items"))
	var catalog := ItemCatalog.new()
	for d in items:
		var path := "res://data/items/%s.tres" % d.id
		if ResourceSaver.save(d, path) != OK:
			push_error("Falha ao salvar " + path)
			return false
		catalog.items.append(load(path))
	return ResourceSaver.save(catalog, CATALOG_PATH) == OK


func _build_pickup() -> Node:
	return _node(Area3D, "ItemPickup", null, "res://scripts/world/item_pickup.gd")


func _pickup(parent: Node, id: String, pos: Vector3, qty := 1) -> void:
	var p := (load(PICKUP_SCENE) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) as Node3D
	p.name = "%s_%d" % [id, parent.get_child_count()]
	parent.add_child(p)
	p.position = pos
	p.set("item_id", StringName(id))
	p.set("quantity", qty)


func _build_loot(root: Node) -> void:
	var loot := _node(Node3D, "Loot", root)
	# Dentro da casa
	_pickup(loot, "water_bottle", Vector3(1.5, 0.85, -15.6))
	_pickup(loot, "can_beans", Vector3(2.1, 0.85, -15.5), 2)
	_pickup(loot, "bandage", Vector3(-3.0, 0.1, -12.6), 2)
	_pickup(loot, "jacket", Vector3(-1.6, 0.1, -16.0))
	# Perto do carro abandonado
	_pickup(loot, "backpack", Vector3(-10.3, 0.0, 2.4))
	_pickup(loot, "water_bottle", Vector3(-9.6, 0.0, 6.5))
	# Caixotes e plataforma
	_pickup(loot, "cereal_bar", Vector3(5.0, 1.0, 3.0), 3)
	_pickup(loot, "soda_can", Vector3(12.5, 1.5, -4.5))
	_pickup(loot, "can_beans", Vector3(11.3, 1.5, -5.2))
	# Na estrada
	_pickup(loot, "soda_can", Vector3(-12.6, 0.02, -8.0))
