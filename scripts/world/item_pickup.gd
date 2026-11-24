class_name ItemPickup
extends Area3D
## Item largado no mundo. Monta o próprio visual a partir do ItemData
## (forma, tamanho e cor) e pode ser pego pelo botão Interagir.

const PICKUP_SCENE := "res://scenes/world/item_pickup.tscn"

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
	collision_layer = 4  # interactable
	collision_mask = 0
	monitoring = false
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
	if d.model:
		var m := d.model.instantiate() as Node3D
		m.rotation_degrees = d.world_rotation
		m.position.y = 0.035  # a origem das armas é a empunhadura: levanta para não afundar no chão
		add_child(m)
		var hit := SphereShape3D.new()
		hit.radius = 0.3
		var c := CollisionShape3D.new()
		c.shape = hit
		c.position.y = 0.1
		add_child(c)
		return
	var size := d.world_size
	var mesh: Mesh
	match d.world_shape:
		ItemData.WorldShape.CYLINDER:
			var c := CylinderMesh.new()
			c.top_radius = size.x * 0.5
			c.bottom_radius = size.x * 0.5
			c.height = size.y
			c.radial_segments = 12
			mesh = c
		ItemData.WorldShape.BAG:
			var cap := CapsuleMesh.new()
			cap.radius = minf(size.x, size.z) * 0.5
			cap.height = maxf(size.y, cap.radius * 2.0)
			cap.radial_segments = 10
			mesh = cap
		_:
			var b := BoxMesh.new()
			b.size = size
			mesh = b
	var mat := StandardMaterial3D.new()
	mat.albedo_color = d.world_color
	mat.roughness = 0.7
	mat.emission_enabled = true
	mat.emission = d.world_color
	mat.emission_energy_multiplier = 0.12
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position.y = size.y * 0.5
	add_child(mi)
	var shape := SphereShape3D.new()
	shape.radius = maxf(maxf(size.x, size.z), 0.25)
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position.y = size.y * 0.5
	add_child(col)
