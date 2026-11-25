class_name PlayerController
extends CharacterBody3D
## Movimentação do sobrevivente em terceira pessoa + ações de inventário.
## Lê apenas ações do InputMap (teclado ou controles touch) e a direção da câmera.

@export_group("Velocidades (m/s)")
@export var walk_speed := 1.5
@export var jog_speed := 3.6
@export var sprint_speed := 5.8
@export var crouch_speed := 1.0
## Inclinação do joystick a partir da qual o personagem corre em vez de andar.
@export_range(0.1, 1.0) var jog_threshold := 0.6

@export_group("Resposta")
@export var acceleration := 10.0
@export var deceleration := 12.0
@export_range(0.0, 1.0) var air_control := 0.3
@export var turn_speed := 10.0
@export var jump_velocity := 4.6
## Altura máxima de degrau que o personagem sobe sozinho (calçadas, soleiras, escadas).
@export var step_height := 0.3
## Segundos parado até o sprint desligar sozinho.
@export var sprint_cancel_delay := 0.6

@export_group("Altura")
@export var stand_height := 1.8
@export var crouch_height := 1.2
@export var stand_camera_height := 1.55
@export var crouch_camera_height := 1.05

@export_group("Referências")
@export var camera_rig_path: NodePath

var is_crouching := false
var is_sprinting := false
## Altura atual do ponto que a câmera segue (suaviza ao agachar).
var camera_height := 1.55
var inventory := Inventory.new()
## Com pistola em mãos o corpo acompanha a câmera (mira); senão vira para onde anda.
var face_camera := false

var _camera_rig: CameraRig
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _focused_interactable: Node = null
var _last_prompt := ""
var _idle_time := 0.0
## Segundos restantes de uma ação de corpo inteiro (beber, comer, pegar): sem andar nem atacar.
var _busy := 0.0
var _noise_timer := 0.0
var _pending_pickup: Node = null
var _pickup_timer := -1.0
## Arma que estava na mão antes de beber/comer/pegar: volta para a mão no fim da ação.
var _rewield_slot := -1

## Raio (m) do barulho dos passos em cada postura: zumbis dentro dele ouvem.
const STEP_NOISE := {"crouch": 1.5, "walk": 4.0, "jog": 9.0, "sprint": 16.0}

@onready var stats: SurvivalStats = $Survival
@onready var _collision: CollisionShape3D = $CollisionShape3D
@onready var _capsule: CapsuleShape3D = _collision.shape
@onready var _visual: Node3D = $Visual
@onready var _animator: SurvivorAnimator = $Visual
@onready var _interaction_area: Area3D = $Visual/InteractionArea


func _ready() -> void:
	add_to_group("player")
	camera_height = stand_camera_height
	inventory.changed.connect(func() -> void: _animator.show_equipment(inventory))
	_animator.show_equipment(inventory)
	stats.died.connect(_on_died)
	if not camera_rig_path.is_empty():
		_camera_rig = get_node(camera_rig_path) as CameraRig
		_camera_rig.set_target(self)


func _physics_process(delta: float) -> void:
	_update_busy(delta)
	if _busy <= 0.0:
		_handle_actions()

	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back", 0.05)
	if _busy > 0.0 or stats.is_dead:
		input = Vector2.ZERO
	var strength := minf(input.length(), 1.0)
	var yaw := _camera_rig.get_yaw() if _camera_rig else 0.0
	var direction := Vector3(input.x, 0.0, input.y).rotated(Vector3.UP, yaw)
	if direction.length_squared() > 0.0:
		direction = direction.normalized()

	# Sprint desliga se o jogador ficar parado (dá tempo de tocar "Correr" e depois mover)
	_idle_time = _idle_time + delta if strength < 0.05 else 0.0
	if is_sprinting and _idle_time > sprint_cancel_delay:
		_set_sprinting(false)
	if is_sprinting and not stats.can_sprint():
		_set_sprinting(false)
		Events.notify.emit("Sem fôlego")

	var target_velocity := direction * _target_speed(strength) * _direction_factor(direction)
	# ao pegar algo um pouco longe, dá um passo curto até o item enquanto abaixa
	if _pending_pickup and is_instance_valid(_pending_pickup) and _pickup_timer > 0.12:
		var to := (_pending_pickup as Node3D).global_position - global_position
		to.y = 0.0
		var gap := to.length() - 0.5
		if gap > 0.05:
			target_velocity = to.normalized() * minf(gap / 0.3, 1.6)
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var rate := acceleration if target_velocity.length_squared() > 0.0 else deceleration
	if not is_on_floor():
		rate *= air_control
	horizontal = horizontal.lerp(target_velocity, 1.0 - exp(-rate * delta))
	velocity.x = horizontal.x
	velocity.z = horizontal.z

	if not is_on_floor():
		velocity.y -= _gravity * delta

	_try_step_up(delta)
	move_and_slide()

	if _aiming() and _camera_rig:
		_visual.rotation.y = lerp_angle(_visual.rotation.y, _camera_rig.get_yaw(), 1.0 - exp(-turn_speed * 1.5 * delta))
	elif direction.length_squared() > 0.0:
		var target_yaw := atan2(-direction.x, -direction.z)
		_visual.rotation.y = lerp_angle(_visual.rotation.y, target_yaw, 1.0 - exp(-turn_speed * delta))

	var target_cam := crouch_camera_height if is_crouching else stand_camera_height
	camera_height = lerpf(camera_height, target_cam, 1.0 - exp(-8.0 * delta))

	var ground_speed := Vector2(velocity.x, velocity.z).length()
	stats.tick(delta, _exertion(ground_speed))
	_emit_step_noise(delta, ground_speed)
	_animator.update_pose(ground_speed, sprint_speed, is_on_floor(), is_crouching, delta, _local_move_dir())
	_update_interaction_focus()


## Guarda a arma durante a ação (mão livre) e lembra qual era para devolver depois.
func _lower_weapon() -> void:
	var weapons := get_node_or_null("Weapons") as WeaponHandler
	if weapons and weapons.wielded_slot != -1:
		_rewield_slot = weapons.wielded_slot
		weapons.set_wielded(-1)


func is_busy() -> bool:
	return _busy > 0.0


func _update_busy(delta: float) -> void:
	var was_busy := _busy > 0.0
	_busy = maxf(_busy - delta, 0.0)
	if was_busy and _busy <= 0.0 and _rewield_slot != -1:
		var weapons := get_node_or_null("Weapons") as WeaponHandler
		if weapons and inventory.equipped(_rewield_slot) != null and weapons.wielded_slot == -1:
			weapons.set_wielded(_rewield_slot)
		_rewield_slot = -1
	if _pickup_timer >= 0.0:
		_pickup_timer -= delta
		if _pickup_timer < 0.0:
			if is_instance_valid(_pending_pickup) and not _pending_pickup.is_queued_for_deletion() \
					and not stats.is_dead:
				_pending_pickup.collect(self)
			_pending_pickup = null


## Passos fazem barulho conforme a postura (agachado quase não se ouve).
func _emit_step_noise(delta: float, ground_speed: float) -> void:
	_noise_timer -= delta
	if _noise_timer > 0.0 or ground_speed < 0.3 or not is_on_floor():
		return
	_noise_timer = 0.5
	var key := "crouch" if is_crouching else ("sprint" if ground_speed > 4.7 else ("jog" if ground_speed > 2.4 else "walk"))
	Events.noise_emitted.emit(global_position, STEP_NOISE[key], self)


## Ataque recebido (ex.: zumbi). Flash vermelho, vibração e um tranco na câmera.
func take_hit(amount: float, from: Node3D = null) -> void:
	if stats.is_dead:
		return
	stats.apply_damage(amount)
	Events.player_damaged.emit(amount)
	GameSettings.vibrate(120, 1.0)
	if _camera_rig:
		_camera_rig.add_recoil(2.5)
	if from and not stats.is_dead:
		var push := global_position - from.global_position
		push.y = 0.0
		if push.length_squared() > 0.001:
			velocity += push.normalized() * 2.5


## Agacha, pega o item do chão e levanta. O item entra no inventário quando a mão o alcança.
func begin_pickup(pickup: Node3D) -> void:
	if _busy > 0.0 or stats.is_dead or _pending_pickup != null:
		return
	_lower_weapon()
	_set_sprinting(false)
	var to := pickup.global_position - global_position
	to.y = 0.0
	if to.length_squared() > 0.01:
		_visual.rotation.y = atan2(-to.x, -to.z)
	var d := Items.get_item(pickup.get("item_id"))
	var length := _animator.play_use(&"pickup", d, 0.5)
	_busy = maxf(length - 0.25, 0.5)
	_pending_pickup = pickup
	_pickup_timer = 0.48
	velocity = Vector3(0, velocity.y, 0)


## Postura de combate: arma em mãos e sem estar em sprint (no sprint a arma abaixa e o corpo
## vira para onde corre).
func _aiming() -> bool:
	return face_camera and not is_sprinting


## Com arma em mãos (corpo virado para a câmera) andar de lado ou de costas é mais lento.
func _direction_factor(direction: Vector3) -> float:
	if not _aiming() or direction.length_squared() < 0.001:
		return 1.0
	var c := direction.dot(facing())
	if c >= 0.0:
		return 0.72 + 0.28 * c
	return 0.72 + 0.12 * c


## Direção do movimento em relação a onde o corpo está virado (x = direita, y = frente).
func _local_move_dir() -> Vector2:
	var v := Vector3(velocity.x, 0.0, velocity.z)
	if not _aiming() or v.length_squared() < 0.01:
		return Vector2(0, 1)
	var fwd := facing()
	var right := fwd.cross(Vector3.UP)
	return Vector2(v.dot(right), v.dot(fwd)).normalized()


## Sobe degraus baixos: se o movimento bate numa borda, testa se cabe por cima e sobe.
func _try_step_up(delta: float) -> void:
	if not is_on_floor() or velocity.y > 0.1:
		return
	var motion := Vector3(velocity.x, 0.0, velocity.z) * delta
	if motion.length() < 0.0005:
		return
	# pequena folga à frente para detectar a borda antes de encostar
	var probe := motion + motion.normalized() * 0.05
	var collision := KinematicCollision3D.new()
	if not test_move(global_transform, probe, collision):
		return
	if collision.get_normal().y > 0.7:
		return  # é rampa/chão, o move_and_slide resolve
	var up := Vector3.UP * step_height
	if test_move(global_transform, up):
		return  # teto baixo
	var raised := global_transform.translated(up)
	if test_move(raised, probe):
		return  # alto demais (parede)
	var ahead := raised.translated(probe)
	var down := KinematicCollision3D.new()
	if not test_move(ahead, -up * 1.05, down):
		return  # não há chão depois do degrau
	if down.get_normal().y < 0.7:
		return
	var new_pos := ahead.origin + down.get_travel()
	if new_pos.y - global_position.y < 0.02:
		return
	global_position = new_pos - probe + motion


func _exertion(ground_speed: float) -> int:
	if ground_speed < 0.3:
		return SurvivalStats.Exertion.IDLE
	if is_sprinting and ground_speed > jog_speed:
		return SurvivalStats.Exertion.SPRINT
	if ground_speed > walk_speed + 0.3:
		return SurvivalStats.Exertion.JOG
	return SurvivalStats.Exertion.WALK


func _handle_actions() -> void:
	if Input.is_action_just_pressed("crouch"):
		_set_crouching(not is_crouching)
	if Input.is_action_just_pressed("sprint"):
		if not is_sprinting and not stats.can_sprint():
			Events.notify.emit("Sem fôlego")
		else:
			_set_sprinting(not is_sprinting)
	if Input.is_action_just_pressed("jump") and is_on_floor():
		if is_crouching:
			_set_crouching(false)
		elif stats.can_jump():
			stats.spend_stamina(stats.jump_cost)
			velocity.y = jump_velocity
		else:
			Events.notify.emit("Sem fôlego")
	if Input.is_action_just_pressed("interact") and _focused_interactable:
		_focused_interactable.interact(self)


func _target_speed(strength: float) -> float:
	if strength < 0.05:
		return 0.0
	if is_crouching:
		return crouch_speed * clampf(strength / jog_threshold, 0.4, 1.0)
	if is_sprinting:
		return sprint_speed
	return walk_speed if strength < jog_threshold else jog_speed


func _set_crouching(value: bool) -> void:
	if value == is_crouching:
		return
	if not value and not _can_stand_up():
		return
	is_crouching = value
	if is_crouching:
		_set_sprinting(false, false)
	var height := crouch_height if is_crouching else stand_height
	_capsule.height = height
	_collision.position.y = height * 0.5
	_emit_state()


func _set_sprinting(value: bool, emit := true) -> void:
	if value and is_crouching:
		_set_crouching(false)
		if is_crouching:
			return
	if value == is_sprinting:
		return
	is_sprinting = value
	if value:
		_idle_time = 0.0  # dá tempo de começar a andar depois de tocar em "Correr"
	if emit:
		_emit_state()


func _emit_state() -> void:
	Events.player_movement_state_changed.emit(is_crouching, is_sprinting)


func _can_stand_up() -> bool:
	var shape := CapsuleShape3D.new()
	shape.radius = _capsule.radius
	shape.height = stand_height
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis(), global_position + Vector3.UP * (stand_height * 0.5 + 0.02))
	query.collision_mask = collision_mask
	query.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


## Escolhe o objeto interativo mais próximo à frente do personagem.
func _update_interaction_focus() -> void:
	var best: Node = null
	var best_distance := INF
	var candidates: Array = _interaction_area.get_overlapping_bodies()
	candidates.append_array(_interaction_area.get_overlapping_areas())
	for candidate in candidates:
		if not candidate.has_method("interact") or candidate.is_queued_for_deletion():
			continue
		var d := global_position.distance_squared_to(candidate.global_position)
		if d < best_distance:
			best_distance = d
			best = candidate
	var verb := ""
	var target_name := ""
	if best:
		verb = best.get_interaction_prompt() if best.has_method("get_interaction_prompt") else "Usar"
		target_name = best.get_interaction_name() if best.has_method("get_interaction_name") else ""
	var prompt := verb + "|" + target_name
	if best != _focused_interactable or prompt != _last_prompt:
		_focused_interactable = best
		_last_prompt = prompt
		Events.interaction_target_changed.emit(verb, target_name)


func _on_died() -> void:
	_set_sprinting(false)
	set_physics_process(false)
	velocity = Vector3.ZERO
	_animator.play_death()
	Events.player_died.emit()


# ---------------------------------------------------------------- acesso para outros sistemas

func animator() -> SurvivorAnimator:
	return _animator


func camera_rig() -> CameraRig:
	return _camera_rig


## Direção para onde o corpo está virado.
func facing() -> Vector3:
	return -_visual.global_basis.z


## Vira o corpo instantaneamente para a direção da câmera (ao atirar).
func snap_to_camera() -> void:
	if _camera_rig:
		_visual.rotation.y = _camera_rig.get_yaw()


# ---------------------------------------------------------------- inventário

## Ao pegar uma arma: se o lugar dela no corpo estiver livre, ela vai direto para lá
## (arma branca nas costas, pistola no coldre).
func auto_equip(item_id: StringName) -> void:
	var d := Items.get_item(item_id)
	if d == null or not d.is_weapon() or d.equip_slot == ItemData.Slot.NONE:
		return
	if inventory.equipped(d.equip_slot) != null:
		return
	var index := inventory.index_of(item_id)
	if index >= 0 and inventory.equip(index):
		Events.notify.emit("%s %s" % [d.display_name, "nas costas" if d.equip_slot == ItemData.Slot.MELEE else "no coldre"])


## Come, bebe ou usa o item da pilha `index`.
func use_item(index: int) -> bool:
	if index < 0 or index >= inventory.stacks.size():
		return false
	var d := inventory.stacks[index].data()
	if d == null or not d.is_usable():
		return false
	if _busy > 0.0 or stats.is_dead:
		return false
	inventory.take_from(index, 1)
	stats.consume(d)
	Events.notify.emit("%s: %s" % [d.use_verb, d.display_name])
	var anim := &""
	if d.category == ItemData.Category.DRINK:
		anim = &"drink"
	elif d.category == ItemData.Category.FOOD:
		anim = &"eat"
	if anim != &"":
		_lower_weapon()
		_set_sprinting(false)
		_busy = _animator.play_use(anim, d, 0.1)
	return true


func equip_item(index: int) -> bool:
	var ok := inventory.equip(index)
	if ok:
		Events.notify.emit("Equipado")
	return ok


func unequip_item(slot: int) -> bool:
	if inventory.unequip(slot):
		return true
	Events.notify.emit("Sem espaço: esvazie a mochila antes")
	return false


## Solta `quantity` unidades da pilha `index` no chão, à frente do personagem.
func drop_item(index: int, quantity := 1) -> bool:
	var taken := inventory.take_from(index, quantity)
	if taken == null:
		return false
	_spawn_dropped(taken)
	return true


func drop_equipped(slot: int) -> bool:
	var taken := inventory.take_equipment(slot)
	if taken == null:
		return false
	# Se a capacidade cair abaixo do peso carregado, o excesso também cai no chão
	while inventory.total_weight() > inventory.capacity() + 0.0001 and not inventory.stacks.is_empty():
		var last := inventory.stacks.size() - 1
		_spawn_dropped(inventory.take_from(last, inventory.stacks[last].quantity))
	_spawn_dropped(taken)
	return true


func _spawn_dropped(stack: ItemStack) -> void:
	var forward := -_visual.global_basis.z
	var offset := Vector3(randf_range(-0.25, 0.25), 0.0, randf_range(-0.25, 0.25))
	var chest := global_position + Vector3.UP * 0.9
	var at := chest + forward * 0.6 + offset
	# não deixa o item atravessar parede/objeto à frente: para antes do obstáculo
	var ray := PhysicsRayQueryParameters3D.create(chest, at + forward * 0.2, 1)
	ray.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	if not hit.is_empty():
		at = chest + (hit.position - chest) * 0.6
	# o item nasce na altura das mãos e cai com física até o chão (ou em cima de algo)
	var pickup := ItemPickup.spawn(get_parent(), stack.item_id, stack.quantity, stack.durability, at)
	pickup.linear_velocity = forward * 0.8 + velocity * 0.5
	var d := stack.data()
	if d:
		Events.notify.emit("Largou %s" % d.display_name)
