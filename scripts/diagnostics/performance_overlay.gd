class_name PerformanceOverlay
extends Control
## Painel de diagnóstico (canto superior esquerdo): FPS, tempo de quadro,
## draw calls, memória e perfil gráfico. Os botões trocam qualidade e limite
## de FPS na hora, para testar no celular sem recompilar.

@export var refresh_interval := 0.5

var _elapsed := 0.0
var _frames := 0
var _worst_frame_ms := 0.0

@onready var _label: Label = %StatsLabel
@onready var _quality_button: Button = %QualityButton
@onready var _fps_button: Button = %FpsButton


func _ready() -> void:
	add_to_group("touch_blocker")
	_quality_button.pressed.connect(GameSettings.cycle_quality)
	_fps_button.pressed.connect(GameSettings.cycle_fps_limit)
	Events.quality_changed.connect(func(_level: int) -> void: _refresh_buttons())
	Events.modal_changed.connect(func(open: bool) -> void: visible = not open)
	_refresh_buttons()


func _process(delta: float) -> void:
	_elapsed += delta
	_frames += 1
	_worst_frame_ms = maxf(_worst_frame_ms, delta * 1000.0)
	if _elapsed < refresh_interval:
		return
	var fps := _frames / _elapsed
	var draw_calls := Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	var primitives := Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	var video_mb := Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0
	var static_mb := OS.get_static_memory_usage() / 1048576.0
	_label.text = "FPS %d  (pior %.1f ms)\nDraw calls %d  ·  Tris %dk\nRAM %.0f MB  ·  VRAM %.0f MB" % [
		roundi(fps), _worst_frame_ms, draw_calls, roundi(primitives / 1000.0), static_mb, video_mb]
	_elapsed = 0.0
	_frames = 0
	_worst_frame_ms = 0.0
	_refresh_buttons()


func _refresh_buttons() -> void:
	_quality_button.text = "Gráfico: %s" % GameSettings.QUALITY_NAMES[GameSettings.quality]
	_fps_button.text = "Limite: %d FPS" % GameSettings.fps_limit
