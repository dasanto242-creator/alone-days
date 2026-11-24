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


func _build() -> void:
	var mark := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.05, 0.05)
	mark.mesh = quad
	mark.rotation_degrees.y = 180.0  # o quad olha para +Z; o nó aponta -Z para a normal
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.05, 0.045, 0.04, 0.9)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mark.material_override = mat
	add_child(mark)

	var spark := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.04
	sphere.height = 0.08
	sphere.radial_segments = 6
	sphere.rings = 3
	spark.mesh = sphere
	var smat := StandardMaterial3D.new()
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.albedo_color = Color(1.0, 0.8, 0.4)
	spark.material_override = smat
	add_child(spark)

	var tween := create_tween()
	tween.tween_property(spark, "scale", Vector3.ONE * 0.1, 0.08)
	tween.tween_callback(spark.queue_free)
	tween.tween_interval(LIFETIME)
	tween.tween_property(mat, "albedo_color:a", 0.0, 1.0)
	tween.tween_callback(queue_free)
