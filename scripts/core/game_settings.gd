extends Node
## Configurações do jogador (autoload "GameSettings").
## Guarda qualidade gráfica, limite de FPS, sensibilidade e vibração em user://settings.cfg.

enum Quality { LOW, MEDIUM, HIGH }

const SETTINGS_PATH := "user://settings.cfg"
## 0 = Automático: tenta 60; se o aparelho não sustentar, trava em 30 (ritmo regular, sem trancos).
const FPS_OPTIONS: Array[int] = [0, 30, 45, 60]
const AUTO_WINDOW := 3.0
const AUTO_MIN_FPS := 52.0
const QUALITY_NAMES: Array[String] = ["Baixo", "Médio", "Alto"]

var quality: int = Quality.MEDIUM
var fps_limit: int = 0
## Limite efetivo escolhido pelo modo automático.
var auto_fps := 60
var _auto_time := 0.0
var _auto_frames := 0
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
	fps_limit = fps if fps in FPS_OPTIONS else 0
	auto_fps = 60
	apply()
	save()


func cycle_fps_limit() -> void:
	var i := FPS_OPTIONS.find(fps_limit)
	set_fps_limit(FPS_OPTIONS[(i + 1) % FPS_OPTIONS.size()])


func fps_label() -> String:
	return "Auto (%d)" % auto_fps if fps_limit == 0 else "%d" % fps_limit


## Modo automático: mede o FPS real em janelas de 3 s. Se não segurar ~60, fixa 30 —
## 30 quadros regulares parecem mais lisos que 40 irregulares numa tela de 60 Hz.
func _process(delta: float) -> void:
	if fps_limit != 0 or auto_fps == 30:
		return
	_auto_time += delta
	_auto_frames += 1
	if _auto_time < AUTO_WINDOW:
		return
	var fps := _auto_frames / _auto_time
	_auto_time = 0.0
	_auto_frames = 0
	if fps < AUTO_MIN_FPS:
		auto_fps = 30
		Engine.max_fps = 30


func apply() -> void:
	Engine.max_fps = auto_fps if fps_limit == 0 else fps_limit
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
	if not fps_limit in FPS_OPTIONS:
		fps_limit = 0
	look_sensitivity = cfg.get_value("controls", "look_sensitivity", look_sensitivity)
	haptics_enabled = cfg.get_value("controls", "haptics", haptics_enabled)
