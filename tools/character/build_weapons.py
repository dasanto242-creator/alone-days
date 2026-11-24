"""Modelos 3D das armas e munição do ALONE DAYS, gerados por código no Blender.

Uso: ~/blender-venv/bin/python tools/character/build_weapons.py <pasta de saída dos .glb> <pasta dos ícones>

Convenção de cada arma (no Blender): origem = centro da empunhadura (onde a mão fecha),
+Z = eixo do polegar (o cabo atravessa o punho nessa direção; taco/chave crescem para +Z),
+Y = frente (cano da pistola). No Godot isso vira: +Y = polegar, -Z = frente.
"""
import math
import os
import sys

import bpy  # precisa vir antes de bmesh/mathutils
import bmesh
from mathutils import Matrix, Vector

OUT = sys.argv[-2] if len(sys.argv) > 2 else "assets/models/weapons"
ICONS = sys.argv[-1] if len(sys.argv) > 2 else "assets/icons/items"


def lin(c):
    return tuple(x ** 2.2 for x in c)


def material(name, color, rough, metal=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*lin(color), 1.0)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    return m


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


class Builder:
    """Junta várias peças (cada uma com seu material) num único objeto."""

    def __init__(self, name):
        self.bm = bmesh.new()
        self.name = name
        self.mats = []

    def _mat_index(self, mat):
        if mat not in self.mats:
            self.mats.append(mat)
        return self.mats.index(mat)

    def _finish_part(self, verts, mat, bevel=0.0, segments=2):
        idx = self._mat_index(mat)
        faces = {f for v in verts for f in v.link_faces}
        for f in faces:
            f.material_index = idx
            f.smooth = True
        if bevel > 0:
            edges = list({e for v in verts for e in v.link_edges})
            bmesh.ops.bevel(self.bm, geom=edges, offset=bevel, segments=segments, affect="EDGES", profile=0.5)

    def box(self, center, size, mat, bevel=0.002, rot=None):
        geom = bmesh.ops.create_cube(self.bm, size=1.0)
        vs = geom["verts"]
        r = rot if rot is not None else Matrix.Identity(3)
        for v in vs:
            local = Vector((v.co.x * size[0], v.co.y * size[1], v.co.z * size[2]))
            v.co = r @ local + Vector(center)
        self._finish_part(vs, mat, bevel)
        return vs

    def lathe(self, profile, mat, segments=16, axis_rot=None, offset=Vector()):
        """profile: lista de (raio, z). Gira em torno de Z."""
        rings = []
        for r, z in profile:
            ring = []
            for i in range(segments):
                a = 2 * math.pi * i / segments
                co = Vector((r * math.cos(a), r * math.sin(a), z))
                if axis_rot is not None:
                    co = axis_rot @ co
                ring.append(self.bm.verts.new(co + offset))
            rings.append(ring)
        allv = [v for ring in rings for v in ring]
        for a, b in zip(rings, rings[1:]):
            for i in range(segments):
                j = (i + 1) % segments
                self.bm.faces.new((a[i], a[j], b[j], b[i]))
        for ring, flip in ((rings[0], True), (rings[-1], False)):
            f = self.bm.faces.new(list(reversed(ring)) if flip else ring)
        self.bm.normal_update()
        self._finish_part(allv, mat)
        return allv

    def cylinder(self, center, radius, depth, mat, axis="Z", segments=12):
        rot = {"Z": Matrix.Identity(3), "X": Matrix.Rotation(math.pi / 2, 3, "Y"),
               "Y": Matrix.Rotation(math.pi / 2, 3, "X")}[axis]
        return self.lathe([(radius, -depth / 2), (radius, depth / 2)], mat, segments, rot, Vector(center))

    def build(self):
        bmesh.ops.recalc_face_normals(self.bm, faces=self.bm.faces[:])
        me = bpy.data.meshes.new(self.name)
        self.bm.to_mesh(me)
        self.bm.free()
        for m in self.mats:
            me.materials.append(m)
        ob = bpy.data.objects.new(self.name, me)
        bpy.context.scene.collection.objects.link(ob)
        return ob


# ---------------------------------------------------------------- armas

def baseball_bat():
    wood = material("Madeira", (0.62, 0.45, 0.28), 0.55)
    tape = material("Fita", (0.08, 0.08, 0.08), 0.9)
    dark = material("MadeiraEscura", (0.35, 0.22, 0.13), 0.6)
    b = Builder("BaseballBat")
    # pomo (knob), cabo com fita, afunilamento e corpo do taco
    b.lathe([(0.0, -0.085), (0.02, -0.084), (0.028, -0.078), (0.026, -0.07), (0.014, -0.064)], dark, 20)
    b.lathe([(0.0135, -0.066), (0.0135, 0.16)], tape, 16)
    b.lathe([(0.0128, 0.155), (0.0132, 0.25), (0.017, 0.36), (0.026, 0.46), (0.032, 0.55), (0.034, 0.65),
             (0.0335, 0.73), (0.03, 0.755), (0.02, 0.763), (0.0, 0.765)], wood, 20)
    # marcas de uso (manchas escuras) feitas como anéis finos
    for z in (0.52, 0.61):
        b.lathe([(0.0342, z), (0.0342, z + 0.006)], dark, 20)
    ob = b.build()
    ob.data.transform(Matrix.Translation((0, 0, -0.1)))  # origem = mão direita; a esquerda fica 9 cm abaixo
    return ob


def pipe_wrench():
    red = material("PinturaVermelha", (0.55, 0.08, 0.06), 0.45, 0.2)
    steel = material("Aco", (0.45, 0.45, 0.47), 0.4, 0.95)
    dark_steel = material("AcoEscuro", (0.2, 0.2, 0.21), 0.5, 0.9)
    b = Builder("PipeWrench")
    # cabo em perfil "I"
    b.box((0, 0, 0.08), (0.02, 0.034, 0.3), red, 0.004)
    b.box((0, 0, 0.08), (0.032, 0.01, 0.3), red, 0.003)
    b.cylinder((0, 0, -0.06), 0.007, 0.034, dark_steel, "X")  # furo de pendurar
    # corpo da cabeça (moldura de aço)
    b.box((0, 0.004, 0.27), (0.042, 0.05, 0.09), steel, 0.004)
    # mandíbula fixa (inferior) com dentes
    b.box((0, 0.05, 0.3), (0.036, 0.075, 0.03), dark_steel, 0.004)
    for i in range(6):
        b.box((0, 0.024 + i * 0.01, 0.318), (0.035, 0.005, 0.008), steel, 0.0)
    # mandíbula móvel em gancho (superior) com dentes
    b.box((0, -0.008, 0.35), (0.03, 0.022, 0.09), dark_steel, 0.004)
    b.box((0, 0.042, 0.388), (0.034, 0.08, 0.028), dark_steel, 0.004)
    for i in range(6):
        b.box((0, 0.024 + i * 0.01, 0.37), (0.033, 0.005, 0.008), steel, 0.0)
    # porca de ajuste serrilhada
    b.lathe([(0.0, 0.252), (0.024, 0.253), (0.026, 0.26), (0.026, 0.282), (0.024, 0.289), (0.0, 0.29)],
            steel, 24, offset=Vector((0, -0.024, 0)))
    for i in range(12):
        a = 2 * math.pi * i / 12
        b.box((math.cos(a) * 0.026, -0.024 + math.sin(a) * 0.026, 0.271), (0.004, 0.004, 0.03), steel, 0.0)
    ob = b.build()
    ob.data.transform(Matrix.Translation((0, 0, -0.11)))
    return ob


def pistol():
    poly = material("Polimero", (0.07, 0.07, 0.075), 0.65)
    slide_m = material("Ferrolho", (0.12, 0.12, 0.13), 0.35, 0.85)
    metal = material("MetalEscuro", (0.25, 0.25, 0.26), 0.4, 0.9)
    b = Builder("Pistol")
    tilt = Matrix.Rotation(math.radians(-16), 3, "X")  # empunhadura inclinada para trás
    # empunhadura com textura (faixas), base do carregador
    b.box((0, -0.004, -0.01), (0.03, 0.046, 0.105), poly, 0.006, tilt)
    b.box((0, -0.02, -0.066), (0.032, 0.05, 0.01), metal, 0.002, tilt)
    # armação (frame) e guarda-mato
    b.box((0, 0.052, 0.055), (0.028, 0.15, 0.022), poly, 0.004)
    b.box((0, 0.058, 0.022), (0.022, 0.006, 0.042), poly, 0.002)     # frente do guarda-mato
    b.box((0, 0.035, 0.003), (0.022, 0.05, 0.006), poly, 0.002)      # base do guarda-mato
    b.box((0, 0.024, 0.028), (0.006, 0.006, 0.022), metal, 0.001)    # gatilho
    # ferrolho (slide) com serrilhado traseiro e janela de ejeção
    b.box((0, 0.05, 0.083), (0.026, 0.19, 0.034), slide_m, 0.003)
    for i in range(6):
        b.box((0, -0.03 + i * 0.006, 0.083), (0.0265, 0.002, 0.028), metal, 0.0)
    b.box((-0.0125, 0.07, 0.088), (0.003, 0.04, 0.014), metal, 0.0)
    b.cylinder((0, 0.146, 0.08), 0.0065, 0.006, metal, "Y")          # boca do cano
    # miras
    b.box((0, 0.135, 0.103), (0.004, 0.006, 0.006), metal, 0.0)
    b.box((0, -0.035, 0.103), (0.018, 0.006, 0.007), metal, 0.0)
    ob = b.build()
    muzzle = bpy.data.objects.new("Muzzle", None)
    muzzle.location = (0, 0.152, 0.08)
    muzzle.parent = ob
    bpy.context.scene.collection.objects.link(muzzle)
    return ob


def ammo_box():
    card = material("Papelao", (0.42, 0.3, 0.16), 0.85)
    print_m = material("Faixa", (0.6, 0.55, 0.35), 0.8)
    b = Builder("AmmoBox")
    b.box((0, 0, 0.02), (0.08, 0.055, 0.04), card, 0.002)
    b.box((0, -0.0276, 0.02), (0.06, 0.001, 0.016), print_m, 0.0)
    return b.build()


# ---------------------------------------------------------------- exportação e ícones

def export(ob, path):
    for o in bpy.context.scene.objects:
        o.select_set(o == ob or o.parent == ob)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_yup=True,
                              export_apply=True)
    print("Exportado:", path)


def render_icon(ob, path, view):
    """Renderiza um ícone 128x128 com fundo transparente e contorno claro (estilo da HUD)."""
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 24
    scene.render.film_transparent = True
    scene.render.resolution_x = 128
    scene.render.resolution_y = 128
    world = bpy.data.worlds.new("W")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 1.4
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.8, 0.8, 0.78, 1)
    scene.world = world
    bbox = [ob.matrix_world @ Vector(c) for c in ob.bound_box]
    center = sum(bbox, Vector()) / 8
    size = max((max(c[i] for c in bbox) - min(c[i] for c in bbox)) for i in range(3))
    cam_data = bpy.data.cameras.new("Cam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = size * 1.15
    cam = bpy.data.objects.new("Cam", cam_data)
    scene.collection.objects.link(cam)
    direction = Vector(view).normalized()
    cam.location = center + direction * 2.0
    cam.rotation_euler = (-direction).to_track_quat("-Z", "Y").to_euler()
    scene.camera = cam
    sun_data = bpy.data.lights.new("Sun", "SUN")
    sun_data.energy = 3.0
    sun = bpy.data.objects.new("Sun", sun_data)
    sun.rotation_euler = (0.6, 0.3, 0.8)
    scene.collection.objects.link(sun)
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    for o in (cam, sun):
        bpy.data.objects.remove(o)


def main():
    os.makedirs(OUT, exist_ok=True)
    os.makedirs(ICONS, exist_ok=True)
    items = [
        ("baseball_bat", baseball_bat, (1.0, -0.2, 0.15)),
        ("pipe_wrench", pipe_wrench, (1.0, 0.2, 0.1)),
        ("pistol", pistol, (1.0, 0.0, 0.05)),
        ("ammo_9mm", ammo_box, (0.6, -0.8, 0.6)),
    ]
    for name, fn, view in items:
        reset()
        ob = fn()
        tris = sum(len(p.vertices) - 2 for p in ob.data.polygons)
        print(f"{name}: {tris} triângulos")
        export(ob, os.path.join(OUT, f"{name}.glb"))
        if name in ("baseball_bat", "pipe_wrench"):
            ob.rotation_euler = (math.radians(-50), 0, 0)  # na diagonal, fica melhor no ícone
            bpy.context.view_layer.update()
        render_icon(ob, os.path.abspath(os.path.join(ICONS, f"{name}.png")), view)


if __name__ == "__main__":
    main()
