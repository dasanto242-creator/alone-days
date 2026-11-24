extends Node
## Teste automático da Etapa 1 (roda sem tela).
## Uso: godot --headless --path . res://tools/smoke_test.tscn
## Simula teclado e toques reais (multitoque) e confere o resultado no jogo.

var _passed := 0
var _failed := 0
var _player: PlayerController
var _rig: CameraRig
var _hud: Node


func _ready() -> void:
	var world := (load("res://scenes/world/test_sandbox.tscn") as PackedScene).instantiate()
	add_child(world)
	_player = world.get_node("Player")
	_rig = world.get_node("CameraRig")
	_hud = world.get_node("HUD")
	await _frames(20)
	await _run()
	print("\n==== RESULTADO: %d ok, %d falhas ====" % [_passed, _failed])
	get_tree().quit(0 if _failed == 0 else 1)


func _run() -> void:
	var vp := get_viewport().get_visible_rect().size
	print("Viewport: ", vp)

	_check("Personagem começa no chão", _player.is_on_floor())

	# --- Teclado: andar para frente
	var start := _player.global_position
	Input.action_press("move_forward")
	await _frames(60)
	Input.action_release("move_forward")
	var moved := start.z - _player.global_position.z
	_check("Teclado W move para frente (%.2f m)" % moved, moved > 2.0)
	await _frames(40)
	_check("Para ao soltar (vel %.2f)" % _player.velocity.length(), _player.velocity.length() < 0.2)

	# --- Pulo
	Input.action_press("jump")
	await _frames(1)
	Input.action_release("jump")
	await _frames(14)
	var jump_height := _player.global_position.y
	_check("Pulo sobe (%.2f m)" % jump_height, jump_height > 0.4)
	await _frames(70)
	_check("Volta ao chão depois do pulo", _player.is_on_floor())

	# --- Agachar
	await _tap_action("crouch")
	_check("Agacha (altura %.1f)" % (_player.get_node("CollisionShape3D").shape as CapsuleShape3D).height,
		_player.is_crouching)
	start = _player.global_position
	Input.action_press("move_forward")
	await _frames(60)
	Input.action_release("move_forward")
	var crouch_dist := start.distance_to(_player.global_position)
	_check("Anda agachado mais devagar (%.2f m)" % crouch_dist, crouch_dist > 0.5 and crouch_dist < 1.6)
	await _tap_action("crouch")
	_check("Levanta", not _player.is_crouching)

	# --- Correr rápido (toggle)
	await _tap_action("sprint")
	Input.action_press("move_forward")
	await _frames(60)
	var sprint_speed := Vector2(_player.velocity.x, _player.velocity.z).length()
	Input.action_release("move_forward")
	_check("Sprint (%.1f m/s)" % sprint_speed, sprint_speed > 5.0)
	await _frames(50)
	_check("Sprint desliga ao parar", not _player.is_sprinting)

	# --- Toque: joystick + câmera ao mesmo tempo (multitoque)
	var yaw_before := rad_to_deg(_rig.get_yaw())
	start = _player.global_position
	_touch(0, Vector2(vp.x * 0.15, vp.y * 0.7), true)
	_touch(1, Vector2(vp.x * 0.7, vp.y * 0.5), true)
	await _frames(1)
	_drag(0, Vector2(vp.x * 0.15, vp.y * 0.7 - 90), Vector2(0, -90))
	_drag(1, Vector2(vp.x * 0.7 + 72, vp.y * 0.5), Vector2(72, 0))
	await _frames(45)
	var joy_moved := start.distance_to(_player.global_position)
	var yaw_delta := rad_to_deg(_rig.get_yaw()) - yaw_before
	_check("Joystick touch move o personagem (%.2f m)" % joy_moved, joy_moved > 1.5)
	_check("Arrastar à direita gira a câmera (%.1f°)" % yaw_delta, absf(yaw_delta) > 10.0)
	_touch(0, Vector2.ZERO, false)
	_touch(1, Vector2.ZERO, false)
	await _frames(40)
	_check("Soltar o joystick para o personagem", _player.velocity.length() < 0.3)

	# --- Botão touch de pular
	var jump_btn := _hud.get_node("%JumpButton") as Control
	_touch(2, jump_btn.get_global_rect().get_center(), true)
	await _frames(2)
	_touch(2, Vector2.ZERO, false)
	await _frames(12)
	_check("Botão Pular (toque) funciona (%.2f m)" % _player.global_position.y, _player.global_position.y > 0.3)
	await _frames(60)

	# --- Porta e botão Interagir
	_teleport(Vector3(0, 0.05, -9.9), 0.0)
	await _frames(10)
	var interact_btn := _hud.get_node("%InteractButton") as ActionButton
	_check("Botão Interagir aparece perto da porta ('%s')" % interact_btn.label,
		interact_btn.visible and interact_btn.label == "Abrir")
	var hinge := _player.get_parent().get_node("House/DoorHinge") as Node3D
	_touch(3, interact_btn.get_global_rect().get_center(), true)
	await _frames(2)
	_touch(3, Vector2.ZERO, false)
	await _frames(40)
	_check("Porta abre (%.0f°)" % rad_to_deg(hinge.rotation.y), absf(rad_to_deg(hinge.rotation.y)) > 80.0)
	_check("Texto muda para 'Fechar'", interact_btn.label == "Fechar")

	# --- Entrar na casa: câmera se aproxima
	_teleport(Vector3(0, 0.15, -14), 0.0)
	await _frames(90)
	var arm := _rig.get_node("Yaw/Pitch/SpringArm3D") as SpringArm3D
	_check("Câmera detecta interior (braço %.2f m)" % arm.spring_length, _rig.is_indoor() and arm.spring_length < 2.4)

	# --- Colisão da câmera com parede
	_teleport(Vector3(0, 0.15, -16.2), 0.0)
	TouchInput.add_look(Vector2(180.0 + rad_to_deg(_rig.get_yaw()), 0))
	await _frames(30)
	var hit := arm.get_hit_length()
	_check("Câmera não atravessa a parede (distância %.2f m)" % hit, hit < 1.0)

	# --- Sair: câmera volta ao normal
	_teleport(Vector3(0, 0.05, 6), 0.0)
	await _frames(120)
	_check("Câmera volta ao normal fora (braço %.2f m)" % arm.spring_length, not _rig.is_indoor() and arm.spring_length > 3.2)

	# --- Escada até a plataforma
	_teleport(Vector3(12, 0.05, 6.5), 0.0)
	var yaw_now := rad_to_deg(_rig.get_yaw())
	TouchInput.add_look(Vector2(-yaw_now, 0))
	await _frames(5)
	Input.action_press("move_forward")
	await _frames(240)
	Input.action_release("move_forward")
	print("    posição final: ", _player.global_position)
	_check("Sobe a escada até a plataforma (y %.2f)" % _player.global_position.y, _player.global_position.y > 1.3)

	# --- Configurações gráficas
	for i in 3:
		GameSettings.cycle_quality()
		await _frames(2)
	GameSettings.cycle_fps_limit()
	_check("Troca de qualidade e FPS sem erros (%s, %d)" % [GameSettings.QUALITY_NAMES[GameSettings.quality], GameSettings.fps_limit], true)


func _teleport(pos: Vector3, _yaw: float) -> void:
	_player.global_position = pos
	_player.velocity = Vector3.ZERO
	_player.reset_physics_interpolation()


func _tap_action(action: String) -> void:
	Input.action_press(action)
	await _frames(1)
	Input.action_release(action)
	await _frames(2)


func _touch(index: int, pos: Vector2, pressed: bool) -> void:
	var ev := InputEventScreenTouch.new()
	ev.index = index
	ev.position = pos
	ev.pressed = pressed
	_send(ev)


func _drag(index: int, pos: Vector2, relative: Vector2) -> void:
	var ev := InputEventScreenDrag.new()
	ev.index = index
	ev.position = pos
	ev.relative = relative
	_send(ev)


## No celular o toque vem do sistema; sem tela, entregamos direto à viewport.
func _send(ev: InputEvent) -> void:
	get_viewport().push_input(ev, true)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _check(description: String, ok: bool) -> void:
	if ok:
		_passed += 1
		print("  [OK]    ", description)
	else:
		_failed += 1
		print("  [FALHA] ", description)
