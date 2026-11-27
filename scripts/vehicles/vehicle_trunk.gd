class_name VehicleTrunk
extends Area3D
## Área atrás do carro: abrir/fechar o porta-malas e mexer nos itens guardados nele.

@export var vehicle_path: NodePath = ^".."


func _ready() -> void:
	collision_layer = 4  # interactable
	collision_mask = 0
	monitoring = false


func vehicle() -> Vehicle:
	return get_node(vehicle_path) as Vehicle


func get_interaction_prompt() -> String:
	return "Porta-malas" if vehicle().trunk_open else "Abrir porta-malas"


func get_interaction_name() -> String:
	var t := vehicle().trunk
	return "%.1f / %.0f kg" % [t.total_weight(), t.capacity()] if vehicle().trunk_open else "Carro"


func get_alt_prompt() -> String:
	return "Fechar" if vehicle().trunk_open else ""


func interact(actor: Node) -> void:
	var v := vehicle()
	if v.is_occupied():
		return
	if not v.trunk_open:
		if actor.has_method("use_trunk"):
			actor.use_trunk(v, true)
	elif actor.has_method("open_container"):
		actor.open_container(v.trunk, "Porta-malas")


func interact_alt(actor: Node) -> void:
	var v := vehicle()
	if v.trunk_open and actor.has_method("use_trunk"):
		actor.use_trunk(v, false)
