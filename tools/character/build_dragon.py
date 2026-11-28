"""Gera o DRAGÃO de montaria do ALONE DAYS no Blender, por código (malha, esqueleto,
texturas assadas e animações).

Uso: ~/blender-venv/bin/python tools/character/build_dragon.py <saida.glb>

- Corpo: cortes transversais ao longo da linha central (focinho -> cauda), patas
  digitígradas, braços-asa com 4 dedos e membrana, chifres, espinhos, dentes, olhos, sela.
- Esqueleto: 50 ossos. Pesos por proximidade aos ossos de cada parte (membrana só nos
  ossos da asa, corpo só na coluna...).
- Animações (30 fps): idle, walk, roar, takeoff, flap, glide, glide_l, glide_r, dive,
  hover, land. Feitas com cinemática direta (ângulos) e inversa (patas no chão).
Medidas em dragon_layout.py.
"""
import math
import os
import sys

import bpy
import bmesh
from mathutils import Matrix, Quaternion, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import dragon_layout as L  # noqa: E402
import survivor_materials as mats  # noqa: E402

OUT = sys.argv[-1] if len(sys.argv) > 1 and sys.argv[-1].endswith(".glb") else \
    os.path.join(HERE, "../../assets/models/dragon/dragon.glb")
FAST = os.environ.get("FAST") == "1"   # sem assar texturas (para testar animações)

X, Y, Z = Vector((1, 0, 0)), Vector((0, 1, 0)), Vector((0, 0, 1))
FPS = 30


def V(t):
    return Vector(t)


def mx(t):
    """Espelha um ponto para o lado esquerdo."""
    return Vector((-t[0], t[1], t[2]))


def qa(axis, deg):
    return Quaternion(axis, math.radians(deg))


def mirror_q(qq):
    """Rotação espelhada no plano YZ (lado esquerdo)."""
    return Quaternion((qq.w, qq.x, -qq.y, -qq.z))


def smooth(x):
    x = min(max(x, 0.0), 1.0)
    return x * x * (3 - 2 * x)


def lerp(a, b, t):
    return a + (b - a) * t


def lin(c):
    return tuple(x ** 2.2 for x in c)


# ================================================================ geometria

def catmull(p0, p1, p2, p3, t):
    t2, t3 = t * t, t * t * t
    return 0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (-p0 + 3 * p1 - 3 * p2 + p3) * t3)


def sample_keys(keys, step):
    """keys: lista de (Vector pos, [atributos...]). Curva suave com amostras a cada ~step m."""
    out = []
    n = len(keys)
    for i in range(n - 1):
        p0 = keys[max(i - 1, 0)]
        p1, p2 = keys[i], keys[i + 1]
        p3 = keys[min(i + 2, n - 1)]
        seg = max(2, int(math.ceil((p2[0] - p1[0]).length / step)))
        for k in range(seg):
            t = k / seg
            pos = catmull(p0[0], p1[0], p2[0], p3[0], t)
            attrs = [max(catmull(a0, a1, a2, a3, t), min(a1, a2) * 0.5)
                     for a0, a1, a2, a3 in zip(p0[1], p1[1], p2[1], p3[1])]
            out.append((pos, attrs))
    out.append(keys[-1])
    return out


def loft(name, samples, segs, hint, cap0=True, cap1=True):
    """Tubo com seções superelípticas. samples: (pos, [meia_larg, meia_alt, expoente, barriga])."""
    bm = bmesh.new()
    rings = []
    side_prev = None
    n = len(samples)
    for i, (p, a) in enumerate(samples):
        t = (samples[min(i + 1, n - 1)][0] - samples[max(i - 1, 0)][0]).normalized()
        if side_prev is None:
            side = t.cross(hint).normalized()
        else:
            side = (side_prev - t * side_prev.dot(t)).normalized()
        side_prev = side
        up = side.cross(t)
        w, h = a[0], a[1]
        ex = a[2] if len(a) > 2 else 2.0
        belly = a[3] if len(a) > 3 else 1.0
        ring = []
        for k in range(segs):
            ang = 2 * math.pi * k / segs
            c, s = math.cos(ang), math.sin(ang)
            cx = math.copysign(abs(c) ** (2 / ex), c)
            sy = math.copysign(abs(s) ** (2 / ex), s)
            hh = h * (belly if s < 0 else 1.0)
            ring.append(bm.verts.new(p + side * cx * w + up * sy * hh))
        rings.append(ring)
    for i in range(n - 1):
        for k in range(segs):
            a0, a1 = rings[i][k], rings[i][(k + 1) % segs]
            b0, b1 = rings[i + 1][k], rings[i + 1][(k + 1) % segs]
            bm.faces.new((a0, a1, b1, b0))
    if cap0:
        c = bm.verts.new(samples[0][0])
        for k in range(segs):
            bm.faces.new((rings[0][(k + 1) % segs], rings[0][k], c))
    if cap1:
        c = bm.verts.new(samples[-1][0])
        for k in range(segs):
            bm.faces.new((rings[-1][k], rings[-1][(k + 1) % segs], c))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for poly in me.polygons:
        poly.use_smooth = True
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    return ob


def tube(name, pts, radii, segs=10, hint=Z, step=0.08, flat=1.0, cap0=True, cap1=True):
    keys = [(V(p), [r, r * flat, 2.0, 1.0]) for p, r in zip(pts, radii)]
    return loft(name, sample_keys(keys, step), segs, hint, cap0, cap1)


def cone(name, base, tip, radius, segs=8, bend=None):
    """Cone (garra, chifre pequeno, espinho, dente). bend: ponto de controle no meio."""
    base, tip = V(base), V(tip)
    mid = V(bend) if bend is not None else (base + tip) * 0.5
    pts = [base, (base + mid) * 0.5, mid, (mid + tip) * 0.5, tip]
    radii = [radius, radius * 0.8, radius * 0.55, radius * 0.28, radius * 0.02]
    hint = Z if abs((tip - base).normalized().dot(Z)) < 0.9 else Y
    return tube(name, pts, radii, segs, hint, step=1e9, cap1=False)


def join(obs, name):
    for o in bpy.context.scene.objects:
        o.select_set(False)
    for o in obs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = obs[0]
    bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    ob.name = name
    ob.data.name = name
    return ob


# ================================================================ corpo

def center_samples(keys, step):
    return sample_keys([(V((0.0, k[0], k[1])), [k[2], k[3], k[4], k[5]]) for k in keys], step)


def surface_top(y):
    """Altura do dorso (z) e meia-largura na posição y (para a sela e os espinhos)."""
    s = center_samples(L.CENTER, 0.05)
    best = min(s, key=lambda e: abs(e[0].y - y))
    return best[0].z + best[1][1], best[1][0], best[0].z


def build_body_parts():
    parts = {"skin": [], "horn": [], "eye": [], "saddle": []}
    body = loft("Trunk", center_samples(L.CENTER, 0.11), 26, Z)
    parts["skin"].append(body)
    jaw = loft("JawMesh", center_samples(L.JAW, 0.08), 18, Z)
    parts["skin"].append(jaw)
    for side in (1, -1):
        sx = lambda p: Vector((p[0] * side, p[1], p[2]))  # noqa: E731
        sfx = "R" if side > 0 else "L"
        # perna: coxa musculosa, canela, metatarso (pé digitígrado)
        leg = [sx(p) for p in L.LEG[:4]]
        thigh_top = sx((0.4, -0.45, 2.15))
        parts["skin"].append(tube(f"Leg{sfx}", [thigh_top, leg[0], (leg[0] + leg[1]) * 0.5, leg[1], leg[2], leg[3]],
                                  [0.42, 0.44, 0.31, 0.19, 0.12, 0.105], 14, Y, step=0.07))
        # dedos do pé (3 para a frente, 1 para trás) com garras
        base = leg[3]
        for i, (ang, ln) in enumerate(((-24, 0.5), (0, 0.6), (24, 0.5), (180, 0.28))):
            d = Vector((math.sin(math.radians(ang)) * side, math.cos(math.radians(ang)), 0.0))
            tip = base + d * ln + Vector((0, 0, -0.06))
            parts["skin"].append(tube(f"Toe{sfx}{i}", [base + Vector((0, 0, 0.04)), base + d * ln * 0.55, tip],
                                      [0.085, 0.06, 0.045], 8, Z, step=1e9))
            parts["horn"].append(cone(f"ToeClaw{sfx}{i}", tip, tip + d * 0.2 + Vector((0, 0, -0.06)), 0.045, 6,
                                      bend=tip + d * 0.12))
        # braço-asa: úmero, antebraço, mão, dedos
        sh, el, wr, hd = sx(L.SHOULDER), sx(L.ELBOW), sx(L.WRIST), sx(L.HAND)
        parts["skin"].append(tube(f"Arm{sfx}", [sh - sx((0.15, 0, 0.05)), sh, (sh + el) * 0.5, el, (el + wr) * 0.5, wr, hd],
                                  [0.26, 0.21, 0.16, 0.12, 0.085, 0.1, 0.075], 12, Z, step=0.08))
        for i, (mid, tip) in enumerate(L.FINGERS):
            r0 = 0.065 if i == 0 else 0.05
            parts["skin"].append(tube(f"Finger{sfx}{i}", [hd, sx(mid), sx(tip)], [r0, r0 * 0.6, 0.012], 8, Z, step=0.12))
        wr_ = sx(L.WRIST)
        parts["horn"].append(cone(f"Thumb{sfx}", wr_ + Vector((0, 0.05, -0.05)), sx(L.THUMB), 0.06, 7,
                                  bend=wr_ + sx((0.05, 0.25, -0.15))))
        # chifres grandes para trás e chifres menores na bochecha
        parts["horn"].append(tube(f"Horn{sfx}", [sx((0.17, 4.9, 3.82)), sx((0.27, 4.45, 4.03)), sx((0.36, 3.95, 4.12)),
                                                  sx((0.43, 3.52, 4.06)), sx((0.46, 3.3, 3.98))],
                                  [0.1, 0.075, 0.05, 0.025, 0.004], 9, Z, step=0.08, cap1=False))
        parts["horn"].append(tube(f"Cheek{sfx}", [sx((0.27, 4.78, 3.55)), sx((0.45, 4.42, 3.52)), sx((0.55, 4.2, 3.47))],
                                  [0.05, 0.03, 0.004], 7, Z, step=0.08, cap1=False))
        parts["horn"].append(tube(f"Brow{sfx}", [sx((0.2, 5.15, 3.78)), sx((0.25, 4.95, 3.84)), sx((0.27, 4.82, 3.86))],
                                  [0.025, 0.035, 0.005], 6, Z, step=0.06, cap1=False))
        # olho (âmbar, com brilho próprio leve)
        bpy.ops.mesh.primitive_uv_sphere_add(segments=12, ring_count=8, radius=0.055,
                                             location=sx((0.29, 5.06, 3.71)))
        eye = bpy.context.active_object
        eye.name = f"Eye{sfx}"
        eye.scale = (0.7, 1.0, 0.8)
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
        parts["eye"].append(eye)
        # dentes
        for k in range(7):
            yy = 5.3 + k * 0.1
            top, w, cz = surface_top(yy)
            parts["horn"].append(cone(f"Tooth{sfx}{k}", (side * (w * 0.78 - 0.01 * k), yy, 3.46 - 0.012 * k),
                                      (side * (w * 0.76 - 0.01 * k), yy + 0.01, 3.32 - 0.012 * k), 0.024, 5))
    # espinhos dorsais (do crânio até a ponta da cauda)
    y = 4.3
    k = 0
    while y > -7.4:
        top, w, cz = surface_top(y)
        h = top - cz
        size = 0.06 + 0.32 * min(h, 0.62)
        if 1.8 < y < 2.85:   # sem espinhos debaixo da sela
            y -= 0.33
            continue
        parts["horn"].append(cone(f"Spike{k}", (0, y + size * 0.3, top - 0.03), (0, y - size * 0.6, top + size), size * 0.32, 6,
                                  bend=(0, y, top + size * 0.55)))
        y -= 0.33 if y > -3 else 0.38
        k += 1
    # ponta da cauda em lança
    bm = bmesh.new()
    pts = [(0, -7.45, 0.92), (0.32, -7.85, 0.88), (0, -8.55, 0.82), (-0.32, -7.85, 0.88)]
    vs = [bm.verts.new(p) for p in pts]
    top = bm.verts.new((0, -7.9, 0.93))
    bot = bm.verts.new((0, -7.9, 0.83))
    for i in range(4):
        bm.faces.new((vs[i], vs[(i + 1) % 4], top))
        bm.faces.new((vs[(i + 1) % 4], vs[i], bot))
    me = bpy.data.meshes.new("Spade")
    bm.to_mesh(me)
    bm.free()
    spade = bpy.data.objects.new("Spade", me)
    bpy.context.scene.collection.objects.link(spade)
    parts["skin"].append(spade)
    # sela de couro, cinta em volta do peito e alça (pito) para segurar
    parts["saddle"].append(build_saddle())
    return parts


def build_saddle():
    bm = bmesh.new()
    nx, ny = 10, 8
    grid = []
    for j in range(ny + 1):
        y = lerp(L.SADDLE_Y[0], L.SADDLE_Y[1], j / ny)
        top, w, cz = surface_top(y)
        row = []
        for i in range(nx + 1):
            u = lerp(-1, 1, i / nx)
            x = u * min(w * 0.92, 0.62)
            # cai pelos lados acompanhando o corpo
            zz = cz + (top - cz) * math.sqrt(max(1 - abs(x / (w * 1.02)) ** 2.4, 0.0)) + 0.045
            lift = 0.07 * (math.exp(-((j / ny) - 1.0) ** 2 * 18) + 0.6 * math.exp(-((j / ny)) ** 2 * 18))
            row.append(bm.verts.new((x, y, zz + lift * (1 - abs(u) ** 2))))
        grid.append(row)
    for j in range(ny):
        for i in range(nx):
            bm.faces.new((grid[j][i], grid[j][i + 1], grid[j + 1][i + 1], grid[j + 1][i]))
    me = bpy.data.meshes.new("Saddle")
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new("Saddle", me)
    bpy.context.scene.collection.objects.link(ob)
    sol = ob.modifiers.new("solid", "SOLIDIFY")
    sol.thickness = 0.05
    sol.offset = -1
    mats._select_only(ob)
    bpy.ops.object.modifier_apply(modifier="solid")
    hy = L.SADDLE_Y[1] - 0.04
    top, w, cz = surface_top(hy)
    horn = tube("SaddleHorn", [(0, hy - 0.02, top + 0.05), (0, hy + 0.02, top + 0.2), (0, hy - 0.01, top + 0.27)], [0.05, 0.04, 0.055], 8, Y, step=1e9)
    sy = L.SADDLE_Y[0] + 0.12
    top2, w2, cz2 = surface_top(sy)
    strap = []
    for k in range(25):
        a = 2 * math.pi * k / 24
        c, s = math.cos(a), math.sin(a)
        strap.append((c * w2 * 1.05, sy, cz2 + s * (top2 - cz2) * 1.05))
    belt = tube("Strap", strap, [0.035] * 25, 6, Y, step=1e9, flat=0.3, cap0=False, cap1=False)
    for poly in ob.data.polygons:
        poly.use_smooth = True
    return join([ob, horn, belt], "SaddleAll")


def membrane_panels(side):
    """Membrana da asa: 3 leques entre os dedos + painel interno (braço/dedo 4/flanco)."""
    sx = (lambda p: V(p)) if side > 0 else mx
    hd = sx(L.HAND)
    fingers = [[hd, sx(m), sx(t)] for m, t in L.FINGERS]

    def poly_at(pts, u):
        lens = [(pts[i + 1] - pts[i]).length for i in range(len(pts) - 1)]
        tot = sum(lens)
        d = u * tot
        for i, ln in enumerate(lens):
            if d <= ln or i == len(lens) - 1:
                return pts[i].lerp(pts[i + 1], min(d / ln, 1.0))
            d -= ln

    bm = bmesh.new()
    NU, NV = 12, 9
    sags = [0.1, 0.16, 0.2]
    for f in range(3):
        a, b = fingers[f], fingers[f + 1]
        grid = []
        for i in range(NU + 1):
            u = i / NU
            row = []
            for j in range(NV + 1):
                v = j / NV
                uu = u * (1 - sags[f] * math.sin(math.pi * v))
                row.append(bm.verts.new(poly_at(a, uu).lerp(poly_at(b, uu), v)))
            grid.append(row)
        for i in range(NU):
            for j in range(NV):
                bm.faces.new((grid[i][j], grid[i + 1][j], grid[i + 1][j + 1], grid[i][j + 1]))
    # painel interno (Coons): raiz = braço, ponta = borda de fuga, lados = dedo 4 e flanco
    arm = [hd, sx(L.WRIST), sx(L.ELBOW), sx(L.SHOULDER)]
    f4 = fingers[3]
    ba = sx(L.BODY_ATTACH)
    tip4 = f4[-1]
    NU2, NV2 = 12, 16
    R = lambda v: poly_at(arm, v)  # noqa: E731
    mid_root = poly_at(arm, 0.5)

    def T(v):
        p = tip4.lerp(ba, v)
        return p + (mid_root - p).normalized() * 0.55 * math.sin(math.pi * v)
    A = lambda u: poly_at(f4, u)  # noqa: E731
    C = lambda u: sx(L.SHOULDER).lerp(ba, u)  # noqa: E731
    grid = []
    for i in range(NU2 + 1):
        u = i / NU2
        row = []
        for j in range(NV2 + 1):
            v = j / NV2
            p = (1 - u) * R(v) + u * T(v) + (1 - v) * A(u) + v * C(u) \
                - ((1 - u) * (1 - v) * R(0) + (1 - u) * v * R(1) + u * (1 - v) * T(0) + u * v * T(1))
            row.append(bm.verts.new(p))
        grid.append(row)
    for i in range(NU2):
        for j in range(NV2):
            bm.faces.new((grid[i][j], grid[i + 1][j], grid[i + 1][j + 1], grid[i][j + 1]))
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.004)
    # normais coerentes, viradas para cima (dos dois lados)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    if sum(fc.normal.z * fc.calc_area() for fc in bm.faces) < 0:
        for fc in bm.faces:
            fc.normal_flip()
    me = bpy.data.meshes.new(f"Membrane{side}")
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new("Membrane" + ("R" if side > 0 else "L"), me)
    bpy.context.scene.collection.objects.link(ob)
    for poly in ob.data.polygons:
        poly.use_smooth = True
    # UV plana vista de cima (as duas asas usam a mesma textura, espelhada)
    uv = me.uv_layers.new(name="UVMap")
    for loop in me.loops:
        co = me.vertices[loop.vertex_index].co
        uv.data[loop.index].uv = (abs(co.x) / 8.8, (co.y + 3.0) / 5.4)
    return ob


# ================================================================ esqueleto

BONES = []   # (nome, cabeça, cauda, pai, conectado)


def define_bones():
    BONES.clear()
    BONES.append(("root", V(L.ROOT_HEAD), V(L.SPINE[0]), None, False))
    BONES.append(("spine1", V(L.SPINE[0]), V(L.SPINE[1]), "root", True))
    BONES.append(("chest", V(L.SPINE[1]), V(L.SPINE[2]), "spine1", True))
    prev = "chest"
    for i in range(5):
        BONES.append((f"neck{i + 1}", V(L.NECK[i]), V(L.NECK[i + 1]), prev, True))
        prev = f"neck{i + 1}"
    BONES.append(("head", V(L.NECK[5]), V(L.HEAD_TAIL), prev, True))
    BONES.append(("jaw", V(L.JAW_BONE[0]), V(L.JAW_BONE[1]), "head", False))
    prev = "root"
    for i in range(10):
        BONES.append((f"tail{i + 1}", V(L.TAIL[i]), V(L.TAIL[i + 1]), prev, i > 0))
        prev = f"tail{i + 1}"
    for side, sfx in ((1, "R"), (-1, "L")):
        sx = (lambda p: V(p)) if side > 0 else mx
        lg = [sx(p) for p in L.LEG]
        BONES.append((f"thigh.{sfx}", lg[0], lg[1], "root", False))
        BONES.append((f"shin.{sfx}", lg[1], lg[2], f"thigh.{sfx}", True))
        BONES.append((f"foot.{sfx}", lg[2], lg[3], f"shin.{sfx}", True))
        BONES.append((f"toe.{sfx}", lg[3], lg[4], f"foot.{sfx}", True))
        BONES.append((f"upperarm.{sfx}", sx(L.SHOULDER), sx(L.ELBOW), "chest", False))
        BONES.append((f"forearm.{sfx}", sx(L.ELBOW), sx(L.WRIST), f"upperarm.{sfx}", True))
        BONES.append((f"hand.{sfx}", sx(L.WRIST), sx(L.HAND), f"forearm.{sfx}", True))
        BONES.append((f"thumb.{sfx}", sx(L.WRIST), sx(L.THUMB), f"hand.{sfx}", False))
        for i, (mid, tip) in enumerate(L.FINGERS):
            BONES.append((f"f{i + 1}a.{sfx}", sx(L.HAND), sx(mid), f"hand.{sfx}", True))
            BONES.append((f"f{i + 1}b.{sfx}", sx(mid), sx(tip), f"f{i + 1}a.{sfx}", True))


def build_armature():
    define_bones()
    arm_data = bpy.data.armatures.new("DragonRig")
    arm = bpy.data.objects.new("Dragon", arm_data)
    bpy.context.scene.collection.objects.link(arm)
    mats._select_only(arm)
    bpy.ops.object.mode_set(mode="EDIT")
    eb = arm_data.edit_bones
    for name, h, t, parent, conn in BONES:
        b = eb.new(name)
        b.head, b.tail = h, t
        b.roll = 0.0
        if parent:
            b.parent = eb[parent]
            b.use_connect = conn
    bpy.ops.object.mode_set(mode="OBJECT")
    return arm


def seg_dist(p, a, b):
    ab = b - a
    t = max(0.0, min(1.0, (p - a).dot(ab) / max(ab.length_squared, 1e-9)))
    return (p - (a + ab * t)).length


def weight(ob, bone_names, power=4.0, top=3, anchor=None, bias=None):
    """Pesos por distância aos segmentos dos ossos (só os ossos indicados)."""
    segs = {n: (h, t) for n, h, t, p, c in BONES if n in bone_names}
    groups = {n: ob.vertex_groups.get(n) or ob.vertex_groups.new(name=n) for n in segs}

    def calc(p):
        ws = []
        for n, (h, t) in segs.items():
            d = seg_dist(p, h, t) + 0.02
            if bias and n in bias:
                d *= bias[n]
            ws.append((1.0 / d ** power, n))
        ws.sort(reverse=True)
        ws = ws[:top]
        s = sum(w for w, n in ws)
        return [(w / s, n) for w, n in ws]
    fixed = calc(V(anchor)) if anchor is not None else None
    for v in ob.data.vertices:
        for w, n in (fixed or calc(v.co)):
            if w > 0.01:
                groups[n].add([v.index], w, "ADD")


def bones_of(prefixes, sfx=None):
    out = []
    for n, h, t, p, c in BONES:
        base, _, s = n.partition(".")
        if any(base.startswith(pf) for pf in prefixes) and (sfx is None or s == sfx or s == ""):
            out.append(n)
    return out


AXIAL = ["root", "spine1", "chest", "neck1", "neck2", "neck3", "neck4", "neck5", "head"] + [f"tail{i}" for i in range(1, 11)]


def skin_parts(parts, arm):
    for ob in parts["skin"]:
        nm = ob.name
        if nm == "Trunk":
            weight(ob, AXIAL, 4.0, 3)
        elif nm == "JawMesh":
            weight(ob, ["jaw"], anchor=(0, 5.2, 3.3))
        elif nm == "Spade":
            weight(ob, ["tail10"], anchor=(0, -7.8, 0.9))
        else:
            sfx = nm[-1] if nm.startswith(("Leg", "Arm")) else nm[-2] if nm.startswith(("Toe", "Finger")) else None
            if nm.startswith("Leg"):
                weight(ob, ["root", "spine1", f"thigh.{sfx}", f"shin.{sfx}", f"foot.{sfx}"], 4.0, 2,
                       bias={"root": 1.6, "spine1": 2.0})
            elif nm.startswith("Toe"):
                weight(ob, [f"toe.{sfx}"], anchor=(0, 0, 0))
            elif nm.startswith("Arm"):
                weight(ob, ["chest", f"upperarm.{sfx}", f"forearm.{sfx}", f"hand.{sfx}"], 4.0, 2, bias={"chest": 2.2})
            elif nm.startswith("Finger"):
                i = int(nm[-1]) + 1
                weight(ob, [f"hand.{sfx}", f"f{i}a.{sfx}", f"f{i}b.{sfx}"], 4.0, 2)
    for ob in parts["horn"]:
        nm = ob.name
        anchor = ob.data.vertices[0].co.copy()
        if nm.startswith(("Horn", "Cheek", "Brow", "Tooth")):
            weight(ob, ["head"], anchor=anchor)
        elif nm.startswith("ToeClaw"):
            weight(ob, [f"toe.{nm[7]}"], anchor=anchor)
        elif nm.startswith("Thumb"):
            weight(ob, [f"thumb.{nm[5]}"], anchor=anchor)
        else:
            weight(ob, AXIAL, 4.0, 2, anchor=anchor)
    for ob in parts["eye"]:
        weight(ob, ["head"], anchor=(0, 5.0, 3.7))
    for ob in parts["saddle"]:
        weight(ob, ["chest", "neck1", "neck2"], 4.0, 2)


def skin_membrane(ob, sfx):
    names = [f"upperarm.{sfx}", f"forearm.{sfx}", f"hand.{sfx}"] + [f"f{i}{p}.{sfx}" for i in range(1, 5) for p in "ab"] \
        + ["chest", "spine1", "root"]
    weight(ob, names, 3.0, 3, bias={"chest": 1.3, "spine1": 1.1, "root": 1.1, f"upperarm.{sfx}": 1.0})


# ================================================================ materiais

def skin_material():
    mat = bpy.data.materials.new("DragonSkin")
    nt = mats._nodes(mat)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    nt.links.new(bsdf.outputs[0], out.inputs[0])
    vec = mats._coord(nt)
    geo = nt.nodes.new("ShaderNodeNewGeometry")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(geo.outputs["Normal"], sep.inputs[0])
    nz = sep.outputs["Z"]
    # dorso escuro (preto-avermelhado), flancos bronze, barriga clara em placas
    top = lin((0.075, 0.035, 0.03))
    side = lin((0.26, 0.12, 0.06))
    belly = lin((0.52, 0.4, 0.27))
    up_amt = mats._math(nt, "MULTIPLY", mats._math(nt, "ADD", nz, 0.15), 1.6, clamp=True)
    down_amt = mats._math(nt, "MULTIPLY", mats._math(nt, "SUBTRACT", mats._math(nt, "MULTIPLY", nz, -1.0), 0.35), 2.4, clamp=True)
    mottle = mats._noise(nt, vec, 1.3, 4.0, 0.6)
    col = mats._mix(nt, mats._math(nt, "MULTIPLY", mottle, 0.5), side, lin((0.18, 0.06, 0.04)))
    col = mats._mix(nt, up_amt, col, top)
    col = mats._mix(nt, down_amt, col, belly)
    # escamas: voronoi (bordas escuras e relevo); barriga: placas transversais
    vor = nt.nodes.new("ShaderNodeTexVoronoi")
    vor.feature = "DISTANCE_TO_EDGE"
    vor.inputs["Scale"].default_value = 14.0
    nt.links.new(vec, vor.inputs["Vector"])
    edge = mats._math(nt, "MULTIPLY", vor.outputs["Distance"], 9.0, clamp=True)
    plates = mats._wave(nt, vec, 4.5, "Y")
    plate_edge = mats._math(nt, "POWER", plates, 0.35)
    scale_dark = mats._math(nt, "SUBTRACT", 1.0, edge)
    col = mats._mix(nt, mats._math(nt, "MULTIPLY", scale_dark, mats._math(nt, "SUBTRACT", 0.55, mats._math(nt, "MULTIPLY", down_amt, 0.5))),
                    col, lin((0.02, 0.012, 0.01)))
    col = mats._mix(nt, mats._math(nt, "MULTIPLY", mats._math(nt, "SUBTRACT", 1.0, plate_edge), mats._math(nt, "MULTIPLY", down_amt, 0.6)),
                    col, lin((0.2, 0.14, 0.09)))
    nt.links.new(col, bsdf.inputs["Base Color"])
    height = mats._mix(nt, down_amt, edge, plate_edge)
    bump = nt.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.55
    bump.inputs["Distance"].default_value = 0.02
    nt.links.new(height, bump.inputs["Height"])
    nt.links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    bsdf.inputs["Roughness"].default_value = 0.45
    return mat, nt


def membrane_material():
    mat = bpy.data.materials.new("DragonWing")
    mat.use_backface_culling = False
    nt = mats._nodes(mat)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    nt.links.new(bsdf.outputs[0], out.inputs[0])
    tc = nt.nodes.new("ShaderNodeTexCoord")
    vec = tc.outputs["UV"]
    base = lin((0.2, 0.065, 0.045))
    dark = lin((0.07, 0.025, 0.02))
    col = mats._mix(nt, mats._noise(nt, vec, 3.0, 5.0, 0.6), base, lin((0.29, 0.11, 0.06)))
    # veias finas e enrugado
    veins = nt.nodes.new("ShaderNodeTexVoronoi")
    veins.feature = "DISTANCE_TO_EDGE"
    veins.inputs["Scale"].default_value = 5.0
    warp = nt.nodes.new("ShaderNodeVectorMath")
    warp.operation = "ADD"
    nt.links.new(vec, warp.inputs[0])
    wn = nt.nodes.new("ShaderNodeTexNoise")
    wn.inputs["Scale"].default_value = 6.0
    nt.links.new(vec, wn.inputs["Vector"])
    sc = nt.nodes.new("ShaderNodeVectorMath")
    sc.operation = "SCALE"
    sc.inputs["Scale"].default_value = 0.06
    nt.links.new(wn.outputs["Color"], sc.inputs[0])
    nt.links.new(sc.outputs[0], warp.inputs[1])
    nt.links.new(warp.outputs[0], veins.inputs["Vector"])
    vmask = mats._math(nt, "LESS_THAN", veins.outputs["Distance"], 0.016)
    col = mats._mix(nt, mats._math(nt, "MULTIPLY", vmask, 0.6), col, dark)
    wr = mats._wave(nt, vec, 38.0, "X", distortion=6.0)
    col = mats._mix(nt, mats._math(nt, "MULTIPLY", wr, 0.15), col, dark)
    nt.links.new(col, bsdf.inputs["Base Color"])
    height = mats._math(nt, "ADD", mats._math(nt, "MULTIPLY", wr, 0.4), mats._math(nt, "MULTIPLY", vmask, 0.6))
    bump = nt.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.35
    bump.inputs["Distance"].default_value = 0.01
    nt.links.new(height, bump.inputs["Height"])
    nt.links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    bsdf.inputs["Roughness"].default_value = 0.6
    return mat, nt


def simple_material(name, color, rough, emission=None):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    b = mat.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*lin(color), 1.0)
    b.inputs["Roughness"].default_value = rough
    if emission:
        b.inputs["Emission Color"].default_value = (*lin(emission), 1.0)
        b.inputs["Emission Strength"].default_value = 1.0
    return mat


def horn_material():
    """Chifres, garras e dentes: marfim na base escurecendo para a ponta (por cor de vértice)."""
    return simple_material("DragonHorn", (0.62, 0.55, 0.42), 0.4)


# ================================================================ animação

class Pose:
    def __init__(self, rig):
        self.r = rig
        self.W = {}
        self.root_off = Vector()

    def get(self, b):
        while b is not None:
            if b in self.W:
                return self.W[b]
            b = self.r.parent[b]
        return Quaternion()

    def pos(self, b):
        p = self.r.parent[b]
        if p is None:
            return self.r.head[b] + self.root_off
        return self.pos(p) + self.get(p) @ (self.r.head[b] - self.r.head[p])

    def tail(self, b):
        return self.pos(b) + self.get(b) @ (self.r.tail[b] - self.r.head[b])

    def fk(self, b, d):
        self.W[b] = self.get(self.r.parent[b]) @ d

    def aim(self, b, direction):
        pw = self.get(self.r.parent[b])
        carried = pw @ (self.r.tail[b] - self.r.head[b]).normalized()
        self.W[b] = carried.rotation_difference(direction.normalized()) @ pw

    def ik2(self, b1, b2, target, pole):
        a = self.pos(b1)
        l1 = (self.r.tail[b1] - self.r.head[b1]).length
        l2 = (self.r.tail[b2] - self.r.head[b2]).length
        d = target - a
        dist = min(max(d.length, abs(l1 - l2) + 0.02), l1 + l2 - 0.002)
        dr = d.normalized()
        cosa = (l1 * l1 + dist * dist - l2 * l2) / (2 * l1 * dist)
        sina = math.sqrt(max(1 - cosa * cosa, 0.0))
        pp = (pole - dr * pole.dot(dr))
        pp = pp.normalized() if pp.length > 1e-5 else Z
        elbow = a + dr * cosa * l1 + pp * sina * l1
        self.aim(b1, elbow - a)
        self.aim(b2, a + dr * dist - elbow)

    def body(self, v):
        """Ponto no referencial do corpo (pose de repouso) -> posição atual."""
        return self.pos("root") + self.get("root") @ (V(v) - self.r.head["root"])

    def blend(self, other, t):
        out = Pose(self.r)
        for b in self.r.order:
            out.W[b] = self.get(b).slerp(other.get(b), t)
        out.root_off = self.root_off.lerp(other.root_off, t)
        return out


class Rig:
    def __init__(self, arm):
        self.arm = arm
        self.head, self.tail, self.parent, self.rest_q = {}, {}, {}, {}
        self.order = [b[0] for b in BONES]
        for b in arm.data.bones:
            self.head[b.name] = b.head_local.copy()
            self.tail[b.name] = b.tail_local.copy()
            self.parent[b.name] = b.parent.name if b.parent else None
            self.rest_q[b.name] = b.matrix_local.to_quaternion()

    def key(self, pose, frame):
        for name in self.order:
            pb = self.arm.pose.bones[name]
            r = self.rest_q[name]
            p = self.parent[name]
            wp = pose.get(p) if p else Quaternion()
            local = r.inverted() @ (wp.inverted() @ pose.get(name)) @ r
            pb.rotation_mode = "QUATERNION"
            pb.rotation_quaternion = local
            pb.keyframe_insert("rotation_quaternion", frame=frame)
        pb = self.arm.pose.bones["root"]
        pb.location = self.rest_q["root"].inverted() @ pose.root_off
        pb.keyframe_insert("location", frame=frame)


# ---------------------------------------------------------------- poses de partes

def spine_pose(p, pitch=0.0, roll=0.0, yaw=0.0, lift=0.0, sway=0.0, breathe=0.0, chest_pitch=0.0):
    p.root_off = Vector((sway, 0.0, lift))
    p.W["root"] = qa(Z, yaw) @ qa(Y, roll) @ qa(X, pitch)
    p.fk("spine1", qa(X, chest_pitch * 0.5 + breathe))
    p.fk("chest", qa(X, chest_pitch * 0.5 - breathe))


def neck_pose(p, pitch=0.0, yaw=0.0, head_dir=None, jaw=0.0, head_roll=0.0):
    for i in range(1, 6):
        w = (0.6 + 0.2 * i) / 3.6 * 2.0
        p.fk(f"neck{i}", qa(Z, yaw * w / 5 * 1.0) @ qa(X, pitch * w / 5))
    if head_dir is None:
        p.fk("head", qa(X, -pitch * 0.25))
    else:
        p.aim("head", head_dir)
    p.fk("jaw", qa(X, -jaw))


def tail_pose(p, t, amp_yaw=6.0, amp_pitch=2.0, speed=1.0, lift=0.0, curl=0.0, phase=0.0):
    for i in range(1, 11):
        k = i / 10
        wy = amp_yaw * (0.4 + k) * math.sin(2 * math.pi * (speed * t - 0.09 * i + phase))
        wp = amp_pitch * (0.4 + k) * math.sin(2 * math.pi * (speed * t - 0.07 * i + phase + 0.25))
        p.fk(f"tail{i}", qa(Z, wy + curl * (0.3 + k)) @ qa(X, wp + lift * (1.2 - k)))


def ground_leg(p, sfx, foot_xy, lift=0.0, toe_pitch=0.0, knee_out=0.0):
    side = 1 if sfx == "R" else -1
    contact = Vector((foot_xy[0], foot_xy[1], 0.1 + lift))
    meta = V(L.LEG[2]) - V(L.LEG[3])       # tornozelo acima e atrás da base dos dedos
    meta.x = 0.0
    if lift > 0.02:
        meta = Quaternion(X, math.radians(-25 * min(lift / 0.3, 1.0))) @ meta
    ankle = contact + meta
    p.ik2(f"thigh.{sfx}", f"shin.{sfx}", ankle, Vector((knee_out * side, 1.0, 0.1)))
    p.aim(f"foot.{sfx}", contact - p.pos(f"foot.{sfx}"))
    p.aim(f"toe.{sfx}", Quaternion(X, math.radians(toe_pitch)) @ Vector((0, 1, -0.08)))


def ground_wing(p, sfx, wrist_xy, lift=0.0, spread=0.0):
    """Asa dobrada apoiada no pulso (como um morcego andando)."""
    side = 1 if sfx == "R" else -1
    target = Vector((wrist_xy[0], wrist_xy[1], 0.16 + lift))
    p.ik2(f"upperarm.{sfx}", f"forearm.{sfx}", target, Vector((0.15 * side, -1.0, 0.75)))
    el = p.pos(f"forearm.{sfx}")
    wr = p.pos(f"hand.{sfx}")
    back = (el - wr).normalized()
    p.aim(f"hand.{sfx}", (back + Vector((0.12 * side, 0, 0.5))).normalized())
    for i in range(1, 5):
        k = (i - 1) / 3
        d = (back * (1.0 - 0.1 * k) + Vector((side * (-0.08 + 0.05 * k + spread * 0.25 * k), -0.55 - 0.12 * k - spread * 0.3 * k, 0.05 - 0.15 * k)))
        p.aim(f"f{i}a.{sfx}", d)
        p.aim(f"f{i}b.{sfx}", (d + Vector((0, -0.08 - 0.05 * k, -0.05))).normalized())
    p.aim(f"thumb.{sfx}", Vector((0.1 * side, 0.6, -0.8)))


def fly_wing(p, sfx, elev=0.0, sweep=0.0, twist=0.0, elbow=0.0, wrist=0.0, spread=1.0, camber=3.0):
    side = 1 if sfx == "R" else -1
    m = (lambda qq: qq) if side > 0 else mirror_q
    p.fk(f"upperarm.{sfx}", m(qa(Z, sweep) @ qa(Y, -elev) @ qa(X, twist)))
    p.fk(f"forearm.{sfx}", m(qa(Z, elbow)))
    p.fk(f"hand.{sfx}", m(qa(Z, -wrist)))
    p.fk(f"thumb.{sfx}", m(qa(Z, 10)))
    a1 = math.atan2(L.FINGERS[0][0][1] - L.HAND[1], L.FINGERS[0][0][0] - L.HAND[0])
    for i in range(1, 5):
        ai = math.atan2(L.FINGERS[i - 1][0][1] - L.HAND[1], L.FINGERS[i - 1][0][0] - L.HAND[0])
        fold = math.degrees(a1 - ai) * (1 - spread)
        p.fk(f"f{i}a.{sfx}", m(qa(Z, fold) @ qa(Y, -camber * 0.5)))
        p.fk(f"f{i}b.{sfx}", m(qa(Y, -camber) @ qa(Z, -fold * 0.15)))


def fly_legs(p, t=0.0, dangle=0.0, forward=0.0):
    """Patas recolhidas para trás no voo (dangle: soltas para baixo; forward: esticadas para pousar)."""
    for sfx, side in (("R", 1), ("L", -1)):
        tuck = Vector((0.55 * side, -1.75, 1.35))
        hang = Vector((0.7 * side, -0.55, 0.45))
        reach = Vector((0.75 * side, 0.55, 0.35))
        loc = tuck.lerp(hang, dangle).lerp(reach, forward)
        ankle = p.body(loc)
        pole = p.get("root") @ Vector((0.1 * side, 0.2 + 0.8 * forward, -1.0))
        p.ik2(f"thigh.{sfx}", f"shin.{sfx}", ankle, pole)
        back = p.get("root") @ Vector((0, -1.0 + 1.6 * forward, -0.6 * (1 - forward) - 0.9 * forward))
        p.aim(f"foot.{sfx}", back)
        p.aim(f"toe.{sfx}", p.get("root") @ Vector((0, -0.5 + 1.2 * forward, -1.0 + 0.6 * forward)))


# ---------------------------------------------------------------- poses completas

def pose_ground(rig, t, walk=None, breathe=1.0, look=0.0, neck_raise=0.0, jaw=0.0, wing_spread=0.0, rear=0.0, lie=0.0):
    p = Pose(rig)
    br = math.sin(2 * math.pi * t / 4.0) * breathe if walk is None else 0.0
    feet = {"R": (0.82, -0.15), "L": (-0.82, -0.15)}
    wrists = {"R": (1.3, 2.15), "L": (-1.3, 2.15)}
    lifts = {"R": 0.0, "L": 0.0, "WR": 0.0, "WL": 0.0}
    sway = lift = roll = 0.0
    if walk is not None:
        ph = walk
        stride = 1.15
        for key, off, base in (("R", 0.5, feet), ("L", 0.0, feet), ("WR", 0.75, wrists), ("WL", 0.25, wrists)):
            q = (ph + off) % 1.0
            duty = 0.68
            if q < duty:      # apoio: o pé vai de frente para trás
                s = q / duty
                dy = stride * (0.5 - s)
                lf = 0.0
            else:             # balanço: sobe e volta para a frente
                s = (q - duty) / (1 - duty)
                dy = stride * (-0.5 + smooth(s))
                lf = math.sin(math.pi * s) * (0.32 if key in ("R", "L") else 0.42)
            sk = key[-1]
            if key in ("R", "L"):
                feet[sk] = (feet[sk][0], feet[sk][1] + dy)
            else:
                wrists[sk] = (wrists[sk][0], wrists[sk][1] + dy * 1.05)
            lifts[key] = lf
        sway = 0.07 * math.sin(2 * math.pi * ph)
        lift = 0.05 * math.cos(4 * math.pi * ph)
        roll = 2.5 * math.sin(2 * math.pi * ph)
    spine_pose(p, pitch=(7 + rear) * (1 - lie), roll=roll, yaw=1.5 * math.sin(2 * math.pi * (walk or 0)),
               lift=lift - 0.12 + rear * 0.02 - 1.0 * lie, sway=sway, breathe=br * 0.8, chest_pitch=2 + rear * 0.5 - 4 * lie)
    if lie > 0:   # deitado: patas recolhidas sob o corpo, pulsos mais abertos
        for k in ("R", "L"):
            feet[k] = (feet[k][0] * (1 + 0.25 * lie), feet[k][1] - 0.25 * lie)
            wrists[k] = (wrists[k][0] * (1 + 0.15 * lie), wrists[k][1] + 0.1 * lie)
    yaw = look + (4 * math.sin(2 * math.pi * walk) if walk is not None else 6 * math.sin(2 * math.pi * t / 4.0))
    neck_pose(p, pitch=-4 + neck_raise + 2 * br + 3 * lie, yaw=yaw * (1 - 0.5 * lie),
              head_dir=Quaternion(Z, math.radians(yaw * 0.6)) @ Vector((0, 1, -0.08 + neck_raise * 0.012)), jaw=jaw)
    tail_pose(p, t, amp_yaw=5 if walk is None else 8, amp_pitch=1.5, speed=0.25 if walk is None else 1.0 / 1.33,
              lift=-2.0 + 4.0 * lie, curl=8 * lie)
    for sfx in ("R", "L"):
        ground_leg(p, sfx, feet[sfx], lifts[sfx], toe_pitch=-18 * lifts[sfx] / 0.32)
    for sfx in ("R", "L"):
        if wing_spread > 0.0:
            p2 = Pose(rig)
            p2.W, p2.root_off = dict(p.W), p.root_off
            ground_wing(p, sfx, wrists[sfx], lifts["W" + sfx])
            gw = {b: p.W[b] for b in p.W if b.endswith("." + sfx) and not b.startswith(("thigh", "shin", "foot", "toe"))}
            fly_wing(p2, sfx, elev=35, sweep=10, elbow=25, wrist=35, spread=0.7)
            for b, wq in gw.items():
                p.W[b] = wq.slerp(p2.W[b], wing_spread)
        else:
            ground_wing(p, sfx, wrists[sfx], lifts["W" + sfx])
    return p


def pose_flight(rig, t, phase=None, glide_turn=0.0, hover=0.0, dive=0.0, flare=0.0, cycle=0.8):
    """phase: fase da batida (0 = asas no alto, 0,45 = fim da descida). None = planando."""
    p = Pose(rig)
    if phase is None:
        osc = math.sin(2 * math.pi * t / 2.0)
        elev = 4 + 1.5 * osc
        sweep, twist, elbow, wrist, spread, camber = -4, 2, 6, 4, 1.0, 4 + osc
        lift = 0.03 * osc
        body_pitch = 0.0
    else:
        ph = phase % 1.0
        if ph < 0.45:     # descida: rápida e com tudo aberto
            s = smooth(ph / 0.45)
            elev = lerp(58, -36, s)
            sweep = 8 * math.sin(math.pi * s)
            twist = -10 * math.sin(math.pi * s)
            elbow = lerp(18, 0, smooth(s * 2))
            wrist = lerp(22, 0, smooth(s * 2))
            spread = 1.0
            camber = 10 * math.sin(math.pi * s)
        else:             # subida: dobra o cotovelo e o pulso para cortar o ar
            s = smooth((ph - 0.45) / 0.55)
            elev = lerp(-36, 58, s)
            sweep = -16 * math.sin(math.pi * s)
            twist = 14 * math.sin(math.pi * s)
            elbow = 38 * math.sin(math.pi * min(s * 1.15, 1.0))
            wrist = 48 * math.sin(math.pi * min(s * 1.1, 1.0))
            spread = 1.0 - 0.4 * math.sin(math.pi * s)
            camber = -8 * math.sin(math.pi * s)
        lift = -0.16 * math.cos(2 * math.pi * (ph - 0.25))
        body_pitch = -3 * math.sin(2 * math.pi * ph)
    # pairar/pousar: corpo de pé, batidas para a frente
    body_pitch = lerp(body_pitch, 32 + body_pitch * 0.5, hover)
    sweep += hover * 18
    elev += flare * 25
    sweep += flare * 15
    twist += flare * 18
    roll_tail = glide_turn
    spine_pose(p, pitch=body_pitch - dive * 12, lift=lift, roll=0.0, chest_pitch=-2 + hover * 4)
    neck_pose(p, pitch=-6 - hover * 18 + dive * 2, yaw=-glide_turn * 14,
              head_dir=Quaternion(Z, math.radians(-glide_turn * 22)) @ Vector((0, 1, -0.12 - dive * 0.25)))
    tail_pose(p, t, amp_yaw=3 if phase is None else 4, amp_pitch=2.5, speed=0.5 if phase is None else 1.0 / cycle,
              lift=-1.5 + hover * 9 - (0 if phase is None else 4 * math.sin(2 * math.pi * (phase - 0.1))),
              curl=-glide_turn * 5.5)
    for sfx in ("R", "L"):
        inner = (glide_turn > 0 and sfx == "R") or (glide_turn < 0 and sfx == "L")
        k = abs(glide_turn) if inner else 0.0
        d_el = dive * 1.0
        fly_wing(p, sfx, elev=elev - 6 * k + d_el * (-6), sweep=sweep - 6 * k - d_el * 38, twist=twist,
                 elbow=elbow + 12 * k + d_el * 62, wrist=wrist + 10 * k + d_el * 78,
                 spread=spread - 0.15 * k - d_el * 0.5, camber=camber)
    fly_legs(p, t, dangle=hover * 0.6, forward=flare)
    return p


# ---------------------------------------------------------------- ações

def new_action(rig, name, frames):
    act = bpy.data.actions.new(name)
    act.use_fake_user = True
    if rig.arm.animation_data is None:
        rig.arm.animation_data_create()
    rig.arm.animation_data.action = act
    act.frame_range = (0, frames)
    act.use_frame_range = True
    return act


def bake_action(rig, name, frames, fn, step=1):
    new_action(rig, name, frames)
    for f in range(0, frames + 1, step):
        rig.key(fn(f / FPS, f), f)
    if frames % step:
        rig.key(fn(frames / FPS, frames), frames)


def create_animations(rig):
    # parado em pé: respira, olha em volta, cauda balança devagar (4 s)
    bake_action(rig, "idle", 120, lambda t, f: pose_ground(rig, t, walk=None), 2)
    # andar em quatro apoios (pulsos das asas como patas da frente)
    bake_action(rig, "lie", 120, lambda t, f: pose_ground(rig, t, None, lie=1.0), 2)
    bake_action(rig, "stand_up", 36, lambda t, f: pose_ground(rig, t, None, lie=1.0 - smooth(f / 36)), 1)
    bake_action(rig, "lie_down", 36, lambda t, f: pose_ground(rig, t, None, lie=smooth(f / 36)), 1)
    bake_action(rig, "walk", 40, lambda t, f: pose_ground(rig, t, walk=f / 40), 1)
    # rugido
    def roar(t, f):
        k = smooth(f / 14) * (1 - smooth((f - 44) / 14))
        jaw = 34 * smooth((f - 10) / 6) * (1 - smooth((f - 40) / 8)) + 3 * math.sin(f * 1.7) * k
        return pose_ground(rig, t, None, 1.0, look=0, neck_raise=26 * k, jaw=jaw, wing_spread=0.55 * k, rear=8 * k)
    bake_action(rig, "roar", 60, roar, 1)
    # batida de asas (0,8 s)
    bake_action(rig, "flap", 24, lambda t, f: pose_flight(rig, t, phase=f / 24), 1)
    # pairar (para pousar): batidas para a frente, corpo de pé, patas soltas
    bake_action(rig, "hover", 21, lambda t, f: pose_flight(rig, t, phase=f / 21, hover=1.0, cycle=0.7), 1)
    # planar (reto e curvas)
    bake_action(rig, "glide", 60, lambda t, f: pose_flight(rig, f / 60 * 2.0, None), 2)
    bake_action(rig, "glide_l", 60, lambda t, f: pose_flight(rig, f / 60 * 2.0, None, glide_turn=-1.0), 2)
    bake_action(rig, "glide_r", 60, lambda t, f: pose_flight(rig, f / 60 * 2.0, None, glide_turn=1.0), 2)
    # mergulho: asas meio fechadas
    bake_action(rig, "dive", 30, lambda t, f: pose_flight(rig, f / 30 * 2.0, None, dive=1.0), 2)

    # decolar: agacha, abre as asas, salta e bate forte (36 quadros; termina como a fase 0 do flap)
    def takeoff(t, f):
        g = pose_ground(rig, t, None)
        crouch = smooth(f / 10) * (1 - smooth((f - 13) / 4))
        g.root_off.z -= 0.42 * crouch
        if f < 12:
            fl = pose_flight(rig, t, phase=0.0)
            k = smooth(f / 11)
            out = g.blend(fl, k * 0.999)
            # pernas continuam no chão (agachadas)
            gl = pose_ground(rig, t, None)
            gl.root_off = out.root_off
            for b in rig.order:
                if b.split(".")[0] in ("thigh", "shin", "foot", "toe"):
                    out.W[b] = g.get(b)
            return out
        fl = pose_flight(rig, t, phase=(f - 12) / 24)
        legs_k = smooth((f - 14) / 12)
        out = fl
        if legs_k < 1:
            ground_like = pose_flight(rig, t, phase=(f - 12) / 24)
            fly_legs(ground_like, t, dangle=1.0 - legs_k * 0.4)
            for b in rig.order:
                if b.split(".")[0] in ("thigh", "shin", "foot", "toe"):
                    out.W[b] = ground_like.get(b).slerp(fl.get(b), legs_k)
        out.root_off = out.root_off * smooth((f - 12) / 6)
        return out
    bake_action(rig, "takeoff", 36, takeoff, 1)

    # pousar: pairando com as asas freando, toca o chão no quadro 15, amortece e recolhe as asas
    def land(t, f):
        if f <= 15:
            return pose_flight(rig, t, phase=(f / 15) * 1.0 % 1.0, hover=1.0, flare=smooth(f / 12))
        g = pose_ground(rig, t, None)
        g.root_off.z -= 0.38 * math.sin(math.pi * min((f - 15) / 18, 1.0))
        fl = pose_flight(rig, t, phase=0.0, hover=1.0, flare=1.0)
        k = smooth((f - 15) / 22)
        out = fl.blend(g, k)
        for b in rig.order:   # pés já no chão desde o toque
            if b.split(".")[0] in ("thigh", "shin", "foot", "toe"):
                out.W[b] = g.get(b)
        out.root_off = g.root_off
        return out
    bake_action(rig, "land", 45, land, 1)
    rig.arm.animation_data.action = None


# ================================================================ montagem

def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.fps = FPS
    arm = build_armature()
    parts = build_body_parts()
    m_r = membrane_panels(1)
    m_l = membrane_panels(-1)
    skin_parts(parts, arm)
    skin_membrane(m_r, "R")
    skin_membrane(m_l, "L")

    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 4
    body = join(parts["skin"], "DragonBody")
    body.data.materials.clear()
    skin_mat, skin_nt = skin_material()
    body.data.materials.append(skin_mat)
    wing_mat, wing_nt = membrane_material()
    m_r.data.materials.append(wing_mat)
    if not FAST:
        mats._smart_uv(body)
        mats._bake(body, skin_nt, 2048, "dragon_skin", 0.45)
        mats._bake(m_r, wing_nt, 1024, "dragon_wing", 0.6)
    m_l.data.materials.append(m_r.data.materials[0])
    wings = join([m_r, m_l], "DragonWings")
    wings.data.materials[0].use_backface_culling = False
    horns = join(parts["horn"], "DragonHorns")
    horns.data.materials.clear()
    horns.data.materials.append(horn_material())
    eyes = join(parts["eye"], "DragonEyes")
    eyes.data.materials.clear()
    eyes.data.materials.append(simple_material("DragonEye", (0.95, 0.55, 0.08), 0.15, emission=(0.5, 0.22, 0.02)))
    saddle = parts["saddle"][0]
    saddle.data.materials.clear()
    saddle.data.materials.append(simple_material("Saddle", (0.27, 0.16, 0.09), 0.7))
    for ob in (body, wings, horns, eyes, saddle):
        ob.parent = arm
        mod = ob.modifiers.new("Armature", "ARMATURE")
        mod.object = arm
    rig = Rig(arm)
    create_animations(rig)
    tris = 0
    for ob in (body, wings, horns, eyes, saddle):
        t = sum(len(p.vertices) - 2 for p in ob.data.polygons)
        tris += t
        print(f"  {ob.name:14s} {t:6d}")
    print("TOTAL triângulos:", tris)
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=OUT, export_format="GLB", export_apply=False, export_animations=True,
        export_skins=True, export_yup=True, export_texcoords=True, export_normals=True,
        export_image_format="AUTO", export_animation_mode="ACTIONS")
    print("Exportado:", OUT)


if __name__ == "__main__":
    main()
