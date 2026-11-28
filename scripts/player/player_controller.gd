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
@onready var parkour: Parkour = $Parkour

## Carro em que está (null = a pé) e etapa: "enter", "drive", "exit".
var vehicle: Vehicle = null
var _vehicle_stage := ""
var _vehicle_time := 0.0
var _approach_from := Vector3.ZERO
const VEHICLE_MASK := 32
## Dragão em que está montado e etapa: "approach", "mount", "ride", "lower", "dismount".
var dragon: Dragon = null
var _dragon_stage := ""
var _dragon_time := 0.0
const MOUNT_TIME := 54.0 / 30.0

## Item consumível na mão (pego do chão com "Pegar"): Consumir ou Guardar.
var held: ItemStack = null
var _pending_hold := false
var _step_distance := 0.0
var _air_time := 0.0
## Pulo parado: o impulso sai depois da preparação (agachar antes de pular).
var _jump_timer := -1.0
var _air_peak_y := 0.0
## Altura (m) a partir da qual a queda machuca.
@export var fall_damage_height := 3.2


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
	if vehicle != null:
		_vehicle_process(delta)
		return
	if dragon != null:
		_dragon_process(delta)
		return
	if parkour.is_active():
		global_position = parkour.step(delta)
		velocity = Vector3.ZERO
		_busy = maxf(_busy - delta, 0.0)
		if not parkour.is_active():
			_busy = 0.0
			_air_time = 0.0
			_finish_action()
		_animator.update_pose(0.0, sprint_speed, true, false, delta)
		return
	_update_busy(delta)
	if _jump_timer >= 0.0:
		_jump_timer -= delta
		if _jump_timer < 0.0 and is_on_floor():
			velocity.y = jump_velocity
	if _busy <= 0.0 and _jump_timer < 0.0:
		_handle_actions()

	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back", 0.05)
	if _busy > 0.0 or stats.is_dead or _jump_timer >= 0.0:
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
	_footsteps(delta, ground_speed)
	_animator.update_pose(ground_speed, sprint_speed, is_on_floor(), is_crouching, delta, _local_move_dir(),
		_aiming())
	_update_interaction_focus()


## Fim de uma ação de corpo inteiro: a arma volta para a mão (se não estiver segurando um item).
func _finish_action() -> void:
	if _rewield_slot != -1 and held == null:
		var weapons := get_node_or_null("Weapons") as WeaponHandler
		if weapons and inventory.equipped(_rewield_slot) != null and weapons.wielded_slot == -1:
			weapons.set_wielded(_rewield_slot)
		_rewield_slot = -1


# ---------------------------------------------------------------- carro

## Entra no carro pela porta do motorista: vai até a porta, abre, senta, fecha e põe as mãos no volante.
func enter_vehicle(v: Vehicle) -> void:
	if vehicle != null or v.is_occupied() or _busy > 0.0 or stats.is_dead or parkour.is_active():
		return
	if held != null and not store_held():
		return
	_lower_weapon()
	_rewield_slot = -1
	_set_sprinting(false)
	if is_crouching:
		_set_crouching(false)
	vehicle = v
	v.set_driver(self)
	_vehicle_stage = "approach"
	_vehicle_time = 0.0
	_approach_from = global_position
	velocity = Vector3.ZERO
	collision_layer = 0
	collision_mask = 0
	Events.interaction_target_changed.emit("", "")
	Events.interaction_alt_changed.emit("")


## Sai do carro (só parado ou quase parado).
func exit_vehicle() -> bool:
	if vehicle == null or _vehicle_stage != "drive":
		return false
	if vehicle.speed_kmh > 6.0:
		Events.notify.emit("Pare o carro para sair")
		return false
	var out := vehicle.exit_position()
	var shape := CapsuleShape3D.new()
	shape.radius = _capsule.radius
	shape.height = stand_height
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(Basis(), out + Vector3.UP * (stand_height * 0.5 + 0.05))
	q.collision_mask = 1 | VEHICLE_MASK | 16
	q.exclude = [vehicle.get_rid()]
	if not get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty():
		Events.notify.emit("Sem espaço para abrir a porta")
		return false
	_vehicle_stage = "exit"
	_vehicle_time = 0.0
	_last_prompt = ""
	Events.interaction_target_changed.emit("", "")
	Events.interaction_alt_changed.emit("")
	vehicle.throttle = 0.0
	vehicle.steer_input = 0.0
	vehicle.handbrake = true
	_animator.set_driving(false)
	_animator.play_use(&"car_exit")
	vehicle.play_door(true)
	if _camera_rig:
		_camera_rig.set_vehicle(null)
	Events.vehicle_changed.emit(null)
	return true


func in_vehicle() -> bool:
	return vehicle != null


func _vehicle_process(delta: float) -> void:
	_vehicle_time += delta
	var seat := vehicle.seat_transform()
	match _vehicle_stage:
		"approach":
			# anda até ao lado da porta, já virado para a frente do carro
			var out := vehicle.exit_position()
			var t := clampf(_vehicle_time / 0.35, 0.0, 1.0)
			global_position = _approach_from.lerp(Vector3(out.x, out.y, out.z), t)
			_visual.rotation.y = lerp_angle(_visual.rotation.y, vehicle.global_rotation.y, 1.0 - exp(-14.0 * delta))
			_animator.update_pose(1.0 if t < 1.0 else 0.0, sprint_speed, true, false, delta)
			if t >= 1.0:
				_vehicle_stage = "enter"
				_vehicle_time = 0.0
				_place_in_seat(seat)
				_animator.play_use(&"car_enter")
				vehicle.play_door(false)
		"enter":
			_place_in_seat(seat)
			if _vehicle_time >= float(Vehicle.ENTER_FRAMES) / 30.0 - 0.05:
				_vehicle_stage = "drive"
				_animator.set_driving(true)
				if _camera_rig:
					_camera_rig.set_vehicle(vehicle)
				vehicle.handbrake = false
				Events.vehicle_changed.emit(vehicle)
				Events.notify.emit("Acelerar / Freio-Ré (ou joystick) · joystick vira o volante · Freio de mão")
		"drive":
			_place_in_seat(seat)
			vehicle.throttle = maxf(Input.get_action_strength("move_forward"), Input.get_action_strength("car_gas"))
			vehicle.brake = maxf(Input.get_action_strength("move_back"), Input.get_action_strength("car_brake"))
			vehicle.steer_input = Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
			vehicle.handbrake = Input.is_action_pressed("jump")
			_animator.set_drive_steer(vehicle.steer_amount())
			if Input.is_action_just_pressed("interact"):
				exit_vehicle()
			var prompt := "Sair" if vehicle.speed_kmh <= 6.0 else ""
			if prompt != _last_prompt:
				_last_prompt = prompt
				Events.interaction_target_changed.emit(prompt, "")
		"exit":
			_place_in_seat(seat)
			if _vehicle_time >= float(Vehicle.ENTER_FRAMES) / 30.0 - 0.05:
				_leave_vehicle()


func _place_in_seat(seat: Transform3D) -> void:
	global_transform = Transform3D(seat.basis.orthonormalized(), seat.origin)
	_visual.rotation = Vector3.ZERO
	velocity = Vector3.ZERO


func _leave_vehicle() -> void:
	var v := vehicle
	var yaw := v.global_rotation.y
	var out := v.exit_position()
	vehicle = null
	_vehicle_stage = ""
	global_transform = Transform3D(Basis(), out + Vector3.UP * 0.05)
	_visual.rotation = Vector3(0, yaw, 0)
	reset_physics_interpolation()
	collision_layer = 2
	collision_mask = 1 | 16 | VEHICLE_MASK
	v.set_driver(null)
	_last_prompt = ""
	Events.interaction_target_changed.emit("", "")


# ---------------------------------------------------------------- dragão

## Vai até o lado esquerdo do dragão deitado, sobe pela asa dobrada e senta na sela.
func mount_dragon(d: Dragon) -> void:
	if dragon != null or vehicle != null or d.is_occupied() or not d.is_lying() or _busy > 0.0 \
			or stats.is_dead or parkour.is_active():
		return
	if held != null and not store_held():
		return
	_lower_weapon()
	_rewield_slot = -1
	_set_sprinting(false)
	if is_crouching:
		_set_crouching(false)
	dragon = d
	d.set_rider(self)
	_dragon_stage = "approach"
	_dragon_time = 0.0
	_approach_from = global_position
	velocity = Vector3.ZERO
	collision_layer = 0
	collision_mask = 0
	_last_prompt = ""
	Events.interaction_target_changed.emit("", "")
	Events.interaction_alt_changed.emit("")


func riding_dragon() -> bool:
	return dragon != null


func _dragon_process(delta: float) -> void:
	_dragon_time += delta
	match _dragon_stage:
		"approach":
			var spot := dragon.mount_position()
			var t := clampf(_dragon_time / 0.45, 0.0, 1.0)
			global_position = _approach_from.lerp(spot, t)
			_visual.rotation.y = lerp_angle(_visual.rotation.y, dragon.global_rotation.y - PI * 0.5, 1.0 - exp(-14.0 * delta))
			_animator.update_pose(1.0 if t < 1.0 else 0.0, sprint_speed, true, false, delta)
			if t >= 1.0:
				_dragon_stage = "mount"
				_dragon_time = 0.0
				_place_in_seat(dragon.seat_transform())
				_animator.play_use(&"mount_dragon")
		"mount":
			_place_in_seat(dragon.seat_transform())
			if _dragon_time >= MOUNT_TIME - 0.05:
				_dragon_stage = "ride"
				_animator.set_riding(true)
				dragon.stand_up()
				if _camera_rig:
					_camera_rig.set_dragon(dragon)
				Events.dragon_changed.emit(dragon)
				Events.notify.emit("Voar: decola · segure para bater asas · joystick guia · Pousar · Rugir")
		"ride":
			_place_in_seat(dragon.seat_transform())
			var mv := Input.get_vector("move_left", "move_right", "move_back", "move_forward", 0.05)
			dragon.steer = mv
			dragon.flap_held = Input.is_action_pressed("dragon_flap")
			if Input.is_action_just_pressed("dragon_flap") and dragon.is_grounded_idle():
				dragon.take_off()
			if Input.is_action_just_pressed("dragon_land"):
				dragon.request_land()
			if Input.is_action_just_pressed("dragon_roar"):
				dragon.roar()
			_animator.set_ride_lean(dragon.roll_deg / 40.0)
			if Input.is_action_just_pressed("interact") and dragon.is_grounded_idle():
				dismount_dragon()
			var prompt := "Desmontar" if dragon.is_grounded_idle() else ""
			if prompt != _last_prompt:
				_last_prompt = prompt
				Events.interaction_target_changed.emit(prompt, "")
		"lower":
			# espera o dragão deitar para descer
			_place_in_seat(dragon.seat_transform())
			if dragon.is_lying():
				_dragon_stage = "dismount"
				_dragon_time = 0.0
				_animator.set_riding(false)
				_animator.play_use(&"dismount_dragon")
		"dismount":
			_place_in_seat(dragon.seat_transform())
			if _dragon_time >= MOUNT_TIME - 0.05:
				_leave_dragon()


## Desmonta (só com o dragão parado no chão): ele deita e o jogador desce pela asa.
func dismount_dragon() -> bool:
	if dragon == null or _dragon_stage != "ride" or not dragon.is_grounded_idle():
		return false
	_dragon_stage = "lower"
	_dragon_time = 0.0
	dragon.steer = Vector2.ZERO
	dragon.flap_held = false
	dragon.lie_down()
	_last_prompt = ""
	Events.interaction_target_changed.emit("", "")
	if _camera_rig:
		_camera_rig.set_dragon(null)
	Events.dragon_changed.emit(null)
	return true


func _leave_dragon() -> void:
	var d := dragon
	var spot := d.mount_position()
	# em encosta: pisa no chão de verdade ao lado do dragão
	var q := PhysicsRayQueryParameters3D.create(spot + Vector3.UP * 3.0, spot + Vector3.DOWN * 4.0, 1)
	q.exclude = [d.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit:
		spot.y = (hit.position as Vector3).y
	dragon = null
	_dragon_stage = ""
	global_transform = Transform3D(Basis(), spot + Vector3.UP * 0.05)
	_visual.rotation = Vector3(0, d.global_rotation.y - PI * 0.5, 0)
	reset_physics_interpolation()
	collision_layer = 2
	collision_mask = 1 | 16 | VEHICLE_MASK
	d.set_rider(null)
	_last_prompt = ""
	Events.interaction_target_changed.emit("", "")


# ---------------------------------------------------------------- porta-malas e fogueira

## Vai até a traseira do carro e abre (ou fecha) a tampa com as duas mãos.
func use_trunk(v: Vehicle, open: bool) -> void:
	if _busy > 0.0 or stats.is_dead or vehicle != null:
		return
	_lower_weapon()
	_set_sprinting(false)
	# fica de frente para a traseira do carro
	var to := v.global_position - global_position
	to.y = 0.0
	if to.length_squared() > 0.01:
		_visual.rotation.y = atan2(-to.x, -to.z)
	var length := _animator.play_use(&"trunk_open" if open else &"trunk_close")
	_busy = maxf(length - 0.15, 0.6)
	v.set_trunk_open(open)
	if open:
		# assim que a tampa sobe, já mostra o que tem dentro
		get_tree().create_timer(length).timeout.connect(func() -> void:
			if is_instance_valid(v) and v.trunk_open and global_position.distance_to(v.global_position) < 4.0:
				open_container(v.trunk, "Porta-malas"))


func open_container(inv: Inventory, title: String) -> void:
	if stats.is_dead:
		return
	Events.container_requested.emit(inv, title)


## Monta uma fogueira à frente com 3 lenhas: ajoelha, arruma as pedras e as toras e acende.
func build_campfire() -> bool:
	if _busy > 0.0 or stats.is_dead or vehicle != null:
		return false
	if inventory.count_of(&"firewood") < 3:
		Events.notify.emit("Precisa de 3 lenhas para a fogueira")
		return false
	var fwd := facing()
	var spot := global_position + fwd * 1.1
	var space := get_world_3d().direct_space_state
	var down := PhysicsRayQueryParameters3D.create(spot + Vector3.UP * 0.8, spot + Vector3.DOWN * 1.0, 1)
	down.exclude = [get_rid()]
	var hit := space.intersect_ray(down)
	if hit.is_empty() or (hit.normal as Vector3).y < 0.85 or absf(hit.position.y - global_position.y) > 0.4:
		Events.notify.emit("Precisa de um chão plano à frente")
		return false
	spot = hit.position
	var shape := SphereShape3D.new()
	shape.radius = 0.5
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(Basis(), spot + Vector3.UP * 0.6)
	q.collision_mask = 1 | 32
	if not space.intersect_shape(q, 1).is_empty():
		Events.notify.emit("Sem espaço para a fogueira aqui")
		return false
	for c in get_tree().get_nodes_in_group("campfires"):
		if (c as Node3D).global_position.distance_to(spot) < 1.5:
			Events.notify.emit("Já tem uma fogueira aqui")
			return false
	_lower_weapon()
	_set_sprinting(false)
	var length := _animator.play_use(&"build_fire")
	_busy = length
	inventory.consume(&"firewood", 3)
	get_tree().create_timer(length * 0.85).timeout.connect(func() -> void:
		var fire := Campfire.new()
		get_parent().add_child(fire)
		fire.global_position = spot
		fire.rotation.y = randf() * TAU
		Events.notify.emit("Fogueira acesa"))
	return true


## Começa um salto/escalada (chamado pelo Parkour).
func begin_parkour(anim: StringName, fwd: Vector3, length: float) -> void:
	_lower_weapon()
	_set_sprinting(false)
	if is_crouching:
		_set_crouching(false)
	_visual.rotation.y = atan2(-fwd.x, -fwd.z)
	_animator.play_use(anim)
	_busy = length
	velocity = Vector3.ZERO


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
	if was_busy and _busy <= 0.0:
		_finish_action()
	if _pickup_timer >= 0.0:
		_pickup_timer -= delta
		if _pickup_timer < 0.0:
			if is_instance_valid(_pending_pickup) and not _pending_pickup.is_queued_for_deletion() \
					and not stats.is_dead:
				if _pending_hold:
					_take_in_hand(_pending_pickup)
				else:
					_pending_pickup.collect(self)
					Sfx.play_3d(&"bag", global_position + Vector3.UP)
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
	Sfx.play_3d(&"player_hurt", global_position + Vector3.UP * 1.5)
	GameSettings.vibrate(120, 1.0)
	if _camera_rig:
		_camera_rig.add_recoil(2.5)
	if from and not stats.is_dead:
		var push := global_position - from.global_position
		push.y = 0.0
		if push.length_squared() > 0.001:
			velocity += push.normalized() * 2.5


## Agacha, pega o item do chão e levanta. O item entra no inventário quando a mão o alcança.
func begin_pickup(pickup: Node3D, hold := false) -> void:
	if _busy > 0.0 or stats.is_dead or _pending_pickup != null:
		return
	if hold and held != null:
		store_held()  # já tinha algo na mão: guarda antes de pegar outro
		if held != null:
			return
	_pending_hold = hold
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
	Sfx.play_3d(&"pickup", pickup.global_position)


## Item pego com "Pegar": fica na mão até o jogador escolher Consumir ou Guardar.
func _take_in_hand(pickup: Node) -> void:
	var stack := (pickup as ItemPickup).take_one()
	if stack == null:
		return
	held = stack
	_animator.set_holding(stack.data())
	_focused_interactable = null
	_last_prompt = ""


## Come/bebe/usa o item que está na mão.
func consume_held() -> bool:
	if held == null or _busy > 0.0 or stats.is_dead:
		return false
	var d := held.data()
	held = null
	_animator.set_holding(null)
	_last_prompt = ""
	return _consume(d)


## Põe o item da mão na mochila (se couber).
func store_held() -> bool:
	if held == null:
		return false
	var d := held.data()
	if inventory.add_item(held.item_id, 1, held.durability) <= 0:
		Events.notify.emit("Sem espaço para %s" % (d.display_name if d else "o item"))
		return false
	held = null
	_animator.set_holding(null)
	_last_prompt = ""
	Sfx.play_3d(&"bag", global_position + Vector3.UP)
	Events.notify.emit("Guardou %s" % (d.display_name if d else ""))
	_finish_action()
	return true


## Passos: um som a cada passada, de acordo com o piso (grama ou piso duro).
func _footsteps(delta: float, ground_speed: float) -> void:
	if not is_on_floor():
		if _air_time == 0.0:
			_air_peak_y = global_position.y
		_air_peak_y = maxf(_air_peak_y, global_position.y)
		_air_time += delta
		return
	if _air_time > 0.2:
		_on_landed(_air_peak_y - global_position.y)
		_step_distance = 0.0
	_air_time = 0.0
	if ground_speed < 0.3:
		_step_distance = 0.0
		return
	_step_distance += ground_speed * delta
	var stride := 0.5 if is_crouching else (0.62 if ground_speed < 2.4 else (1.0 if ground_speed < 4.7 else 1.3))
	if _step_distance < stride:
		return
	_step_distance = 0.0
	var surface := &"step_grass"
	var floor_hit := get_last_slide_collision()
	if floor_hit and floor_hit.get_collider() is Node and (floor_hit.get_collider() as Node).name != "Ground":
		surface = &"step_hard"
	var vol := -12.0 if is_crouching else (-4.0 if ground_speed < 2.4 else 0.0)
	Sfx.play_3d(surface, global_position, vol)


## Volta ao chão: a altura da queda decide a aterrissagem (leve, pesada) e o dano.
func _on_landed(drop: float) -> void:
	if drop < 0.25:
		return
	var hard := drop > 2.2
	_animator.play_land(hard)
	Sfx.play_3d(&"land", global_position, 2.0 if hard else -3.0)
	if hard:
		_busy = maxf(_busy, 0.55)  # leva um tempo para se recuperar
		velocity.x *= 0.2
		velocity.z *= 0.2
		GameSettings.vibrate(60, 0.8)
	if drop > fall_damage_height:
		var dmg := (drop - fall_damage_height) * 18.0
		stats.apply_damage(dmg)
		Events.player_damaged.emit(dmg)
		Sfx.play_3d(&"player_hurt", global_position + Vector3.UP * 1.2)
		Events.notify.emit("Queda feia")


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
		if held == null and parkour.try_start():
			pass
		elif is_crouching:
			_set_crouching(false)
		elif stats.can_jump():
			stats.spend_stamina(stats.jump_cost)
			var speed := Vector2(velocity.x, velocity.z).length()
			if speed > 2.2:
				# correndo: impulso na hora, numa perna só, levando o embalo para frente
				velocity.y = jump_velocity * 0.92
				_animator.start_jump(true)
			else:
				# parado/andando: agacha um instante e então pula
				_jump_timer = 0.13
				_animator.start_jump(false, 0.13)
		else:
			Events.notify.emit("Sem fôlego")
	if held != null:
		if Input.is_action_just_pressed("interact"):
			consume_held()
		elif Input.is_action_just_pressed("interact_alt"):
			store_held()
		return
	if Input.is_action_just_pressed("interact") and _focused_interactable:
		_focused_interactable.interact(self)
	elif Input.is_action_just_pressed("interact_alt") and _focused_interactable \
			and _focused_interactable.has_method("interact_alt"):
		_focused_interactable.interact_alt(self)


func _target_speed(strength: float) -> float:
	if strength < 0.05:
		return 0.0
	if is_crouching:
		return crouch_speed * clampf(strength / jog_threshold, 0.4, 1.0)
	if is_sprinting:
		return sprint_speed
	var weapons_node := get_node_or_null("Weapons") as WeaponHandler
	if weapons_node and weapons_node.aiming:
		# mirando de verdade (arma na linha dos olhos): só passos lentos e firmes
		return walk_speed * 0.6
	if _aiming():
		# mirando: passos mais curtos e cuidadosos; o "trote" fica contido
		return walk_speed * 0.8 if strength < jog_threshold else jog_speed * 0.72
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
	var verb := ""
	var target_name := ""
	var alt := ""
	var best: Node = null
	if held != null:
		# item na mão: os botões viram Consumir (Beber/Comer/Usar) e Guardar
		var d := held.data()
		verb = d.use_verb if d and not d.use_verb.is_empty() else "Consumir"
		target_name = d.display_name if d else ""
		alt = "Guardar"
	elif _busy <= 0.0:
		var best_distance := INF
		var candidates: Array = _interaction_area.get_overlapping_bodies()
		candidates.append_array(_interaction_area.get_overlapping_areas())
		for candidate in candidates:
			if not candidate.has_method("interact") or candidate.is_queued_for_deletion():
				continue
			var dist := global_position.distance_squared_to(candidate.global_position)
			if dist < best_distance:
				best_distance = dist
				best = candidate
		if best:
			verb = best.get_interaction_prompt() if best.has_method("get_interaction_prompt") else "Usar"
			target_name = best.get_interaction_name() if best.has_method("get_interaction_name") else ""
			alt = best.get_alt_prompt() if best.has_method("get_alt_prompt") else ""
	var prompt := verb + "|" + target_name + "|" + alt
	if best != _focused_interactable or prompt != _last_prompt:
		_focused_interactable = best
		_last_prompt = prompt
		Events.interaction_target_changed.emit(verb, target_name)
		Events.interaction_alt_changed.emit(alt)


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
	return _consume(d)


func _consume(d: ItemData) -> bool:
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
		Sfx.play_3d(&"drink" if anim == &"drink" else &"eat", global_position + Vector3.UP * 1.5)
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
