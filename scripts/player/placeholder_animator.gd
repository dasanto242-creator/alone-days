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


func update_pose(ground_speed: float, max_speed: float, grounded: bool, crouching: bool, delta: float) -> void:
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
