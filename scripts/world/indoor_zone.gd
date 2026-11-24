class_name IndoorZone
extends Area3D
## Volume colocado dentro de construções. Quando o jogador entra,
## a câmera se aproxima e reduz o deslocamento do ombro (com transição suave).


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node3D) -> void:
	var rig := _rig_for(body)
	if rig:
		rig.enter_indoor()


func _on_body_exited(body: Node3D) -> void:
	var rig := _rig_for(body)
	if rig:
		rig.exit_indoor()


func _rig_for(body: Node3D) -> CameraRig:
	if body is PlayerController and not (body as PlayerController).camera_rig_path.is_empty():
		return body.get_node((body as PlayerController).camera_rig_path) as CameraRig
	return null
