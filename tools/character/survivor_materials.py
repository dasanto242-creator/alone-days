"""Materiais e texturas do sobrevivente: tudo procedural no Blender e "assado" (bake)
em texturas de imagem, que o glTF/Godot entendem. Nada de textura de terceiros."""
import os

import bpy
import numpy as np
from mathutils import Vector

def lin(c):
    """Cores escritas em sRGB (como num editor de imagem) -> linear (como o Blender usa)."""
    return tuple(x ** 2.2 for x in c)


SKIN = lin((0.72, 0.53, 0.42))
LIPS = lin((0.6, 0.38, 0.35))
BROWS = lin((0.17, 0.13, 0.1))
STUBBLE = lin((0.38, 0.3, 0.25))
HAIR = lin((0.13, 0.1, 0.08))

GARMENTS = {
    #           cor base               rugosidade  padrão   escala  sujeira  textura
    "Jacket": (lin((0.33, 0.36, 0.24)), 0.85, "canvas", 900.0, 0.35, 1024),
    "Shirt": (lin((0.24, 0.24, 0.25)), 0.9, "cotton", 600.0, 0.2, 512),
    "Pants": (lin((0.25, 0.27, 0.3)), 0.85, "twill", 700.0, 0.35, 1024),
    "Boots": (lin((0.2, 0.15, 0.11)), 0.55, "leather", 120.0, 0.4, 512),
    "Beanie": (lin((0.2, 0.2, 0.2)), 0.95, "knit", 160.0, 0.15, 512),
    "Backpack": (lin((0.4, 0.36, 0.27)), 0.85, "canvas", 800.0, 0.45, 1024),
    "Holster": (lin((0.14, 0.11, 0.08)), 0.55, "leather", 150.0, 0.2, 256),
}


# ---------------------------------------------------------------- pele

def paint_skin_features(body, used, base, skel, joint):
    """Pinta sobrancelhas, lábios e barba rala como cor por vértice (vira textura no bake)."""
    raw = {}
    for bone, pairs in skel.weights.items():
        for vi, w in pairs:
            raw.setdefault(vi, {})[bone] = w
    eyes = [joint("eye.L____head"), joint("eye.R____head")]
    mouth = (joint("jaw____tail") if "jaw____tail" in skel.joint_pos else eyes[0]) * 1.0
    attr = body.data.color_attributes.new("features", "FLOAT_COLOR", "POINT")
    for li, vi in enumerate(used):
        co = body.data.vertices[li].co
        w = raw.get(vi, {})
        color = Vector(SKIN)
        lips = sum(x for b, x in w.items() if b.startswith("oris"))
        stubble = w.get("jaw", 0.0) + w.get("special04", 0.0) * 0.5
        brow = 0.0
        for e in eyes:
            dx = abs(co.x - e.x) / 0.03
            dz = (co.z - (e.z + 0.022)) / 0.009
            if co.y < e.y + 0.005 and dx < 1.0:
                brow = max(brow, max(0.0, 1.0 - dz * dz) * (1.0 - dx ** 4))
        hair = 0.0
        e0 = eyes[0]
        if w.get("head", 0.0) > 0.5 and co.z > e0.z - 0.035 and co.y > e0.y + 0.075:
            hair = min((co.y - (e0.y + 0.075)) / 0.03, 1.0)
        if hair > 0.0:
            color = color.lerp(Vector(HAIR), hair * 0.9)
        if stubble > 0.25 and lips < 0.3:
            color = color.lerp(Vector(STUBBLE), min((stubble - 0.25) * 1.4, 0.45))
        if lips > 0.55:
            color = color.lerp(Vector(LIPS), min((lips - 0.55) * 1.5, 0.6))
        color = color.lerp(Vector(BROWS), min(brow * 1.2, 0.92))
        attr.data[li].color = (color.x, color.y, color.z, 1.0)


# ---------------------------------------------------------------- utilidades de nós

def _nodes(mat):
    mat.use_nodes = True
    nt = mat.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    return nt


def _coord(nt, kind="Object"):
    tc = nt.nodes.new("ShaderNodeTexCoord")
    return tc.outputs[kind]


def _noise(nt, vec, scale, detail=6.0, rough=0.55):
    n = nt.nodes.new("ShaderNodeTexNoise")
    n.inputs["Scale"].default_value = scale
    n.inputs["Detail"].default_value = detail
    n.inputs["Roughness"].default_value = rough
    nt.links.new(vec, n.inputs["Vector"])
    return n.outputs["Fac"]


def _math(nt, op, a, b=None, clamp=False):
    m = nt.nodes.new("ShaderNodeMath")
    m.operation = op
    m.use_clamp = clamp
    for i, x in enumerate((a, b)):
        if x is None:
            continue
        if isinstance(x, (int, float)):
            m.inputs[i].default_value = x
        else:
            nt.links.new(x, m.inputs[i])
    return m.outputs[0]


def _mix(nt, fac, a, b, blend="MIX"):
    m = nt.nodes.new("ShaderNodeMix")
    m.data_type = "RGBA"
    m.blend_type = blend
    m.clamp_result = True
    for sock, val in ((m.inputs[0], fac), (m.inputs[6], a), (m.inputs[7], b)):
        if isinstance(val, (int, float)):
            sock.default_value = val
        elif isinstance(val, tuple):
            sock.default_value = (*val, 1.0) if len(val) == 3 else val
        else:
            nt.links.new(val, sock)
    return m.outputs[2]


def _wave(nt, vec, scale, axis, profile="SIN", distortion=0.0):
    w = nt.nodes.new("ShaderNodeTexWave")
    w.wave_type = "BANDS"
    w.bands_direction = axis
    w.wave_profile = profile
    w.inputs["Scale"].default_value = scale
    w.inputs["Distortion"].default_value = distortion
    nt.links.new(vec, w.inputs["Vector"])
    return w.outputs["Fac"]


def _pattern(nt, kind, scale):
    """Retorna (fator de cor 0..1, altura para relevo)."""
    vec = _coord(nt)
    if kind == "canvas":
        a = _wave(nt, vec, scale, "X")
        b = _wave(nt, vec, scale, "Z")
        h = _math(nt, "MULTIPLY", _math(nt, "ADD", a, b), 0.5)
    elif kind == "twill":
        h = _wave(nt, vec, scale, "DIAGONAL")
    elif kind == "knit":
        h = _wave(nt, vec, scale, "X", "SAW", 2.0)
    elif kind == "leather":
        h = _noise(nt, vec, scale, 8.0, 0.7)
    else:  # cotton
        h = _noise(nt, vec, scale, 4.0, 0.5)
    return h, h


def _build_fabric(mat, color, roughness, kind, scale, dirt, zipper=False):
    nt = _nodes(mat)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    nt.links.new(bsdf.outputs[0], out.inputs[0])
    weave, height = _pattern(nt, kind, scale)
    vec = _coord(nt)
    # variação de cor em grande escala (desbotado) + manchas de sujeira
    fade = _noise(nt, vec, 3.0, 4.0, 0.6)
    grime = _math(nt, "GREATER_THAN", _noise(nt, vec, 7.0, 8.0, 0.65), 0.58)
    dark = tuple(c * 0.55 for c in color)
    light = tuple(min(c * 1.25 + 0.02, 1.0) for c in color)
    col = _mix(nt, fade, dark, light)
    col = _mix(nt, _math(nt, "MULTIPLY", weave, 0.08), col, (0.0, 0.0, 0.0))
    mud = lin((0.3, 0.26, 0.2))
    col = _mix(nt, _math(nt, "MULTIPLY", grime, dirt * 0.6), col, mud)
    if zipper:
        # zíper e vista: faixa escura vertical no centro da frente
        sep = nt.nodes.new("ShaderNodeSeparateXYZ")
        nt.links.new(vec, sep.inputs[0])
        band = _math(nt, "LESS_THAN", _math(nt, "ABSOLUTE", sep.outputs["X"]), 0.007)
        front = _math(nt, "LESS_THAN", sep.outputs["Y"], 0.0)
        col = _mix(nt, _math(nt, "MULTIPLY", band, front), col, lin((0.08, 0.08, 0.07)))
    nt.links.new(col, bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = roughness
    # relevo: trama + rugas
    wrinkles = _noise(nt, vec, 14.0, 3.0, 0.5)
    hsum = _math(nt, "ADD", _math(nt, "MULTIPLY", height, 0.15), wrinkles)
    bump = nt.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.25
    bump.inputs["Distance"].default_value = 0.004
    nt.links.new(hsum, bump.inputs["Height"])
    nt.links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    return nt, bsdf


def _build_skin(mat):
    nt = _nodes(mat)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    nt.links.new(bsdf.outputs[0], out.inputs[0])
    attr = nt.nodes.new("ShaderNodeAttribute")
    attr.attribute_name = "features"
    vec = _coord(nt)
    blotch = _noise(nt, vec, 30.0, 4.0, 0.5)          # manchas avermelhadas
    pores = _noise(nt, vec, 900.0, 2.0, 0.5)          # poros
    col = _mix(nt, _math(nt, "MULTIPLY", blotch, 0.08), attr.outputs["Color"], lin((0.7, 0.45, 0.4)), "MIX")
    col = _mix(nt, _math(nt, "MULTIPLY", pores, 0.08), col, (0.0, 0.0, 0.0), "MIX")
    nt.links.new(col, bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.55
    bump = nt.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.12
    bump.inputs["Distance"].default_value = 0.001
    nt.links.new(_math(nt, "ADD", pores, _math(nt, "MULTIPLY", blotch, 0.3)), bump.inputs["Height"])
    nt.links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    return nt, bsdf


# ---------------------------------------------------------------- bake

def _select_only(ob):
    for o in bpy.context.scene.objects:
        o.select_set(False)
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob


def _smart_uv(ob):
    _select_only(ob)
    for uv in list(ob.data.uv_layers):
        ob.data.uv_layers.remove(uv)
    ob.data.uv_layers.new(name="UVMap")
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=1.15, island_margin=0.006)
    bpy.ops.object.mode_set(mode="OBJECT")


def _bake(ob, nt, size, name, roughness):
    _select_only(ob)
    albedo = bpy.data.images.new(f"{name}_albedo", size, size)
    normal = bpy.data.images.new(f"{name}_normal", size, size)
    normal.colorspace_settings.name = "Non-Color"
    node = nt.nodes.new("ShaderNodeTexImage")
    nt.nodes.active = node
    scene = bpy.context.scene
    scene.render.bake.margin = 8
    node.image = albedo
    bpy.ops.object.bake(type="DIFFUSE", pass_filter={"COLOR"})
    node.image = normal
    bpy.ops.object.bake(type="NORMAL", normal_space="TANGENT")
    for img in (albedo, normal):
        img.pack()
    # Material final (simples, só imagens) que o glTF exporta
    mat = ob.active_material
    nt2 = _nodes(mat)
    out = nt2.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt2.nodes.new("ShaderNodeBsdfPrincipled")
    nt2.links.new(bsdf.outputs[0], out.inputs[0])
    t_alb = nt2.nodes.new("ShaderNodeTexImage")
    t_alb.image = albedo
    t_nrm = nt2.nodes.new("ShaderNodeTexImage")
    t_nrm.image = normal
    nmap = nt2.nodes.new("ShaderNodeNormalMap")
    nt2.links.new(t_alb.outputs["Color"], bsdf.inputs["Base Color"])
    nt2.links.new(t_nrm.outputs["Color"], nmap.inputs["Color"])
    nt2.links.new(nmap.outputs["Normal"], bsdf.inputs["Normal"])
    bsdf.inputs["Roughness"].default_value = roughness


def apply_all(meshes, base, region):
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 4
    for ob in meshes:
        name = ob.name
        mat = bpy.data.materials.new(name)
        ob.data.materials.clear()
        ob.data.materials.append(mat)
        if name == "Body":
            nt, _ = _build_skin(mat)
            _bake(ob, nt, 1024, "skin", 0.55)
        elif name == "Eyes":
            _build_eyes(mat)
        else:
            color, rough, kind, scale, dirt, size = GARMENTS[name]
            _smart_uv(ob)
            nt, _ = _build_fabric(mat, color, rough, kind, scale, dirt, zipper=(name == "Jacket"))
            _bake(ob, nt, size, name.lower(), rough)
        for poly in ob.data.polygons:
            poly.use_smooth = True


MH_DATA = ""


def _recolored_eye():
    """Escurece a íris (a original fica avermelhada de longe) e salva uma cópia."""
    from PIL import Image
    src = os.path.join(MH_DATA, "eyes", "materials", "brown_eye.png")
    im = np.asarray(Image.open(src).convert("RGB")).astype(np.float32) / 255.0
    r, g, b = im[..., 0], im[..., 1], im[..., 2]
    iris = np.clip((r - g * 1.15) * 4.0, 0.0, 1.0)[..., None]
    target = np.array([0.22, 0.15, 0.1], dtype=np.float32) * (0.5 + im.mean(axis=2, keepdims=True))
    out = im * (1 - iris) + target * iris
    path = "/tmp/alone_days_eye.png"
    Image.fromarray((np.clip(out, 0, 1) * 255).astype(np.uint8)).save(path)
    return path


def _build_eyes(mat):
    nt = _nodes(mat)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    nt.links.new(bsdf.outputs[0], out.inputs[0])
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = bpy.data.images.load(_recolored_eye())
    tex.image.pack()
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.15
