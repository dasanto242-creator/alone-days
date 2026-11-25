class_name ImpactEffect
extends Node3D
## Marca de tiro: faísca rápida + marca escura na superfície, que some depois de um tempo.

const LIFETIME := 8.0


static func spawn(parent: Node, at: Vector3, normal: Vector3) -> ImpactEffect:
	var fx := ImpactEffect.new()
	parent.add_child(fx)
	fx.global_position = at + normal * 0.003
	if absf(normal.dot(Vector3.UP)) < 0.99:
		fx.look_at(at + normal, Vector3.UP)
	else:
		fx.look_at(at + normal, Vector3.FORWARD)
	fx._build()
	return fx


static var _mark_mesh: QuadMesh
static var _mark_mat: StandardMaterial3D
static var _spark_mesh: SphereMesh
static var _spark_mat: StandardMaterial3D


## Recursos criados uma vez só e compartilhados por todas as marcas (sem travadas ao atirar).
static func _ensure_resources() -> void:
	if _mark_mesh:
		return
	_mark_mesh = QuadMesh.new()
	_mark_mesh.size = Vector2(0.05, 0.05)
	_mark_mat = StandardMaterial3D.new()
	_mark_mat.albedo_color = Color(0.05, 0.045, 0.04, 0.9)
	_mark_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_spark_mesh = SphereMesh.new()
	_spark_mesh.radius = 0.04
	_spark_mesh.height = 0.08
	_spark_mesh.radial_segments = 6
	_spark_mesh.rings = 3
	_spark_mat = StandardMaterial3D.new()
	_spark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_spark_mat.albedo_color = Color(1.0, 0.8, 0.4)


func _build() -> void:
	_ensure_resources()
	var mark := MeshInstance3D.new()
	mark.mesh = _mark_mesh
	mark.material_override = _mark_mat
	mark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mark.rotation_degrees.y = 180.0  # o quad olha para +Z; o nó aponta -Z para a normal
	add_child(mark)
	var spark := MeshInstance3D.new()
	spark.mesh = _spark_mesh
	spark.material_override = _spark_mat
	spark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(spark)
	var tween := create_tween()
	tween.tween_property(spark, "scale", Vector3.ONE * 0.1, 0.08)
	tween.tween_callback(spark.queue_free)
	tween.tween_interval(LIFETIME)
	tween.tween_property(mark, "scale", Vector3.ONE * 0.01, 0.6)
	tween.tween_callback(queue_free)
