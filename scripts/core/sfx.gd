extends Node
## Sons do jogo (autoload "Sfx").
## Todos os efeitos são próprios, sintetizados por tools/audio/make_sounds.py.
##   Sfx.play_3d(&"gunshot", posição)      -> som no mundo (some com a distância)
##   Sfx.play_2d(&"ui_click")              -> som de interface
## Nomes com variações (step_grass_0..3, zombie_groan_0..2) são sorteados automaticamente.
## Um conjunto fixo de tocadores é reaproveitado: nada é criado durante o jogo.

const DIR := "res://assets/audio/sfx/"
const NAMES := ["step_grass_0", "step_grass_1", "step_grass_2", "step_grass_3",
	"step_hard_0", "step_hard_1", "step_hard_2", "step_hard_3",
	"gunshot", "gun_empty", "reload", "swing", "hit_flesh", "wood_knock", "axe_chop", "tree_crack",
	"tree_fall", "zombie_groan_0", "zombie_groan_1", "zombie_groan_2", "zombie_attack", "zombie_hurt",
	"zombie_death", "player_hurt", "player_effort", "land", "climb_scrape", "eat", "drink", "pickup",
	"bag", "door", "ui_click", "engine_loop", "tire_skid", "car_door", "car_crash"]
## Distância máxima em que cada som ainda é ouvido (m). Padrão: 30.
const RANGE := {&"gunshot": 140.0, &"tree_fall": 70.0, &"tree_crack": 50.0, &"zombie_groan": 28.0,
	&"step_grass": 14.0, &"step_hard": 16.0, &"axe_chop": 40.0, &"car_crash": 60.0}
const POOL_SIZE := 16

var _streams := {}       # nome -> AudioStream
var _variants := {}      # base -> [nomes]
var _pool: Array[AudioStreamPlayer3D] = []
var _next := 0
var _ui: AudioStreamPlayer
var _ambient: AudioStreamPlayer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for n in NAMES:
		var path: String = DIR + n + ".wav"
		if not ResourceLoader.exists(path):
			continue
		_streams[StringName(n)] = load(path)
		var parts := (n as String).rsplit("_", true, 1)
		if parts.size() == 2 and parts[1].is_valid_int():
			var base := StringName(parts[0])
			if not _variants.has(base):
				_variants[base] = []
			_variants[base].append(StringName(n))
	for i in POOL_SIZE:
		var p := AudioStreamPlayer3D.new()
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p.unit_size = 4.0
		p.max_polyphony = 1
		add_child(p)
		_pool.append(p)
	_ui = AudioStreamPlayer.new()
	add_child(_ui)
	_start_ambient()


func play_3d(sound: StringName, at: Vector3, volume_db := 0.0, pitch_jitter := 0.07) -> void:
	var stream := _pick(sound)
	if stream == null or not is_inside_tree():
		return
	var p := _free_player()
	p.stream = stream
	p.global_position = at
	p.volume_db = volume_db
	p.max_distance = RANGE.get(_base(sound), 30.0)
	p.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	p.play()


func play_2d(sound: StringName, volume_db := 0.0) -> void:
	var stream := _pick(sound)
	if stream == null:
		return
	_ui.stream = stream
	_ui.volume_db = volume_db
	_ui.play()


func stream(sound: StringName) -> AudioStream:
	return _pick(sound)


func has_sound(sound: StringName) -> bool:
	return _pick(sound) != null


func _pick(sound: StringName) -> AudioStream:
	if _streams.has(sound):
		return _streams[sound]
	if _variants.has(sound):
		return _streams[(_variants[sound] as Array).pick_random()]
	return null


func _base(sound: StringName) -> StringName:
	return sound if not _streams.has(sound) else StringName(String(sound).rstrip("0123456789").trim_suffix("_"))


## Pega um tocador livre; se todos estiverem tocando, reaproveita o mais antigo.
func _free_player() -> AudioStreamPlayer3D:
	for i in POOL_SIZE:
		var p := _pool[(_next + i) % POOL_SIZE]
		if not p.playing:
			_next = (_next + i + 1) % POOL_SIZE
			return p
	var oldest := _pool[_next]
	_next = (_next + 1) % POOL_SIZE
	return oldest


## Vento de fundo em loop (baixo, sem posição).
func _start_ambient() -> void:
	var path := DIR + "ambient_wind.wav"
	if not ResourceLoader.exists(path):
		return
	var wind := load(path) as AudioStreamWAV
	if wind == null:
		return
	wind = wind.duplicate() as AudioStreamWAV
	wind.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wind.loop_begin = 0
	wind.loop_end = int(wind.get_length() * wind.mix_rate)
	_ambient = AudioStreamPlayer.new()
	_ambient.stream = wind
	_ambient.volume_db = -14.0
	add_child(_ambient)
	_ambient.play()
