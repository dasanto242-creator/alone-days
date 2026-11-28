"""Gera a vegetação e as pedras do ALONE DAYS no Blender, por código.

Uso: ~/blender-venv/bin/python tools/character/build_nature.py <pasta de saída>

Saídas (assets/models/nature/):
  pine_a.glb, pine_b.glb  pinheiros: tronco (material "Bark") + galhos em cartões de agulhas
                          (material "Needles", usa a textura com transparência no jogo)
  pine_far.png            imagem do pinheiro (para os de longe: 2 cartões cruzados)
  rock_a.glb, rock_b.glb  pedras (material "Rock")
Os materiais de verdade (texturas, vento) são aplicados no Godot (tools/build_scenes.gd).
"""
import math
import os
import random
import sys

import bpy
import bmesh
from mathutils import Matrix, Vector, noise

OUT = sys.argv[-1] if len(sys.argv) > 1 and not sys.argv[-1].endswith(".py") else \
    os.path.join(os.path.dirname(__file__), "../../assets/models/nature")
TEX = os.path.join(os.path.dirname(os.path.abspath(__file__)), "../../assets/textures/world")


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def link(ob):
    bpy.context.scene.collection.objects.link(ob)
    return ob


def material(name, color):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    m.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (*color, 1.0)
    return m


def trunk_mesh(bm, height, r0, r1, seg=10, rings=9, lean=0.0, seed=0):
    rnd = random.Random(seed)
    uv = bm.loops.layers.uv.verify()
    verts = []
    for j in range(rings + 1):
        t = j / rings
        z = height * t
        r = r0 + (r1 - r0) * (t ** 0.8)
        if j == 0:
            r *= 1.35   # base alargada (raízes)
        off = Vector((lean * t * t, 0.15 * math.sin(t * 5 + seed) * t, 0))
        ring = []
        for k in range(seg + 1):
            a = 2 * math.pi * k / seg
            rr = r * (1 + 0.06 * noise.noise(Vector((math.cos(a) * 2, math.sin(a) * 2, z * 0.7 + seed))))
            ring.append(bm.verts.new((off.x + math.cos(a) * rr, off.y + math.sin(a) * rr, z)))
        verts.append(ring)
    for j in range(rings):
        for k in range(seg):
            f = bm.faces.new((verts[j][k], verts[j][k + 1], verts[j + 1][k + 1], verts[j + 1][k]))
            f.material_index = 0
            f.smooth = True
            for loop, (uu, vv) in zip(f.loops, ((k / seg, j / rings), ((k + 1) / seg, j / rings),
                                                ((k + 1) / seg, (j + 1) / rings), (k / seg, (j + 1) / rings))):
                loop[uv].uv = (uu * 2.0, vv * height / 1.6)
    return lambda t: Vector((lean * t * t, 0.15 * math.sin(t * 5 + seed) * t, height * t))


def card(bm, base, direction, length, width, droop, roll, uv, idx=1):
    """Galho: cartão curvado (3 seções) de base até a ponta, com a textura de agulhas."""
    d = direction.normalized()
    side = d.cross(Vector((0, 0, 1)))
    if side.length < 1e-4:
        side = Vector((1, 0, 0))
    side.normalize()
    side = Matrix.Rotation(roll, 3, d) @ side
    rows = []
    for i in range(4):
        t = i / 3
        p = base + d * length * t + Vector((0, 0, -droop * length * t * t))
        w = width * (0.35 + 0.65 * math.sin(math.pi * min(t * 1.15, 1.0)) + 0.1 * (1 - t))
        rows.append((bm.verts.new(p - side * w * 0.5), bm.verts.new(p + side * w * 0.5), t))
    for i in range(3):
        a0, a1, t0 = rows[i]
        b0, b1, t1 = rows[i + 1]
        f = bm.faces.new((a0, a1, b1, b0))
        f.material_index = idx
        f.smooth = True
        for loop, (uu, vv) in zip(f.loops, ((0, t0), (1, t0), (1, t1), (0, t1))):
            loop[uv].uv = (uu, 0.03 + vv * 0.93)


def pine(name, height, seed, whorls, spread):
    rnd = random.Random(seed)
    bm = bmesh.new()
    uv = bm.loops.layers.uv.verify()
    axis = trunk_mesh(bm, height, 0.27 * height / 9.0, 0.03, seg=9, rings=8, lean=rnd.uniform(-0.3, 0.3), seed=seed)
    start = 0.2
    for w in range(whorls):
        t = start + (1 - start) * (w / whorls) ** 0.92
        center = axis(t)
        n = 7 if t < 0.55 else 6 if t < 0.8 else 4
        rot0 = rnd.uniform(0, 2 * math.pi)
        length = spread * (1.06 - t) ** 0.85 + 0.35
        for b in range(n):
            a = rot0 + 2 * math.pi * b / n + rnd.uniform(-0.3, 0.3)
            d = Vector((math.cos(a), math.sin(a), rnd.uniform(-0.05, 0.25)))
            ln = length * rnd.uniform(0.85, 1.12)
            base = center + Vector((math.cos(a), math.sin(a), 0)) * 0.05
            card(bm, base, d, ln, ln * 1.1, 0.28, 0.0, uv)
            card(bm, base + Vector((0, 0, 0.05)), d, ln * 0.92, ln * 0.6, 0.22, math.pi * 0.5, uv)
    # ponta (broto) com dois cartões verticais
    top = axis(1.0)
    for a in (0.0, math.pi * 0.5):
        d = Vector((0, 0, 1))
        s = Vector((math.cos(a), math.sin(a), 0))
        v0 = bm.verts.new(top - s * 0.45 + Vector((0, 0, -0.9)))
        v1 = bm.verts.new(top + s * 0.45 + Vector((0, 0, -0.9)))
        v2 = bm.verts.new(top + s * 0.06 + Vector((0, 0, 0.5)))
        v3 = bm.verts.new(top - s * 0.06 + Vector((0, 0, 0.5)))
        f = bm.faces.new((v0, v1, v2, v3))
        f.material_index = 1
        for loop, (uu, vv) in zip(f.loops, ((0, 0.03), (1, 0.03), (0.6, 0.96), (0.4, 0.96))):
            loop[uv].uv = (uu, vv)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = link(bpy.data.objects.new(name, me))
    ob.data.materials.append(MATS["Bark"])
    ob.data.materials.append(MATS["Needles"])
    return ob


def rock(name, seed, size):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=3, radius=1.0)
    ob = bpy.context.active_object
    ob.name = name
    me = ob.data
    off = Vector((seed * 3.1, seed * 1.7, seed * 2.3))
    for v in me.vertices:
        p = v.co
        n1 = noise.fractal(p * 0.9 + off, 0.6, 2.0, 4)
        n2 = noise.ridged_multi_fractal(p * 1.7 + off, 0.8, 2.0, 3, 1.0, 2.0)
        r = 1.0 + 0.32 * n1 + 0.08 * n2
        q = p * r
        q.z = q.z * 0.62 if q.z > 0 else q.z * 0.35   # achatada, enterrada
        v.co = Vector((q.x * size[0], q.y * size[1], q.z * size[2]))
    for poly in me.polygons:
        poly.use_smooth = True
    bpy.ops.object.shade_auto_smooth(angle=math.radians(50))
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=1.15)
    bpy.ops.object.mode_set(mode="OBJECT")
    ob.data.materials.append(MATS["Rock"])
    return ob


def export(ob, path):
    for o in bpy.context.scene.objects:
        o.select_set(False)
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_yup=True,
                              export_apply=True, export_materials="PLACEHOLDER")
    print("Exportado:", path)


def render_far(ob, path):
    """Imagem lateral do pinheiro com fundo transparente (para os cartões de longe)."""
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE" if "BLENDER_EEVEE" in [e.identifier for e in bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items] else "CYCLES"
    if scene.render.engine == "CYCLES":
        scene.cycles.samples = 16
        scene.cycles.device = "CPU"
    scene.render.film_transparent = True
    scene.render.resolution_x = 256
    scene.render.resolution_y = 512
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    # materiais com as texturas de verdade para o render
    for mname, tex, alpha in (("Bark", "bark_albedo.png", False), ("Needles", "pine_needles.png", True)):
        m = MATS[mname]
        nt = m.node_tree
        bsdf = nt.nodes["Principled BSDF"]
        img = nt.nodes.new("ShaderNodeTexImage")
        img.image = bpy.data.images.load(os.path.join(TEX, tex))
        nt.links.new(img.outputs["Color"], bsdf.inputs["Base Color"])
        if alpha:
            nt.links.new(img.outputs["Alpha"], bsdf.inputs["Alpha"])
            m.blend_method = "CLIP" if hasattr(m, "blend_method") else m.blend_method
        bsdf.inputs["Roughness"].default_value = 0.8
    h = ob.dimensions.z
    cam_data = bpy.data.cameras.new("cam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = h * 1.04
    cam = link(bpy.data.objects.new("cam", cam_data))
    cam.location = (0, -30, h * 0.5)
    cam.rotation_euler = (math.radians(90), 0, 0)
    scene.camera = cam
    sun = link(bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN")))
    sun.data.energy = 3.5
    sun.rotation_euler = (math.radians(50), 0, math.radians(30))
    world = bpy.data.worlds.new("w")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.55, 0.6, 0.65, 1)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.9
    scene.world = world
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    print("Imagem:", path, "altura", h)


MATS = {}


def main():
    reset()
    os.makedirs(OUT, exist_ok=True)
    MATS["Bark"] = material("Bark", (0.25, 0.18, 0.12))
    MATS["Needles"] = material("Needles", (0.12, 0.2, 0.09))
    MATS["Rock"] = material("Rock", (0.45, 0.44, 0.42))
    a = pine("PineA", 9.5, 3, 13, 2.5)
    b = pine("PineB", 12.5, 7, 15, 2.2)
    for ob in (a, b):
        t = sum(len(p.vertices) - 2 for p in ob.data.polygons)
        print(f"  {ob.name}: {t} triângulos")
    export(a, os.path.join(OUT, "pine_a.glb"))
    export(b, os.path.join(OUT, "pine_b.glb"))
    r1 = rock("RockA", 1, (1.0, 0.8, 0.8))
    r2 = rock("RockB", 2, (1.4, 1.0, 1.1))
    export(r1, os.path.join(OUT, "rock_a.glb"))
    export(r2, os.path.join(OUT, "rock_b.glb"))
    for ob in (r1, r2, b):
        ob.hide_render = True
    render_far(a, os.path.join(OUT, "pine_far.png"))


if __name__ == "__main__":
    main()
