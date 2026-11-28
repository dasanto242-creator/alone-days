class_name Dragon
extends CharacterBody3D
## Dragão de montaria (serpe: as asas são os braços).
##
## Sem cavaleiro fica deitado, respirando. Montado: anda em quatro apoios, decola,
## voa batendo as asas ou planando, inclina nas curvas, mergulha, perde sustentação
## se ficar lento demais e pousa (pairando, freando com as asas e amortecendo nas patas).
##
## Voo (modelo simples, mas físico):
## - velocidade no ar ganha com mergulho e perde subindo (gravidade ao longo da trajetória),
##   arrasto quadrático, empuxo das batidas de asa;
## - abaixo da velocidade de estol o corpo afunda e o nariz cai;
## - curva coordenada: taxa de giro = g·tan(inclinação)/velocidade.
## O visual (Pivot) inclina e arfa; a colisão fica nivelada.

enum State { LYING, STAND_UP, STANDING, LIE_DOWN, ROAR, TAKEOFF, FLYING, LANDING, TOUCHDOWN }

const SEAT_BONE := "neck1"
const SEAT_POINT := Vector3(0.0, 3.04, -2.3)      # sela no modelo (pose de repouso)
const MOUNT_SPOT := Vector3(-1.75, 0.0, -2.2)     # onde o jogador sobe (lado esquerdo)
const CENTER := Vector3(0.0, 2.1, -0.5)           # centro de massa (giro do corpo no voo)
const G := 9.8
const LOOPS: Array[StringName] = [&"lie", &"idle", &"walk", &"flap", &"hover", &"glide", &"glide_l",
	&"glide_r", &"dive"]
const STATES: Array[StringName] = [&"lie", &"stand_up", &"lie_down", &"idle", &"walk", &"roar", &"takeoff",
	&"flap", &"hover", &"glide", &"dive", &"land"]

@export var walk_speed := 3.4
@export var turn_speed_deg := 60.0
@export var stall_speed := 9.0
@export var max_speed := 42.0
@export var flap_accel := 7.5
@export var max_altitude := 240.0

var rider: Node3D = null
var state := State.LYING
var airspeed := 0.0
var pitch_deg := 0.0
var roll_deg := 0.0
## Comandos do cavaleiro: steer.x = virar (-1 esq, 1 dir); steer.y = cima/frente (+1) ou baixo/ré (-1).
var steer := Vector2.ZERO
var flap_held := false

var _state_time := 0.0
var _auto_flap := 0.0
var _flapping := false
var _flap_clock := 0.0
var _step_clock := 0.0
var _anim_state := &""
var _ground_speed := 0.0
var _model: Node3D
var _anim: AnimationPlayer
var _tree: AnimationTree
var _skeleton: Skeleton3D
var _seat_bone := -1
var _wind: AudioStreamPlayer3D

@onready var _pivot: Node3D = $Pivot


func _ready() -> void:
	add_to_group("dragons")
	collision_layer = 32       # mesma camada dos veículos (o jogador e os zumbis colidem)
	collision_mask = 1 | 16 | 32
	floor_max_angle = deg_to_rad(50.0)
	floor_snap_length = 0.6
	_model = _pivot.get_node("Model") as Node3D
	_anim = _model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	_skeleton = _model.find_child("Skeleton3D", true, false) as Skeleton3D
	_seat_bone = _skeleton.find_bone(SEAT_BONE)
	for a in LOOPS:
		if _anim.has_animation(a):
			_anim.get_animation(a).loop_mode = Animation.LOOP_LINEAR
	_build_tree()
	_wind = AudioStreamPlayer3D.new()
	var st: AudioStream = Sfx.stream(&"dragon_wind")
	if st is AudioStreamWAV:
		st = (st as AudioStreamWAV).duplicate()
		(st as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
		(st as AudioStreamWAV).loop_end = int(st.get_length() * (st as AudioStreamWAV).mix_rate)
	_wind.stream = st
	_wind.volume_db = -40.0
	_wind.unit_size = 12.0
	_wind.position = CENTER
	add_child(_wind)
	_set_anim(&"lie")


func _build_tree() -> void:
	_tree = AnimationTree.new()
	_tree.name = "AnimationTree"
	_model.add_child(_tree)
	_tree.anim_player = _tree.get_path_to(_anim)
	var bt := AnimationNodeBlendTree.new()
	var tr := AnimationNodeTransition.new()
	tr.xfade_time = 0.4
	for s in STATES:
		tr.add_input(String(s))
	bt.add_node("state", tr)
	var i := 0
	for s in STATES:
		var node: AnimationNode
		if s == &"glide":
			var bs := AnimationNodeBlendSpace1D.new()
			bs.min_space = -1.0
			bs.max_space = 1.0
			for pair in [[&"glide_l", -1.0], [&"glide", 0.0], [&"glide_r", 1.0]]:
				var a := AnimationNodeAnimation.new()
				a.animation = pair[0]
				bs.add_blend_point(a, pair[1], -1, String(pair[0]))
			node = bs
		else:
			var a := AnimationNodeAnimation.new()
			a.animation = s
			node = a
		bt.add_node(String(s), node)
		bt.connect_node("state", i, String(s))
		i += 1
	var ts := AnimationNodeTimeScale.new()
	bt.add_node("speed", ts)
	bt.connect_node("speed", 0, "state")
	bt.connect_node("output", 0, "speed")
	_tree.tree_root = bt
	_tree.active = true
	_tree.set("parameters/speed/scale", 1.0)


func _set_anim(name: StringName, speed := 1.0) -> void:
	_tree.set("parameters/speed/scale", speed)
	if name == _anim_state:
		return
	_anim_state = name
	_tree.set("parameters/state/transition_request", String(name))


func current_anim() -> StringName:
	return _anim_state


# ================================================================ cavaleiro

func is_occupied() -> bool:
	return rider != null


func set_rider(r: Node3D) -> void:
	rider = r
	steer = Vector2.ZERO
	flap_held = false


## Onde o jogador fica de pé para montar (no chão, ao lado do ombro esquerdo).
func mount_position() -> Vector3:
	return global_transform * MOUNT_SPOT


## Transformação do assento: acompanha o pescoço, a arfagem e a inclinação do corpo.
func seat_transform() -> Transform3D:
	var pose := _skeleton.get_bone_global_pose(_seat_bone)
	var rest := _skeleton.get_bone_global_rest(_seat_bone)
	var t := _skeleton.global_transform * pose * rest.affine_inverse() * Transform3D(Basis(), SEAT_POINT)
	return Transform3D(t.basis.orthonormalized(), t.origin)


func is_flying() -> bool:
	return state in [State.TAKEOFF, State.FLYING, State.LANDING]


func is_grounded_idle() -> bool:
	return state == State.STANDING


func is_lying() -> bool:
	return state == State.LYING


func stand_up() -> void:
	if state == State.LYING:
		_enter(State.STAND_UP)


func lie_down() -> void:
	if state == State.STANDING:
		_enter(State.LIE_DOWN)


func take_off() -> bool:
	if state != State.STANDING:
		return false
	_enter(State.TAKEOFF)
	return true


func request_land() -> void:
	if state == State.FLYING:
		_enter(State.LANDING)


func roar() -> void:
	if state == State.STANDING:
		_enter(State.ROAR)
	Sfx.play_3d(&"dragon_roar", global_transform * Vector3(0, 3.4, -5.0), 4.0, 0.03)


func altitude() -> float:
	return global_position.y - _ground_height()


func speed_kmh() -> float:
	return (airspeed if is_flying() else _ground_speed) * 3.6


# ================================================================ estados

func _enter(s: State) -> void:
	state = s
	_state_time = 0.0
	match s:
		State.LYING:
			_set_anim(&"lie")
		State.STAND_UP:
			_set_anim(&"stand_up")
		State.LIE_DOWN:
			_set_anim(&"lie_down")
		State.STANDING:
			_set_anim(&"idle")
		State.ROAR:
			_set_anim(&"roar")
		State.TAKEOFF:
			_set_anim(&"takeoff")
			Sfx.play_3d(&"dragon_flap", global_position + Vector3.UP * 2.0, 2.0)
		State.FLYING:
			_flap_clock = 0.0
		State.LANDING:
			_set_anim(&"hover")
		State.TOUCHDOWN:
			_set_anim(&"land")


func _physics_process(delta: float) -> void:
	_state_time += delta
	match state:
		State.LYING, State.LIE_DOWN, State.STAND_UP, State.ROAR:
			_ground_hold(delta)
			if state == State.STAND_UP and _state_time >= 1.2:
				_enter(State.STANDING)
			elif state == State.LIE_DOWN and _state_time >= 1.2:
				_enter(State.LYING)
			elif state == State.ROAR and _state_time >= 2.0:
				_enter(State.STANDING)
		State.STANDING:
			_ground_move(delta)
		State.TAKEOFF:
			_takeoff(delta)
		State.FLYING:
			_fly(delta)
		State.LANDING:
			_land_approach(delta)
		State.TOUCHDOWN:
			_touchdown(delta)
	_update_visual(delta)
	_update_audio(delta)


func _gravity(delta: float) -> void:
	if is_on_floor():
		velocity.y = minf(velocity.y, 0.0)
	else:
		velocity.y -= G * 2.0 * delta


func _ground_hold(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, 8.0 * delta)
	velocity.z = move_toward(velocity.z, 0.0, 8.0 * delta)
	_gravity(delta)
	move_and_slide()
	_ground_speed = 0.0
	pitch_deg = lerpf(pitch_deg, 0.0, 1.0 - exp(-4.0 * delta))
	roll_deg = lerpf(roll_deg, 0.0, 1.0 - exp(-4.0 * delta))


func _ground_move(delta: float) -> void:
	var fwd := maxf(steer.y, 0.0) if rider else 0.0
	var turn := steer.x if rider else 0.0
	_ground_speed = move_toward(_ground_speed, walk_speed * fwd, 3.0 * delta)
	rotation.y -= deg_to_rad(turn_speed_deg) * turn * delta * (0.6 + 0.4 * fwd)
	var dir := -global_transform.basis.z
	velocity.x = dir.x * _ground_speed
	velocity.z = dir.z * _ground_speed
	_gravity(delta)
	move_and_slide()
	var moving := _ground_speed > 0.2 or absf(turn) > 0.15
	if moving:
		_set_anim(&"walk", clampf(maxf(_ground_speed / 1.8, absf(turn) * 0.8), 0.5, 1.9))
		_step_clock += delta * clampf(maxf(_ground_speed / 1.8, absf(turn) * 0.8), 0.5, 1.9)
		if _step_clock >= 0.667:
			_step_clock -= 0.667
			Sfx.play_3d(&"dragon_step", global_position, -2.0)
	else:
		_set_anim(&"idle")
	pitch_deg = lerpf(pitch_deg, 0.0, 1.0 - exp(-4.0 * delta))
	roll_deg = lerpf(roll_deg, 0.0, 1.0 - exp(-4.0 * delta))


func _takeoff(delta: float) -> void:
	var fwd := -global_transform.basis.z
	if _state_time < 0.38:
		velocity = Vector3(0, minf(velocity.y, 0.0), 0)
	else:
		if _state_time - delta < 0.38:
			velocity.y = 7.5
			Sfx.play_3d(&"dragon_flap", global_position + Vector3.UP * 2.0, 4.0)
		var k := clampf((_state_time - 0.38) / 0.8, 0.0, 1.0)
		var horiz := lerpf(1.0, 10.0, k)
		velocity.x = fwd.x * horiz
		velocity.z = fwd.z * horiz
		velocity.y = move_toward(velocity.y, 3.5, 6.0 * delta)
	move_and_slide()
	pitch_deg = lerpf(pitch_deg, 12.0 if _state_time > 0.4 else 0.0, 1.0 - exp(-3.0 * delta))
	if _state_time >= 1.2:
		airspeed = 11.0
		_auto_flap = 2.0
		_enter(State.FLYING)


func _fly(delta: float) -> void:
	var stall := clampf((stall_speed - airspeed) / stall_speed, 0.0, 1.0)
	_auto_flap = maxf(_auto_flap - delta, 0.0)
	_flapping = flap_held or _auto_flap > 0.0 or airspeed < stall_speed + 1.5
	# arfagem e inclinação seguem o comando (com inércia); lento demais, o nariz cai
	var target_pitch := steer.y * 38.0
	if stall > 0.0 and not _flapping:
		target_pitch = minf(target_pitch, -18.0 * stall)
	if global_position.y > max_altitude:
		target_pitch = minf(target_pitch, -5.0)
	pitch_deg = lerpf(pitch_deg, target_pitch, 1.0 - exp(-1.8 * delta))
	roll_deg = lerpf(roll_deg, steer.x * 50.0, 1.0 - exp(-2.4 * delta))
	var pr := deg_to_rad(pitch_deg)
	# energia: gravidade ao longo da trajetória, arrasto e batidas de asa
	airspeed -= G * sin(pr) * delta
	airspeed -= 0.0022 * airspeed * airspeed * delta
	if _flapping:
		airspeed += flap_accel * clampf(1.0 - airspeed / 30.0, 0.0, 1.0) * delta
	airspeed = clampf(airspeed, 0.0, max_speed)
	# curva coordenada
	var v := maxf(airspeed, 7.0)
	rotation.y -= (G * tan(deg_to_rad(roll_deg)) / v + steer.x * 0.12) * delta
	var yaw_b := Basis(Vector3.UP, rotation.y)
	var dir := yaw_b * Vector3(0, sin(pr), -cos(pr))
	var sink := -1.3          # planando, desce devagar
	if _flapping:
		sink = 2.2 * (1.0 - stall)
	sink -= 9.0 * stall * (0.5 if _flapping else 1.0)
	velocity = dir * airspeed + Vector3.UP * sink
	if global_position.y > max_altitude:
		velocity.y = minf(velocity.y, 0.0)
	move_and_slide()
	if get_slide_collision_count() > 0 and not is_on_floor():
		airspeed *= 0.92
	if is_on_floor():
		_enter(State.TOUCHDOWN)
		return
	# animação: bater asas, mergulho ou planar inclinando para o lado da curva
	if _flapping:
		var rate := 1.0 + (0.25 if flap_held else 0.0) + stall * 0.3
		_set_anim(&"flap", rate)
		_flap_clock += delta * rate
		if _flap_clock >= 0.8:
			_flap_clock -= 0.8
		if _flap_clock < delta * rate:
			Sfx.play_3d(&"dragon_flap", global_position + Vector3.UP * 2.5, 0.0)
	elif pitch_deg < -20.0 and airspeed > 14.0:
		_set_anim(&"dive")
	else:
		_set_anim(&"glide")
		_tree.set("parameters/glide/blend_position", clampf(roll_deg / 45.0, -1.0, 1.0))


func _land_approach(delta: float) -> void:
	# pairando: freia, desce e alinha o corpo; quando o chão está perto, começa a pousar
	airspeed = move_toward(airspeed, 0.0, 7.0 * delta)
	pitch_deg = lerpf(pitch_deg, 0.0, 1.0 - exp(-2.0 * delta))
	roll_deg = lerpf(roll_deg, 0.0, 1.0 - exp(-3.0 * delta))
	var dir := -global_transform.basis.z
	var alt := altitude()
	var vy := -clampf(alt * 0.9, 2.5, 9.0)
	velocity = dir * airspeed + Vector3.UP * vy
	rotation.y -= steer.x * 0.6 * delta
	move_and_slide()
	_flap_clock += delta
	if _flap_clock >= 0.7:
		_flap_clock -= 0.7
		Sfx.play_3d(&"dragon_flap", global_position + Vector3.UP * 2.0, 1.0)
	if alt < 1.6 or is_on_floor():
		_enter(State.TOUCHDOWN)


func _touchdown(delta: float) -> void:
	airspeed = move_toward(airspeed, 0.0, 14.0 * delta)
	_ground_speed = 0.0
	var dir := -global_transform.basis.z
	velocity.x = dir.x * airspeed
	velocity.z = dir.z * airspeed
	if not is_on_floor():
		velocity.y = -clampf(altitude() / maxf(0.5 - _state_time, 0.12), 2.0, 12.0)
	else:
		velocity.y = 0.0
	move_and_slide()
	pitch_deg = lerpf(pitch_deg, 0.0, 1.0 - exp(-5.0 * delta))
	roll_deg = lerpf(roll_deg, 0.0, 1.0 - exp(-5.0 * delta))
	if _state_time > 0.45 and _state_time - delta <= 0.45:
		Sfx.play_3d(&"dragon_step", global_position, 4.0)
		Sfx.play_3d(&"land", global_position, 0.0)
	if _state_time >= 1.5:
		_enter(State.STANDING)


func _ground_height() -> float:
	var space := get_world_3d().direct_space_state
	var from := global_position + Vector3.UP * 1.0
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 400.0, 1)
	q.exclude = [get_rid()]
	var hit := space.intersect_ray(q)
	return (hit.position as Vector3).y if hit else -1000.0


# ================================================================ visual e som

func _update_visual(delta: float) -> void:
	# o corpo arfa e inclina em volta do centro de massa
	var b := Basis(Vector3.RIGHT, deg_to_rad(pitch_deg)) * Basis(Vector3.FORWARD, deg_to_rad(roll_deg))
	_pivot.transform = Transform3D(b, CENTER)
	_model.position = -CENTER


func _update_audio(delta: float) -> void:
	if _wind == null or _wind.stream == null:
		return
	var k := clampf((airspeed - 5.0) / 30.0, 0.0, 1.0) if is_flying() else 0.0
	if k > 0.01 and not _wind.playing:
		_wind.play()
	elif k <= 0.01 and _wind.playing:
		_wind.stop()
	_wind.volume_db = lerpf(_wind.volume_db, lerpf(-30.0, 2.0, k), 1.0 - exp(-3.0 * delta))
	_wind.pitch_scale = 0.75 + k * 0.6
