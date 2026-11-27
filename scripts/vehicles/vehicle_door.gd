class_name VehicleDoor
extends Area3D
## Área ao lado da porta do motorista: mostra "Entrar" e põe o jogador no carro.

@export var vehicle_path: NodePath = ^".."


func _ready() -> void:
	collision_layer = 4  # interactable
	collision_mask = 0
	monitoring = false


func vehicle() -> Vehicle:
	return get_node(vehicle_path) as Vehicle


func get_interaction_prompt() -> String:
	return "" if vehicle().is_occupied() else "Entrar"


func get_interaction_name() -> String:
	return "Carro"


func interact(actor: Node) -> void:
	if not vehicle().is_occupied() and actor.has_method("enter_vehicle"):
		actor.enter_vehicle(vehicle())
