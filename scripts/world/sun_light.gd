class_name SunLight
extends DirectionalLight3D
## Sol da cena. Ajusta as sombras conforme o perfil gráfico:
## Baixo = sem sombras · Médio = 1 divisão, 30 m · Alto = 2 divisões, 50 m.


func _ready() -> void:
	Events.quality_changed.connect(_apply)
	_apply(GameSettings.quality)


func _apply(level: int) -> void:
	match level:
		GameSettings.Quality.LOW:
			shadow_enabled = false
		GameSettings.Quality.MEDIUM:
			shadow_enabled = true
			directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
			directional_shadow_max_distance = 30.0
			RenderingServer.directional_shadow_atlas_set_size(2048, true)
		GameSettings.Quality.HIGH:
			shadow_enabled = true
			directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
			directional_shadow_max_distance = 50.0
			RenderingServer.directional_shadow_atlas_set_size(4096, true)
