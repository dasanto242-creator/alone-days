extends Node3D
## Grama do cenário (pedaços de MultiMesh com distância máxima de desenho).
## Qualidade gráfica: Baixo = sem grama, Médio = 55% dos tufos e até 40 m, Alto = tudo até 60 m.


func _ready() -> void:
	Events.quality_changed.connect(_apply)
	_apply(GameSettings.quality)


func _apply(level: int) -> void:
	visible = level != GameSettings.Quality.LOW
	var frac := 1.0 if level == GameSettings.Quality.HIGH else 0.55
	var dist := 60.0 if level == GameSettings.Quality.HIGH else 40.0
	for c in get_children():
		var mmi := c as MultiMeshInstance3D
		if mmi == null:
			continue
		mmi.multimesh.visible_instance_count = int(mmi.multimesh.instance_count * frac)
		mmi.visibility_range_end = dist
