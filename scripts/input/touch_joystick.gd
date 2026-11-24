class_name TouchJoystick
extends Control
## Joystick flutuante: aparece onde o polegar encosta e segue o dedo se ele
## passar do limite. Só desenha e calcula o vetor; quem trata os toques é o MobileControls.

@export var radius := 85.0
@export var knob_radius := 34.0
@export_range(0.0, 0.5) var dead_zone := 0.15
## Posição de repouso (fração da área) onde o joystick fica esmaecido quando não está em uso.
@export var idle_anchor := Vector2(0.16, 0.74)
@export var base_color := Color(0.06, 0.07, 0.06, 0.45)
@export var ring_color := Color(0.62, 0.66, 0.5, 0.55)
@export var knob_color := Color(0.78, 0.8, 0.7, 0.75)

## Vetor de saída: x para direita, y para BAIXO (como na tela). Comprimento 0..1.
var value := Vector2.ZERO
var active := false

var _center := Vector2.ZERO
var _knob := Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func begin(global_pos: Vector2) -> void:
	active = true
	_center = _to_local(global_pos)
	_knob = _center
	value = Vector2.ZERO
	queue_redraw()


func drag(global_pos: Vector2) -> void:
	var p := _to_local(global_pos)
	var offset := p - _center
	if offset.length() > radius:
		# Base acompanha o dedo, para o jogador nunca "perder" o joystick.
		_center = p - offset.normalized() * radius
		offset = p - _center
	_knob = _center + offset
	var raw := offset / radius
	var length := raw.length()
	if length < dead_zone:
		value = Vector2.ZERO
	else:
		value = raw.normalized() * inverse_lerp(dead_zone, 1.0, minf(length, 1.0))
	queue_redraw()


func end() -> void:
	active = false
	value = Vector2.ZERO
	queue_redraw()


func _to_local(global_pos: Vector2) -> Vector2:
	return get_global_transform().affine_inverse() * global_pos


func _draw() -> void:
	var center := _center if active else size * idle_anchor
	var knob := _knob if active else center
	var alpha := 1.0 if active else 0.45
	draw_circle(center, radius, Color(base_color, base_color.a * alpha))
	draw_arc(center, radius, 0.0, TAU, 48, Color(ring_color, ring_color.a * alpha), 2.5, true)
	draw_circle(knob, knob_radius, Color(knob_color, knob_color.a * alpha))
