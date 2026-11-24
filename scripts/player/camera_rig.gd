class_name CameraRig
extends Node3D
## Câmera em terceira pessoa: atrás e um pouco acima do ombro.
## Estrutura: CameraRig > Yaw > Pitch > SpringArm3D > Camera3D.
## O SpringArm3D lança uma esfera da cabeça até a câmera e a aproxima quando
## encontra parede ou objeto, então a câmera nunca atravessa o cenário.

@export var follow_sharpness := 18.0
@export var transition_sharpness := 5.0

@export_group("Distância")
@export var outdoor_distance := 3.6
@export var indoor_distance := 2.1
@export var outdoor_shoulder := 0.45
@export var indoor_shoulder := 0.25

@export_group("Ângulos (graus)")
@export var min_pitch := -65.0
@export var max_pitch := 35.0
@export var start_pitch := -14.0

var _target: PlayerController
var _yaw_deg := 0.0
var _pitch_deg := -14.0
var _indoor_count := 0

@onready var _yaw: Node3D = $Yaw
@onready var _pitch: Node3D = $Yaw/Pitch
@onready var _arm: SpringArm3D = $Yaw/Pitch/SpringArm3D
@onready var _camera: Camera3D = $Yaw/Pitch/SpringArm3D/Camera3D


func _ready() -> void:
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_pitch_deg = start_pitch
	_arm.spring_length = outdoor_distance
	_arm.position.x = outdoor_shoulder
	_camera.make_current()


func set_target(target: PlayerController) -> void:
	if not is_node_ready():
		await ready
	_target = target
	_arm.add_excluded_object(target.get_rid())
	_yaw_deg = rad_to_deg(target.global_rotation.y)
	global_position = target.global_position + Vector3.UP * target.camera_height


## Rotação horizontal da câmera, em radianos. O personagem anda relativo a ela.
func get_yaw() -> float:
	return deg_to_rad(_yaw_deg)


func get_pitch_degrees() -> float:
	return _pitch_deg


## Coice da arma: levanta a mira um pouco.
func add_recoil(degrees: float) -> void:
	_pitch_deg = clampf(_pitch_deg + degrees, min_pitch, max_pitch)
	_yaw_deg += randf_range(-0.4, 0.4) * degrees


func enter_indoor() -> void:
	_indoor_count += 1


func exit_indoor() -> void:
	_indoor_count = maxi(_indoor_count - 1, 0)


func is_indoor() -> bool:
	return _indoor_count > 0


func _process(delta: float) -> void:
	var look := TouchInput.consume_look() * GameSettings.look_sensitivity
	_yaw_deg = wrapf(_yaw_deg - look.x, -180.0, 180.0)
	_pitch_deg = clampf(_pitch_deg - look.y, min_pitch, max_pitch)
	_yaw.rotation.y = deg_to_rad(_yaw_deg)
	_pitch.rotation.x = deg_to_rad(_pitch_deg)

	if _target:
		var goal := _target.get_global_transform_interpolated().origin + Vector3.UP * _target.camera_height
		global_position = global_position.lerp(goal, 1.0 - exp(-follow_sharpness * delta))

	var t := 1.0 - exp(-transition_sharpness * delta)
	var indoor := is_indoor()
	_arm.spring_length = lerpf(_arm.spring_length, indoor_distance if indoor else outdoor_distance, t)
	_arm.position.x = lerpf(_arm.position.x, indoor_shoulder if indoor else outdoor_shoulder, t)
