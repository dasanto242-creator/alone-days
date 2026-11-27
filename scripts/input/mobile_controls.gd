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
var _enabled := true
var _target_label: Label

@onready var _safe_area: Control = %SafeArea
@onready var _joystick: TouchJoystick = %Joystick
@onready var _interact_button: ActionButton = %InteractButton
@onready var _crouch_button: ActionButton = %CrouchButton
@onready var _sprint_button: ActionButton = %SprintButton
@onready var _attack_button: ActionButton = %AttackButton
@onready var _reload_button: ActionButton = %ReloadButton
@onready var _alt_button: ActionButton = %AltInteractButton
@onready var _jump_button: ActionButton = %JumpButton
@onready var _aim_button: ActionButton = %AimButton
@onready var _gas_button: ActionButton = %GasButton
@onready var _brake_button: ActionButton = %BrakeButton
@onready var _handbrake_button: ActionButton = %HandbrakeButton
var _driving := false
var _weapon_kind := 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for node in find_children("*", "ActionButton", true, false):
		_buttons.append(node as ActionButton)
	_interact_button.visible = false
	_alt_button.visible = false
	Events.interaction_alt_changed.connect(func(verb: String) -> void:
		if not verb.is_empty():
			_alt_button.label = verb
		_set_button_visible(_alt_button, not verb.is_empty()))
	_target_label = Label.new()
	_target_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_target_label.size = Vector2(240, 24)
	_target_label.position = Vector2(_interact_button.radius - 120.0, -30.0)
	_target_label.add_theme_font_size_override("font_size", 16)
	_target_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	_target_label.add_theme_constant_override("shadow_offset_x", 1)
	_target_label.add_theme_constant_override("shadow_offset_y", 1)
	_interact_button.add_child(_target_label)
	Events.interaction_target_changed.connect(_on_interaction_target_changed)
	Events.modal_changed.connect(func(open: bool) -> void: set_enabled(not open))
	Events.weapon_state_changed.connect(_on_weapon_state_changed)
	_on_weapon_state_changed(ItemData.WeaponKind.NONE, "", false)
	Events.player_movement_state_changed.connect(_on_player_movement_state_changed)
	Events.vehicle_changed.connect(_on_vehicle_changed)
	Events.aim_changed.connect(func(on: bool) -> void: _aim_button.highlighted = on)
	for b in [_gas_button, _brake_button, _handbrake_button]:
		b.visible = false
	get_viewport().size_changed.connect(_apply_safe_area)
	_apply_safe_area()


## Desliga os controles (ex.: inventário aberto) e solta tudo que estava pressionado.
func set_enabled(value: bool) -> void:
	_enabled = value
	visible = value
	if not value:
		release_all()


func release_all() -> void:
	if _joystick_finger != -1:
		_joystick.end()
		_push_move(Vector2.ZERO)
	_joystick_finger = -1
	_look_finger = -1
	for finger in _button_fingers:
		(_button_fingers[finger] as ActionButton).release()
	_button_fingers.clear()


func _input(event: InputEvent) -> void:
	if not _enabled:
		return
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
	# Toques em botões de interface (inventário, painel) ficam com a interface
	for blocker in get_tree().get_nodes_in_group("touch_blocker"):
		if blocker is Control and blocker.is_visible_in_tree() and blocker.get_global_rect().has_point(pos):
			return false
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


func _on_interaction_target_changed(verb: String, target_name: String) -> void:
	_interact_button.visible = not verb.is_empty()
	_interact_button.label = verb
	_target_label.text = target_name
	if verb.is_empty():
		for finger in _button_fingers.keys():
			if _button_fingers[finger] == _interact_button:
				_interact_button.release()
				_button_fingers.erase(finger)


## Botões de arma só aparecem quando fazem sentido.
func _on_weapon_state_changed(kind: int, _ammo: String, _has_weapons: bool) -> void:
	_weapon_kind = kind
	if _driving:
		return
	_set_button_visible(_attack_button, kind != ItemData.WeaponKind.NONE)
	_attack_button.label = "Atirar" if kind == ItemData.WeaponKind.PISTOL else "Atacar"
	_set_button_visible(_reload_button, kind == ItemData.WeaponKind.PISTOL)
	_set_button_visible(_aim_button, kind == ItemData.WeaponKind.PISTOL)


func _set_button_visible(button: ActionButton, value: bool) -> void:
	if button.visible == value:
		return
	button.visible = value
	if not value:
		for finger in _button_fingers.keys():
			if _button_fingers[finger] == button:
				button.release()
				_button_fingers.erase(finger)


## Dirigindo: some tudo que é de quem está a pé e aparecem os pedais e o freio de mão.
## O joystick vira o volante (e também acelera/freia, para quem preferir um dedo só).
func _on_vehicle_changed(vehicle: Node) -> void:
	_driving = vehicle != null
	for b in [_jump_button, _crouch_button, _sprint_button]:
		_set_button_visible(b, not _driving)
	if _driving:
		_set_button_visible(_alt_button, false)
	for b in [_gas_button, _brake_button, _handbrake_button]:
		_set_button_visible(b, _driving)
	if _driving:
		_set_button_visible(_attack_button, false)
		_set_button_visible(_reload_button, false)
		_set_button_visible(_aim_button, false)
	else:
		_on_weapon_state_changed(_weapon_kind, "", false)


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
