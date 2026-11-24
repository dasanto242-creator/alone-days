class_name PlaceholderAnimator
extends Node3D
## Animação procedural do boneco provisório (até entrar o modelo 3D definitivo).
## A passada avança pela DISTÂNCIA percorrida, não pelo tempo, então os pés
## acompanham a velocidade real e o personagem não parece deslizar.
## O modelo definitivo vai implementar o mesmo método update_pose() com AnimationTree.

@export var stride_length := 1.1
@export var hips_height := 0.95
@export var crouch_hips_height := 0.62

var _phase := 0.0
var _crouch_blend := 0.0

@onready var _hips: Node3D = $Body/Hips
@onready var _leg_l: Node3D = $Body/Hips/LegL
@onready var _leg_r: Node3D = $Body/Hips/LegR
@onready var _arm_l: Node3D = $Body/Hips/Torso/ArmL
@onready var _arm_r: Node3D = $Body/Hips/Torso/ArmR
@onready var _torso: Node3D = $Body/Hips/Torso
@onready var _body: Node3D = $Body
@onready var _backpack: Node3D = $Body/Hips/Torso/Backpack
@onready var _upper_meshes: Array[MeshInstance3D] = [
	$Body/Hips/Torso/Chest, $Body/Hips/Torso/ArmL/Mesh, $Body/Hips/Torso/ArmR/Mesh]

const SHIRT_COLOR := Color(0.42, 0.44, 0.46)

var _upper_material := StandardMaterial3D.new()
var _dead := false


func _ready() -> void:
	_upper_material.roughness = 0.9
	_upper_material.albedo_color = SHIRT_COLOR
	for mesh in _upper_meshes:
		mesh.material_override = _upper_material


## Mostra no corpo o que está equipado (mochila nas costas, jaqueta no tronco).
func show_equipment(inventory: Inventory) -> void:
	if not is_node_ready():
		await ready
	_backpack.visible = inventory.equipped(ItemData.Slot.BACK) != null
	var jacket := inventory.equipped(ItemData.Slot.BODY)
	_upper_material.albedo_color = jacket.data().world_color if jacket and jacket.data() else SHIRT_COLOR


func play_death() -> void:
	_dead = true
	var tween := create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(_body, "rotation:x", -PI * 0.5, 0.7)
	tween.parallel().tween_property(_body, "position:y", 0.15, 0.7)


func update_pose(ground_speed: float, max_speed: float, grounded: bool, crouching: bool, delta: float) -> void:
	if _dead:
		return
	_crouch_blend = lerpf(_crouch_blend, 1.0 if crouching else 0.0, 1.0 - exp(-10.0 * delta))
	var speed_ratio := clampf(ground_speed / max_speed, 0.0, 1.0)

	if grounded:
		_phase = fmod(_phase + ground_speed * delta / stride_length * TAU, TAU)

	var swing := sin(_phase) * lerpf(0.15, 0.85, speed_ratio) * minf(ground_speed * 2.0, 1.0)
	var bob := absf(cos(_phase)) * 0.05 * minf(ground_speed, 1.0)

	if not grounded:
		swing = 0.35
		bob = 0.0

	var crouch_bend := 0.9 * _crouch_blend
	_leg_l.rotation.x = swing + crouch_bend
	_leg_r.rotation.x = -swing + crouch_bend
	_arm_l.rotation.x = -swing * 0.8
	_arm_r.rotation.x = swing * 0.8
	_torso.rotation.x = -0.12 * speed_ratio - 0.25 * _crouch_blend
	_hips.position.y = lerpf(hips_height, crouch_hips_height, _crouch_blend) + bob
