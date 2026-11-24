class_name MobileControls
extends Control
## Gerencia todos os toques da tela de jogo (multitoque real).
## Cada dedo é "dono" de um único elemento enquanto estiver na tela:
##   - botão de ação (prioridade, se o toque começar em cima dele);
##   - joystick (toque começando no lado esquerdo);
##   - câmera (toque começando no lado direito).
## Um toque que começa num botão nunca gira a câmera.

## Fração da largura (a partir da esquerda) reservada para o joystick.
@export_range(0.2, 0.6) var joystick_zone_ratio := 0.42
## Fração da altura no topo onde o joystick não nasce (deixa espaço para HUD/menus).
@export_range(0.0, 0.5) var top_dead_zone_ratio := 0.2
## Quantos graus a câmera gira ao arrastar o dedo pela altura inteira da tela.
@export var look_degrees_per_screen := 200.0

var _buttons: Array[ActionButton] = []
var _button_fingers := {}  # índice do dedo -> ActionButton
var _joystick_finger := -1
var _look_finger := -1

@onready var _safe_area: Control = %SafeArea
@onready var _joystick: TouchJoystick = %Joystick
@onready var _interact_button: ActionButton = %InteractButton
@onready var _crouch_button: ActionButton = %CrouchButton
@onready var _sprint_button: ActionButton = %SprintButton


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for node in find_children("*", "ActionButton", true, false):
		_buttons.append(node as ActionButton)
	_interact_button.visible = false
	Events.interaction_target_changed.connect(_on_interaction_target_changed)
	Events.player_movement_state_changed.connect(_on_player_movement_state_changed)
	get_viewport().size_changed.connect(_apply_safe_area)
	_apply_safe_area()


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			if _on_touch_down(touch.index, touch.position):
				get_viewport().set_input_as_handled()
		else:
			_on_touch_up(touch.index)
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		_on_touch_move(drag.index, drag.position, drag.relative)


func _on_touch_down(finger: int, pos: Vector2) -> bool:
	for button in _buttons:
		if button.is_visible_in_tree() and button.contains_point(pos):
			_button_fingers[finger] = button
			button.press()
			GameSettings.vibrate()
			return true

	var screen := get_viewport_rect().size
	var left_side := pos.x < screen.x * joystick_zone_ratio
	if left_side and _joystick_finger == -1 and pos.y > screen.y * top_dead_zone_ratio:
		_joystick_finger = finger
		_joystick.begin(pos)
		return true
	if not left_side and _look_finger == -1:
		_look_finger = finger
		return true
	return false


func _on_touch_move(finger: int, pos: Vector2, relative: Vector2) -> void:
	if finger == _joystick_finger:
		_joystick.drag(pos)
		_push_move(_joystick.value)
	elif finger == _look_finger:
		var degrees_per_pixel := look_degrees_per_screen / get_viewport_rect().size.y
		TouchInput.add_look(relative * degrees_per_pixel)


func _on_touch_up(finger: int) -> void:
	if finger == _joystick_finger:
		_joystick_finger = -1
		_joystick.end()
		_push_move(Vector2.ZERO)
	elif finger == _look_finger:
		_look_finger = -1
	elif _button_fingers.has(finger):
		(_button_fingers[finger] as ActionButton).release()
		_button_fingers.erase(finger)


## Converte o vetor do joystick em ações analógicas do InputMap.
func _push_move(v: Vector2) -> void:
	_set_action(&"move_right", maxf(v.x, 0.0))
	_set_action(&"move_left", maxf(-v.x, 0.0))
	_set_action(&"move_back", maxf(v.y, 0.0))
	_set_action(&"move_forward", maxf(-v.y, 0.0))


func _set_action(action: StringName, strength: float) -> void:
	if strength > 0.001:
		Input.action_press(action, strength)
	else:
		Input.action_release(action)


func _on_interaction_target_changed(prompt: String) -> void:
	_interact_button.visible = not prompt.is_empty()
	_interact_button.label = prompt
	if prompt.is_empty():
		for finger in _button_fingers.keys():
			if _button_fingers[finger] == _interact_button:
				_interact_button.release()
				_button_fingers.erase(finger)


func _on_player_movement_state_changed(is_crouching: bool, is_sprinting: bool) -> void:
	_crouch_button.highlighted = is_crouching
	_sprint_button.highlighted = is_sprinting


## Afasta os controles do entalhe (notch) e das bordas arredondadas da tela.
func _apply_safe_area() -> void:
	if not OS.has_feature("mobile"):
		return
	var window_size := Vector2(DisplayServer.window_get_size())
	var safe := Rect2(DisplayServer.get_display_safe_area())
	if window_size.x <= 0.0 or safe.size.x <= 0.0:
		return
	var scale_factor := get_viewport_rect().size / window_size
	var left := maxf(safe.position.x, 0.0) * scale_factor.x
	var top := maxf(safe.position.y, 0.0) * scale_factor.y
	var right := maxf(window_size.x - safe.end.x, 0.0) * scale_factor.x
	var bottom := maxf(window_size.y - safe.end.y, 0.0) * scale_factor.y
	_safe_area.offset_left = left
	_safe_area.offset_top = top
	_safe_area.offset_right = -right
	_safe_area.offset_bottom = -bottom
