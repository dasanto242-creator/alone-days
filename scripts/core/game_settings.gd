extends Node
## Configurações do jogador (autoload "GameSettings").
## Guarda qualidade gráfica, limite de FPS, sensibilidade e vibração em user://settings.cfg.

enum Quality { LOW, MEDIUM, HIGH }

const SETTINGS_PATH := "user://settings.cfg"
const FPS_OPTIONS: Array[int] = [30, 45, 60]
const QUALITY_NAMES: Array[String] = ["Baixo", "Médio", "Alto"]

var quality: int = Quality.MEDIUM
var fps_limit: int = 60
var look_sensitivity: float = 1.0
var haptics_enabled: bool = true


func _ready() -> void:
	_load()
	apply()


func set_quality(level: int) -> void:
	quality = clampi(level, Quality.LOW, Quality.HIGH)
	apply()
	save()


func cycle_quality() -> void:
	set_quality((quality + 1) % QUALITY_NAMES.size())


func set_fps_limit(fps: int) -> void:
	fps_limit = fps if fps in FPS_OPTIONS else 60
	apply()
	save()


func cycle_fps_limit() -> void:
	var i := FPS_OPTIONS.find(fps_limit)
	set_fps_limit(FPS_OPTIONS[(i + 1) % FPS_OPTIONS.size()])


func apply() -> void:
	Engine.max_fps = fps_limit
	var viewport := get_viewport()
	viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	viewport.msaa_3d = Viewport.MSAA_DISABLED
	match quality:
		Quality.LOW:
			viewport.scaling_3d_scale = 0.7
		Quality.MEDIUM:
			viewport.scaling_3d_scale = 0.85
		Quality.HIGH:
			viewport.scaling_3d_scale = 1.0
			viewport.msaa_3d = Viewport.MSAA_2X
	Events.quality_changed.emit(quality)


func vibrate(duration_ms: int = 12, amplitude: float = 0.4) -> void:
	if haptics_enabled and OS.has_feature("mobile"):
		Input.vibrate_handheld(duration_ms, amplitude)


func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("graphics", "quality", quality)
	cfg.set_value("graphics", "fps_limit", fps_limit)
	cfg.set_value("controls", "look_sensitivity", look_sensitivity)
	cfg.set_value("controls", "haptics", haptics_enabled)
	cfg.save(SETTINGS_PATH)


func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	quality = clampi(cfg.get_value("graphics", "quality", quality), Quality.LOW, Quality.HIGH)
	fps_limit = cfg.get_value("graphics", "fps_limit", fps_limit)
	look_sensitivity = cfg.get_value("controls", "look_sensitivity", look_sensitivity)
	haptics_enabled = cfg.get_value("controls", "haptics", haptics_enabled)
