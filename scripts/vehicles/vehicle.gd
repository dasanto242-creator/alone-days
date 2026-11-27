class_name Vehicle
extends RigidBody3D
## Carro com física própria ("raycast vehicle"): cada roda é um raio para baixo com mola e
## amortecedor; o pneu gera força lateral (aderência) e longitudinal (motor/freio) limitadas pelo
## atrito, então o carro escorrega de verdade quando passa do limite. Funciona com qualquer motor
## de física (Jolt incluso).
##
## Direção: volante com resposta suave (não vira instantâneo), menos ângulo em alta velocidade,
## volta sozinho ao centro. Motor com curva de torque, câmbio automático de 5 marchas e ré.
## Freio de mão trava as rodas de trás (dá para "puxar" a traseira).

signal driver_changed(driver: Node)

const MODEL_SCENE := "res://assets/models/vehicles/hatch.glb"
## Quadros (30 fps) da animação de entrar; a porta abre e fecha nesses intervalos
## (iguais a tools/character/car_layout.py).
const ENTER_FRAMES := 56
const DOOR_OPEN_F := Vector2(3, 12)
const DOOR_CLOSE_F := Vector2(40, 48)
const DOOR_OPEN_DEG := 68.0

@export_group("Chassi")
@export var vehicle_mass := 1150.0
@export var wheel_radius := 0.32
@export var suspension_rest := 0.26      ## comprimento livre da mola (m)
@export var spring_k := 36000.0          ## N/m por roda
@export var damper_c := 3600.0           ## N·s/m por roda
@export var anti_roll := 9000.0
@export_group("Pneus")
@export var grip := 1.05                 ## coeficiente de atrito pneu-chão
@export var lateral_stiffness := 0.85    ## quanto da velocidade lateral o pneu "mata" por quadro
@export var handbrake_rear_grip := 0.45
@export_group("Motor e câmbio")
@export var peak_torque := 175.0         ## N·m
@export var gear_ratios := PackedFloat32Array([3.45, 2.05, 1.42, 1.08, 0.86])
@export var reverse_ratio := 3.3
@export var final_drive := 4.1
@export var max_rpm := 6300.0
@export var idle_rpm := 850.0
@export var brake_force := 9000.0        ## N (total)
@export var handbrake_force := 5500.0
@export_group("Direção")
@export var max_steer_deg := 34.0
@export var steer_speed := 2.4           ## rad/s ao virar o volante
@export var steer_return := 3.2          ## rad/s ao soltar
@export var steering_wheel_turns := 2.6  ## rad no volante por unidade de esterço

var driver: Node = null
var throttle := 0.0
var brake := 0.0
var steer_input := 0.0
var handbrake := false
var gear := 1                     ## 1..5, -1 = ré, 0 = neutro
var rpm := 850.0
var speed_kmh := 0.0

var _steer := 0.0                 ## esterço atual suavizado (-1..1)
var _wheels: Array[Dictionary] = []
var _model: Node3D
var _door: Node3D
var _door_base: Basis
var _steering_wheel: Node3D
var _sw_base: Basis
var _door_anim := -1.0            ## tempo da animação da porta (s); -1 = parada
var _door_reverse := false
var _engine: AudioStreamPlayer3D
var _skid: AudioStreamPlayer3D
var _shift_timer := 0.0
var _last_hit := 0.0
var _reverse_hold := 0.0


func _ready() -> void:
	add_to_group("vehicles")
	mass = vehicle_mass
	collision_layer = 32         # veículos
	collision_mask = 1 | 2 | 16 | 32
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0, 0.42, 0.15)
	angular_damp = 0.6
	linear_damp = 0.02
	contact_monitor = true
	max_contacts_reported = 4
	can_sleep = true
	body_entered.connect(_on_body_entered)
	handbrake = true
	_model = get_node_or_null("Model")
	if _model == null:
		_model = (load(MODEL_SCENE) as PackedScene).instantiate()
		_model.name = "Model"
		add_child(_model)
	_door = _model.find_child("Door_FL", true, false) as Node3D
	_door_base = _door.basis if _door else Basis()
	_steering_wheel = _model.find_child("SteeringWheel", true, false) as Node3D
	_sw_base = _steering_wheel.basis if _steering_wheel else Basis()
	for n in ["FL", "FR", "RL", "RR"]:
		var node := _model.find_child("Wheel_" + n, true, false) as Node3D
		if node == null:
			continue
		var p := node.position
		_wheels.append({
			"name": n, "node": node, "base": node.basis, "front": n[0] == "F", "left": n[1] == "L",
			# montagem calculada para que, parado (mola comprimida pelo peso), a roda fique exatamente
			# onde está no modelo e a carroceria na altura certa
			"mount": Vector3(p.x, p.y + suspension_rest - _static_sag(), p.z), "length": suspension_rest,
			"spin": 0.0, "contact": false, "load": 0.0, "slip": 0.0,
		})
	_engine = _make_audio(&"engine_loop", -6.0)
	_skid = _make_audio(&"tire_skid", -60.0)


func _static_sag() -> float:
	return vehicle_mass * 9.8 * 0.25 / spring_k


func _make_audio(sound: StringName, vol: float) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	var stream: AudioStream = Sfx.stream(sound) if Sfx.has_method("stream") else null
	if stream is AudioStreamWAV:
		stream = (stream as AudioStreamWAV).duplicate()
		(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
		(stream as AudioStreamWAV).loop_end = int(stream.get_length() * (stream as AudioStreamWAV).mix_rate)
	p.stream = stream
	p.volume_db = vol
	p.unit_size = 6.0
	p.max_distance = 60.0
	p.position = Vector3(0, 0.6, -1.5)
	add_child(p)
	return p


# ---------------------------------------------------------------- pontos do carro

func seat_transform() -> Transform3D:
	var seat := _model.find_child("Seat", true, false) as Node3D
	return seat.global_transform if seat else global_transform


func exit_position() -> Vector3:
	var e := _model.find_child("Exit_L", true, false) as Node3D
	return e.global_position if e else global_position + global_basis.x * -1.6


func is_occupied() -> bool:
	return driver != null


## Abre e fecha a porta junto com a animação de entrar (ou sair, ao contrário).
func play_door(exiting: bool) -> void:
	_door_anim = 0.0
	_door_reverse = exiting


func set_driver(d: Node) -> void:
	driver = d
	if d == null:
		throttle = 0.0
		steer_input = 0.0
		brake = 0.0
		handbrake = true
	sleeping = false
	driver_changed.emit(d)


# ---------------------------------------------------------------- física

func _physics_process(delta: float) -> void:
	_update_door(delta)
	var fwd := -global_basis.z
	var v_fwd := linear_velocity.dot(fwd)
	speed_kmh = absf(v_fwd) * 3.6
	_update_controls(delta, v_fwd)
	var max_angle := deg_to_rad(max_steer_deg) * lerpf(1.0, 0.35, clampf(speed_kmh / 120.0, 0.0, 1.0))
	var steer_angle := _steer * max_angle
	var space := get_world_3d().direct_space_state
	var drive_force := _engine_force(v_fwd, delta)
	var compress := {}
	for w in _wheels:
		var mount: Vector3 = global_transform * (w.mount as Vector3)
		var down := -global_basis.y
		var ray_len: float = suspension_rest + wheel_radius + 0.08
		var q := PhysicsRayQueryParameters3D.create(mount, mount + down * ray_len, 1 | 32)
		q.exclude = [get_rid()]
		var hit := space.intersect_ray(q)
		w.contact = not hit.is_empty()
		if not w.contact:
			w.length = lerpf(w.length, suspension_rest, 1.0 - exp(-10.0 * delta))
			w.load = 0.0
			compress[w.name] = 0.0
			continue
		var length: float = clampf(mount.distance_to(hit.position) - wheel_radius, 0.0, suspension_rest)
		var x: float = suspension_rest - length
		# o pneu "sobe" degraus (meio-fio) em vez de o raio pular de uma vez: limita a velocidade de
		# compressão, senão o amortecedor dá um coice enorme e o carro decola
		var vel_comp: float = clampf(((w.length as float) - length) / delta, -1.8, 1.8)
		w.length = length
		compress[w.name] = x
		var spring := spring_k * x + damper_c * vel_comp
		spring = maxf(spring, 0.0)
		w.load = spring
		var contact: Vector3 = hit.position
		var normal: Vector3 = hit.normal
		apply_force(normal * spring, contact - global_position)
		# referencial do pneu (dianteiras esterçam)
		var basis_w := global_basis
		if w.front:
			basis_w = basis_w * Basis(Vector3.UP, -steer_angle)
		var t_fwd := (-basis_w.z).slide(normal).normalized()
		var t_side := basis_w.x.slide(normal).normalized()
		var v := linear_velocity + angular_velocity.cross(contact - global_position)
		var v_long := v.dot(t_fwd)
		var v_lat := v.dot(t_side)
		var mu := grip
		if handbrake and not w.front:
			mu *= handbrake_rear_grip
		var max_f := mu * spring
		# lateral: tenta anular o escorregamento, limitado pelo atrito
		var wheel_mass := mass * 0.25
		var f_lat := -v_lat * wheel_mass / delta * lateral_stiffness
		# longitudinal: motor (tração dianteira), freios e resistência ao rolamento
		var f_long := -v_long * 18.0
		if w.front:
			f_long += drive_force * 0.5
		# em ré os pedais invertem: "freio" acelera para trás e "acelerar" freia
		var pedal_brake := throttle if gear == -1 else brake
		var b := pedal_brake * brake_force * 0.25 * (1.2 if w.front else 0.8)
		if handbrake and not w.front:
			b += handbrake_force * 0.5
		if b > 0.0:
			var stop := wheel_mass * absf(v_long) / delta
			f_long -= signf(v_long) * minf(b, stop)
		# círculo de atrito: força total do pneu não passa do limite
		var total := Vector2(f_long, f_lat)
		if total.length() > max_f:
			total = total.normalized() * max_f
			w.slip = 1.0
		else:
			w.slip = 0.0
		# aplica perto da altura do centro de massa (geometria anti-mergulho/anti-agachamento da
		# suspensão): o carro inclina um pouco ao frear e acelerar, sem "empinar"
		var app := contact + global_basis.y * (center_of_mass.y + (w.mount as Vector3).y * 0.0 - 0.05) * 0.75
		apply_force(t_fwd * total.x + t_side * total.y, app - global_position)
		w.spin = fmod((w.spin as float) + v_long / wheel_radius * delta, TAU)
	# barra estabilizadora (menos rolagem nas curvas)
	for pair in [["FL", "FR"], ["RL", "RR"]]:
		var diff: float = compress.get(pair[0], 0.0) - compress.get(pair[1], 0.0)
		var f := diff * anti_roll
		for i in 2:
			var w := _find_wheel(pair[i])
			if w.is_empty() or not w.contact:
				continue
			var sign := 1.0 if i == 0 else -1.0
			apply_force(global_basis.y * f * sign, global_transform * (w.mount as Vector3) - global_position)
	# arrasto do ar
	apply_central_force(-linear_velocity * linear_velocity.length() * 0.45)
	_update_visuals(delta, steer_angle)
	_update_audio(delta)


func _find_wheel(n: String) -> Dictionary:
	for w in _wheels:
		if w.name == n:
			return w
	return {}


func _update_controls(delta: float, v_fwd: float) -> void:
	# volante: gira com velocidade limitada e volta ao centro sozinho (mais rápido em velocidade)
	var target := steer_input
	var rate := steer_speed if absf(target) > absf(_steer) or signf(target) != signf(_steer) else steer_return
	rate *= lerpf(1.0, 1.6, clampf(speed_kmh / 80.0, 0.0, 1.0)) if is_zero_approx(target) else 1.0
	_steer = move_toward(_steer, target, rate * delta)
	if driver == null:
		return
	# ré: com o carro parado, continuar segurando o freio por um instante engata a ré
	if gear >= 1 and brake > 0.3 and throttle < 0.05 and absf(v_fwd) < 0.4:
		_reverse_hold += delta
	else:
		_reverse_hold = 0.0
	if gear >= 1 and _reverse_hold > 0.45:
		gear = -1
	elif gear == -1 and throttle > 0.3 and v_fwd > -0.5:
		gear = 1


func _engine_force(v_fwd: float, delta: float) -> float:
	_shift_timer = maxf(_shift_timer - delta, 0.0)
	var wheel_rpm := absf(v_fwd) / wheel_radius * 60.0 / TAU
	var ratio := reverse_ratio if gear == -1 else gear_ratios[clampi(gear, 1, gear_ratios.size()) - 1]
	var engine_rpm := wheel_rpm * ratio * final_drive
	var accel := brake if gear == -1 else throttle
	if driver == null:
		accel = 0.0
	# câmbio automático
	if gear >= 1 and _shift_timer <= 0.0:
		if engine_rpm > max_rpm * 0.9 and gear < gear_ratios.size():
			gear += 1
			_shift_timer = 0.5
		elif engine_rpm < 2000.0 and gear > 1:
			gear -= 1
			_shift_timer = 0.5
	var target_rpm := maxf(engine_rpm, idle_rpm + accel * 1800.0 * (1.0 if speed_kmh < 8.0 else 0.0))
	rpm = lerpf(rpm, clampf(target_rpm, idle_rpm, max_rpm), 1.0 - exp(-8.0 * delta))
	if _shift_timer > 0.3 or accel <= 0.01:
		return 0.0
	# curva de torque: cresce até ~4000 rpm e cai perto do limite
	var t := clampf(rpm / max_rpm, 0.0, 1.0)
	var torque := peak_torque * (0.55 + 0.45 * sin(t * PI * 0.95)) * (0.0 if rpm >= max_rpm * 0.99 else 1.0)
	var force := torque * ratio * final_drive * 0.88 / wheel_radius * accel
	if gear == -1:
		force = -force * (0.0 if speed_kmh > 22.0 else 1.0)
	return force


func _update_visuals(delta: float, steer_angle: float) -> void:
	for w in _wheels:
		var node: Node3D = w.node
		var m: Vector3 = w.mount
		node.position = Vector3(m.x, m.y - (w.length as float), m.z)
		var b := Basis(Vector3.RIGHT, -(w.spin as float))
		if w.front:
			b = Basis(Vector3.UP, -steer_angle) * b
		node.basis = b * (w.base as Basis)
	if _steering_wheel:
		_steering_wheel.basis = _sw_base * Basis(Vector3.UP, -_steer * steering_wheel_turns)


func steer_amount() -> float:
	return _steer


func _update_door(delta: float) -> void:
	if _door == null or _door_anim < 0.0:
		return
	_door_anim += delta
	var f := _door_anim * 30.0
	if _door_reverse:
		f = ENTER_FRAMES - f
	var a := door_angle(f)
	_door.basis = _door_base * Basis(Vector3.UP, -deg_to_rad(a))
	if _door_anim * 30.0 >= ENTER_FRAMES:
		_door_anim = -1.0
		_door.basis = _door_base
	# sons da porta: abrir (início) e bater (fim)
	var frame_now := int(_door_anim * 30.0)
	if frame_now == int(DOOR_OPEN_F.x) or frame_now == int(DOOR_CLOSE_F.y):
		Sfx.play_3d(&"car_door", _door.global_position + Vector3.UP * 0.6)


static func door_angle(frame: float) -> float:
	var s := func(t: float) -> float:
		t = clampf(t, 0.0, 1.0)
		return t * t * (3.0 - 2.0 * t)
	if frame <= DOOR_OPEN_F.y:
		return DOOR_OPEN_DEG * s.call((frame - DOOR_OPEN_F.x) / (DOOR_OPEN_F.y - DOOR_OPEN_F.x))
	return DOOR_OPEN_DEG * (1.0 - s.call((frame - DOOR_CLOSE_F.x) / (DOOR_CLOSE_F.y - DOOR_CLOSE_F.x)))


func _update_audio(delta: float) -> void:
	if _engine and _engine.stream:
		var running := driver != null
		if running and not _engine.playing:
			_engine.play()
		elif not running and _engine.playing:
			_engine.stop()
		_engine.pitch_scale = clampf(0.55 + rpm / max_rpm * 1.25, 0.5, 2.0)
		_engine.volume_db = lerpf(_engine.volume_db, -10.0 + throttle * 7.0, 1.0 - exp(-6.0 * delta))
	if _skid and _skid.stream:
		var slipping := 0.0
		for w in _wheels:
			if w.contact and w.slip > 0.5 and linear_velocity.length() > 4.0:
				slipping += 0.25
		var target_db := -60.0 if slipping <= 0.0 else lerpf(-14.0, -2.0, slipping)
		_skid.volume_db = lerpf(_skid.volume_db, target_db, 1.0 - exp(-10.0 * delta))
		if slipping > 0.0 and not _skid.playing:
			_skid.play()
		elif _skid.volume_db < -50.0 and _skid.playing:
			_skid.stop()
	_last_hit = maxf(_last_hit - delta, 0.0)


## Batidas: barulho e dano em zumbis atropelados.
func _on_body_entered(body: Node) -> void:
	var speed := linear_velocity.length()
	if body is Zombie and speed > 4.0:
		(body as Zombie).apply_damage(speed * 9.0, driver if driver else self, (body as Node3D).global_position + Vector3.UP)
	if speed > 3.0 and _last_hit <= 0.0:
		_last_hit = 0.4
		Sfx.play_3d(&"car_crash", global_position, clampf(-14.0 + speed, -12.0, 4.0))
		Events.noise_emitted.emit(global_position, 25.0, self)
