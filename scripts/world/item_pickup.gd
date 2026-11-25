class_name ItemPickup
extends RigidBody3D
## Item largado no mundo, com física: cai, quica pouco, repousa em cima do que estiver
## embaixo (chão, mesa, estante) e é empurrado de leve quando o personagem esbarra nele.
## Monta o próprio visual e a colisão a partir do ItemData e pode ser pego pelo botão Interagir.

const PICKUP_SCENE := "res://scenes/world/item_pickup.tscn"

## Um material por cor, compartilhado por todos os itens (evita criar recursos e trocar estado na GPU).
static var _materials := {}
static var _physics_material: PhysicsMaterial

@export var item_id: StringName
@export var quantity := 1
@export_range(0.0, 100.0) var durability := 100.0


static func spawn(parent: Node, id: StringName, qty: int, condition: float, at: Vector3) -> ItemPickup:
	var pickup := (load(PICKUP_SCENE) as PackedScene).instantiate() as ItemPickup
	pickup.item_id = id
	pickup.quantity = qty
	pickup.durability = condition
	parent.add_child(pickup)
	pickup.global_position = at
	return pickup


func _ready() -> void:
	collision_layer = 4      # interactable (o botão Interagir encontra)
	collision_mask = 1 | 2   # repousa no mundo e é empurrado pelo jogador
	if _physics_material == null:
		_physics_material = PhysicsMaterial.new()
		_physics_material.friction = 0.9
		_physics_material.bounce = 0.05
	physics_material_override = _physics_material
	linear_damp = 0.6
	angular_damp = 2.0
	can_sleep = true
	var d := Items.get_item(item_id)
	if d == null:
		push_warning("ItemPickup com item desconhecido: %s" % item_id)
		return
	_build_visual(d)


func get_interaction_prompt() -> String:
	return "Pegar"


func get_interaction_name() -> String:
	var d := Items.get_item(item_id)
	if d == null:
		return ""
	return d.display_name if quantity <= 1 else "%s (%d)" % [d.display_name, quantity]


func interact(actor: Node) -> void:
	# o personagem agacha e pega; o item entra no inventário quando a mão chega nele
	if actor.has_method("begin_pickup"):
		actor.begin_pickup(self)
	else:
		collect(actor)


func collect(actor: Node) -> void:
	var inventory: Inventory = actor.get("inventory")
	var d := Items.get_item(item_id)
	if inventory == null or d == null:
		return
	var added := inventory.add_item(item_id, quantity, durability)
	if added <= 0:
		Events.notify.emit("Sem espaço para %s" % d.display_name)
		return
	Events.notify.emit("+%d %s" % [added, d.display_name] if added > 1 else "+ %s" % d.display_name)
	if actor.has_method("auto_equip"):
		actor.auto_equip(item_id)
	quantity -= added
	if quantity <= 0:
		queue_free()
	else:
		Events.notify.emit("Sem espaço para o restante")


func _build_visual(d: ItemData) -> void:
	mass = clampf(d.weight, 0.2, 5.0)
	if d.model:
		var m := d.model.instantiate() as Node3D
		m.rotation_degrees = d.world_rotation
		add_child(m)
		# colisão = caixa que envolve o modelo (já girado como fica deitado no chão)
		var box := _model_bounds(m)
		var shape := BoxShape3D.new()
		shape.size = box.size.max(Vector3(0.04, 0.04, 0.04))
		var c := CollisionShape3D.new()
		c.shape = shape
		c.position = box.get_center()
		add_child(c)
		return
	var size := d.world_size
	var mesh: Mesh
	var col_shape: Shape3D
	match d.world_shape:
		ItemData.WorldShape.CYLINDER:
			var c := CylinderMesh.new()
			c.top_radius = size.x * 0.5
			c.bottom_radius = size.x * 0.5
			c.height = size.y
			c.radial_segments = 12
			mesh = c
			var cs := CylinderShape3D.new()
			cs.radius = size.x * 0.5
			cs.height = size.y
			col_shape = cs
		ItemData.WorldShape.BAG:
			var cap := CapsuleMesh.new()
			cap.radius = minf(size.x, size.z) * 0.5
			cap.height = maxf(size.y, cap.radius * 2.0)
			cap.radial_segments = 10
			mesh = cap
			var bs := BoxShape3D.new()
			bs.size = Vector3(cap.radius * 2.0, cap.height, cap.radius * 2.0)
			col_shape = bs
		_:
			var b := BoxMesh.new()
			b.size = size
			mesh = b
			var bs := BoxShape3D.new()
			bs.size = size
			col_shape = bs
	var key := d.world_color.to_html()
	if not _materials.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = d.world_color
		m.roughness = 0.7
		m.emission_enabled = true
		m.emission = d.world_color
		m.emission_energy_multiplier = 0.12
		_materials[key] = m
	var mat: StandardMaterial3D = _materials[key]
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position.y = size.y * 0.5
	add_child(mi)
	var col := CollisionShape3D.new()
	col.shape = col_shape
	col.position.y = size.y * 0.5
	add_child(col)


## Caixa (no espaço do item) que envolve todas as malhas do modelo.
func _model_bounds(model: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for g in model.find_children("*", "MeshInstance3D", true, false):
		var mi := g as MeshInstance3D
		if mi.mesh == null:
			continue
		var xf := _relative_transform(mi, self)
		var b: AABB = xf * mi.mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	if first:
		box = AABB(Vector3(-0.1, 0.0, -0.1), Vector3(0.2, 0.1, 0.2))
	return box


static func _relative_transform(node: Node3D, root: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var n: Node = node
	while n and n != root:
		if n is Node3D:
			xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf
