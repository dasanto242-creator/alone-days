"""Gera o CARRO do ALONE DAYS (hatch compacto abandonado) no Blender, por código.

Uso: ~/blender-venv/bin/python tools/character/build_car.py <saida.glb>

Peças exportadas (nós separados no glTF, usados pelo jogo):
  Body          carroceria oca (lata + vidros), com o vão da porta do motorista
  Door_FL       porta do motorista (origem na dobradiça; gira em torno do eixo vertical)
  SteeringWheel volante (origem no centro; gira em torno do próprio eixo Y no Godot)
  Wheel_FL/FR/RL/RR  rodas (origem no centro; giram em X)
  Interior      painel, bancos, assoalho
  Seat, Exit_L  marcadores (empties): onde o motorista senta e onde fica ao sair
Medidas em car_layout.py (as mesmas usadas nas animações de entrar/dirigir).
"""
import math
import os
import sys

import bpy
import bmesh
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import car_layout as L  # noqa: E402
import survivor_materials as mats  # noqa: E402

OUT = sys.argv[-1] if len(sys.argv) > 1 and sys.argv[-1].endswith(".glb") else \
    os.path.join(HERE, "../../assets/models/vehicles/hatch.glb")


def lin(c):
    return tuple(x ** 2.2 for x in c)


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def link(ob):
    bpy.context.scene.collection.objects.link(ob)
    return ob


def select_only(ob):
    for o in bpy.context.scene.objects:
        o.select_set(False)
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob


def apply_mods(ob):
    select_only(ob)
    for m in list(ob.modifiers):
        bpy.ops.object.modifier_apply(modifier=m.name)


def extrude_profile(name, pts, x0, x1):
    """Perfil lateral (y, z) extrudado de x0 a x1."""
    bm = bmesh.new()
    vs = [bm.verts.new((x0, y, z)) for y, z in pts]
    f = bm.faces.new(vs)
    ret = bmesh.ops.extrude_face_region(bm, geom=[f])
    moved = [v for v in ret["geom"] if isinstance(v, bmesh.types.BMVert)]
    bmesh.ops.translate(bm, verts=moved, vec=(x1 - x0, 0, 0))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    return link(bpy.data.objects.new(name, me))


def box(name, center, size, rot=None):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    m = Matrix.Diagonal((*size, 1.0))
    if rot is not None:
        m = rot.to_4x4() @ m
    bmesh.ops.transform(bm, matrix=Matrix.Translation(center) @ m, verts=bm.verts)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    return link(bpy.data.objects.new(name, me))


def lathe(name, profile, segments=24):
    """profile: (raio, x) girado em torno do eixo X (rodas)."""
    bm = bmesh.new()
    rings = []
    for r, x in profile:
        rings.append([bm.verts.new((x, r * math.cos(2 * math.pi * i / segments), r * math.sin(2 * math.pi * i / segments)))
                      for i in range(segments)])
    for a, b in zip(rings, rings[1:]):
        for i in range(segments):
            j = (i + 1) % segments
            bm.faces.new((a[i], a[j], b[j], b[i]))
    bm.faces.new(rings[0])
    bm.faces.new(list(reversed(rings[-1])))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = link(bpy.data.objects.new(name, me))
    for p in ob.data.polygons:
        p.use_smooth = True
    return ob


def torus(name, major, minor, seg=28, sides=10):
    bm = bmesh.new()
    rings = []
    for i in range(seg):
        a = 2 * math.pi * i / seg
        c = Vector((math.cos(a), math.sin(a), 0))
        rings.append([bm.verts.new(c * (major + minor * math.cos(2 * math.pi * j / sides)) +
                                   Vector((0, 0, minor * math.sin(2 * math.pi * j / sides)))) for j in range(sides)])
    for i in range(seg):
        a, b = rings[i], rings[(i + 1) % seg]
        for j in range(sides):
            k = (j + 1) % sides
            bm.faces.new((a[j], a[k], b[k], b[j]))
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = link(bpy.data.objects.new(name, me))
    for p in ob.data.polygons:
        p.use_smooth = True
    return ob


def boolean(target, cutter, op):
    m = target.modifiers.new("Bool", "BOOLEAN")
    m.object = cutter
    m.operation = op
    m.solver = "EXACT"
    apply_mods(target)


def join(obs, name):
    select_only(obs[0])
    for o in obs[1:]:
        o.select_set(True)
    bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    ob.name = name
    ob.data.name = name
    return ob


def set_origin(ob, point):
    """Move a origem do objeto para `point` (mundo) sem mexer na geometria."""
    off = Vector(point) - ob.location
    ob.data.transform(Matrix.Translation(-off))
    ob.location = Vector(point)


def material(name, color, rough, metal=0.0, emission=None, alpha=1.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*lin(color), 1.0)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    if emission:
        b.inputs["Emission Color"].default_value = (*lin(emission), 1.0)
        b.inputs["Emission Strength"].default_value = 2.0
    if alpha < 1.0:
        b.inputs["Alpha"].default_value = alpha
        m.surface_render_method = "BLENDED"
    return m


# ---------------------------------------------------------------- carroceria

def arch(yc, r, zc, start_deg, end_deg, n=10):
    return [(yc + r * math.cos(math.radians(start_deg + (end_deg - start_deg) * i / n)),
             zc + r * math.sin(math.radians(start_deg + (end_deg - start_deg) * i / n))) for i in range(n + 1)]


def lower_profile():
    r = L.WHEEL_RADIUS + 0.1
    zc = L.WHEEL_RADIUS
    pts = [(-2.0, 0.27), (-2.06, 0.42), (-2.06, 0.8), (-1.96, 0.97), (-1.0, 0.98), (0.95, 0.94), (1.6, 0.88),
           (1.95, 0.8), (2.06, 0.62), (2.05, 0.38), (1.98, 0.27)]
    bottom = [(L.AXLE_FRONT + r + 0.02, 0.27)] + arch(L.AXLE_FRONT, r, zc, -8, 188)[1:-1] + \
        [(L.AXLE_FRONT - r - 0.02, 0.27), (L.AXLE_REAR + r + 0.02, 0.27)] + \
        arch(L.AXLE_REAR, r, zc, -8, 188)[1:-1] + [(L.AXLE_REAR - r - 0.02, 0.27)]
    return pts + bottom


def cabin_profile():
    return [(0.98, 0.9), (0.32, 1.5), (0.12, 1.56), (-1.3, 1.58), (-1.55, 1.52), (-1.92, 1.0), (-1.92, 0.9)]


def build_body():
    lower = extrude_profile("Lower", lower_profile(), -L.WIDTH / 2, L.WIDTH / 2)
    cabin = extrude_profile("Cabin", cabin_profile(), -0.75, 0.75)
    for v in cabin.data.vertices:  # teto mais estreito que a linha da cintura
        if v.co.z > 1.3:
            v.co.x *= 0.9
    for ob, w in ((lower, 0.05), (cabin, 0.04)):
        m = ob.modifiers.new("Bevel", "BEVEL")
        m.width = w
        m.segments = 3
        m.limit_method = "ANGLE"
        m.angle_limit = math.radians(25)
        apply_mods(ob)
    boolean(lower, cabin, "UNION")
    bpy.data.objects.remove(cabin)
    body = lower
    body.name = "Body"
    # interior oco: caixa do habitáculo + cópia encolhida da cabine (vidros com espessura)
    inner_box = box("InnerBox", (0, -0.42, 0.66), (1.58, 2.7, 0.7))
    inner_cab = extrude_profile("InnerCab", [(0.86, 0.86), (0.28, 1.45), (0.1, 1.5), (-1.25, 1.52),
                                             (-1.48, 1.47), (-1.8, 0.98), (-1.8, 0.86)], -0.67, 0.67)
    for v in inner_cab.data.vertices:
        if v.co.z > 1.3:
            v.co.x *= 0.9
    boolean(inner_box, inner_cab, "UNION")
    bpy.data.objects.remove(inner_cab)
    boolean(body, inner_box, "DIFFERENCE")
    bpy.data.objects.remove(inner_box)
    # porta do motorista: recorta da carroceria e vira peça separada
    hx, hy = L.DOOR_HINGE
    z0, z1 = L.DOOR_Z
    cut = box("DoorCut", (-0.85, (hy + L.DOOR_REAR_Y) / 2, (z0 + z1) / 2), (0.4, hy - L.DOOR_REAR_Y, z1 - z0))
    door = body.copy()
    door.data = body.data.copy()
    link(door)
    door.name = "Door_FL"
    boolean(door, cut, "INTERSECT")
    cut2 = box("DoorCut2", (-0.85, (hy + L.DOOR_REAR_Y) / 2, (z0 + z1) / 2),
               (0.42, hy - L.DOOR_REAR_Y + 0.012, z1 - z0 + 0.012))
    boolean(body, cut2, "DIFFERENCE")
    for c in (cut, cut2):
        bpy.data.objects.remove(c)
    return body, door


def assign_body_materials(ob, paint, glass, trim):
    ob.data.materials.clear()
    for m in (paint, glass, trim):
        ob.data.materials.append(m)
    for p in ob.data.polygons:
        c = p.center
        n = p.normal
        is_glass = 1.0 < c.z < 1.5 and not (-0.7 < c.y < -0.55) and c.y > -1.6
        if is_glass and abs(c.x) > 0.62 and n.y > 0.3:
            is_glass = False   # coluna A
        if is_glass and c.z > 1.45 and n.z > 0.6:
            is_glass = False   # teto
        if c.y < -1.5 and 1.0 < c.z < 1.5 and n.y < -0.5:
            is_glass = True    # vidro traseiro
        if is_glass:
            p.material_index = 1
        elif c.z < 0.42 or (c.z < 0.55 and abs(c.y) > 1.85) or (c.z < 0.8 and n.z < -0.3):
            p.material_index = 2   # para-choques, saias e caixas de roda pretos
        else:
            p.material_index = 0
        p.use_smooth = True


def paint_material():
    """Pintura azul desbotada com sujeira na parte de baixo e manchas de ferrugem (vai virar textura)."""
    mat = bpy.data.materials.new("Paint")
    nt = mats._nodes(mat)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    nt.links.new(bsdf.outputs[0], out.inputs[0])
    vec = mats._coord(nt)
    base = lin((0.22, 0.33, 0.42))
    faded = lin((0.42, 0.48, 0.5))
    col = mats._mix(nt, mats._noise(nt, vec, 1.5, 3.0, 0.5), base, faded)
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(vec, sep.inputs[0])
    # sujeira: mais forte perto do chão
    low = mats._math(nt, "SUBTRACT", 1.0, mats._math(nt, "MULTIPLY", sep.outputs["Z"], 1.6))
    dirt_amt = mats._math(nt, "MULTIPLY", mats._math(nt, "MAXIMUM", low, 0.0), mats._noise(nt, vec, 6.0, 6.0, 0.6))
    col = mats._mix(nt, mats._math(nt, "MULTIPLY", dirt_amt, 1.4), col, lin((0.3, 0.26, 0.2)))
    rust = mats._math(nt, "GREATER_THAN", mats._noise(nt, vec, 9.0, 8.0, 0.7), 0.66)
    col = mats._mix(nt, mats._math(nt, "MULTIPLY", rust, 0.9), col, lin((0.36, 0.17, 0.07)))
    nt.links.new(col, bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.55
    return mat, nt


# ---------------------------------------------------------------- rodas, volante, interior

def build_wheel(name, center, left):
    r = L.WHEEL_RADIUS
    w = L.WHEEL_WIDTH / 2
    tire = lathe(name + "_t", [(r * 0.62, -w), (r * 0.9, -w), (r * 0.97, -w * 0.8), (r, -w * 0.4), (r, w * 0.4),
                               (r * 0.97, w * 0.8), (r * 0.9, w), (r * 0.62, w)], 28)
    rim = lathe(name + "_r", [(0.0, w * 0.55), (r * 0.2, w * 0.6), (r * 0.25, w * 0.35), (r * 0.6, w * 0.4),
                              (r * 0.64, w * 0.1), (r * 0.64, -w * 0.6), (0.0, -w * 0.6)], 20)
    tire.data.materials.append(MAT["tire"])
    rim.data.materials.append(MAT["rim"])
    ob = join([tire, rim], name)
    if left:
        ob.data.transform(Matrix.Rotation(math.pi, 4, "Z"))  # aro virado para fora
    ob.location = center
    return ob


def build_steering_wheel():
    ring = torus("SW_ring", L.STEER_RADIUS, 0.016)
    hub = lathe("SW_hub", [(0.0, -0.03), (0.05, -0.03), (0.055, 0.0), (0.04, 0.025), (0.0, 0.03)], 14)
    hub.data.transform(Matrix.Rotation(math.pi / 2, 4, "Y"))  # eixo do cubo em Z
    spokes = []
    for a in (90, 210, 330):
        r = math.radians(a)
        s = box("SW_s%d" % a, (math.cos(r) * L.STEER_RADIUS * 0.5, math.sin(r) * L.STEER_RADIUS * 0.5, -0.005),
                (L.STEER_RADIUS * 0.85, 0.035, 0.014), Matrix.Rotation(r, 3, "Z"))
        spokes.append(s)
    col = lathe("SW_col", [(0.022, -0.3), (0.022, -0.02)], 10)
    col.data.transform(Matrix.Rotation(math.pi / 2, 4, "Y"))
    for o in [ring, hub, col] + spokes:
        o.data.materials.append(MAT["plastic"])
    sw = join([ring, hub, col] + spokes, "SteeringWheel")
    sw.location = L.STEER_CENTER
    sw.rotation_euler = (math.radians(L.STEER_TILT_DEG), 0, 0)
    return sw


def build_interior():
    parts = []
    parts.append(box("Dash", (0, 0.72, 0.9), (1.5, 0.5, 0.3)))
    parts.append(box("DashTop", (0, 0.62, 1.04), (1.5, 0.3, 0.06), Matrix.Rotation(math.radians(-12), 3, "X")))
    parts.append(box("Floor", (0, -0.3, 0.31), (1.5, 2.6, 0.03)))
    sx, sy, sz = L.SEAT
    for x in (sx, -sx):
        parts.append(box("Cushion", (x, sy - 0.08, sz + 0.42), (0.5, 0.52, 0.12),
                         Matrix.Rotation(math.radians(-6), 3, "X")))
        parts.append(box("Back", (x, sy - 0.42, sz + 0.82), (0.5, 0.12, 0.7), Matrix.Rotation(math.radians(-14), 3, "X")))
        parts.append(box("Head", (x, sy - 0.52, sz + 1.28), (0.26, 0.1, 0.18), Matrix.Rotation(math.radians(-14), 3, "X")))
    parts.append(box("RearSeat", (0, -1.25, 0.55), (1.4, 0.5, 0.14)))
    parts.append(box("RearBack", (0, -1.52, 0.85), (1.4, 0.12, 0.6), Matrix.Rotation(math.radians(-12), 3, "X")))
    for p in parts:
        p.data.materials.append(MAT["seat"] if p.name.startswith(("Cushion", "Back", "Head", "Rear")) else MAT["plastic"])
    return join(parts, "Interior")


def build_details(door):
    """Faróis, lanternas, grade, placa, maçaneta e retrovisor (o esquerdo vai na porta)."""
    det = []
    for x in (-0.62, 0.62):
        det.append((box("HeadL", (x, 2.04, 0.7), (0.34, 0.06, 0.13)), MAT["headlight"]))
        det.append((box("TailL", (x, -2.05, 0.82), (0.26, 0.05, 0.14)), MAT["taillight"]))
    det.append((box("Grille", (0, 2.06, 0.56), (0.8, 0.04, 0.16)), MAT["plastic"]))
    det.append((box("PlateF", (0, 2.08, 0.38), (0.4, 0.02, 0.12)), MAT["plate"]))
    det.append((box("PlateR", (0, -2.08, 0.55), (0.4, 0.02, 0.12)), MAT["plate"]))
    det.append((box("MirrorR", (0.95, 0.82, 1.05), (0.16, 0.08, 0.1)), MAT["plastic"]))
    for ob, m in det:
        ob.data.materials.append(m)
    hx, hy = L.DOOR_HINGE
    handle = box("Handle", Vector(L.HANDLE_OUT) + Vector((-0.012, 0, 0)), (0.025, 0.14, 0.03))
    mirror = box("MirrorL", (-0.95, 0.82, 1.05), (0.16, 0.08, 0.1))
    for o in (handle, mirror):
        o.data.materials.append(MAT["plastic"])
    return join([o for o, _ in det], "Details"), handle, mirror


MAT = {}


def main():
    reset()
    MAT.update({
        "glass": material("Glass", (0.12, 0.15, 0.17), 0.08, 0.0, alpha=0.45),
        "trim": material("Trim", (0.06, 0.06, 0.06), 0.7),
        "tire": material("Tire", (0.05, 0.05, 0.05), 0.92),
        "rim": material("Rim", (0.45, 0.45, 0.46), 0.4, 0.85),
        "plastic": material("Plastic", (0.07, 0.07, 0.075), 0.6),
        "seat": material("SeatFabric", (0.16, 0.15, 0.14), 0.95),
        "headlight": material("Headlight", (0.85, 0.85, 0.8), 0.1, emission=(0.4, 0.4, 0.35)),
        "taillight": material("Taillight", (0.5, 0.04, 0.03), 0.2, emission=(0.25, 0.0, 0.0)),
        "plate": material("Plate", (0.85, 0.85, 0.82), 0.5),
    })
    body, door = build_body()
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 4
    for ob, size, tag in ((body, 1024, "car_paint"), (door, 512, "car_door")):
        body_paint, nt = paint_material()
        assign_body_materials(ob, body_paint, MAT["glass"], MAT["trim"])
        # separa a lataria (material 0) para assar a pintura com sujeira e ferrugem numa textura
        select_only(ob)
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.select_all(action="DESELECT")
        ob.active_material_index = 0
        bpy.ops.object.material_slot_select()
        bpy.ops.mesh.separate(type="SELECTED")
        bpy.ops.object.mode_set(mode="OBJECT")
        painted = [o for o in bpy.context.selected_objects if o != ob][0]
        painted.data.materials.clear()
        painted.data.materials.append(body_paint)
        for poly in painted.data.polygons:
            poly.material_index = 0
        mats._smart_uv(painted)
        mats._bake(painted, nt, size, tag, 0.5)
        joined = join([ob, painted], ob.name)
        if ob is body:
            body = joined
        else:
            door = joined
    hx, hy = L.DOOR_HINGE
    set_origin(door, (hx, hy, 0.0))
    details, handle, mirror = build_details(door)
    door_parts = join([door, handle, mirror], "Door_FL")
    set_origin(door_parts, (hx, hy, 0.0))
    interior = build_interior()
    sw = build_steering_wheel()
    wheels = []
    for name, y in (("F", L.AXLE_FRONT), ("R", L.AXLE_REAR)):
        for side, x in (("L", -L.TRACK / 2), ("R", L.TRACK / 2)):
            wheels.append(build_wheel(f"Wheel_{name}{side}", (x, y, L.WHEEL_RADIUS), side == "L"))
    body_all = join([body, details], "Body")
    for name, p in (("Seat", L.SEAT), ("Exit_L", L.EXIT)):
        e = bpy.data.objects.new(name, None)
        e.location = p
        link(e)
    tris = 0
    for ob in bpy.context.scene.objects:
        if ob.type == "MESH":
            t = sum(len(p.vertices) - 2 for p in ob.data.polygons)
            tris += t
            print(f"  {ob.name:14s} {t:6d}")
    print("TOTAL triângulos:", tris)
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", export_yup=True, export_apply=True)
    print("Exportado:", OUT)
    del body_all, door_parts, interior, sw, wheels


if __name__ == "__main__":
    main()
