extends Node3D
## Floresta: distância de desenho dos pinheiros 3D e dos de longe conforme a qualidade gráfica.
## Baixo: pinheiros 3D só até 70 m, sem sombra; Médio: 110 m; Alto: 150 m.


func _ready() -> void:
	Events.quality_changed.connect(_apply)
	_apply(GameSettings.quality)


func _apply(level: int) -> void:
	var near: float = [40.0, 65.0, 100.0][level]
	var far: float = [600.0, 900.0, 1100.0][level]
	var groups: Array = []
	for chunk in get_children():
		if chunk.name == "Near":
			groups.append_array(chunk.get_children())
		else:
			groups.append(chunk)
	for chunk in groups:
		for c in chunk.get_children():
			var mmi := c as MultiMeshInstance3D
			if mmi == null:
				continue
			if c.name.begins_with("Pines"):
				mmi.visibility_range_end = near
				mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if level == 0 else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			elif c.name == "Far":
				mmi.visibility_range_begin = near - 10.0
				mmi.visibility_range_end = far
			elif c.name.begins_with("Rocks"):
				mmi.visibility_range_end = far * 0.45
