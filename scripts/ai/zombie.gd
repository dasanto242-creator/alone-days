class_name Zombie
extends CharacterBody3D
## Zumbi: lento, cambaleante. Vê (cone de visão + linha de visada) e ouve (barulhos do
## barramento Events). Máquina de estados:
##   IDLE/PATROL -> SUSPICIOUS (viu algo de relance / ouviu passos) -> INVESTIGATE (vai até o ponto)
##   -> ALERT (tem certeza: vira e geme) -> CHASE -> ATTACK -> ... -> SEARCH (perdeu o alvo) -> PATROL
## Contrato de dano: apply_damage(amount, source, point). Tiro na cabeça causa dano triplo.
##
## Desempenho: a "cabeça" (percepção e decisões) roda em intervalos que crescem com a distância
## do jogador; longe demais o zumbi fica parado e invisível (visibility range).

enum State { IDLE, PATROL, SUSPICIOUS, INVESTIGATE, ALERT, CHASE, ATTACK, SEARCH, STAGGER, DEAD }
const STATE_NAMES := ["Idle", "Patrol", "Suspicious", "Investigate", "Alert", "Chase", "Attack", "Search",
	"Stagger", "Dead"]

## Velocidade no chão do ciclo z_walk (m/s) na velocidade normal da animação.
const WALK_NOMINAL := 0.385
const HEAD_HEIGHT := 1.45

@export var max_health := 100.0
@export var walk_speed := 0.38
@export var chase_speed := 0.85
@export var turn_speed := 2.2
@export_group("Sentidos")
@export var sight_range := 18.0
@export_range(10.0, 180.0) var sight_half_angle := 65.0
@export var hearing_multiplier := 1.0
@export_group("Ataque")
@export var attack_range := 1.2
@export var attack_damage := 14.0
@export var attack_cooldown := 1.4
@export_group("Patrulha")
@export var patrol_radius := 6.0

var health := 100.0
var state: State = State.IDLE
## 0..1: quanto o zumbi "tem certeza" de que viu o jogador.
var awareness := 0.0

var _player: PlayerController
var _anim: AnimationPlayer
var _visual: Node3D
var _home := Vector3.ZERO
var _target := Vector3.ZERO
var _state_time := 0.0
var _think_timer := 0.0
var _think_interval := 0.2
var _sees_player := false
var _lost_time := 0.0
var _attack_timer := 0.0
var _attack_hit_done := false
var _current_anim := &""
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _dormant := false


func _ready() -> void:
	add_to_group("zombies")
	health = max_health
	_home = global_position
	_target = global_position
	_visual = $Visual
	_anim = find_child("AnimationPlayer", true, false) as AnimationPlayer
	for loop_name in [&"z_idle", &"z_walk"]:
		if _anim.has_animation(loop_name):
			_anim.get_animation(loop_name).loop_mode = Animation.LOOP_LINEAR
	for g in find_children("*", "GeometryInstance3D", true, false):
		var gi := g as GeometryInstance3D
		gi.visibility_range_end = 90.0
		gi.visibility_range_end_margin = 5.0
		if gi.name == "Eyes":
			gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	Events.noise_emitted.connect(_on_noise)
	_think_timer = randf() * 0.3  # zumbis não pensam todos no mesmo quadro
	_set_state(State.PATROL if randf() < 0.6 else State.IDLE)


func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		return
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as PlayerController
		if _player == null:
			return
	var dist := global_position.distance_to(_player.global_position)
	# longe do jogador: congela tudo (não anda, não anima, não pensa)
	_dormant = dist > 85.0
	_anim.active = not _dormant
	if _dormant:
		return
	_think_interval = 0.15 if dist < 20.0 else (0.4 if dist < 45.0 else 1.0)
	_state_time += delta
	_attack_timer = maxf(_attack_timer - delta, 0.0)
	_think_timer -= delta
	if _think_timer <= 0.0:
		var dt := _think_interval - _think_timer
		_think_timer = _think_interval
		_think(dt, dist)
	_act(delta, dist)


# ---------------------------------------------------------------- decisões

func _think(dt: float, dist: float) -> void:
	_sees_player = _can_see_player(dist)
	if _player.stats.is_dead:
		_sees_player = false
	if _sees_player:
		# mais perto = percebe mais rápido; agachado demora mais
		var gain := lerpf(2.5, 0.35, clampf(dist / sight_range, 0.0, 1.0))
		if _player.is_crouching:
			gain *= 0.45
		awareness = minf(awareness + gain * dt, 1.0)
		_lost_time = 0.0
	else:
		awareness = maxf(awareness - 0.12 * dt, 0.0)
		_lost_time += dt

	match state:
		State.IDLE, State.PATROL:
			if _sees_player and awareness >= 1.0:
				_alert()
			elif _sees_player and awareness > 0.25:
				_target = _player.global_position
				_set_state(State.SUSPICIOUS)
			elif state == State.IDLE and _state_time > randf_range(4.0, 8.0):
				_pick_patrol_point()
				_set_state(State.PATROL)
			elif state == State.PATROL and _flat_distance(_target) < 0.6:
				_set_state(State.IDLE)
		State.SUSPICIOUS:
			if _sees_player:
				_target = _player.global_position
				if awareness >= 1.0:
					_alert()
			elif _state_time > 2.5:
				_set_state(State.INVESTIGATE)
		State.INVESTIGATE:
			if _sees_player and awareness >= 0.6:
				_alert()
			elif _sees_player:
				_target = _player.global_position
			elif _flat_distance(_target) < 0.8 or _state_time > 25.0:
				_set_state(State.SEARCH)
		State.ALERT:
			if _state_time > 0.7:
				_set_state(State.CHASE)
		State.CHASE:
			if _player.stats.is_dead:
				_set_state(State.SEARCH)
			elif _sees_player or dist < 2.5:
				_target = _player.global_position
				if dist <= attack_range and _attack_timer <= 0.0:
					_set_state(State.ATTACK)
			elif _lost_time > 5.0:
				_set_state(State.SEARCH)
		State.SEARCH:
			if _sees_player and awareness >= 0.5:
				_alert()
			elif _state_time > 10.0:
				awareness = 0.0
				_home = global_position
				_set_state(State.PATROL)
				_pick_patrol_point()
			elif _flat_distance(_target) < 0.7:
				var a := randf() * TAU
				_target = global_position + Vector3(cos(a), 0, sin(a)) * randf_range(2.0, 4.0)


func _alert() -> void:
	awareness = 1.0
	_target = _player.global_position
	_set_state(State.ALERT)


func _can_see_player(dist: float) -> bool:
	if dist < 1.6:
		return true  # muito perto: percebe mesmo de costas
	var range_ := sight_range * (0.6 if _player.is_crouching else 1.0)
	if dist > range_:
		return false
	var to := _player.global_position - global_position
	to.y = 0.0
	if _facing().angle_to(to.normalized()) > deg_to_rad(sight_half_angle):
		return false
	var eye := global_position + Vector3.UP * 1.55
	var aim := _player.global_position + Vector3.UP * (0.8 if _player.is_crouching else 1.3)
	var ray := PhysicsRayQueryParameters3D.create(eye, aim, 1)
	return get_world_3d().direct_space_state.intersect_ray(ray).is_empty()


func _on_noise(at: Vector3, radius: float, _source: Node) -> void:
	if state == State.DEAD or _dormant:
		return
	var d := global_position.distance_to(at)
	if d > radius * hearing_multiplier:
		return
	match state:
		State.CHASE, State.ATTACK, State.ALERT, State.STAGGER:
			return
	_target = at
	if radius >= 20.0 or d < radius * 0.35:
		# barulho forte (tiro) ou muito perto: vai direto investigar, mais desconfiado
		awareness = maxf(awareness, 0.5)
		_set_state(State.INVESTIGATE)
	elif state != State.INVESTIGATE:
		_set_state(State.SUSPICIOUS)


# ---------------------------------------------------------------- ação (todo quadro)

func _act(delta: float, dist: float) -> void:
	var speed := 0.0
	var face_to := Vector3.INF
	match state:
		State.PATROL, State.INVESTIGATE, State.SEARCH:
			speed = walk_speed
			face_to = _target
		State.SUSPICIOUS, State.ALERT:
			face_to = _target
		State.CHASE:
			speed = chase_speed
			face_to = _target
		State.ATTACK:
			face_to = _player.global_position
			_update_attack(dist)
		State.STAGGER:
			if _state_time > 0.55:
				_target = _player.global_position
				_set_state(State.CHASE)
	if face_to != Vector3.INF:
		var desired := face_to - global_position
		desired.y = 0.0
		if desired.length_squared() > 0.04:
			if speed > 0.0:
				desired = _avoid_obstacles(desired.normalized())
			_turn_towards(desired, delta)
		else:
			speed = 0.0
	# anda para onde o corpo está virado (não desliza de lado); devagar enquanto ainda vira
	var forward := _facing()
	var along := 1.0
	if face_to != Vector3.INF:
		var desired2 := face_to - global_position
		desired2.y = 0.0
		if desired2.length_squared() > 0.0001:
			along = clampf(forward.dot(desired2.normalized()), 0.0, 1.0)
	var hv := forward * speed * along
	velocity.x = lerpf(velocity.x, hv.x, 1.0 - exp(-6.0 * delta))
	velocity.z = lerpf(velocity.z, hv.z, 1.0 - exp(-6.0 * delta))
	velocity.y = 0.0 if is_on_floor() else velocity.y - _gravity * delta
	move_and_slide()
	var ground := Vector2(velocity.x, velocity.z).length()
	if state in [State.ATTACK, State.STAGGER]:
		return
	if ground > 0.08:
		_play(&"z_walk", clampf(ground / WALK_NOMINAL, 0.6, 2.4))
	else:
		_play(&"z_idle", 1.0)


func _update_attack(dist: float) -> void:
	var length := _anim.get_animation(&"z_attack").length
	if not _attack_hit_done and _state_time >= length * 0.45:
		_attack_hit_done = true
		var to := _player.global_position - global_position
		to.y = 0.0
		var in_front := to.length() < 0.05 or _facing().angle_to(to.normalized()) < deg_to_rad(55.0)
		if dist <= attack_range + 0.45 and in_front and not _player.stats.is_dead:
			_player.take_hit(attack_damage, self)
	if _state_time >= length:
		_attack_timer = attack_cooldown
		_set_state(State.CHASE)


## Desvia de paredes/objetos: testa a direção desejada e ângulos cada vez maiores.
func _avoid_obstacles(desired: Vector3) -> Vector3:
	var space := get_world_3d().direct_space_state
	var from := global_position + Vector3.UP * 0.5
	for angle in [0.0, 35.0, -35.0, 70.0, -70.0, 110.0, -110.0]:
		var dir := desired.rotated(Vector3.UP, deg_to_rad(angle))
		var ray := PhysicsRayQueryParameters3D.create(from, from + dir * 1.1, 1)
		ray.exclude = [get_rid()]
		if space.intersect_ray(ray).is_empty():
			return dir
	return desired


func _turn_towards(dir: Vector3, delta: float) -> void:
	var target_yaw := atan2(-dir.x, -dir.z)
	var rate := turn_speed * (1.6 if state == State.CHASE else 1.0)
	_visual.rotation.y = rotate_toward(_visual.rotation.y, target_yaw, rate * delta)


# ---------------------------------------------------------------- dano

func apply_damage(amount: float, source: Node, point: Vector3) -> void:
	if state == State.DEAD:
		return
	var headshot := point.y - global_position.y > HEAD_HEIGHT
	var dmg := amount * (3.0 if headshot else 1.0)
	health -= dmg
	Events.hit_landed.emit(self, dmg, point)
	_blood_burst(point)
	if health <= 0.0:
		_die()
		return
	# foi atacado: sabe onde o jogador está
	awareness = 1.0
	if source is Node3D:
		_target = (source as Node3D).global_position
	if dmg >= 15.0 or state != State.ATTACK:
		_set_state(State.STAGGER)
		_play(&"z_hit", 1.0, true)


func is_dead() -> bool:
	return state == State.DEAD


func _die() -> void:
	health = 0.0
	_set_state(State.DEAD)
	collision_layer = 0
	collision_mask = 1
	velocity = Vector3.ZERO
	_play(&"z_death", 1.0, true)
	_anim.active = true


func _blood_burst(point: Vector3) -> void:
	var fx := CPUParticles3D.new()
	fx.one_shot = true
	fx.amount = 14
	fx.lifetime = 0.5
	fx.explosiveness = 0.95
	fx.direction = Vector3.UP
	fx.spread = 70.0
	fx.initial_velocity_min = 0.8
	fx.initial_velocity_max = 2.2
	fx.gravity = Vector3(0, -9.0, 0)
	fx.scale_amount_min = 0.5
	fx.scale_amount_max = 1.0
	var quad := QuadMesh.new()
	quad.size = Vector2(0.04, 0.04)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.albedo_color = Color(0.35, 0.02, 0.02)
	quad.material = mat
	fx.mesh = quad
	get_parent().add_child(fx)
	fx.global_position = point
	fx.emitting = true
	get_tree().create_timer(1.0).timeout.connect(fx.queue_free)


# ---------------------------------------------------------------- utilidades

func _set_state(s: State) -> void:
	state = s
	_state_time = 0.0
	if s == State.ATTACK:
		_attack_hit_done = false
		velocity.x = 0.0
		velocity.z = 0.0
		_play(&"z_attack", 1.0, true)


func _pick_patrol_point() -> void:
	var a := randf() * TAU
	_target = _home + Vector3(cos(a), 0, sin(a)) * randf_range(2.0, patrol_radius)


func _play(anim_name: StringName, speed: float, restart := false) -> void:
	_anim.speed_scale = speed
	if anim_name == _current_anim and not restart:
		return
	_current_anim = anim_name
	if restart:
		_anim.stop()
	_anim.play(anim_name, 0.25)


func _facing() -> Vector3:
	return -_visual.global_basis.z


func _flat_distance(p: Vector3) -> float:
	return Vector2(p.x - global_position.x, p.z - global_position.z).length()


func state_name() -> String:
	return STATE_NAMES[state]
