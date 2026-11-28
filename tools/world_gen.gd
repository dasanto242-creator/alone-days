extends RefCounted
## Gera o mundo em volta da área de teste (usado por tools/build_scenes.gd):
## - terreno de 1 km x 1 km: plano no meio, colinas e montanhas com neve em volta
##   (pedaços de 128 m para o celular só desenhar o que está na tela + colisão por mapa de altura);
## - floresta de pinheiros (perto: modelo 3D; longe: 2 cartões com a imagem do pinheiro);
## - pedras; grama que balança (em pedaços com distância máxima de desenho);
## - materiais com as texturas de assets/textures/world.

const SIZE := 1024.0
const CHUNK := 128.0
const RES := 20                       # quadrados por pedaço (6,4 m)
const FLAT := 88.0                    # meia-largura da área plana
const NEAR_CELL := 48.0               # célula dos pinheiros 3D (perto)
const TEX := "res://assets/textures/world/"
const NATURE := "res://assets/models/nature/"
const MAT_DIR := "res://assets/materials/"

var n_hills := FastNoiseLite.new()
var n_mount := FastNoiseLite.new()
var n_forest := FastNoiseLite.new()
var materials := {}
## Áreas sem árvores/grama/pedras: [centro x, centro z, meia-largura x, meia-largura z]
var keep_clear: Array = []


func _init() -> void:
	n_hills.seed = 11
	n_hills.frequency = 0.0065
	n_hills.fractal_octaves = 4
	n_mount.seed = 23
	n_mount.frequency = 0.0032
	n_mount.fractal_octaves = 5
	n_forest.seed = 31
	n_forest.frequency = 0.012
	n_forest.fractal_octaves = 2
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(MAT_DIR))


static func _smooth(a: float, b: float, x: float) -> float:
	var t := clampf((x - a) / (b - a), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


## Altura do terreno (m) no ponto (x, z).
func height(x: float, z: float) -> float:
	var d := maxf(absf(x), absf(z)) - FLAT
	if d <= 0.0:
		return 0.0
	var hills := (n_hills.get_noise_2d(x, z) * 0.5 + 0.5) * 30.0 * _smooth(0.0, 80.0, d)
	var ridge := 1.0 - absf(n_mount.get_noise_2d(x, z))
	var mount := pow(ridge, 2.3) * 190.0 * _smooth(60.0, 380.0, d)
	return (hills + mount) * _smooth(0.0, 30.0, d)


func normal(x: float, z: float) -> Vector3:
	var e := 1.5
	var dx := height(x + e, z) - height(x - e, z)
	var dz := height(x, z + e) - height(x, z - e)
	return Vector3(-dx, 2.0 * e, -dz).normalized()


func _cleared(x: float, z: float, margin := 0.0) -> bool:
	for r in keep_clear:
		if absf(x - r[0]) < r[2] + margin and absf(z - r[1]) < r[3] + margin:
			return true
	return false


# ================================================================ materiais

func _tex(name: String) -> Texture2D:
	return load(TEX + name + ".png") as Texture2D


func _save_mat(name: String, m: Material) -> Material:
	var path := MAT_DIR + name + ".tres"
	ResourceSaver.save(m, path)
	m.take_over_path(path)
	materials[name] = m
	return m


## Material de superfície com textura projetada no mundo (paredes, chão, caixas...).
func surface_mat(name: String, tex: String, tile_m: float, roughness := 0.9, tint := Color.WHITE) -> StandardMaterial3D:
	if materials.has(name):
		return materials[name]
	var m := StandardMaterial3D.new()
	m.albedo_texture = _tex(tex + "_albedo")
	m.albedo_color = tint
	m.normal_enabled = true
	m.normal_texture = _tex(tex + "_normal")
	m.normal_scale = 1.0
	m.roughness = roughness
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_triplanar_sharpness = 4.0
	m.uv1_scale = Vector3.ONE / tile_m
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return _save_mat(name, m) as StandardMaterial3D


func make_materials() -> void:
	var t := ShaderMaterial.new()
	t.shader = load("res://shaders/terrain.gdshader")
	for s in ["grass_albedo", "grass_normal", "dirt_albedo", "dirt_normal", "rock_albedo", "rock_normal", "snow_albedo", "macro_noise"]:
		t.set_shader_parameter(s, _tex(s))
	_save_mat("terrain", t)
	var needles := ShaderMaterial.new()
	needles.shader = load("res://shaders/foliage.gdshader")
	needles.set_shader_parameter("albedo_tex", _tex("pine_needles"))
	needles.set_shader_parameter("mode", 1.0)
	needles.set_shader_parameter("tree_height", 11.0)
	needles.set_shader_parameter("wind_strength", 0.35)
	needles.set_shader_parameter("wind_speed", 0.9)
	needles.set_shader_parameter("alpha_cut", 0.38)
	needles.set_shader_parameter("tint", Color(0.95, 1.0, 0.92))
	_save_mat("pine_needles", needles)
	var far := ShaderMaterial.new()
	far.shader = load("res://shaders/foliage.gdshader")
	far.set_shader_parameter("albedo_tex", load(NATURE + "pine_far.png"))
	far.set_shader_parameter("mode", 1.0)
	far.set_shader_parameter("tree_height", 11.0)
	far.set_shader_parameter("wind_strength", 0.12)
	far.set_shader_parameter("alpha_cut", 0.4)
	far.set_shader_parameter("base_shade", 0.85)
	far.set_shader_parameter("tint", Color(1.15, 1.2, 1.15))
	far.set_shader_parameter("translucency", 0.15)
	_save_mat("pine_far", far)
	var grass := ShaderMaterial.new()
	grass.shader = load("res://shaders/foliage.gdshader")
	grass.set_shader_parameter("albedo_tex", _tex("grass_blades"))
	grass.set_shader_parameter("mode", 0.0)
	grass.set_shader_parameter("wind_strength", 0.13)
	grass.set_shader_parameter("wind_speed", 1.6)
	grass.set_shader_parameter("alpha_cut", 0.35)
	grass.set_shader_parameter("base_shade", 0.62)
	grass.set_shader_parameter("tint", Color(0.92, 0.95, 0.85))
	_save_mat("grass_blades", grass)
	var bark := StandardMaterial3D.new()
	bark.albedo_texture = _tex("bark_albedo")
	bark.normal_enabled = true
	bark.normal_texture = _tex("bark_normal")
	bark.roughness = 0.95
	_save_mat("bark", bark)
	surface_mat("rock", "rock", 2.5, 0.85)
	surface_mat("plaster", "plaster", 3.4, 0.92)
	surface_mat("wood", "wood", 2.0, 0.8)
	surface_mat("wood_dark", "wood", 2.0, 0.8, Color(0.62, 0.55, 0.5))
	surface_mat("roof", "roof", 2.2, 0.75)
	surface_mat("concrete", "concrete", 3.0, 0.9, Color(0.78, 0.77, 0.74))
	surface_mat("asphalt", "asphalt", 5.0, 0.85)


# ================================================================ terreno

func build_terrain() -> Node3D:
	var root := Node3D.new()
	root.name = "Terrain"
	var mat: Material = materials["terrain"]
	var half := SIZE * 0.5
	var n := int(SIZE / CHUNK)
	for cj in n:
		for ci in n:
			var x0 := -half + ci * CHUNK
			var z0 := -half + cj * CHUNK
			var flat := true
			for j in RES + 1:
				for i in RES + 1:
					if height(x0 + i * CHUNK / RES, z0 + j * CHUNK / RES) != 0.0:
						flat = false
						break
				if not flat:
					break
			var res := 1 if flat else RES
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			for j in res + 1:
				for i in res + 1:
					var x := x0 + i * CHUNK / res
					var z := z0 + j * CHUNK / res
					st.set_normal(Vector3.UP if flat else normal(x, z))
					st.set_uv(Vector2(x, z) * 0.1)
					st.add_vertex(Vector3(x, height(x, z), z))
			for j in res:
				for i in res:
					var a := j * (res + 1) + i
					st.add_index(a)
					st.add_index(a + 1)
					st.add_index(a + res + 1)
					st.add_index(a + 1)
					st.add_index(a + res + 2)
					st.add_index(a + res + 1)
			st.generate_tangents()
			var mi := MeshInstance3D.new()
			mi.name = "Chunk_%d_%d" % [ci, cj]
			mi.mesh = st.commit()
			mi.material_override = mat
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(mi)
	# colisão: mapa de altura (161 x 161 pontos a cada 6,4 m), escalado
	var body := StaticBody3D.new()
	body.name = "Ground"
	body.collision_layer = 1
	body.collision_mask = 0
	root.add_child(body)
	var w := int(SIZE / (CHUNK / RES)) + 1
	var step := SIZE / float(w - 1)
	var data := PackedFloat32Array()
	data.resize(w * w)
	for j in w:
		for i in w:
			data[j * w + i] = height(-half + i * step, -half + j * step)
	var hm := HeightMapShape3D.new()
	hm.map_width = w
	hm.map_depth = w
	hm.map_data = data
	var col := CollisionShape3D.new()
	col.name = "HeightMap"
	col.shape = hm
	col.scale = Vector3(step, 1.0, step)
	body.add_child(col)
	return root


# ================================================================ floresta e pedras

func _mesh_from(path: String, surface_mats: Array) -> ArrayMesh:
	var scn := (load(path) as PackedScene).instantiate()
	var mi := scn.find_child("*", true, false) as MeshInstance3D
	if mi == null:
		for c in scn.find_children("*", "MeshInstance3D", true, false):
			mi = c
			break
	var src := mi.mesh as ArrayMesh
	var out := ArrayMesh.new()
	for s in src.get_surface_count():
		out.add_surface_from_arrays(src.surface_get_primitive_type(s), src.surface_get_arrays(s))
		out.surface_set_material(s, surface_mats[mini(s, surface_mats.size() - 1)])
	scn.free()
	return out


func _impostor_mesh(h: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var w := h * 0.5
	for a in [0.0, PI * 0.5]:
		var s := Vector3(cos(a), 0, sin(a)) * w * 0.5
		var n := Vector3(-sin(a), 0, cos(a))
		var v := [Vector3(-s.x, -0.2, -s.z), Vector3(s.x, -0.2, s.z), Vector3(s.x, h - 0.2, s.z), Vector3(-s.x, h - 0.2, -s.z)]
		var uv := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
		for idx in [0, 1, 2, 0, 2, 3]:
			st.set_normal(n)
			st.set_uv(uv[idx])
			st.add_vertex(v[idx])
	return st.commit()


func build_forest() -> Node3D:
	var root := Node3D.new()
	root.name = "Forest"
	root.set_script(load("res://scripts/world/forest_quality.gd"))
	var pines := [_mesh_from(NATURE + "pine_a.glb", [materials["bark"], materials["pine_needles"]]),
		_mesh_from(NATURE + "pine_b.glb", [materials["bark"], materials["pine_needles"]])]
	var heights := [9.5, 12.5]
	ResourceSaver.save(pines[0], NATURE + "pine_a_mesh.res")
	ResourceSaver.save(pines[1], NATURE + "pine_b_mesh.res")
	var far := _impostor_mesh(10.4)
	far.surface_set_material(0, materials["pine_far"])
	var rocks := [_mesh_from(NATURE + "rock_a.glb", [materials["rock"]]), _mesh_from(NATURE + "rock_b.glb", [materials["rock"]])]
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var half := SIZE * 0.5
	var n := int(SIZE / CHUNK)
	var chunks := {}   # Vector2i -> {"near": [[], []], "far": [], "rocks": [[], []]}
	var near_cells := {}   # pinheiros 3D em células menores (só as perto são desenhadas)
	var trunk := CylinderShape3D.new()
	trunk.radius = 0.28
	trunk.height = 4.0
	var grid := 15.0
	var count := 0
	var z := -half + 8.0
	while z < half - 8.0:
		var x := -half + 8.0
		while x < half - 8.0:
			var px := x + rng.randf_range(-6.0, 6.0)
			var pz := z + rng.randf_range(-6.0, 6.0)
			x += grid
			var d := maxf(absf(px), absf(pz)) - FLAT
			if d < -34.0 or _cleared(px, pz, 4.0):
				continue
			var f := n_forest.get_noise_2d(px, pz)
			var h := height(px, pz)
			var nrm := normal(px, pz)
			if f < -0.12 + (0.25 if d < 0 else 0.0) or h > 112.0 + f * 30.0 or nrm.y < 0.8:
				continue
			var key := Vector2i(int(floor((px + half) / CHUNK)), int(floor((pz + half) / CHUNK)))
			if not chunks.has(key):
				chunks[key] = {"near": [[], []], "far": [], "shapes": []}
			var kind := rng.randi() % 2
			var s := rng.randf_range(0.8, 1.25)
			var t := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), Vector3(px, h - 0.15, pz))
			chunks[key]["near"][kind].append(t)
			var cell := Vector2i(int(floor((px + half) / NEAR_CELL)), int(floor((pz + half) / NEAR_CELL)))
			if not near_cells.has(cell):
				near_cells[cell] = [[], []]
			near_cells[cell][kind].append(t)
			var fs: float = s * float(heights[kind]) / 10.0
			chunks[key]["far"].append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * fs), t.origin))
			chunks[key]["shapes"].append(Vector3(px, h + 2.0 * s, pz))
			count += 1
		z += grid
	# pedras espalhadas (mais nas encostas)
	var rock_count := 0
	for i in 420:
		var px := rng.randf_range(-half + 10, half - 10)
		var pz := rng.randf_range(-half + 10, half - 10)
		var d := maxf(absf(px), absf(pz)) - FLAT
		if d < -20.0 or _cleared(px, pz, 3.0):
			continue
		var h := height(px, pz)
		var key := Vector2i(int(floor((px + half) / CHUNK)), int(floor((pz + half) / CHUNK)))
		if not chunks.has(key):
			chunks[key] = {"near": [[], []], "far": [], "shapes": []}
		if not chunks[key].has("rocks"):
			chunks[key]["rocks"] = [[], []]
		var s := rng.randf_range(0.5, 2.2) * (1.0 + clampf(d / 200.0, 0.0, 1.5))
		var nrm := normal(px, pz)
		var b := Basis(Quaternion(Vector3.UP, nrm)) * Basis(Vector3.UP, rng.randf() * TAU)
		chunks[key]["rocks"][rng.randi() % 2].append(Transform3D(b.scaled(Vector3.ONE * s), Vector3(px, h - 0.15 * s, pz)))
		chunks[key]["shapes"].append(Vector4(px, h + 0.25 * s, pz, 0.75 * s))
		rock_count += 1
	for key in chunks:
		var c: Dictionary = chunks[key]
		var node := Node3D.new()
		node.name = "Chunk_%d_%d" % [key.x, key.y]
		root.add_child(node)
		if not c["far"].is_empty():
			node.add_child(_mmi("Far", far, c["far"], 140.0, 1100.0, false))
		if c.has("rocks"):
			for kind in 2:
				if not c["rocks"][kind].is_empty():
					node.add_child(_mmi("Rocks%d" % kind, rocks[kind], c["rocks"][kind], 0.0, 450.0, true))
		var body := StaticBody3D.new()
		body.name = "Collision"
		body.collision_layer = 1
		body.collision_mask = 0
		node.add_child(body)
		var k := 0
		for sp in c["shapes"]:
			var col := CollisionShape3D.new()
			col.name = "S%d" % k
			k += 1
			if sp is Vector3:
				col.shape = trunk
				col.position = sp
			else:
				var sph := SphereShape3D.new()
				sph.radius = sp.w
				col.shape = sph
				col.position = Vector3(sp.x, sp.y, sp.z)
			body.add_child(col)
	var near_root := Node3D.new()
	near_root.name = "Near"
	root.add_child(near_root)
	for cell in near_cells:
		var node := Node3D.new()
		node.name = "Cell_%d_%d" % [cell.x, cell.y]
		near_root.add_child(node)
		for kind in 2:
			if not near_cells[cell][kind].is_empty():
				node.add_child(_mmi("Pines%d" % kind, pines[kind], near_cells[cell][kind], 0.0, 100.0, true))
	print("  floresta: %d pinheiros, %d pedras, %d pedaços" % [count, rock_count, chunks.size()])
	return root


func _mmi(name: String, mesh: Mesh, xforms: Array, vis_begin: float, vis_end: float, shadows: bool) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = name
	mmi.multimesh = mm
	mmi.visibility_range_begin = vis_begin
	mmi.visibility_range_end = vis_end
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mmi


# ================================================================ grama

func _grass_clump() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var w := 0.55
	var h := 0.5
	for k in 3:
		var a := k * PI / 3.0
		var s := Vector3(cos(a), 0, sin(a)) * w
		var n := Vector3(-sin(a), 0, cos(a))
		var v := [-s, s, s + Vector3(0, h, 0), -s + Vector3(0, h, 0)]
		var uv := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
		for idx in [0, 1, 2, 0, 2, 3]:
			st.set_normal(n)
			st.set_uv(uv[idx])
			st.add_vertex(v[idx])
	var m := st.commit()
	m.surface_set_material(0, materials["grass_blades"])
	return m


func build_grass() -> Node3D:
	var root := Node3D.new()
	root.name = "Grass"
	root.set_script(load("res://scripts/world/grass_field.gd"))
	var clump := _grass_clump()
	var rng := RandomNumberGenerator.new()
	rng.seed = 91
	var size := 24.0
	var extent := 96.0
	var per := 360
	var total := 0
	var cz := -extent
	while cz < extent:
		var cx := -extent
		while cx < extent:
			var xs: Array = []
			var cols: Array = []
			for i in per:
				var px := cx + rng.randf() * size
				var pz := cz + rng.randf() * size
				if _cleared(px, pz):
					continue
				var nrm := normal(px, pz)
				if nrm.y < 0.88:
					continue
				var s := rng.randf_range(0.7, 1.35)
				var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.8, 1.3), s))
				xs.append(Transform3D(b, Vector3(px, height(px, pz) - 0.02, pz)))
				var g := rng.randf_range(0.82, 1.1)
				cols.append(Color(g * rng.randf_range(0.95, 1.12), g, g * rng.randf_range(0.8, 1.0)))
			if not xs.is_empty():
				var mm := MultiMesh.new()
				mm.transform_format = MultiMesh.TRANSFORM_3D
				mm.use_colors = true
				mm.mesh = clump
				mm.instance_count = xs.size()
				for i in xs.size():
					mm.set_instance_transform(i, xs[i])
					mm.set_instance_color(i, cols[i])
				var mmi := MultiMeshInstance3D.new()
				mmi.name = "G_%d_%d" % [int(cx), int(cz)]
				mmi.multimesh = mm
				mmi.visibility_range_end = 55.0
				mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				root.add_child(mmi)
				total += xs.size()
			cx += size
		cz += size
	print("  grama: %d tufos" % total)
	return root
