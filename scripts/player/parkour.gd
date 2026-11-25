class_name Parkour
extends Node
## Escalar e pular obstáculos (filho "Parkour" do Player).
##
## Ao tocar em Pular de frente para um obstáculo:
##   - muro baixo e fino (0,4–1,3 m de altura, até 0,8 m de espessura, chão livre do outro lado)
##     -> SALTO (vault): apoia a mão e passa as pernas de lado;
##   - borda mais alta ou bloco largo (0,9–2,1 m) com espaço em cima -> ESCALADA (climb).
## Durante o movimento o corpo segue a mesma trajetória usada para criar as animações
## (tools/character/survivor_anims.py: VAULT_PATH / CLIMB_PATH), ajustada à altura,
## distância e espessura reais do obstáculo, então mãos e pés caem no lugar certo.

const FPS := 30.0
const VAULT_PATH := [[0, 0.0, 0.0], [6, 0.22, 0.0], [10, 0.42, 0.2], [14, 0.68, 0.32], [19, 1.0, 0.15],
	[24, 1.3, 0.0], [28, 1.4, 0.0]]
const VAULT_H := 1.0
const VAULT_FACE := 0.5
const VAULT_THICK := 0.3
const CLIMB_PATH := [[0, 0.0, 0.0], [5, 0.08, 0.0], [9, 0.2, 0.25], [16, 0.25, 0.75], [22, 0.35, 1.15],
	[30, 0.6, 1.45], [37, 0.85, 1.5], [44, 0.9, 1.5]]
const CLIMB_H := 1.5
const CLIMB_FACE := 0.45

const WORLD_MASK := 1
const MAX_REACH := 1.1        ## distância máxima até a face do obstáculo
const VAULT_MIN := 0.4
const VAULT_MAX := 1.3
const VAULT_MAX_THICK := 0.8
const CLIMB_MIN := 0.9
const CLIMB_MAX := 2.1

enum Kind { NONE, VAULT, CLIMB }

var kind: Kind = Kind.NONE
var _player: PlayerController
var _start := Vector3.ZERO
var _fwd := Vector3.FORWARD
var _height := 1.0
var _face := 0.5
var _thick := 0.3
var _time := 0.0
var _length := 0.0
var _sounded := {}


func _ready() -> void:
	_player = get_parent() as PlayerController


func is_active() -> bool:
	return kind != Kind.NONE


## Analisa o que está à frente e, se der, começa o salto ou a escalada.
func try_start() -> bool:
	if is_active() or not _player.is_on_floor():
		return false
	var scan := analyze(_player.global_position, _player.facing())
	if scan.is_empty():
		return false
	_begin(scan)
	return true


## Retorna {kind, height, face, thick, fwd} ou {} se não houver obstáculo que dê para passar.
func analyze(origin: Vector3, facing: Vector3) -> Dictionary:
	var space := _player.get_world_3d().direct_space_state
	var fwd := Vector3(facing.x, 0.0, facing.z).normalized()
	if fwd.length_squared() < 0.5:
		return {}
	# 1) há uma face à frente, na altura dos joelhos?
	var from := origin + Vector3.UP * 0.35
	var hit := _ray(space, from, from + fwd * MAX_REACH)
	if hit.is_empty():
		return {}
	var n: Vector3 = hit.normal
	if absf(n.y) > 0.4 or -n.dot(fwd) < 0.6:
		return {}  # superfície inclinada (rampa) ou de lado demais
	var face := Vector3(hit.position - origin).dot(fwd)
	# 2) onde fica o topo?
	var probe := origin + fwd * (face + 0.05)
	var down := _ray(space, probe + Vector3.UP * (CLIMB_MAX + 0.6), probe + Vector3.UP * 0.05)
	if down.is_empty():
		return {}
	var height: float = down.position.y - origin.y
	if height < VAULT_MIN or height > CLIMB_MAX:
		return {}
	# não pode ter nada logo acima da borda (teto, outra parede)
	if not _ray(space, origin + Vector3.UP * (height + 0.1) + fwd * (face - 0.15),
			origin + Vector3.UP * (height + 0.1) + fwd * (face + 0.4)).is_empty():
		return {}
	# 3) espessura: até onde o topo continua?
	var thick := 0.0
	var d := 0.1
	var far_ground := INF
	while d <= 1.4:
		var p := origin + fwd * (face + d)
		var h := _ray(space, p + Vector3.UP * (height + 0.3), p + Vector3.DOWN * 0.5)
		var top_y: float = h.position.y - origin.y if not h.is_empty() else -1.0
		if top_y < height - 0.3:
			thick = maxf(d - 0.05, 0.08)
			far_ground = top_y
			break
		d += 0.1
	if height <= VAULT_MAX and thick > 0.0 and thick <= VAULT_MAX_THICK and far_ground > -0.6 and far_ground < 0.15:
		var land := origin + fwd * (face + thick + (1.4 - VAULT_FACE - VAULT_THICK))
		if _capsule_free(space, land + Vector3.UP * (far_ground + 0.05)):
			return {"kind": Kind.VAULT, "height": height, "face": face, "thick": thick, "fwd": fwd,
				"land": far_ground}
	if height >= CLIMB_MIN:
		var stand := origin + fwd * (face + 0.45) + Vector3.UP * (height + 0.03)
		if _capsule_free(space, stand):
			return {"kind": Kind.CLIMB, "height": height, "face": face, "thick": thick, "fwd": fwd}
	return {}


func _begin(scan: Dictionary) -> void:
	kind = scan.kind
	_start = _player.global_position
	_fwd = scan.fwd
	_height = scan.height
	_face = scan.face
	_thick = scan.thick
	_time = 0.0
	_sounded.clear()
	var path: Array = VAULT_PATH if kind == Kind.VAULT else CLIMB_PATH
	_length = float(path[-1][0]) / FPS
	_player.begin_parkour(&"vault" if kind == Kind.VAULT else &"climb", _fwd, _length)
	Sfx.play_3d(&"player_effort", _player.global_position + Vector3.UP * 1.5)
	if kind == Kind.CLIMB:
		Sfx.play_3d(&"climb_scrape", _player.global_position + _fwd * _face + Vector3.UP * _height, -4.0)


## Chamado pelo Player a cada quadro de física enquanto ativo. Devolve a nova posição.
func step(delta: float) -> Vector3:
	_time += delta
	var frame := minf(_time * FPS, _last_frame())
	var fu := _path_at(frame)
	var pos := _start + _fwd * _map_forward(fu.x) + Vector3.UP * _map_up(fu.y)
	if kind == Kind.VAULT and frame >= 22.0 and not _sounded.has("land"):
		_sounded["land"] = true
		Sfx.play_3d(&"land", pos)
	if _time >= _length:
		kind = Kind.NONE
	return pos


func _last_frame() -> float:
	var path: Array = VAULT_PATH if kind == Kind.VAULT else CLIMB_PATH
	return float(path[-1][0])


func _path_at(frame: float) -> Vector2:
	var path: Array = VAULT_PATH if kind == Kind.VAULT else CLIMB_PATH
	for i in path.size() - 1:
		var a: Array = path[i]
		var b: Array = path[i + 1]
		if frame <= float(b[0]):
			var t := (frame - float(a[0])) / (float(b[0]) - float(a[0]))
			return Vector2(lerpf(a[1], b[1], t), lerpf(a[2], b[2], t))
	var last: Array = path[-1]
	return Vector2(last[1], last[2])


## Trajetória padrão -> obstáculo real (distância até a face e espessura).
func _map_forward(f: float) -> float:
	if kind == Kind.VAULT:
		if f <= VAULT_FACE:
			return f * _face / VAULT_FACE
		if f <= VAULT_FACE + VAULT_THICK:
			return _face + (f - VAULT_FACE) * _thick / VAULT_THICK
		return _face + _thick + (f - VAULT_FACE - VAULT_THICK)
	if f <= CLIMB_FACE:
		return f * _face / CLIMB_FACE
	return _face + (f - CLIMB_FACE)


func _map_up(u: float) -> float:
	if kind == Kind.VAULT:
		return u * _height / VAULT_H
	return u * (_height + 0.03) / CLIMB_H


func _ray(space: PhysicsDirectSpaceState3D, a: Vector3, b: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(a, b, WORLD_MASK)
	q.exclude = [_player.get_rid()]
	return space.intersect_ray(q)


func _capsule_free(space: PhysicsDirectSpaceState3D, feet: Vector3) -> bool:
	var shape := CapsuleShape3D.new()
	shape.radius = 0.27
	shape.height = 1.7
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(Basis(), feet + Vector3.UP * 0.9)
	q.collision_mask = WORLD_MASK
	q.exclude = [_player.get_rid()]
	return space.intersect_shape(q, 1).is_empty()
