class_name ZombieSpawner
extends Node3D
## Mantém poucos zumbis vivos na área (limite fixo = custo previsível no celular).
## Pontos de nascimento = filhos Marker3D. Corpos somem depois de um tempo, sempre longe do
## jogador, e um novo zumbi nasce num ponto afastado.

const ZOMBIE_SCENE := "res://scenes/characters/zombie.tscn"

@export var max_alive := 3
@export var respawn_delay := 90.0
@export var corpse_time := 45.0
## Nunca nasce nem some a menos desta distância do jogador.
@export var min_player_distance := 25.0

var _scene: PackedScene
var _dead_since := {}   # Zombie -> segundos morto
var _respawn_timer := 0.0
var _check_timer := 0.0


func _ready() -> void:
	_scene = load(ZOMBIE_SCENE)
	var points := _points()
	for i in mini(max_alive, points.size()):
		_spawn_at(points[i].global_position)


func _process(delta: float) -> void:
	_check_timer -= delta
	if _check_timer > 0.0:
		return
	_check_timer = 2.0
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var alive := 0
	for z in get_tree().get_nodes_in_group("zombies"):
		var zombie := z as Zombie
		if not zombie.is_dead():
			alive += 1
			continue
		_dead_since[zombie] = _dead_since.get(zombie, 0.0) + 2.0
		if _dead_since[zombie] > corpse_time and _far_from(player, zombie.global_position):
			_dead_since.erase(zombie)
			zombie.queue_free()
	if alive < max_alive:
		_respawn_timer += 2.0
		if _respawn_timer >= respawn_delay:
			var candidates := _points().filter(func(p: Node3D) -> bool: return _far_from(player, p.global_position))
			if not candidates.is_empty():
				_spawn_at((candidates.pick_random() as Node3D).global_position)
				_respawn_timer = 0.0
	else:
		_respawn_timer = 0.0


func _spawn_at(at: Vector3) -> Zombie:
	var z := _scene.instantiate() as Zombie
	get_parent().add_child.call_deferred(z)
	z.position = at + Vector3(randf_range(-1.5, 1.5), 0.05, randf_range(-1.5, 1.5))
	z.rotation.y = 0.0
	return z


func _points() -> Array:
	return get_children().filter(func(n: Node) -> bool: return n is Marker3D)


func _far_from(player: Node3D, at: Vector3) -> bool:
	return player == null or player.global_position.distance_to(at) >= min_player_distance
