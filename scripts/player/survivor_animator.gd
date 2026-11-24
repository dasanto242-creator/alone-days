class_name SurvivorAnimator
extends Node3D
## Anima o modelo 3D do sobrevivente (assets/models/survivor/survivor.glb).
## Escolhe a animação pela velocidade real e ajusta a velocidade de reprodução
## para os pés acompanharem o chão (sem deslizar). Troca com transição suave.

## Velocidade no chão (m/s) em que cada ciclo foi animado: passada / tempo de apoio.
const NOMINAL_SPEED := {
	&"walk": 1.5, &"run": 4.25, &"sprint": 7.8, &"crouch_walk": 1.0,
}
const LOOPING: Array[StringName] = [&"idle", &"walk", &"run", &"sprint", &"crouch_idle", &"crouch_walk"]

@export var blend_time := 0.22
@export var model_path: NodePath = ^"Model"

var _player: AnimationPlayer
var _current: StringName = &""
var _dead := false
var _airborne_time := 0.0
var _jacket: Node3D
var _backpack: Node3D


func _ready() -> void:
	var model := get_node(model_path)
	_player = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	_jacket = model.find_child("Jacket", true, false) as Node3D
	_backpack = model.find_child("Backpack", true, false) as Node3D
	for anim_name in LOOPING:
		if _player.has_animation(anim_name):
			_player.get_animation(anim_name).loop_mode = Animation.LOOP_LINEAR
	_play(&"idle", 0.0)


func update_pose(ground_speed: float, _max_speed: float, grounded: bool, crouching: bool, delta: float) -> void:
	if _dead:
		return
	_airborne_time = 0.0 if grounded else _airborne_time + delta
	var target: StringName
	var scale := 1.0
	if _airborne_time > 0.12:
		target = &"jump"
	elif crouching:
		target = &"crouch_walk" if ground_speed > 0.25 else &"crouch_idle"
	elif ground_speed < 0.25:
		target = &"idle"
	elif ground_speed < 2.6:
		target = &"walk"
	elif ground_speed < 4.8:
		target = &"run"
	else:
		target = &"sprint"
	if NOMINAL_SPEED.has(target):
		scale = clampf(ground_speed / NOMINAL_SPEED[target], 0.5, 1.6)
	_play(target, blend_time)
	_player.speed_scale = scale


## Mostra no corpo o que está equipado (mochila nas costas, jaqueta).
func show_equipment(inventory: Inventory) -> void:
	if not is_node_ready():
		await ready
	if _backpack:
		_backpack.visible = inventory.equipped(ItemData.Slot.BACK) != null
	if _jacket:
		_jacket.visible = inventory.equipped(ItemData.Slot.BODY) != null


func play_death() -> void:
	_dead = true
	_player.speed_scale = 1.0
	_play(&"death", 0.15)


func current_animation() -> StringName:
	return _current


func _play(anim_name: StringName, blend: float) -> void:
	if anim_name == _current or not _player.has_animation(anim_name):
		return
	_current = anim_name
	_player.play(anim_name, blend)
