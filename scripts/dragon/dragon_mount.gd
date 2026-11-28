class_name DragonMount
extends Area3D
## Área ao lado do ombro esquerdo do dragão: "Montar".

@export var dragon_path: NodePath = ^".."


func _ready() -> void:
	collision_layer = 4  # interactable
	collision_mask = 0
	monitoring = false


func dragon() -> Dragon:
	return get_node(dragon_path) as Dragon


func get_interaction_prompt() -> String:
	var d := dragon()
	return "Montar" if d.is_lying() and not d.is_occupied() else ""


func get_interaction_name() -> String:
	return "Dragão"


func interact(actor: Node) -> void:
	var d := dragon()
	if d.is_lying() and not d.is_occupied() and actor.has_method("mount_dragon"):
		actor.mount_dragon(d)
