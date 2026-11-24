class_name PracticeTarget
extends StaticBody3D
## Alvo de treino (placa de tiro ou boneco de pancada): balança ao ser atingido e conta acertos.
## Contrato de dano usado pelas armas: apply_damage(amount, source, point).

@export var swing_degrees := 14.0
@export var visual_path: NodePath = ^"Visual"

var hits := 0
var total_damage := 0.0
var _tween: Tween


func apply_damage(amount: float, source: Node, _point: Vector3) -> void:
	hits += 1
	total_damage += amount
	var visual := get_node_or_null(visual_path) as Node3D
	if visual == null:
		return
	var away := 1.0
	if source is Node3D:
		var local := to_local((source as Node3D).global_position)
		away = -signf(local.z) if absf(local.z) > 0.01 else 1.0
	if _tween:
		_tween.kill()
	visual.rotation.x = 0.0
	_tween = create_tween().set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	visual.rotation.x = deg_to_rad(swing_degrees) * away
	_tween.tween_property(visual, "rotation:x", 0.0, 0.9)
