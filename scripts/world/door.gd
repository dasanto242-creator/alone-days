class_name Door
extends AnimatableBody3D
## Porta que abre e fecha ao interagir. Gira o nó pai (a dobradiça).
## Contrato de objetos interativos (usado pelo PlayerController):
##   get_interaction_prompt() -> String   e   interact(actor: Node) -> void

@export var open_angle_degrees := 100.0
@export var duration := 0.45

var is_open := false
var _tween: Tween


func get_interaction_prompt() -> String:
	return "Fechar" if is_open else "Abrir"


func interact(actor: Node) -> void:
	is_open = not is_open
	var hinge := get_parent() as Node3D
	var direction := 1.0
	if is_open and actor is Node3D:
		# Abre para o lado oposto ao jogador, para não empurrá-lo.
		var local := hinge.to_local((actor as Node3D).global_position)
		direction = -1.0 if local.z > 0.0 else 1.0
	var target := deg_to_rad(open_angle_degrees * direction) if is_open else 0.0
	if _tween:
		_tween.kill()
	_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_property(hinge, "rotation:y", target, duration)
