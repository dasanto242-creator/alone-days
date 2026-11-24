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

	await _run_stage2()


# ================================================================ ETAPA 2

func _run_stage2() -> void:
	print("\n-- Etapa 2: sobrevivência e inventário --")
	var inv := _player.inventory
	var stats := _player.stats
	var interact_btn := _hud.get_node("%InteractButton") as ActionButton

	# --- Pegar a mochila perto do carro
	await _approach(Vector3(-10.3, 0.0, 2.4))
	_check("Botão mostra 'Pegar' perto da mochila", interact_btn.visible and interact_btn.label == "Pegar")
	await _tap_action("interact")
	await _frames(3)
	_check("Mochila foi para o inventário", inv.count_of(&"backpack") == 1)
	_check("Capacidade base 6 kg (%.1f)" % inv.capacity(), is_equal_approx(inv.capacity(), 6.0))

	# --- Equipar: capacidade aumenta e aparece nas costas
	var backpack_mesh := _player.get_node("Visual/Model").find_child("Backpack", true, false) as Node3D
	_check("Sem mochila nas costas antes de equipar", not backpack_mesh.visible)
	_player.equip_item(0)
	_check("Equipar mochila aumenta capacidade (%.1f kg)" % inv.capacity(), is_equal_approx(inv.capacity(), 22.0))
	_check("Mochila aparece nas costas", backpack_mesh.visible)
	var animator := _player.get_node("Visual") as SurvivorAnimator
	_check("Animação parado = idle (%s)" % animator.current_animation(), animator.current_animation() == &"idle")

	# --- Pegar água e beber
	await _approach(Vector3(-9.6, 0.0, 6.5))
	await _tap_action("interact")
	await _frames(3)
	_check("Pegou garrafa de água", inv.count_of(&"water_bottle") == 1)
	stats.water = 30.0
	var idx := _index_of(&"water_bottle")
	_player.use_item(idx)
	_check("Beber água: sede 30 → %.0f" % stats.water, is_equal_approx(stats.water, 70.0))
	_check("Garrafa consumida", inv.count_of(&"water_bottle") == 0)

	# --- Fome e sede caem mais rápido correndo
	stats.food = 100.0
	stats.water = 100.0
	stats.tick(60.0, SurvivalStats.Exertion.IDLE)
	var food_idle := 100.0 - stats.food
	stats.food = 100.0
	stats.tick(60.0, SurvivalStats.Exertion.SPRINT)
	var food_sprint := 100.0 - stats.food
	_check("Fome cai com o tempo (%.2f/min parado)" % food_idle, food_idle > 1.0)
	_check("Correndo gasta o dobro (%.2f/min)" % food_sprint, is_equal_approx(food_sprint, food_idle * 2.0))

	# --- Sem comida e água: perde vida. Bem alimentado: recupera
	stats.food = 0.0
	stats.water = 0.0
	stats.health = 100.0
	stats.tick(10.0, SurvivalStats.Exertion.IDLE)
	_check("Fome e sede zeradas tiram vida (%.1f)" % stats.health, stats.health < 95.0)
	stats.food = 40.0
	stats.water = 100.0
	var before := stats.health
	stats.tick(10.0, SurvivalStats.Exertion.IDLE)
	_check("Mal alimentado não recupera vida (%.1f → %.1f)" % [before, stats.health], stats.health <= before)
	stats.food = 100.0
	stats.water = 100.0
	stats.tick(10.0, SurvivalStats.Exertion.IDLE)
	_check("Bem alimentado recupera vida (%.1f → %.1f)" % [before, stats.health], stats.health > before)
	stats.food = 20.0
	_check("Com fome a stamina recupera mais devagar", stats.stamina_regen_factor() < 1.0)
	stats.food = 100.0
	stats.health = 100.0

	# --- Stamina: sprint gasta, esgotar desliga o sprint e bloqueia o pulo
	stats.stamina = 100.0
	_teleport(Vector3(0, 0.05, 20), 0.0)
	await _frames(5)
	await _tap_action("sprint")
	Input.action_press("move_forward")
	await _frames(90)
	_check("Sprint gasta stamina (%.0f)" % stats.stamina, stats.stamina < 85.0)
	var anim := (_player.get_node("Visual") as SurvivorAnimator).current_animation()
	_check("Animação de sprint ao correr rápido (%s)" % anim, anim == &"sprint")
	stats.stamina = 3.0
	await _frames(20)
	Input.action_release("move_forward")
	_check("Stamina esgotada desliga o sprint", not _player.is_sprinting and stats.is_exhausted)
	await _frames(30)
	var y0 := _player.global_position.y
	await _tap_action("jump")
	await _frames(10)
	_check("Exausto não consegue pular", _player.global_position.y - y0 < 0.1)
	await _frames(150)
	_check("Stamina recupera descansando (%.0f)" % stats.stamina, stats.stamina > 40.0 and not stats.is_exhausted)

	# --- Animações de agachar e andar
	var animator2 := _player.get_node("Visual") as SurvivorAnimator
	await _tap_action("crouch")
	await _frames(10)
	_check("Agachado parado = crouch_idle (%s)" % animator2.current_animation(), animator2.current_animation() == &"crouch_idle")
	Input.action_press("move_forward", 0.5)
	await _frames(40)
	_check("Agachado andando = crouch_walk (%s)" % animator2.current_animation(), animator2.current_animation() == &"crouch_walk")
	Input.action_release("move_forward")
	await _tap_action("crouch")
	Input.action_press("move_forward", 0.4)
	await _frames(40)
	_check("Joystick leve = walk (%s)" % animator2.current_animation(), animator2.current_animation() == &"walk")
	Input.action_release("move_forward")
	await _frames(30)

	# --- Largar item: aparece no chão e pode ser pego de novo
	inv.add_item(&"soda_can", 2)
	var count_before := _count_pickups()
	_player.drop_item(_index_of(&"soda_can"), 1)
	await _frames(3)
	_check("Largar cria item no chão (%d → %d)" % [count_before, _count_pickups()], _count_pickups() == count_before + 1)
	_check("Sobrou 1 refrigerante", inv.count_of(&"soda_can") == 1)

	# --- Limite de peso
	var added := inv.add_item(&"can_beans", 200)
	_check("Limite de peso respeitado (+%d latas, %.1f/%.1f kg)" % [added, inv.total_weight(), inv.capacity()],
		added < 200 and inv.total_weight() <= inv.capacity() + 0.001)
	_check("Não dá para tirar a mochila cheia", not _player.unequip_item(ItemData.Slot.BACK))
	while inv.count_of(&"can_beans") > 2:
		inv.take_from(_index_of(&"can_beans"), 4)

	# --- Empilhamento
	var stacks_before := inv.stacks.size()
	inv.add_item(&"bandage", 3)
	inv.add_item(&"bandage", 2)
	_check("Itens iguais empilham (1 pilha de 5 bandagens)", inv.stacks.size() == stacks_before + 1 and inv.count_of(&"bandage") == 5)

	# --- Salvar e carregar estado (preparação para o sistema de save)
	var snapshot := inv.to_dict()
	var copy := Inventory.new()
	copy.load_dict(snapshot)
	_check("Inventário serializa e restaura", copy.to_dict() == snapshot and is_equal_approx(copy.capacity(), inv.capacity()))

	# --- Interface: abrir pelo botão, controles somem, usar item pela tela
	var inv_btn := _hud.get_node("%InventoryButton") as Button
	var controls := _hud.get_node("MobileControls") as MobileControls
	_touch(5, inv_btn.get_global_rect().get_center(), true)
	_click(inv_btn.get_global_rect().get_center())
	await _frames(3)
	_touch(5, Vector2.ZERO, false)
	var screen := _hud.get_node("%InventoryScreen") as InventoryScreen
	_check("Toque no botão Mochila abre o inventário", screen.visible)
	_check("Controles de jogo ficam ocultos", not controls.visible)
	var rig_yaw := _rig.get_yaw()
	_check("Toque no botão não girou a câmera", is_equal_approx(rig_yaw, _rig.get_yaw()))
	stats.health = 50.0
	var band_index := _index_of(&"bandage")
	var slot_btn := screen.find_child("Slot%d" % band_index, true, false) as Button
	slot_btn.pressed.emit()
	var primary := screen.find_child("PrimaryButton", true, false) as Button
	_check("Ação contextual mostra 'Usar' para bandagem", primary.visible and primary.text == "Usar")
	primary.pressed.emit()
	_check("Usar bandagem pela tela cura (%.0f)" % stats.health, is_equal_approx(stats.health, 65.0))
	(screen.find_child("CloseButton", true, false) as Button).pressed.emit()
	await _frames(2)
	_check("Fechar volta aos controles", not screen.visible and controls.visible)

	# --- Morte
	stats.apply_damage(500.0)
	await get_tree().create_timer(1.5).timeout
	var death := _hud.get_node("DeathScreen") as Control
	_check("Vida zerada mostra a tela de morte", stats.is_dead and death.visible)


func _approach(item_pos: Vector3) -> void:
	_teleport(item_pos + Vector3(0, 0.05, 0.7), 0.0)
	(_player.get_node("Visual") as Node3D).rotation.y = 0.0
	await _frames(6)


func _index_of(id: StringName) -> int:
	for i in _player.inventory.stacks.size():
		if _player.inventory.stacks[i].item_id == id:
			return i
	return -1


func _count_pickups() -> int:
	var n := 0
	for node in _player.get_parent().find_children("*", "Area3D", true, false):
		if node is ItemPickup and not node.is_queued_for_deletion():
			n += 1
	return n


func _click(pos: Vector2) -> void:
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.position = pos
		ev.global_position = pos
		ev.pressed = pressed
		_send(ev)


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
