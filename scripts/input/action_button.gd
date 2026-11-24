@tool
class_name ActionButton
extends Control
## Botão circular de ação. Ao ser tocado, aciona uma ação do InputMap
## (a mesma usada pelo teclado). Os toques são tratados pelo MobileControls,
## o que permite apertar vários botões e mover o joystick ao mesmo tempo.

@export var action: StringName = &""
@export var label := "":
	set(v):
		label = v
		queue_redraw()
@export var radius := 44.0:
	set(v):
		radius = v
		custom_minimum_size = Vector2.ONE * radius * 2.0
		queue_redraw()
## Área de toque extra além do círculo visível (facilita acertar no celular).
@export var touch_padding := 10.0
@export var font_size := 15

var highlighted := false:
	set(v):
		highlighted = v
		queue_redraw()

var _pressed := false

const COLOR_BASE := Color(0.06, 0.07, 0.06, 0.5)
const COLOR_PRESSED := Color(0.2, 0.23, 0.14, 0.75)
const COLOR_RING := Color(0.62, 0.66, 0.5, 0.6)
const COLOR_ACTIVE := Color(0.55, 0.65, 0.25, 0.95)
const COLOR_TEXT := Color(0.86, 0.86, 0.8, 0.95)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2.ONE * radius * 2.0


func contains_point(global_pos: Vector2) -> bool:
	var center := get_global_rect().get_center()
	var scale_factor := get_global_transform().get_scale().x
	return center.distance_to(global_pos) <= (radius + touch_padding) * scale_factor


func press() -> void:
	_pressed = true
	if action != &"":
		Input.action_press(action)
	queue_redraw()


func release() -> void:
	_pressed = false
	if action != &"":
		Input.action_release(action)
	queue_redraw()


func _draw() -> void:
	var center := size * 0.5
	draw_circle(center, radius, COLOR_PRESSED if _pressed else COLOR_BASE)
	var ring := COLOR_ACTIVE if highlighted else COLOR_RING
	draw_arc(center, radius, 0.0, TAU, 48, ring, 3.0 if highlighted else 2.0, true)
	if label.is_empty():
		return
	var font := ThemeDB.fallback_font
	var text_size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	var pos := center + Vector2(-text_size.x * 0.5, font_size * 0.35)
	draw_string(font, pos, label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, COLOR_TEXT)
