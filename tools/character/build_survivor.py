"""Gera o personagem SOBREVIVENTE do ALONE DAYS no Blender (bpy), a partir da base CC0 do MakeHuman.

Uso:  ~/blender-venv/bin/python tools/character/build_survivor.py <pasta makehuman/data> <saida.glb>

Etapas: forma do corpo -> esqueleto de jogo -> pesos -> roupas geradas sobre o corpo
-> mochila -> olhos -> texturas -> otimização -> animações -> exportação GLB.
"""
import math
import os
import sys

import bpy  # precisa vir antes de bmesh/mathutils
import bmesh
import numpy as np
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from mh_base import BaseMesh, Skeleton, load_mhclo  # noqa: E402
import survivor_materials as mats  # noqa: E402
import survivor_anims as anims  # noqa: E402

MH_DATA = sys.argv[-2] if len(sys.argv) > 2 else "/tmp/mh/makehuman/data"
OUT = sys.argv[-1] if len(sys.argv) > 2 else os.path.join(HERE, "../../assets/models/survivor/survivor.glb")
mats.MH_DATA = MH_DATA
PREVIEW_ONLY = os.environ.get("PREVIEW_ONLY") == "1"
# VARIANT=zombie gera o zumbi (mesmo esqueleto, corpo magro, roupa rasgada, sangue)
ZOMBIE = os.environ.get("VARIANT") == "zombie"
mats.ZOMBIE = ZOMBIE

# ---------------------------------------------------------------- forma do corpo
# Homem adulto (~25-35 anos), atlético, ~1,80 m, traços miscigenados.
BODY_TARGETS = [
    ("macrodetails/universal-male-young-averagemuscle-averageweight.target", 0.5),
    ("macrodetails/universal-male-young-maxmuscle-averageweight.target", 0.5),
    ("macrodetails/caucasian-male-young.target", 0.5),
    ("macrodetails/african-male-young.target", 0.3),
    ("macrodetails/asian-male-young.target", 0.2),
    ("macrodetails/height/male-young-averagemuscle-averageweight-maxheight.target", 0.05),
]

if ZOMBIE:
    # Homem magro, definhado
    BODY_TARGETS = [
        ("macrodetails/universal-male-young-minmuscle-minweight.target", 0.8),
        ("macrodetails/universal-male-young-averagemuscle-minweight.target", 0.2),
        ("macrodetails/caucasian-male-young.target", 0.6),
        ("macrodetails/african-male-young.target", 0.2),
        ("macrodetails/asian-male-young.target", 0.2),
    ]

# Esqueleto de jogo: ossos mantidos (os demais são fundidos no ancestral mais próximo)
KEEP = {"root", "spine05", "spine04", "spine03", "spine02", "spine01",
        "neck01", "neck02", "neck03", "head", "jaw"}
for side in ("L", "R"):
    for b in ("clavicle", "shoulder01", "upperarm01", "upperarm02", "lowerarm01", "lowerarm02",
              "wrist", "pelvis", "upperleg01", "upperleg02", "lowerleg01", "lowerleg02", "foot"):
        KEEP.add(f"{b}.{side}")
    for f in range(1, 6):
        for j in range(1, 4):
            KEEP.add(f"finger{f}-{j}.{side}")

REGION_OF_BONE = {
    "head": "HEAD", "jaw": "HEAD", "neck03": "HEAD", "neck02": "NECK", "neck01": "NECK",
    "spine01": "TORSO", "spine02": "TORSO", "spine03": "TORSO", "spine04": "TORSO", "spine05": "TORSO",
    "clavicle": "TORSO", "root": "HIP", "pelvis": "HIP",
    "shoulder01": "UPPERARM", "upperarm01": "UPPERARM", "upperarm02": "UPPERARM",
    "lowerarm01": "FOREARM", "lowerarm02": "FOREARM", "wrist": "HAND",
    "upperleg01": "THIGH", "upperleg02": "THIGH", "lowerleg01": "SHIN", "lowerleg02": "SHIN", "foot": "FOOT",
}


def bone_region(bone):
    if bone.startswith("finger"):
        return "HAND"
    return REGION_OF_BONE.get(bone.split(".")[0], "HEAD")


def to_bl(c):
    """MakeHuman (dm, Y para cima, frente +Z) -> Blender (m, Z para cima, frente -Y)."""
    return Vector((c[0] * 0.1, -c[2] * 0.1, c[1] * 0.1))


def clean_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


# ---------------------------------------------------------------- esqueleto

def kept_ancestor(skel, bone):
    while bone is not None and bone not in KEEP:
        bone = skel.bones[bone]["parent"]
    return bone


def build_armature(skel, z_shift):
    arm_data = bpy.data.armatures.new("SurvivorRig")
    arm = bpy.data.objects.new("Survivor", arm_data)
    bpy.context.scene.collection.objects.link(arm)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="EDIT")
    eb = arm_data.edit_bones
    for name in skel.bones:
        if name not in KEEP:
            continue
        b = eb.new(name)
        b.head = to_bl(skel.head(name)) + Vector((0, 0, z_shift))
        b.tail = to_bl(skel.tail(name)) + Vector((0, 0, z_shift))
        if (b.tail - b.head).length < 1e-4:
            b.tail = b.head + Vector((0, 0, 0.02))
        n = skel.plane_normal(name)
        if n is not None:
            nb = to_bl(n).normalized()
            if abs(nb.dot((b.tail - b.head).normalized())) < 0.95:
                b.align_roll(nb)
    for name in skel.bones:
        if name not in KEEP:
            continue
        parent = kept_ancestor(skel, skel.bones[name]["parent"])
        if parent:
            eb[name].parent = eb[parent]
            eb[name].use_connect = False
    bpy.ops.object.mode_set(mode="OBJECT")
    return arm


def vertex_weights(skel):
    """Pesos por vértice da malha base, já fundidos para os ossos mantidos."""
    per_vertex = {}
    for bone, pairs in skel.weights.items():
        target = kept_ancestor(skel, bone) if bone in skel.bones else None
        if target is None:
            continue
        for vi, w in pairs:
            d = per_vertex.setdefault(vi, {})
            d[target] = d.get(target, 0.0) + w
    return per_vertex


# ---------------------------------------------------------------- malhas

def make_mesh(name, verts, faces, uv_faces=None):
    me = bpy.data.meshes.new(name)
    me.from_pydata([tuple(v) for v in verts], [], [tuple(f) for f in faces])
    if uv_faces is not None:
        uv = me.uv_layers.new(name="UVMap")
        k = 0
        for poly, fuv in zip(me.polygons, uv_faces):
            for li, uvc in zip(poly.loop_indices, fuv):
                uv.data[li].uv = uvc
    me.validate()
    me.update()
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    return ob


def assign_weights(ob, weights_by_local_index):
    for li, wd in weights_by_local_index.items():
        total = sum(wd.values()) or 1.0
        for bone, w in wd.items():
            vg = ob.vertex_groups.get(bone) or ob.vertex_groups.new(name=bone)
            vg.add([li], w / total, "REPLACE")


def body_submesh(base, face_filter, z_shift, weights, name):
    """Cria um objeto com as faces do corpo que passam no filtro (com UVs e pesos)."""
    sel = [f for f in base.faces if f[2] == "body" and face_filter(f[0])]
    used = sorted({v for f in sel for v in f[0]})
    remap = {v: i for i, v in enumerate(used)}
    verts = [to_bl(base.coords[v]) + Vector((0, 0, z_shift)) for v in used]
    faces = [[remap[v] for v in f[0]] for f in sel]
    uv_faces = [[tuple(base.uvs[t]) for t in f[1]] for f in sel]
    ob = make_mesh(name, verts, faces, uv_faces)
    assign_weights(ob, {remap[v]: weights.get(v, {"root": 1.0}) for v in used})
    return ob, used


def inflate(ob, thickness, smooth_iters=4, smooth_factor=0.5):
    """Afasta a malha da pele (vira roupa) e suaviza o relevo anatômico."""
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bm.normal_update()
    for v in bm.verts:
        v.co += v.normal * thickness
    inner = [v for v in bm.verts if not v.is_boundary]
    for _ in range(smooth_iters):
        bmesh.ops.smooth_vert(bm, verts=inner, factor=smooth_factor,
                              use_axis_x=True, use_axis_y=True, use_axis_z=True)
    bm.to_mesh(ob.data)
    bm.free()


def decimate(ob, ratio):
    if ratio >= 1.0:
        return
    m = ob.modifiers.new("Decimate", "DECIMATE")
    m.ratio = ratio
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.modifier_apply(modifier=m.name)


def solidify(ob, thickness):
    m = ob.modifiers.new("Solidify", "SOLIDIFY")
    m.thickness = thickness
    m.offset = -1.0
    m.use_rim = True
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.modifier_apply(modifier=m.name)


def tri_count(ob):
    return sum(len(p.vertices) - 2 for p in ob.data.polygons)


# ---------------------------------------------------------------- construção

def build():
    clean_scene()
    base = BaseMesh(MH_DATA)
    base.apply_targets(BODY_TARGETS)
    skel = Skeleton(MH_DATA, base)
    weights = vertex_weights(skel)

    body_verts = base.group_vertices("body")
    min_y = base.coords[body_verts][:, 1].min()
    z_shift = -min_y * 0.1
    height = (base.coords[body_verts][:, 1].max() - min_y) * 0.1
    print(f"Altura: {height:.2f} m")

    # Região de cada vértice pelo osso dominante
    region = {}
    for v in body_verts:
        wd = weights.get(v)
        region[v] = bone_region(max(wd, key=wd.get)) if wd else "TORSO"
    zc = lambda v: base.coords[v][1] * 0.1 + z_shift  # altura em metros
    j = lambda name: to_bl(skel.joint_pos[name]) + Vector((0, 0, z_shift))
    waist_z = j("spine04____head").z + 0.02
    ankle_z = j("foot.L____head").z
    boot_top = ankle_z + 0.13
    brow_z = j("eye.L____head").z + 0.03

    def in_regions(names, extra=None):
        def f(face_verts):
            return all(region[v] in names or (extra and extra(v)) for v in face_verts)
        return f

    shirt_f = in_regions({"TORSO"}, lambda v: region[v] == "UPPERARM" and zc(v) > j("upperarm02.L____head").z - 0.01)
    pants_f = in_regions({"HIP", "THIGH", "SHIN"}, lambda v: region[v] == "TORSO" and zc(v) < waist_z)
    boots_f = lambda fv: all(region[v] == "FOOT" or (region[v] == "SHIN" and zc(v) < boot_top) for v in fv)
    beanie_f = lambda fv: all(region[v] == "HEAD" and zc(v) > brow_z for v in fv)
    hem_z = waist_z - 0.1
    jacket_f = in_regions({"TORSO", "UPPERARM", "FOREARM"},
                          lambda v: region[v] in ("HIP", "THIGH") and zc(v) > hem_z)

    def jacket_face(fv):
        if not jacket_f(fv):
            return False
        # barra reta: no tronco nada abaixo da linha do quadril (braços ficam livres)
        return all(zc(v) >= hem_z or region[v] in ("UPPERARM", "FOREARM") for v in fv)

    covered = lambda fv: shirt_f(fv) or (pants_f(fv) and not shirt_f(fv)) or boots_f(fv) or beanie_f(fv) or \
        all(region[v] == "TORSO" for v in fv) or all(region[v] in ("HIP", "THIGH") for v in fv)
    if ZOMBIE:
        return build_zombie(base, skel, weights, region, z_shift, zc, j, shirt_f, pants_f, boot_top)
    # Corpo visível: cabeça, pescoço, braços e mãos (o resto fica sob roupa)
    body, body_used = body_submesh(base, lambda fv: not covered(fv), z_shift, weights, "Body")
    mats.paint_skin_features(body, body_used, base, skel, j)

    shirt, _ = body_submesh(base, shirt_f, z_shift, weights, "Shirt")
    inflate(shirt, 0.006, 3)
    relax_boundary(shirt, 8)
    pants, _ = body_submesh(base, lambda fv: pants_f(fv) and not all(zc(v) < boot_top - 0.04 for v in fv),
                            z_shift, weights, "Pants")
    inflate(pants, 0.02, 12)
    relax_boundary(pants, 10)
    boots = build_boots(base, region, weights, z_shift, boot_top)
    beanie, _ = body_submesh(base, beanie_f, z_shift, weights, "Beanie")
    inflate(beanie, 0.01, 5, 0.6)
    relax_boundary(beanie, 15)
    add_cuff(beanie)
    jacket, _ = body_submesh(base, jacket_face, z_shift, weights, "Jacket")
    inflate(jacket, 0.03, 10, 0.6)
    relax_boundary(jacket, 12)
    flatten_hem(jacket, hem_z)
    add_collar(jacket)

    eyes = build_eyes(base, z_shift, skel)

    # Otimização (orçamento ~20 mil triângulos no total)
    for ob, ratio in ((body, 0.55), (shirt, 0.4), (pants, 0.45), (beanie, 0.45), (jacket, 0.5)):
        decimate(ob, ratio)
    for ob, th in ((jacket, 0.007), (pants, 0.004), (shirt, 0.003), (beanie, 0.004)):
        solidify(ob, th)

    arm = build_armature(skel, z_shift)
    backpack = build_backpack(arm, jacket, z_shift)
    sockets = socket_frames(arm, jacket)
    holster = build_holster(sockets["Socket_Holster"])

    meshes = [body, shirt, pants, boots, beanie, jacket, backpack, holster] + eyes
    mats.apply_all(meshes, base, region)

    for ob in meshes:
        ob.parent = arm
        mod = ob.modifiers.new("Armature", "ARMATURE")
        mod.object = arm

    total = 0
    for ob in meshes:
        t = tri_count(ob)
        total += t
        print(f"  {ob.name:10s} {t:6d} triângulos")
    print(f"  TOTAL      {total:6d} triângulos")

    add_sockets(arm, sockets)
    if not PREVIEW_ONLY:
        anims.create_all(arm)
    export(OUT)


def build_zombie(base, skel, weights, region, z_shift, zc, j, shirt_f, pants_f, boot_top):
    """Zumbi: corpo inteiro (aparece pelos rasgos), camisa e calça rasgadas, botas gastas."""
    in_boot = lambda fv: all(region[v] == "FOOT" or (region[v] == "SHIN" and zc(v) < boot_top - 0.02) for v in fv)
    body, body_used = body_submesh(base, lambda fv: not in_boot(fv), z_shift, weights, "Body")
    mats.paint_skin_features(body, body_used, base, skel, j)
    shirt, _ = body_submesh(base, shirt_f, z_shift, weights, "Shirt")
    inflate(shirt, 0.012, 3)
    relax_boundary(shirt, 6)
    pants, _ = body_submesh(base, lambda fv: pants_f(fv) and not all(zc(v) < boot_top - 0.04 for v in fv),
                            z_shift, weights, "Pants")
    inflate(pants, 0.018, 10)
    relax_boundary(pants, 8)
    # rasgos: buracos aleatórios + barras esfarrapadas
    tear(shirt, seed=3, holes=0.12, hem_z=j("spine04____head").z - 0.02, ragged=0.06)
    tear(pants, seed=11, holes=0.12, hem_z=j("lowerleg01.L____head").z - 0.1, ragged=0.09)
    boots = build_boots(base, region, weights, z_shift, boot_top)
    eyes = build_eyes(base, z_shift, skel)
    for ob, ratio in ((body, 0.4), (shirt, 0.5), (pants, 0.5)):
        decimate(ob, ratio)
    for ob, th in ((pants, 0.004), (shirt, 0.003)):
        solidify(ob, th)
    arm = build_armature(skel, z_shift)
    meshes = [body, shirt, pants, boots] + eyes
    mats.apply_all(meshes, base, region)
    for ob in meshes:
        ob.parent = arm
        mod = ob.modifiers.new("Armature", "ARMATURE")
        mod.object = arm
    total = sum(tri_count(ob) for ob in meshes)
    print(f"  TOTAL      {total:6d} triângulos")
    if not PREVIEW_ONLY:
        import zombie_anims
        zombie_anims.create_all(arm)
    export(OUT)


def tear(ob, seed, holes, hem_z, ragged):
    """Remove faces onde um ruído 3D passa do limiar (buracos) e recorta a barra em zigue-zague."""
    from mathutils import noise
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    off = Vector((seed * 7.31, seed * 3.17, seed * 1.93))
    kill = []
    for f in bm.faces:
        c = f.calc_center_median()
        n = noise.noise((c + off) * 9.0) + 0.5 * noise.noise((c + off) * 23.0)
        if n > 0.62 - holes * 2.0:
            kill.append(f)
            continue
        # barra esfarrapada: altura de corte varia ao redor do corpo
        edge = hem_z + ragged * (0.5 + 0.5 * noise.noise(Vector((c.x * 25.0, c.y * 25.0, seed))))
        if c.z < edge:
            kill.append(f)
    bmesh.ops.delete(bm, geom=kill, context="FACES")
    # remove pedacinhos soltos (ilhas pequenas)
    seen = set()
    for f in list(bm.faces):
        if f in seen or not f.is_valid:
            continue
        island, stack = [], [f]
        seen.add(f)
        while stack:
            g = stack.pop()
            island.append(g)
            for e in g.edges:
                for h in e.link_faces:
                    if h not in seen:
                        seen.add(h)
                        stack.append(h)
        if len(island) < 12:
            bmesh.ops.delete(bm, geom=island, context="FACES")
    bm.to_mesh(ob.data)
    bm.free()
    relax_boundary(ob, 3, 0.3)


def flatten_soles(ob):
    """Achata a sola da bota e engrossa um pouco o calcanhar."""
    for v in ob.data.vertices:
        if v.co.z < 0.03:
            v.co.z = max(v.co.z - 0.012, -0.004)


def boundary_loops(bm):
    """Agrupa as arestas de borda em laços fechados (barra, punhos, gola...)."""
    edges = {e for e in bm.edges if e.is_boundary}
    loops = []
    while edges:
        e0 = edges.pop()
        loop = {e0}
        stack = list(e0.verts)
        while stack:
            v = stack.pop()
            for e in v.link_edges:
                if e in edges:
                    edges.remove(e)
                    loop.add(e)
                    stack.extend(e.verts)
        loops.append(loop)
    return loops


def add_collar(ob):
    """Gola: levanta o laço de borda mais alto (contorno do pescoço)."""
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    loops = boundary_loops(bm)
    if loops:
        neck = max(loops, key=lambda lp: sum(v.co.z for e in lp for v in e.verts) / (2 * len(lp)))
        verts = {v for e in neck for v in e.verts}
        center = sum((v.co for v in verts), Vector()) / len(verts)
        ret = bmesh.ops.extrude_edge_only(bm, edges=list(neck))
        for v in [g for g in ret["geom"] if isinstance(g, bmesh.types.BMVert)]:
            d = Vector((v.co.x - center.x, v.co.y - center.y, 0)).normalized()
            v.co += d * 0.01 + Vector((0, 0, 0.032))
    bm.to_mesh(ob.data)
    bm.free()


def build_boots(base, region, weights, z_shift, boot_top):
    """Botas: casco convexo do pé + tornozelo (sem dedos), com sola achatada."""
    from mathutils import kdtree
    pts = {"L": [], "R": []}
    idx = {"L": [], "R": []}
    for v, r in region.items():
        z = base.coords[v][1] * 0.1 + z_shift
        if r == "FOOT" or (r == "SHIN" and z < boot_top):
            side = "L" if base.coords[v][0] > 0 else "R"
            pts[side].append(to_bl(base.coords[v]) + Vector((0, 0, z_shift)))
            idx[side].append(v)
    bm = bmesh.new()
    for side in ("L", "R"):
        c = sum(pts[side], Vector()) / len(pts[side])
        verts = []
        for p in pts[side]:
            d = p - c
            grow = Vector((d.x * 0.12, d.y * 0.06, 0.0))
            q = p + grow
            q.z = max(q.z - 0.008, 0.0) if p.z < 0.035 else q.z
            verts.append(bm.verts.new(q))
        bmesh.ops.convex_hull(bm, input=verts)
    for v in [v for v in bm.verts if not v.link_faces]:
        bm.verts.remove(v)
    # mais resolução para o sombreamento suave
    bmesh.ops.subdivide_edges(bm, edges=bm.edges[:], cuts=1, use_grid_fill=True, smooth=0.7)
    for v in bm.verts:
        if v.co.z < 0.015:
            v.co.z = 0.0
    me = bpy.data.meshes.new("Boots")
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new("Boots", me)
    bpy.context.scene.collection.objects.link(ob)
    decimate(ob, 0.6)
    # pesos: copia do vértice do pé mais próximo
    all_idx = idx["L"] + idx["R"]
    tree = kdtree.KDTree(len(all_idx))
    for i, v in enumerate(all_idx):
        tree.insert(to_bl(base.coords[v]) + Vector((0, 0, z_shift)), i)
    tree.balance()
    assign_weights(ob, {mv.index: weights.get(all_idx[tree.find(mv.co)[1]], {"root": 1.0})
                        for mv in me.vertices})
    return ob


def relax_boundary(ob, iterations=10, factor=0.5):
    """Remove o serrilhado das bordas (barra, punho, gola) alisando os vértices de borda."""
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    boundary = [v for v in bm.verts if v.is_boundary]
    for _ in range(iterations):
        new = {}
        for v in boundary:
            nbs = [e.other_vert(v) for e in v.link_edges if e.is_boundary]
            if len(nbs) == 2:
                avg = (nbs[0].co + nbs[1].co) * 0.5
                new[v] = v.co.lerp(avg, factor)
        for v, co in new.items():
            v.co = co
    bm.to_mesh(ob.data)
    bm.free()


def flatten_hem(ob, hem_z):
    """Deixa a barra da jaqueta reta (horizontal)."""
    for v in ob.data.vertices:
        if abs(v.co.x) < 0.22 and v.co.z < hem_z + 0.05:
            v.co.z = max(v.co.z, hem_z)


def add_cuff(ob):
    """Barra dobrada do gorro: estende a borda para baixo e para fora."""
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    edges = [e for e in bm.edges if e.is_boundary]
    center = sum((v.co for v in bm.verts), Vector()) / max(len(bm.verts), 1)
    if edges:
        ret = bmesh.ops.extrude_edge_only(bm, edges=edges)
        for v in [g for g in ret["geom"] if isinstance(g, bmesh.types.BMVert)]:
            d = Vector((v.co.x - center.x, v.co.y - center.y, 0)).normalized()
            v.co += d * 0.004 + Vector((0, 0, -0.022))
    bm.to_mesh(ob.data)
    bm.free()


def build_eyes(base, z_shift, skel):
    path = os.path.join(MH_DATA, "eyes", "low-poly", "low-poly.mhclo")
    coords, uvs, faces = load_mhclo(path, base)
    verts = [to_bl(c) + Vector((0, 0, z_shift)) for c in coords]
    uv_faces = [[tuple(uvs[t]) for t in f[1]] for f in faces]
    ob = make_mesh("Eyes", verts, [f[0] for f in faces], uv_faces)
    vg = ob.vertex_groups.new(name="head")
    vg.add(list(range(len(verts))), 1.0, "REPLACE")
    return [ob]


def build_backpack(arm, body, z_shift):
    """Mochila de lona: corpo, tampa, bolso frontal e alças. Presa ao osso spine02."""
    rig = arm.data
    s3 = arm.matrix_world @ rig.bones["spine02"].head_local
    s1 = arm.matrix_world @ rig.bones["spine01"].head_local
    bm = bmesh.new()

    def box(center, size, bevel=0.012):
        geom = bmesh.ops.create_cube(bm, size=1.0)
        vs = geom["verts"]
        for v in vs:
            v.co = Vector((v.co.x * size[0], v.co.y * size[1], v.co.z * size[2])) + center
        if bevel > 0:
            edges = list({e for v in vs for e in v.link_edges})
            bmesh.ops.bevel(bm, geom=edges, offset=bevel, segments=2, affect="EDGES", profile=0.6)

    back = [v.co.y for v in body.data.vertices if s3.z - 0.12 < v.co.z < s1.z and abs(v.co.x) < 0.08]
    back_y = sorted(back)[-max(len(back) // 20, 1)] if back else s3.y + 0.12
    print(f"  costas em y={back_y:.3f} (spine02 y={s3.y:.3f})")
    c = Vector((0, back_y + 0.1, (s3.z + s1.z) * 0.5 - 0.04))
    box(c, (0.31, 0.19, 0.44), 0.03)                                        # corpo
    box(c + Vector((0, 0.005, 0.2)), (0.32, 0.2, 0.08), 0.025)               # tampa
    box(c + Vector((0, 0.11, -0.08)), (0.22, 0.06, 0.18), 0.018)             # bolso frontal
    for sx in (-1, 1):
        box(c + Vector((0.165 * sx, 0.0, -0.06)), (0.05, 0.13, 0.2), 0.015)  # bolsos laterais
        # alças: sobem pelas costas, passam pelo ombro e descem pelo peito
        top = Vector((0.1 * sx, back_y + 0.02, s1.z + 0.11))
        box(top, (0.055, 0.07, 0.025), 0.008)
        front = Vector((0.11 * sx, s1.y - 0.13, s1.z - 0.05))
        box(front, (0.05, 0.025, 0.26), 0.008)
    me = bpy.data.meshes.new("Backpack")
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new("Backpack", me)
    bpy.context.scene.collection.objects.link(ob)
    vg = ob.vertex_groups.new(name="spine02")
    vg.add(list(range(len(me.vertices))), 1.0, "REPLACE")
    return ob


# ---------------------------------------------------------------- pontos de fixação (armas)
SOCKET_BONES = {"Socket_Hand_R": "wrist.R", "Socket_Back": "spine02", "Socket_Back_Pack": "spine02",
                "Socket_Holster": "upperleg01.R"}


def _frame(pos, fwd, up):
    """Matriz com +Z = eixo do polegar/cabo (exato) e +Y = frente da arma (ortogonalizada).
    Mesma convenção das animações (survivor_anims.basis_z): a direção da arma manda."""
    z = up.normalized()
    y = (fwd - z * fwd.dot(z)).normalized()
    x = y.cross(z)
    m = Matrix((x, y, z)).transposed().to_4x4()
    m.translation = pos
    return m


def socket_frames(arm, jacket):
    b = arm.data.bones
    h = lambda n: b[n].head_local
    wr, el = h("wrist.R"), h("lowerarm01.R")
    thumb = (h("finger2-1.R") - h("finger5-1.R")).normalized()
    palm = wr + (h("finger3-1.R") - wr) * 0.55
    back = [v.co.y for v in jacket.data.vertices if h("spine02").z < v.co.z < h("spine01").z + 0.05 and abs(v.co.x) < 0.1]
    back_y = sorted(back)[-max(len(back) // 20, 1)]
    top = h("spine01").z + 0.1
    down_left = Vector((0.5, 0.0, -1.0))
    hip = h("upperleg01.R")
    return {
        "Socket_Hand_R": _frame(palm, wr - el, thumb),
        # arma branca presa na diagonal: cabo sobre o ombro direito, ponta em direção ao quadril esquerdo
        "Socket_Back": _frame(Vector((-0.11, back_y + 0.035, top)), Vector((0, 1, 0)), down_left),
        "Socket_Back_Pack": _frame(Vector((-0.11, back_y + 0.235, top + 0.02)), Vector((0, 1, 0)), down_left),
        # coldre na lateral da coxa direita: cano para baixo, topo do ferrolho para a frente
        "Socket_Holster": _frame(Vector((hip.x - 0.1, hip.y + 0.01, hip.z - 0.05)), Vector((0, 0, -1)),
                                 Vector((0, -1, 0))),
    }


def add_sockets(arm, frames):
    bpy.context.view_layer.update()
    for name, m in frames.items():
        e = bpy.data.objects.new(name, None)
        e.empty_display_size = 0.05
        bpy.context.scene.collection.objects.link(e)
        e.parent = arm
        e.parent_type = "BONE"
        e.parent_bone = SOCKET_BONES[name]
        bpy.context.view_layer.update()
        e.matrix_world = m


def build_holster(frame):
    """Coldre de couro: envolve ferrolho e cano (a empunhadura fica para fora)."""
    bm = bmesh.new()
    geom = bmesh.ops.create_cube(bm, size=1.0)
    for v in geom["verts"]:
        # no referencial do encaixe: x lateral, y = direção do cano (para baixo), z = topo do ferrolho
        local = Vector((v.co.x * 0.042, v.co.y * 0.17 + 0.075, v.co.z * 0.06 + 0.075))
        v.co = frame @ local
    bmesh.ops.bevel(bm, geom=bm.edges[:], offset=0.008, segments=2, affect="EDGES", profile=0.5)
    me = bpy.data.meshes.new("Holster")
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new("Holster", me)
    bpy.context.scene.collection.objects.link(ob)
    vg = ob.vertex_groups.new(name="upperleg01.R")
    vg.add(list(range(len(me.vertices))), 1.0, "REPLACE")
    return ob


def export(path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=path, export_format="GLB", export_apply=False, export_animations=True,
        export_skins=True, export_yup=True, export_texcoords=True, export_normals=True,
        export_image_format="AUTO", export_animation_mode="ACTIONS")
    print("Exportado:", path)


if __name__ == "__main__":
    build()
