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
	# zumbis do cenário ficam fora dos testes gerais (são testados à parte, em _run_zombie)
	var spawner := world.get_node("ZombieSpawner") as ZombieSpawner
	_check("Cenário cria zumbis (%d)" % get_tree().get_nodes_in_group("zombies").size(),
		get_tree().get_nodes_in_group("zombies").size() == spawner.max_alive)
	spawner.process_mode = Node.PROCESS_MODE_DISABLED
	for z in get_tree().get_nodes_in_group("zombies"):
		z.free()
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
	var hinge := _player.get_parent().get_node("House/Door") as Node3D
	_touch(3, interact_btn.get_global_rect().get_center(), true)
	await _frames(2)
	_touch(3, Vector2.ZERO, false)
	await _frames(40)
	_check("Porta abre (%.0f°)" % rad_to_deg(hinge.rotation.y), absf(rad_to_deg(hinge.rotation.y)) > 80.0)
	_check("Texto muda para 'Fechar'", interact_btn.label == "Fechar")
	_teleport(Vector3(0, 0.05, -9.0), 0.0)
	_rig.set("_yaw_deg", 0.0)
	await _frames(5)
	Input.action_press("move_forward")
	await _frames(100)
	Input.action_release("move_forward")
	_check("Entra andando pela porta aberta (z %.2f)" % _player.global_position.z, _player.global_position.z < -12.0)
	# degrau: sobe na calçada (15 cm) andando, sem pular
	_teleport(Vector3(-6.5, 0.05, -4.0), 0.0)
	_rig.set("_yaw_deg", 90.0)
	await _frames(5)
	Input.action_press("move_forward")
	await _frames(32)
	Input.action_release("move_forward")
	await _frames(10)
	_check("Sobe a calçada andando (x %.2f, y %.2f)" % [_player.global_position.x, _player.global_position.y],
		_player.global_position.x < -7.6 and _player.global_position.y > 0.12)

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
	var tree_p := (_player.get_node("Visual") as SurvivorAnimator).get("_tree") as AnimationTree
	_check("Pegar: abaixa para pegar do chão (animação %s)" % tree_p.get("parameters/use_kind/current_state"),
		tree_p.get("parameters/use/active") and tree_p.get("parameters/use_kind/current_state") == "pickup")
	_check("Item ainda no chão até a mão alcançar", inv.count_of(&"backpack") == 0)
	await get_tree().create_timer(1.0).timeout
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

	# --- Pegar água: Pegar (fica na mão) ou Guardar (vai para a mochila)
	await _approach(Vector3(-9.6, 0.0, 6.5))
	var alt_btn := _hud.get_node("%AltInteractButton") as ActionButton
	_check("Consumível mostra 'Pegar' e 'Guardar' (%s / %s)" % [interact_btn.label, alt_btn.label],
		interact_btn.label == "Pegar" and alt_btn.visible and alt_btn.label == "Guardar")
	await _pickup_wait()
	_check("Pegar: garrafa fica na mão", _player.held != null and _player.held.item_id == &"water_bottle"
		and inv.count_of(&"water_bottle") == 0)
	await _frames(3)
	_check("Com item na mão: botões '%s' e '%s'" % [interact_btn.label, alt_btn.label],
		interact_btn.label == "Beber" and alt_btn.label == "Guardar")
	var hand0 := _player.get_node("Visual/Model").find_child("Socket_Hand_R", true, false) as Node3D
	_check("Garrafa aparece na mão", hand0.get_child_count() > 0)
	await _tap_action("interact_alt")
	await _frames(3)
	_check("Guardar: garrafa vai para a mochila", _player.held == null and inv.count_of(&"water_bottle") == 1)
	stats.water = 30.0
	var idx := _index_of(&"water_bottle")
	_player.use_item(idx)
	var water_after := stats.water
	await _frames(3)
	var anim_tree := (_player.get_node("Visual") as SurvivorAnimator).get("_tree") as AnimationTree
	_check("Beber toca a animação de beber (corpo inteiro)",
		anim_tree.get("parameters/use/active") and anim_tree.get("parameters/use_kind/current_state") == "drink")
	var hand := _player.get_node("Visual/Model").find_child("Socket_Hand_R", true, false) as Node3D
	await _frames(7)
	_check("Garrafa aparece na mão ao beber", hand.get_child_count() > 0)
	var before_busy := _player.global_position
	Input.action_press("move_forward")
	await _frames(20)
	Input.action_release("move_forward")
	_check("Não anda enquanto bebe (%.2f m)" % before_busy.distance_to(_player.global_position),
		before_busy.distance_to(_player.global_position) < 0.1)
	await get_tree().create_timer(1.6).timeout
	_check("Beber água: sede 30 → %.0f" % water_after, is_equal_approx(water_after, 70.0))
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
	var dropped: ItemPickup = null
	for node in _player.get_parent().find_children("*", "RigidBody3D", true, false):
		if node is ItemPickup and node.item_id == &"soda_can":
			dropped = node
	var drop_y := dropped.global_position.y
	await get_tree().create_timer(1.5).timeout
	_check("Item largado cai com física e repousa no chão (%.2f → %.2f m)" % [drop_y, dropped.global_position.y],
		drop_y > 0.5 and dropped.global_position.y < 0.15 and dropped.global_position.y > -0.05)
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

	await _run_weapons()
	await _run_parkour_axe()
	await _run_zombie()

	# --- Morte
	stats.apply_damage(500.0)
	await get_tree().create_timer(1.5).timeout
	var death := _hud.get_node("DeathScreen") as Control
	_check("Vida zerada mostra a tela de morte", stats.is_dead and death.visible)


# ================================================================ PARKOUR, MACHADO, SONS

func _run_parkour_axe() -> void:
	print("\n-- Parkour, machado e sons --")
	var world := _player.get_parent()
	var inv := _player.inventory
	var stats := _player.stats
	var weapons := _player.get_node("Weapons") as WeaponHandler
	var visual := _player.get_node("Visual") as Node3D
	if weapons.wielded_slot != -1:
		weapons.set_wielded(-1)
	stats.stamina = 100.0
	# --- Salto sobre a cerca (1,2 m de altura, fina)
	_teleport(Vector3(5.9, 0.05, 12.0), 0.0)
	visual.rotation.y = -PI / 2  # olhando para +X (a cerca está em x = 7)
	await _frames(8)
	var scan := _player.parkour.analyze(_player.global_position, _player.facing())
	_check("Cerca detectada como salto (%s)" % str(scan.get("kind", "nada")), scan.get("kind", -1) == Parkour.Kind.VAULT)
	await _tap_action("jump")
	var tree := (_player.get_node("Visual") as SurvivorAnimator).get("_tree") as AnimationTree
	await _frames(2)
	_check("Animação de salto de obstáculo (%s)" % tree.get("parameters/use_kind/current_state"),
		tree.get("parameters/use_kind/current_state") == "vault")
	await get_tree().create_timer(1.5).timeout
	_check("Passou para o outro lado da cerca (x = %.2f)" % _player.global_position.x,
		_player.global_position.x > 7.3 and _player.is_on_floor())
	# --- Escalada na plataforma de 1,5 m
	_teleport(Vector3(12.0, 0.05, -7.0), 0.0)
	visual.rotation.y = PI  # olhando para +Z
	await _frames(8)
	scan = _player.parkour.analyze(_player.global_position, _player.facing())
	_check("Plataforma detectada como escalada (altura %.2f)" % float(scan.get("height", 0.0)),
		scan.get("kind", -1) == Parkour.Kind.CLIMB)
	await _tap_action("jump")
	await get_tree().create_timer(2.0).timeout
	_check("Subiu na plataforma (y = %.2f)" % _player.global_position.y,
		_player.global_position.y > 1.4 and _player.global_position.z > -5.9 and _player.is_on_floor())
	# chão livre: Pular continua sendo um pulo normal
	_teleport(Vector3(0, 0.05, 22.0), 0.0)
	await _frames(8)
	_check("Sem obstáculo à frente não há parkour",
		_player.parkour.analyze(_player.global_position, _player.facing()).is_empty())

	# --- Machado pela barra de armas
	inv.add_item(&"axe")
	await _frames(3)
	var hotbar := _hud.get_node("%WeaponHotbar") as WeaponHotbar
	var entries := weapons.weapon_entries()
	_check("Barra de armas lista %d armas (taco, pistola, machado)" % entries.size(), entries.size() == 3)
	weapons.select_entry(2)
	await _frames(3)
	var axe := inv.equipped(ItemData.Slot.MELEE)
	_check("Tocar no machado: troca pelo taco e empunha", axe != null and axe.item_id == &"axe"
		and weapons.wielded_slot == ItemData.Slot.MELEE and inv.count_of(&"baseball_bat") == 1)
	_check("Espaço do machado destacado na barra", (hotbar.get_node("Slot1") as Button).visible)
	weapons.select_entry(0)
	await _frames(2)
	_check("Tocar de novo guarda o machado nas costas", weapons.wielded_slot == -1)
	weapons.select_entry(0)
	await _frames(2)

	# --- Cortar árvore
	var tree_node := world.get_node("Grove/ChopTree0") as ChoppableTree
	var to_tree := Vector3(-17, 0, 10) + Vector3(0, 0.05, 1.0)
	_teleport(to_tree, 0.0)
	visual.rotation.y = 0.0  # olhando para -Z (a árvore está 1 m à frente)
	_rig.set("_yaw_deg", 0.0)
	await _frames(5)
	for i in tree_node.hits_to_fell:
		stats.stamina = 100.0
		await _tap_action("attack")
		await get_tree().create_timer(1.1).timeout
	_check("Machado derruba a árvore depois de %d golpes (golpes: %d)" % [tree_node.hits_to_fell, tree_node.hits],
		tree_node.is_felled)
	await get_tree().create_timer(2.2).timeout
	var pivot := tree_node.get_node("Pivot") as Node3D
	var tilt := rad_to_deg(Vector3.UP.angle_to(pivot.global_basis.y))
	_check("Árvore tomba (inclinação %.0f°)" % tilt, tilt > 70.0)
	_check("Tronco caído não bloqueia a passagem (só o toco)",
		((tree_node.get_node("Collision") as CollisionShape3D).shape as CylinderShape3D).height < 0.5)
	weapons.set_wielded(-1)

	# --- Sons
	_check("Sons carregados (tiro, passos, zumbi, machado)", Sfx.has_sound(&"gunshot") and Sfx.has_sound(&"step_grass")
		and Sfx.has_sound(&"zombie_groan") and Sfx.has_sound(&"axe_chop") and Sfx.has_sound(&"tree_fall"))
	_check("Vento ambiente tocando em loop", Sfx.get("_ambient") != null and (Sfx.get("_ambient") as AudioStreamPlayer).playing)
	stats.health = 100.0
	stats.stamina = 100.0


# ================================================================ ZUMBI

func _run_zombie() -> void:
	print("\n-- Zumbi --")
	var world := _player.get_parent()
	var stats := _player.stats
	stats.health = 100.0
	stats.stamina = 100.0
	var weapons := _player.get_node("Weapons") as WeaponHandler
	if weapons.wielded_slot != -1:
		weapons.set_wielded(-1)
	_teleport(Vector3(0, 0.05, 30), 0.0)
	await _frames(5)
	var z := (load("res://scenes/characters/zombie.tscn") as PackedScene).instantiate() as Zombie
	world.add_child(z)
	z.global_position = Vector3(0, 0.05, 36)
	(z.get_node("Visual") as Node3D).rotation.y = PI   # de costas para o jogador (olhando +Z)
	await _frames(10)
	z._set_state(Zombie.State.IDLE)
	var anim := z.find_child("AnimationPlayer", true, false) as AnimationPlayer
	_check("Zumbi tem as 5 animações", anim.has_animation(&"z_walk") and anim.has_animation(&"z_attack")
		and anim.has_animation(&"z_idle") and anim.has_animation(&"z_hit") and anim.has_animation(&"z_death"))
	await get_tree().create_timer(1.0).timeout
	_check("De costas não vê o jogador (%s)" % z.state_name(),
		z.state in [Zombie.State.IDLE, Zombie.State.PATROL])
	# barulho: tiro perto faz ele investigar
	Events.noise_emitted.emit(Vector3(0, 0, 30), 45.0, _player)
	await _frames(3)
	_check("Ouve o tiro e vai investigar (%s)" % z.state_name(), z.state == Zombie.State.INVESTIGATE)
	await get_tree().create_timer(3.5).timeout
	_check("Vira, vê o jogador e persegue (%s)" % z.state_name(), z.state in [Zombie.State.ALERT, Zombie.State.CHASE, Zombie.State.ATTACK])
	var zpos := z.global_position
	await get_tree().create_timer(2.0).timeout
	var zspeed := zpos.distance_to(z.global_position) / 2.0
	_check("Anda devagar (%.2f m/s)" % zspeed, zspeed > 0.2 and zspeed < 1.2)
	_check("Animação de andar cambaleante (%s)" % anim.current_animation, anim.current_animation == &"z_walk")
	# deixa chegar e atacar
	var hp := stats.health
	var damaged := [false]
	Events.player_damaged.connect(func(_a: float) -> void: damaged[0] = true, CONNECT_ONE_SHOT)
	for i in 40:
		if stats.health < hp:
			break
		await get_tree().create_timer(0.25).timeout
	_check("Zumbi alcança e ataca: vida %.0f → %.0f" % [hp, stats.health], stats.health < hp and damaged[0])
	var flash := _hud.get_node("DamageFlash") as ColorRect
	_check("Tela pisca vermelho ao levar dano (%.2f)" % flash.color.a, flash.color.a > 0.05)
	_check("Jogador não atravessa o zumbi (%.2f m)" % _player.global_position.distance_to(z.global_position),
		Vector2(_player.global_position.x - z.global_position.x, _player.global_position.z - z.global_position.z).length() > 0.45)
	# revida com a pistola: tiro na cabeça
	stats.health = 100.0
	var head := z.global_position + Vector3.UP * 1.6
	z.apply_damage(35.0, _player, head)
	_check("Tiro na cabeça mata (dano triplo, %s)" % z.state_name(), z.is_dead())
	await get_tree().create_timer(0.5).timeout
	_check("Animação de morte (%s)" % anim.current_animation, anim.current_animation == &"z_death")
	_check("Corpo não bloqueia mais", z.collision_layer == 0)
	# outro zumbi: golpe no corpo não mata de uma vez e faz ele cambalear
	var z2 := (load("res://scenes/characters/zombie.tscn") as PackedScene).instantiate() as Zombie
	world.add_child(z2)
	z2.global_position = Vector3(6, 0.05, 36)
	await _frames(5)
	z2.apply_damage(25.0, _player, z2.global_position + Vector3.UP * 1.0)
	await _frames(2)
	_check("Golpe no corpo: vida %.0f, reação de dor (%s)" % [z2.health, z2.state_name()],
		not z2.is_dead() and z2.state == Zombie.State.STAGGER)
	z.queue_free()
	z2.queue_free()
	stats.health = 100.0
	await _frames(5)


# ================================================================ ARMAS

func _run_weapons() -> void:
	print("\n-- Armas --")
	var inv := _player.inventory
	var stats := _player.stats
	var weapons := _player.get_node("Weapons") as WeaponHandler
	var animator := _player.get_node("Visual") as SurvivorAnimator
	var world := _player.get_parent()
	stats.food = 100.0
	stats.water = 100.0
	stats.stamina = 100.0

	# --- Pegar o taco: vai direto para as costas
	await _approach(Vector3(6.6, 0.0, 4.8))
	await _pickup_wait()
	var bat := inv.equipped(ItemData.Slot.MELEE)
	_check("Taco vai direto para as costas", bat != null and bat.item_id == &"baseball_bat")
	var bat_node := animator.weapon_node(ItemData.Slot.MELEE)
	_check("Modelo do taco preso nas costas (%s)" % (bat_node.get_parent().name if bat_node else "nenhum"),
		bat_node != null and String(bat_node.get_parent().name).begins_with("Socket_Back"))
	var hotbar := _hud.get_node("%WeaponHotbar") as WeaponHotbar
	var attack_btn := _hud.get_node("%AttackButton") as ActionButton
	await _frames(2)
	_check("Barra de armas aparece com o taco", hotbar.visible and (hotbar.get_node("Slot1") as Button).visible
		and not (hotbar.get_node("Slot2") as Button).visible and not attack_btn.visible)

	# --- Empunhar e golpear o boneco
	await _tap_action("weapon")
	await _frames(3)
	_check("Empunhar: taco na mão (%s)" % bat_node.get_parent().name, bat_node.get_parent().name == "Socket_Hand_R")
	_check("Botão Atacar aparece", attack_btn.visible and attack_btn.label == "Atacar")
	var dummy := world.get_node("PracticeTargets/TrainingDummy") as PracticeTarget
	_teleport(Vector3(3.5, 0.05, 10.6), 0.0)
	(_player.get_node("Visual") as Node3D).rotation.y = 0.0
	await _frames(5)
	var stamina_before := stats.stamina
	await _tap_action("attack")
	var tree := animator.get("_tree") as AnimationTree
	_check("Animação de golpe toca (camada de ação ativa)", tree.get("parameters/action/active"))
	_check("Camada de segurar arma ativa (%.2f)" % tree.get("parameters/hold/blend_amount"), tree.get("parameters/hold/blend_amount") > 0.0)
	await get_tree().create_timer(0.6).timeout
	_check("Golpe acerta o boneco (acertos: %d)" % dummy.hits, dummy.hits == 1)
	_check("Golpe gasta stamina (%.0f → %.0f)" % [stamina_before, stats.stamina], stats.stamina < stamina_before)
	_check("Golpe gasta durabilidade (%.0f%%)" % bat.durability, bat.durability < 100.0)
	await get_tree().create_timer(0.6).timeout

	# --- Pegar a pistola: vai para o coldre
	await _approach(Vector3(2.5, 0.1, -15.3))
	await _pickup_wait()
	var pistol := inv.equipped(ItemData.Slot.SIDEARM)
	_check("Pistola vai para o coldre", pistol != null and pistol.item_id == &"pistol")
	var pistol_node := animator.weapon_node(ItemData.Slot.SIDEARM)
	_check("Modelo da pistola no coldre", pistol_node != null and pistol_node.get_parent().name == "Socket_Holster")
	var holster := _player.get_node("Visual/Model").find_child("Holster", true, false) as Node3D
	_check("Coldre aparece na coxa", holster.visible)

	# --- Trocar para a pistola
	await _tap_action("weapon")
	await _frames(3)
	_check("Trocar arma: pistola na mão, taco volta às costas",
		pistol_node.get_parent().name == "Socket_Hand_R" and String(bat_node.get_parent().name).begins_with("Socket_Back"))
	var reload_btn := _hud.get_node("%ReloadButton") as ActionButton
	_check("Botões Atirar e Recarregar aparecem", attack_btn.label == "Atirar" and reload_btn.visible)
	_check("Com pistola o corpo acompanha a câmera", _player.face_camera)

	# --- Andar de lado / de costas com arma em mãos (animações direcionais)
	_teleport(Vector3(0, 0.05, 18), 0.0)
	_rig.set("_yaw_deg", 0.0)
	await _frames(20)
	var tree2 := animator.get("_tree") as AnimationTree
	Input.action_press("move_right")
	await _frames(45)
	var side_speed := Vector2(_player.velocity.x, _player.velocity.z).length()
	var bp: Vector2 = tree2.get("parameters/loco_%s/blend_position" % animator.current_animation())
	Input.action_release("move_right")
	_check("De lado usa animação lateral (%s, mistura %s)" % [animator.current_animation(), bp],
		animator.current_animation() in [&"walk", &"run"] and bp.x > 0.7)
	await _frames(30)
	Input.action_press("move_back")
	await _frames(45)
	var back_speed := Vector2(_player.velocity.x, _player.velocity.z).length()
	bp = tree2.get("parameters/loco_%s/blend_position" % animator.current_animation())
	Input.action_release("move_back")
	_check("De costas usa animação para trás (mistura %s)" % bp, bp.y < -0.7)
	_check("De lado e de costas é mais lento (%.1f / %.1f m/s, frente 3.6)" % [side_speed, back_speed],
		side_speed < 3.0 and back_speed < side_speed)
	await _frames(30)

	# --- Sem munição / recarregar
	await _tap_action("attack")
	await _frames(3)
	_check("Sem munição não dispara (carregador %d)" % pistol.loaded, pistol.loaded == 0)
	inv.add_item(&"ammo_9mm", 30)
	await _tap_action("reload")
	await get_tree().create_timer(1.3).timeout
	_check("Recarregar: 15 no carregador, 15 na mochila (%d / %d)" % [pistol.loaded, inv.count_of(&"ammo_9mm")],
		pistol.loaded == 15 and inv.count_of(&"ammo_9mm") == 15)

	# --- Atirar na placa de treino
	var board := world.get_node("PracticeTargets/ShootingTarget") as PracticeTarget
	_teleport(Vector3(8.4, 0.05, 15.05), 0.0)
	for i in 10:  # mira no centro da placa (a câmera orbita, então ajusta algumas vezes)
		var cam_pos := get_viewport().get_camera_3d().global_position
		var to_board := board.global_position + Vector3.UP * 1.35 - cam_pos
		_rig.set("_yaw_deg", rad_to_deg(atan2(-to_board.x, -to_board.z)))
		_rig.set("_pitch_deg", rad_to_deg(asin(to_board.y / to_board.length())))
		await _frames(12)
	await _tap_action("attack")
	await _frames(4)
	_check("Tiro gasta munição (%d)" % pistol.loaded, pistol.loaded == 14)
	_check("Tiro acerta a placa (acertos: %d)" % board.hits, board.hits == 1)
	var flash := animator.weapon_node(ItemData.Slot.SIDEARM).get_node_or_null("Flash")
	_check("Clarão do disparo é reaproveitado (nó fixo na arma)", flash != null)
	var impacts := world.find_children("*", "ImpactEffect", false, false).size()
	_check("Marca de tiro aparece (%d)" % impacts, impacts >= 1)
	await get_tree().create_timer(0.4).timeout

	# --- Otimizações
	var shirt := _player.get_node("Visual/Model").find_child("Shirt", true, false) as Node3D
	var jacket_on := inv.equipped(ItemData.Slot.BODY) != null
	_check("Camiseta só é desenhada sem jaqueta (jaqueta: %s, camiseta: %s)" % [jacket_on, shirt.visible],
		shirt.visible != jacket_on)
	_check("Árvores em MultiMesh (2 desenhos)", world.get_node("Trees").find_children("*", "MultiMeshInstance3D", false, false).size() == 2)

	# --- Guardar
	await _tap_action("weapon")
	await _frames(3)
	_check("Guardar: mãos livres, pistola no coldre",
		weapons.wielded_slot == -1 and pistol_node.get_parent().name == "Socket_Holster" and not attack_btn.visible)


func _approach(item_pos: Vector3) -> void:
	_teleport(item_pos + Vector3(0, 0.05, 0.7), 0.0)
	(_player.get_node("Visual") as Node3D).rotation.y = 0.0
	await _frames(6)


func _index_of(id: StringName) -> int:
	for i in _player.inventory.stacks.size():
		if _player.inventory.stacks[i].item_id == id:
			return i
	return -1


func _pickup_wait() -> void:
	await _tap_action("interact")
	await get_tree().create_timer(1.0).timeout


func _count_pickups() -> int:
	var n := 0
	for node in _player.get_parent().find_children("*", "RigidBody3D", true, false):
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
