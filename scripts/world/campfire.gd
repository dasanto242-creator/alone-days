class_name Campfire
extends StaticBody3D
## Fogueira acesa. Tudo é montado por código (camadas que, juntas, dão a sensação de calor):
##   - línguas de fogo animadas (folha de quadros, mistura aditiva, cor do branco-amarelo ao vermelho);
##   - brilho no miolo e brasas pulsando no carvão;
##   - faíscas subindo com turbulência; fumaça que sobe, abre e some;
##   - luz alaranjada que tremula (intensidade e posição) e ilumina tudo em volta;
##   - ar tremendo em cima do fogo (distorção de calor; desligada no gráfico Baixo);
##   - som de crepitar em loop.
## Encostar no fogo queima (jogador e zumbis). Perto dele o fôlego volta mais rápido.
## A lenha acaba: as chamas diminuem até virar brasa e fumaça. "Adicionar lenha" reaviva.

const MODEL := "res://assets/models/weapons/campfire.glb"
const FLAME_TEX := "res://assets/textures/fx/flame_sheet.png"
const SPARK_TEX := "res://assets/textures/fx/spark.png"
const GLOW_TEX := "res://assets/textures/fx/glow.png"
const SMOKE_TEX := "res://assets/textures/fx/smoke.png"
const HEAT_TEX := "res://assets/textures/fx/heat_noise.png"

## Segundos de fogo que cada lenha dá.
@export var seconds_per_log := 150.0
@export var max_fuel := 600.0
@export var burn_damage := 7.0         ## por segundo, encostando no fogo
@export var warmth_radius := 3.2

var fuel := 300.0
var lit := true

var _flames: GPUParticles3D
var _core: GPUParticles3D
var _sparks: GPUParticles3D
var _smoke: GPUParticles3D
var _light: OmniLight3D
var _heat: MeshInstance3D
var _coal_mat: StandardMaterial3D
var _audio: AudioStreamPlayer3D
var _burn_area: Area3D
var _t := 0.0
var _tick := 0.0
var _intensity := 1.0
var _warm_notice := 0.0
var _since_out := 0.0

static var _cache := {}


func _ready() -> void:
	add_to_group("campfires")
	collision_layer = 1 | 4   # mundo + interativo (aparece no botão de interação)
	collision_mask = 0
	var shape := CylinderShape3D.new()
	shape.radius = 0.55
	shape.height = 0.16
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position.y = 0.08
	add_child(col)
	var model := (load(MODEL) as PackedScene).instantiate() as Node3D
	add_child(model)
	_setup_coals(model)
	_flames = _make_flames()
	_core = _make_core()
	_sparks = _make_sparks()
	_smoke = _make_smoke()
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.56, 0.24)
	_light.omni_range = 9.0
	_light.omni_attenuation = 1.3
	_light.position = Vector3(0, 0.6, 0)
	_light.shadow_enabled = GameSettings.quality >= GameSettings.Quality.HIGH
	add_child(_light)
	if GameSettings.quality >= GameSettings.Quality.MEDIUM:
		_heat = _make_heat_haze()
	_audio = AudioStreamPlayer3D.new()
	var stream: AudioStream = Sfx.stream(&"fire_loop")
	if stream is AudioStreamWAV:
		stream = (stream as AudioStreamWAV).duplicate()
		(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
		(stream as AudioStreamWAV).loop_end = int(stream.get_length() * (stream as AudioStreamWAV).mix_rate)
	_audio.stream = stream
	_audio.unit_size = 3.0
	_audio.max_distance = 22.0
	_audio.position.y = 0.4
	add_child(_audio)
	_audio.play()
	_burn_area = Area3D.new()
	_burn_area.collision_layer = 0
	_burn_area.collision_mask = 2 | 16   # jogador e zumbis
	var burn_shape := CylinderShape3D.new()
	burn_shape.radius = 0.42
	burn_shape.height = 0.9
	var bcol := CollisionShape3D.new()
	bcol.shape = burn_shape
	bcol.position.y = 0.45
	_burn_area.add_child(bcol)
	add_child(_burn_area)
	Sfx.play_3d(&"fire_ignite", global_position + Vector3.UP * 0.4)


# ---------------------------------------------------------------- interação

func get_interaction_prompt() -> String:
	return "Adicionar lenha" if lit else "Reacender"


func get_interaction_name() -> String:
	if not lit:
		return "Fogueira apagada"
	return "Fogueira · %d min" % ceili(fuel / 60.0)


func get_alt_prompt() -> String:
	return "Apagar" if lit else ""


func interact(actor: Node) -> void:
	var inv: Inventory = actor.get("inventory")
	if inv == null or inv.count_of(&"firewood") <= 0:
		Events.notify.emit("Precisa de lenha")
		return
	inv.consume(&"firewood", 1)
	add_fuel(seconds_per_log)
	Events.notify.emit("Lenha na fogueira")


func interact_alt(_actor: Node) -> void:
	extinguish()


func add_fuel(seconds: float) -> void:
	fuel = minf(fuel + seconds, max_fuel)
	if not lit:
		lit = true
		_audio.play()
		Sfx.play_3d(&"fire_ignite", global_position + Vector3.UP * 0.4)
	Sfx.play_3d(&"fire_log", global_position + Vector3.UP * 0.3)
	# tora nova levanta uma nuvem de faíscas
	_sparks.restart()


func extinguish() -> void:
	if not lit:
		return
	fuel = 0.0
	lit = false
	Sfx.play_3d(&"fire_log", global_position, -4.0)
	Events.notify.emit("Fogueira apagada")


func is_burning() -> bool:
	return lit and fuel > 0.0


# ---------------------------------------------------------------- simulação

func _process(delta: float) -> void:
	_t += delta
	if lit:
		fuel = maxf(fuel - delta, 0.0)
		if fuel <= 0.0:
			lit = false
	# intensidade: cheia com lenha, vai caindo no último minuto, brasa quando acaba
	var target := clampf(fuel / 60.0, 0.0, 1.0) if lit else 0.0
	# acende devagar; ao apagar (abafar com terra) as chamas morrem rápido e fica só a fumaça
	_intensity = lerpf(_intensity, target, 1.0 - exp(-(1.5 if lit else 4.0) * delta))
	var k := _intensity
	_flames.amount_ratio = clampf(0.15 + 0.85 * k, 0.0, 1.0)
	_flames.emitting = k > 0.04
	_core.emitting = k > 0.04
	_sparks.amount_ratio = clampf(0.3 + 0.7 * k, 0.0, 1.0)
	_sparks.emitting = k > 0.1
	_smoke.amount_ratio = clampf(1.1 - k * 0.6, 0.3, 1.0)
	_since_out = 0.0 if lit else _since_out + delta
	_smoke.emitting = lit or _since_out < 25.0   # depois de apagar, ainda solta fumaça um tempo
	# tremulação da luz: várias ondas + ruído, e o ponto de luz dança um pouco (sombras se mexem)
	var flick := 0.75 + 0.12 * sin(_t * 9.3) + 0.08 * sin(_t * 17.1 + 1.3) + 0.06 * sin(_t * 31.7) \
		+ randf_range(-0.06, 0.06)
	_light.light_energy = (0.35 + 2.4 * k) * flick
	_light.position = Vector3(0.04 * sin(_t * 7.1), 0.55 + 0.05 * sin(_t * 11.0), 0.04 * cos(_t * 5.3))
	_light.visible = k > 0.01 or _coal_glow() > 0.05
	if _coal_mat:
		_coal_mat.emission_energy_multiplier = _coal_glow() * (0.85 + 0.15 * sin(_t * 2.3) + 0.1 * sin(_t * 5.9))
	if _heat:
		_heat.visible = k > 0.15
		(_heat.material_override as ShaderMaterial).set_shader_parameter("strength", 0.016 * k)
	_audio.volume_db = linear_to_db(clampf(0.08 + 0.92 * k, 0.001, 1.0))
	if not lit and _intensity < 0.01 and _audio.playing:
		_audio.stop()
	_tick -= delta
	if _tick <= 0.0:
		_tick = 0.5
		_heat_effects(0.5)


func _coal_glow() -> float:
	return clampf(_intensity * 3.0 + (0.4 if fuel > 0.0 or _t < 1.0 else 0.0), 0.0, 3.0)


## Queima quem encosta no fogo; perto dele o corpo esquenta (fôlego volta mais rápido).
func _heat_effects(dt: float) -> void:
	if _intensity < 0.15:
		return
	for body in _burn_area.get_overlapping_bodies():
		if body is PlayerController:
			var p := body as PlayerController
			if not p.stats.is_dead:
				p.take_hit(burn_damage * dt * _intensity, null)
				Events.notify.emit("Você está se queimando!")
		elif body is Zombie:
			(body as Zombie).apply_damage(burn_damage * 2.0 * dt, self, body.global_position + Vector3.UP)
	_warm_notice = maxf(_warm_notice - dt, 0.0)
	var player := get_tree().get_first_node_in_group("player") as PlayerController
	if player and not player.stats.is_dead:
		var d := player.global_position.distance_to(global_position)
		if d < warmth_radius and d > 0.5:
			player.stats.stamina = minf(player.stats.stamina + 3.0 * dt * _intensity, 100.0)
			if _warm_notice <= 0.0:
				Events.notify.emit("Calor da fogueira")
				_warm_notice = 60.0


# ---------------------------------------------------------------- montagem dos efeitos

func _setup_coals(model: Node3D) -> void:
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		for i in m.mesh.get_surface_count():
			var mat := m.mesh.surface_get_material(i)
			if mat and mat.resource_name == "Brasa":
				_coal_mat = StandardMaterial3D.new()
				_coal_mat.albedo_color = Color(0.1, 0.04, 0.02)
				_coal_mat.roughness = 0.9
				_coal_mat.emission_enabled = true
				_coal_mat.emission = Color(1.0, 0.32, 0.06)
				_coal_mat.emission_energy_multiplier = 2.0
				m.set_surface_override_material(i, _coal_mat)


static func _tex(path: String) -> Texture2D:
	if not _cache.has(path):
		_cache[path] = load(path)
	return _cache[path]


func _ramp(stops: Array) -> GradientTexture1D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array(stops.map(func(s: Array) -> float: return s[0]))
	g.colors = PackedColorArray(stops.map(func(s: Array) -> Color: return s[1]))
	var t := GradientTexture1D.new()
	t.gradient = g
	return t


func _curve(points: Array) -> CurveTexture:
	var c := Curve.new()
	for p in points:
		c.add_point(Vector2(p[0], p[1]))
	var t := CurveTexture.new()
	t.curve = c
	return t


func _billboard_mat(tex: Texture2D, additive: bool, h_frames := 1, v_frames := 1) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = tex
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = false
	m.disable_receive_shadows = true
	if h_frames > 1 or v_frames > 1:
		m.particles_anim_h_frames = h_frames
		m.particles_anim_v_frames = v_frames
		m.particles_anim_loop = true
	return m


func _particles(amount: int, lifetime: float, mesh: Mesh, pm: ParticleProcessMaterial) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.draw_pass_1 = mesh
	p.process_material = pm
	p.visibility_aabb = AABB(Vector3(-2, -0.5, -2), Vector3(4, 6, 4))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.local_coords = false
	add_child(p)
	return p


func _make_flames() -> GPUParticles3D:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.16
	pm.direction = Vector3.UP
	pm.spread = 10.0
	pm.initial_velocity_min = 0.35
	pm.initial_velocity_max = 0.7
	pm.gravity = Vector3(0, 1.3, 0)          # ar quente sobe e acelera
	pm.damping_min = 0.4
	pm.damping_max = 0.8
	pm.scale_min = 0.55
	pm.scale_max = 1.0
	pm.scale_curve = _curve([[0.0, 0.55], [0.25, 1.0], [0.7, 0.75], [1.0, 0.15]])
	pm.angle_min = -8.0
	pm.angle_max = 8.0
	pm.anim_speed_min = 1.0
	pm.anim_speed_max = 1.6
	pm.anim_offset_max = 1.0
	pm.color_ramp = _ramp([
		[0.0, Color(1.6, 1.35, 0.8, 0.0)], [0.08, Color(1.8, 1.25, 0.55, 0.95)], [0.35, Color(1.6, 0.6, 0.14, 0.85)],
		[0.7, Color(1.0, 0.22, 0.04, 0.45)], [1.0, Color(0.4, 0.06, 0.02, 0.0)]])
	var quad := QuadMesh.new()
	quad.size = Vector2(0.48, 0.95)
	quad.center_offset = Vector3(0, 0.3, 0)
	quad.material = _billboard_mat(_tex(FLAME_TEX), true, 4, 4)
	var p := _particles(32, 0.8, quad, pm)
	p.position = Vector3(0, 0.08, 0)
	p.fixed_fps = 30
	return p


func _make_core() -> GPUParticles3D:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.05
	pm.gravity = Vector3(0, 0.25, 0)
	pm.scale_min = 0.8
	pm.scale_max = 1.2
	pm.color_ramp = _ramp([[0.0, Color(1.4, 0.7, 0.2, 0.0)], [0.3, Color(1.4, 0.65, 0.18, 0.55)],
		[1.0, Color(1.2, 0.4, 0.1, 0.0)]])
	var quad := QuadMesh.new()
	quad.size = Vector2(1.1, 1.0)
	quad.material = _billboard_mat(_tex(GLOW_TEX), true)
	var p := _particles(5, 0.6, quad, pm)
	p.position = Vector3(0, 0.3, 0)
	return p


func _make_sparks() -> GPUParticles3D:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.15
	pm.direction = Vector3.UP
	pm.spread = 22.0
	pm.initial_velocity_min = 1.2
	pm.initial_velocity_max = 2.8
	pm.gravity = Vector3(0, 0.4, 0)
	pm.damping_min = 0.6
	pm.damping_max = 1.4
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 1.4
	pm.turbulence_noise_scale = 2.0
	pm.turbulence_influence_min = 0.08
	pm.turbulence_influence_max = 0.2
	pm.scale_min = 0.5
	pm.scale_max = 1.2
	pm.lifetime_randomness = 0.6
	pm.color_ramp = _ramp([[0.0, Color(2.2, 1.6, 0.6, 1.0)], [0.5, Color(2.0, 0.7, 0.15, 0.9)],
		[1.0, Color(0.8, 0.1, 0.02, 0.0)]])
	var quad := QuadMesh.new()
	quad.size = Vector2(0.035, 0.035)
	quad.material = _billboard_mat(_tex(SPARK_TEX), true)
	var p := _particles(18, 2.2, quad, pm)
	p.position = Vector3(0, 0.25, 0)
	return p


func _make_smoke() -> GPUParticles3D:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.18
	pm.direction = Vector3.UP
	pm.spread = 12.0
	pm.initial_velocity_min = 0.45
	pm.initial_velocity_max = 0.8
	pm.gravity = Vector3(0.12, 0.12, 0.05)   # um ventinho leva a fumaça de lado
	pm.damping_min = 0.1
	pm.damping_max = 0.3
	pm.angle_min = -180.0
	pm.angle_max = 180.0
	pm.angular_velocity_min = -20.0
	pm.angular_velocity_max = 20.0
	pm.scale_min = 0.8
	pm.scale_max = 1.2
	pm.scale_curve = _curve([[0.0, 0.35], [1.0, 1.0]])
	pm.color_ramp = _ramp([[0.0, Color(0.3, 0.29, 0.28, 0.0)], [0.15, Color(0.32, 0.31, 0.3, 0.32)],
		[0.6, Color(0.4, 0.4, 0.4, 0.18)], [1.0, Color(0.5, 0.5, 0.5, 0.0)]])
	var quad := QuadMesh.new()
	quad.size = Vector2(1.6, 1.6)
	var mat := _billboard_mat(_tex(SMOKE_TEX), false)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX  # recebe a luz do fogo
	quad.material = mat
	var p := _particles(14, 4.5, quad, pm)
	p.position = Vector3(0, 0.9, 0)
	return p


func _make_heat_haze() -> MeshInstance3D:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform sampler2D noise_tex : repeat_enable, filter_linear;
uniform float strength = 0.016;
void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}
void fragment() {
	vec2 n = texture(noise_tex, UV * vec2(1.0, 1.4) + vec2(0.0, TIME * 0.7)).rg - 0.5;
	n += (texture(noise_tex, UV * 2.3 + vec2(TIME * 0.1, TIME * 1.3)).rg - 0.5) * 0.5;
	float mask = smoothstep(0.0, 0.35, UV.x) * smoothstep(1.0, 0.65, UV.x) * smoothstep(0.0, 0.45, UV.y)
		* smoothstep(1.0, 0.75, UV.y);
	ALBEDO = texture(screen_tex, SCREEN_UV + n * strength * mask).rgb;
	ALPHA = mask;
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("noise_tex", _tex(HEAT_TEX))
	var quad := QuadMesh.new()
	quad.size = Vector2(1.1, 1.8)
	var mi := MeshInstance3D.new()
	mi.mesh = quad
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(0, 1.25, 0)
	add_child(mi)
	return mi
