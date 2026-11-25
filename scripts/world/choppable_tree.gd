class_name ChoppableTree
extends StaticBody3D
## Árvore que pode ser cortada com machado.
## Cada golpe: a árvore treme, solta lascas e marca o corte. No último golpe ela estala,
## tomba para o lado oposto ao jogador (acelerando, como uma árvore de verdade), quica no chão,
## fica um tempo deitada, afunda e some. Sobra o toco. Depois de um tempo ela cresce de novo.
## Contrato de dano das armas: apply_damage(amount, source, point).

signal felled

@export var hits_to_fell := 5
@export var regrow_time := 300.0

var hits := 0
var is_felled := false

var _pivot: Node3D      # gira na base: tronco + copa caem juntos
var _stump: MeshInstance3D
var _notch: MeshInstance3D
var _tween: Tween
var _hint_cooldown := 0.0

static var _trunk_mesh: CylinderMesh
static var _crown_low: CylinderMesh
static var _crown_high: CylinderMesh
static var _stump_mesh: CylinderMesh
static var _notch_mesh: BoxMesh
static var _chip_mesh: BoxMesh


static func _ensure_resources() -> void:
	if _trunk_mesh:
		return
	var bark := StandardMaterial3D.new()
	bark.albedo_color = Color(0.27, 0.2, 0.14)
	bark.roughness = 0.95
	var leaves := StandardMaterial3D.new()
	leaves.albedo_color = Color(0.17, 0.25, 0.13)
	leaves.roughness = 0.9
	var leaves2 := StandardMaterial3D.new()
	leaves2.albedo_color = Color(0.14, 0.21, 0.11)
	leaves2.roughness = 0.9
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.72, 0.58, 0.4)
	wood.roughness = 0.85
	_trunk_mesh = CylinderMesh.new()
	_trunk_mesh.top_radius = 0.12
	_trunk_mesh.bottom_radius = 0.2
	_trunk_mesh.height = 4.2
	_trunk_mesh.radial_segments = 8
	_trunk_mesh.material = bark
	_crown_low = CylinderMesh.new()
	_crown_low.top_radius = 0.3
	_crown_low.bottom_radius = 1.6
	_crown_low.height = 2.6
	_crown_low.radial_segments = 9
	_crown_low.material = leaves
	_crown_high = CylinderMesh.new()
	_crown_high.top_radius = 0.0
	_crown_high.bottom_radius = 1.15
	_crown_high.height = 2.6
	_crown_high.radial_segments = 9
	_crown_high.material = leaves2
	_stump_mesh = CylinderMesh.new()
	_stump_mesh.top_radius = 0.19
	_stump_mesh.bottom_radius = 0.23
	_stump_mesh.height = 0.35
	_stump_mesh.radial_segments = 8
	_stump_mesh.material = bark
	_notch_mesh = BoxMesh.new()
	_notch_mesh.size = Vector3(0.22, 0.12, 0.08)
	_notch_mesh.material = wood
	_chip_mesh = BoxMesh.new()
	_chip_mesh.size = Vector3(0.04, 0.012, 0.025)
	_chip_mesh.material = wood


func _ready() -> void:
	add_to_group("choppable_trees")
	collision_layer = 1
	collision_mask = 0
	_ensure_resources()
	_pivot = Node3D.new()
	_pivot.name = "Pivot"
	_pivot.position.y = 0.35
	add_child(_pivot)
	var trunk := MeshInstance3D.new()
	trunk.mesh = _trunk_mesh
	trunk.position.y = 2.1
	_pivot.add_child(trunk)
	for c in [[_crown_low, 3.2], [_crown_high, 4.9]]:
		var crown := MeshInstance3D.new()
		crown.mesh = c[0]
		crown.position.y = c[1]
		_pivot.add_child(crown)
	_stump = MeshInstance3D.new()
	_stump.mesh = _stump_mesh
	_stump.position.y = 0.175
	add_child(_stump)
	_notch = MeshInstance3D.new()
	_notch.mesh = _notch_mesh
	_notch.visible = false
	_pivot.add_child(_notch)
	if get_node_or_null("Collision") == null:
		var shape := CylinderShape3D.new()
		shape.radius = 0.2
		shape.height = 4.5
		var col := CollisionShape3D.new()
		col.name = "Collision"
		col.shape = shape
		col.position.y = 2.25
		add_child(col)


func _process(delta: float) -> void:
	_hint_cooldown = maxf(_hint_cooldown - delta, 0.0)


func apply_damage(_amount: float, source: Node, point: Vector3) -> void:
	if is_felled:
		return
	var power := _chop_power(source)
	var from := (source as Node3D).global_position if source is Node3D else global_position + Vector3.BACK
	if power <= 0.0:
		_shake(from, 0.5)
		Sfx.play_3d(&"wood_knock", point)
		if _hint_cooldown <= 0.0:
			Events.notify.emit("Precisa de um machado para cortar")
			_hint_cooldown = 4.0
		return
	hits += 1
	Sfx.play_3d(&"axe_chop", point)
	_chips(point, from)
	# marca do corte cresce virada para quem está cortando
	var dir := from - global_position
	dir.y = 0.0
	dir = dir.normalized() if dir.length_squared() > 0.001 else Vector3.BACK
	_notch.visible = true
	_notch.position = Vector3(0, 0.45, 0) - _pivot.position + dir * 0.17
	_notch.look_at(_pivot.global_position + Vector3.UP * 0.1 + dir * 2.0, Vector3.UP)
	_notch.scale = Vector3(1, 1, 0.6 + 0.6 * float(hits) / hits_to_fell)
	if hits >= hits_to_fell:
		_fell(from)
	else:
		_shake(from, 1.0)


func _chop_power(source: Node) -> float:
	if source == null:
		return 0.0
	var weapons := source.get_node_or_null("Weapons")
	if weapons == null:
		return 0.0
	var d: ItemData = weapons.wielded_data()
	return d.chop_power if d else 0.0


func _shake(from: Vector3, strength: float) -> void:
	if _tween:
		_tween.kill()
	var away := global_position - from
	away.y = 0.0
	away = away.normalized() if away.length_squared() > 0.001 else Vector3.FORWARD
	var axis := Vector3.UP.cross(away).normalized()
	var base := Basis()
	_pivot.basis = base
	_tween = create_tween()
	_tween.tween_property(_pivot, "basis", Basis(axis, deg_to_rad(2.2 * strength)), 0.06)
	_tween.tween_property(_pivot, "basis", Basis(axis, deg_to_rad(-1.2 * strength)), 0.12)
	_tween.tween_property(_pivot, "basis", base, 0.25).set_trans(Tween.TRANS_SINE)


func _fell(from: Vector3) -> void:
	is_felled = true
	felled.emit()
	Sfx.play_3d(&"tree_crack", global_position + Vector3.UP * 1.5)
	if _tween:
		_tween.kill()
	_pivot.basis = Basis()
	var away := global_position - from
	away.y = 0.0
	away = away.normalized() if away.length_squared() > 0.001 else Vector3.FORWARD
	var axis := Vector3.UP.cross(away).normalized()
	# o corte cede: o tronco sobe um pouco da base cortada e tomba acelerando
	_tween = create_tween()
	_tween.tween_property(_pivot, "basis", Basis(axis, deg_to_rad(6.0)), 0.7).set_trans(Tween.TRANS_SINE)
	_tween.tween_property(_pivot, "basis", Basis(axis, deg_to_rad(86.0)), 1.3) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_tween.tween_callback(func() -> void:
		Sfx.play_3d(&"tree_fall", global_position + away * 3.0)
		Events.noise_emitted.emit(global_position, 25.0, self))
	_tween.tween_property(_pivot, "basis", Basis(axis, deg_to_rad(80.0)), 0.15).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_pivot, "basis", Basis(axis, deg_to_rad(84.0)), 0.25).set_ease(Tween.EASE_IN)
	_tween.tween_interval(4.0)
	# afunda no chão e some
	_tween.tween_property(_pivot, "position:y", -1.0, 2.5).set_trans(Tween.TRANS_SINE)
	_tween.tween_callback(func() -> void: _pivot.visible = false)
	# o tronco em pé deixa de bloquear assim que começa a cair; o toco continua sólido
	var col := get_node_or_null("Collision") as CollisionShape3D
	if col:
		var stump_shape := CylinderShape3D.new()
		stump_shape.radius = 0.21
		stump_shape.height = 0.35
		col.set_deferred("shape", stump_shape)
		col.set_deferred("position", Vector3(0, 0.175, 0))
	get_tree().create_timer(regrow_time).timeout.connect(_regrow)


func _regrow() -> void:
	if not is_inside_tree():
		return
	hits = 0
	is_felled = false
	_notch.visible = false
	_pivot.basis = Basis()
	_pivot.position.y = 0.35
	_pivot.scale = Vector3.ONE * 0.05
	_pivot.visible = true
	var col := get_node_or_null("Collision") as CollisionShape3D
	if col:
		var shape := CylinderShape3D.new()
		shape.radius = 0.2
		shape.height = 4.5
		col.shape = shape
		col.position.y = 2.25
	create_tween().tween_property(_pivot, "scale", Vector3.ONE, 20.0)


func _chips(point: Vector3, from: Vector3) -> void:
	var fx := CPUParticles3D.new()
	fx.one_shot = true
	fx.amount = 10
	fx.lifetime = 0.7
	fx.explosiveness = 0.95
	var out := from - point
	out.y = 0.0
	fx.direction = (out.normalized() + Vector3.UP * 0.6).normalized() if out.length_squared() > 0.0 else Vector3.UP
	fx.spread = 45.0
	fx.initial_velocity_min = 1.5
	fx.initial_velocity_max = 3.0
	fx.gravity = Vector3(0, -9.8, 0)
	fx.angular_velocity_min = -400.0
	fx.angular_velocity_max = 400.0
	fx.mesh = _chip_mesh
	get_parent().add_child(fx)
	fx.global_position = point
	fx.emitting = true
	get_tree().create_timer(1.2).timeout.connect(fx.queue_free)
