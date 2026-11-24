class_name SurvivalHud
extends Control
## Indicadores discretos de vida, fome, sede e stamina (canto superior direito).
## Ficam esmaecidos quando cheios e chamam atenção quando baixos:
## âmbar abaixo de 30% e vermelho piscando abaixo de 12%.

const ROWS := [
	{"key": "health", "icon": "res://assets/icons/ui/health.svg", "color": Color(0.72, 0.3, 0.26)},
	{"key": "food", "icon": "res://assets/icons/ui/food.svg", "color": Color(0.7, 0.62, 0.38)},
	{"key": "water", "icon": "res://assets/icons/ui/water.svg", "color": Color(0.4, 0.58, 0.72)},
	{"key": "stamina", "icon": "res://assets/icons/ui/stamina.svg", "color": Color(0.62, 0.7, 0.4)},
]
const ROW_HEIGHT := 24.0
const ICON_SIZE := 20.0
const BAR_WIDTH := 96.0
const BAR_HEIGHT := 6.0

var _stats: SurvivalStats
var _icons: Array[Texture2D] = []
var _blink := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(ICON_SIZE + 8.0 + BAR_WIDTH, ROW_HEIGHT * ROWS.size())
	for row in ROWS:
		_icons.append(load(row.icon))
	_bind.call_deferred()


func _bind() -> void:
	var player := get_tree().get_first_node_in_group("player") as PlayerController
	if player:
		_stats = player.stats
		_stats.stats_changed.connect(queue_redraw)
	queue_redraw()


func _process(delta: float) -> void:
	_blink = fmod(_blink + delta * 3.0, TAU)
	if _stats and _any_critical():
		queue_redraw()


func _any_critical() -> bool:
	return _stats.health < 12.0 or _stats.food < 12.0 or _stats.water < 12.0


func _draw() -> void:
	if _stats == null:
		return
	for i in ROWS.size():
		var row: Dictionary = ROWS[i]
		var value: float = _stats.get(row.key) / SurvivalStats.MAX
		var y := i * ROW_HEIGHT
		var color: Color = row.color
		var alpha := 0.75 if value > 0.95 else 1.0
		if value < 0.12 and row.key != "stamina":
			color = UiTheme.DANGER
			alpha = 0.55 + 0.45 * (0.5 + 0.5 * sin(_blink))
		elif value < 0.3:
			color = UiTheme.WARNING
		var icon_rect := Rect2(Vector2(0, y + (ROW_HEIGHT - ICON_SIZE) * 0.5), Vector2.ONE * ICON_SIZE)
		draw_texture_rect(_icons[i], icon_rect, false, Color(color.lightened(0.25), alpha))
		var bar_pos := Vector2(ICON_SIZE + 8.0, y + (ROW_HEIGHT - BAR_HEIGHT) * 0.5)
		draw_rect(Rect2(bar_pos, Vector2(BAR_WIDTH, BAR_HEIGHT)), Color(0, 0, 0, 0.45))
		draw_rect(Rect2(bar_pos, Vector2(BAR_WIDTH * value, BAR_HEIGHT)), Color(color, alpha))
