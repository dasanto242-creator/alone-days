"""Animações do sobrevivente, geradas por código (keyframes próprios, sem captura de terceiros).

As pernas usam cinemática inversa planar: para cada quadro calculamos onde o pé deve
estar (no chão durante o apoio, levantado no balanço) e resolvemos coxa + joelho.
Assim o pé fica parado no chão enquanto o corpo passa por cima: sem "patinar".

Convenções (espaço da armadura no Blender): frente = -Y, cima = +Z, esquerda do personagem = +X.
"""
import math

import bpy
from mathutils import Quaternion, Vector

FPS = 30
X = Vector((1, 0, 0))
Y = Vector((0, 1, 0))
Z = Vector((0, 0, 1))


def q(axis, deg):
    return Quaternion(axis, math.radians(deg))


class Rig:
    def __init__(self, arm):
        self.arm = arm
        self.pb = arm.pose.bones
        b = arm.data.bones
        self.hip_z = b["upperleg01.L"].head_local.z
        self.ankle_z = b["foot.L"].head_local.z
        self.l1 = (b["lowerleg01.L"].head_local - b["upperleg01.L"].head_local).length
        self.l2 = (b["foot.L"].head_local - b["lowerleg01.L"].head_local).length
        self.rest_q = {name: bone.matrix_local.to_quaternion() for name, bone in b.items()}
        # Na pose de repouso do MakeHuman o antebraço aponta para a frente (cotovelo dobrado).
        # Calcula a correção que alinha o antebraço com o braço (cotovelo reto).
        self.forearm_fix = {}
        for side in ("L", "R"):
            upper = b[f"lowerarm01.{side}"].head_local - b[f"upperarm01.{side}"].head_local
            fore = b[f"wrist.{side}"].head_local - b[f"lowerarm01.{side}"].head_local
            self.forearm_fix[side] = fore.normalized().rotation_difference(upper.normalized())

    def reset(self):
        for p in self.pb:
            p.rotation_mode = "QUATERNION"
            p.rotation_quaternion = Quaternion()
            p.location = Vector()

    def rot(self, bone, q_arm):
        """Rotação dada em eixos da armadura, convertida para o espaço local do osso."""
        r = self.rest_q[bone]
        self.pb[bone].rotation_quaternion = r.inverted() @ q_arm @ r

    def move_root(self, delta):
        self.pb["root"].location = self.rest_q["root"].inverted() @ delta

    def key_all(self, frame):
        for p in self.pb:
            p.keyframe_insert("rotation_quaternion", frame=frame)
        self.pb["root"].keyframe_insert("location", frame=frame)

    # ------------------------------------------------------------ pernas (IK planar)
    def leg(self, side, forward, lift, hip_drop, toe=0.0):
        """forward: pé à frente do quadril (m); lift: altura do pé; hip_drop: quanto o quadril desceu."""
        h = (self.hip_z - hip_drop) - (self.ankle_z + lift)
        d = math.hypot(forward, h)
        d = min(d, (self.l1 + self.l2) * 0.999)
        cos_k = (self.l1 ** 2 + self.l2 ** 2 - d ** 2) / (2 * self.l1 * self.l2)
        knee = math.pi - math.acos(max(-1.0, min(1.0, cos_k)))
        cos_a = (self.l1 ** 2 + d ** 2 - self.l2 ** 2) / (2 * self.l1 * d)
        thigh = math.atan2(forward, h) + math.acos(max(-1.0, min(1.0, cos_a)))
        t_deg, k_deg = math.degrees(thigh), math.degrees(knee)
        self.rot(f"upperleg01.{side}", q(X, -t_deg))
        self.rot(f"lowerleg01.{side}", q(X, k_deg))
        self.rot(f"foot.{side}", q(X, (t_deg - k_deg) + toe))

    # ------------------------------------------------------------ braços
    def arm_pose(self, side, swing, elbow, lower=34.0, out=0.0, twist=0.0):
        """swing > 0: braço para frente. elbow: dobra do cotovelo. lower: baixa o braço da pose A."""
        s = 1.0 if side == "L" else -1.0
        down = q(Y, s * (lower - out))
        self.rot(f"upperarm01.{side}", q(X, -swing) @ down)
        self.rot(f"lowerarm01.{side}", q(X, -elbow) @ q(Z, s * twist) @ self.forearm_fix[side])
        self.rot(f"wrist.{side}", q(X, -elbow * 0.1))
        # mão relaxada: dedos levemente fechados
        for f in range(2, 6):
            for jn in range(1, 4):
                self.rot(f"finger{f}-{jn}.{side}", q(X, -(18 + 8 * jn)))
        self.rot(f"finger1-2.{side}", q(Z, s * 12))

    def spine(self, lean=0.0, twist=0.0, side=0.0):
        for i, b in enumerate(("spine05", "spine04", "spine03", "spine02", "spine01")):
            w = 0.2
            self.rot(b, q(X, lean * w) @ q(Z, twist * w * (1 if i > 1 else 0.3)) @ q(Y, side * w))

    def head(self, pitch=0.0, yaw=0.0):
        self.rot("neck01", q(X, pitch * 0.4) @ q(Z, yaw * 0.4))
        self.rot("head", q(X, pitch * 0.6) @ q(Z, yaw * 0.6))


def new_action(rig, name, frames, loop=True):
    arm = rig.arm
    act = bpy.data.actions.new(name)
    act.use_fake_user = True
    if arm.animation_data is None:
        arm.animation_data_create()
    arm.animation_data.action = act
    act.frame_range = (0, frames)
    act.use_frame_range = True
    return act


def finish(rig, act, cyclic=True):
    for fc in _fcurves(act):
        for kp in fc.keyframe_points:
            kp.interpolation = "BEZIER"
        if cyclic:
            fc.modifiers.new("CYCLES")
    rig.arm.animation_data.action = None


def _fcurves(act):
    if hasattr(act, "fcurves") and len(act.fcurves):
        return act.fcurves
    curves = []
    for layer in getattr(act, "layers", []):
        for strip in layer.strips:
            for bag in strip.channelbags:
                curves.extend(bag.fcurves)
    return curves


# ---------------------------------------------------------------- ciclos

def locomotion(rig, name, cycle_s, stride, lift, stance, bob, drop, lean, arm_swing, elbow, toe_off=20.0):
    frames = round(cycle_s * FPS)
    act = new_action(rig, name, frames)
    step = 2  # keyframe a cada 2 quadros (curvas suaves e arquivo leve)
    for f in range(0, frames + 1, step):
        p = f / frames
        rig.reset()
        hip_bob = drop + bob * (0.5 + 0.5 * math.cos(4 * math.pi * p))
        rig.move_root(Vector((math.sin(2 * math.pi * p) * 0.015, 0, -hip_bob)))
        for side, off in (("L", 0.0), ("R", 0.5)):
            ph = (p + off) % 1.0
            if ph < stance:  # apoio: pé no chão, vai de frente para trás
                t = ph / stance
                fwd = stride * 0.5 - stride * t
                up = 0.0
                toe = -toe_off * max(0.0, (t - 0.75) / 0.25)
            else:            # balanço: pé sobe e volta para a frente
                t = (ph - stance) / (1 - stance)
                fwd = -stride * 0.5 + stride * (0.5 - 0.5 * math.cos(math.pi * t))
                up = lift * math.sin(math.pi * t)
                toe = 10.0 * math.sin(math.pi * t)
            rig.leg(side, fwd, up, hip_bob, toe)
        swing = math.sin(2 * math.pi * p)
        rig.arm_pose("L", -arm_swing * swing, elbow + abs(swing) * elbow * 0.3)
        rig.arm_pose("R", arm_swing * swing, elbow + abs(swing) * elbow * 0.3)
        rig.spine(lean=lean, twist=6 * swing * arm_swing / 30.0)
        rig.head(pitch=-lean * 0.5)
        rig.key_all(f)
    finish(rig, act)


def idle(rig):
    frames = 90
    act = new_action(rig, "idle", frames)
    for f in range(0, frames + 1, 6):
        p = f / frames
        b = math.sin(2 * math.pi * p)
        rig.reset()
        rig.move_root(Vector((0.012 * b, 0, -0.02)))
        rig.leg("L", 0.04, 0.0, 0.02 - 0.0, 0)
        rig.leg("R", -0.03, 0.0, 0.02, 0)
        rig.arm_pose("L", 4 + b, 12, out=3)
        rig.arm_pose("R", 3 - b, 14, out=3)
        rig.spine(lean=2 + 1.5 * math.sin(4 * math.pi * p), side=b * 2)
        rig.head(pitch=1.5 * math.sin(4 * math.pi * p + 1), yaw=6 * math.sin(2 * math.pi * p + 0.7))
        rig.key_all(f)
    finish(rig, act)


def crouch_idle(rig):
    frames = 60
    act = new_action(rig, "crouch_idle", frames)
    for f in range(0, frames + 1, 6):
        b = math.sin(2 * math.pi * f / frames)
        rig.reset()
        rig.move_root(Vector((0, 0.06, -0.4)))
        rig.leg("L", 0.18, 0.0, 0.4, 0)
        rig.leg("R", -0.05, 0.0, 0.4, 15)
        rig.arm_pose("L", 25, 55, out=8)
        rig.arm_pose("R", 20, 60, out=8)
        rig.spine(lean=28 + b * 1.5)
        rig.head(pitch=-22)
        rig.key_all(f)
    finish(rig, act)


def crouch_walk(rig):
    frames = 36
    act = new_action(rig, "crouch_walk", frames)
    stride, stance = 0.75, 0.62
    for f in range(0, frames + 1, 2):
        p = f / frames
        rig.reset()
        drop = 0.4 + 0.02 * (0.5 + 0.5 * math.cos(4 * math.pi * p))
        rig.move_root(Vector((0.02 * math.sin(2 * math.pi * p), 0.06, -drop)))
        for side, off in (("L", 0.0), ("R", 0.5)):
            ph = (p + off) % 1.0
            if ph < stance:
                t = ph / stance
                fwd, up = stride * 0.5 - stride * t, 0.0
            else:
                t = (ph - stance) / (1 - stance)
                fwd = -stride * 0.5 + stride * (0.5 - 0.5 * math.cos(math.pi * t))
                up = 0.07 * math.sin(math.pi * t)
            rig.leg(side, fwd, up, drop, 0)
        s = math.sin(2 * math.pi * p)
        rig.arm_pose("L", 20 - 10 * s, 60, out=8)
        rig.arm_pose("R", 20 + 10 * s, 60, out=8)
        rig.spine(lean=28, twist=4 * s)
        rig.head(pitch=-22)
        rig.key_all(f)
    finish(rig, act)


def jump(rig):
    """Impulso + pose no ar (fica no último quadro enquanto estiver no ar)."""
    act = new_action(rig, "jump", 14)
    poses = [  # quadro, queda do quadril, (pé L, pé R), braços, inclinação
        (0, 0.02, (0.0, 0.0), (0, 15), 4),
        (4, 0.16, (0.05, -0.05), (-25, 30), 18),
        (8, -0.02, (0.02, -0.12), (40, 40), 2),
        (14, 0.05, (0.12, -0.1), (25, 50), 6),
    ]
    for f, drop, (fl, fr), (sw, el), lean in poses:
        rig.reset()
        rig.move_root(Vector((0, 0, -drop)))
        lift = 0.0 if f < 8 else 0.22
        rig.leg("L", fl, lift, drop, 0 if f < 8 else -15)
        rig.leg("R", fr, lift * 0.6, drop, -20 if f >= 8 else 0)
        rig.arm_pose("L", sw, el, out=10)
        rig.arm_pose("R", sw, el, out=10)
        rig.spine(lean=lean)
        rig.key_all(f)
    finish(rig, act, cyclic=False)


def death(rig):
    """Joelhos cedem e o corpo cai de costas."""
    act = new_action(rig, "death", 45)
    keys = [  # quadro, deslocamento do root (y, z), rotação do tronco (X), joelhos, braços
        (0, (0.0, -0.02), 0, 0.02, (4, 12)),
        (10, (0.0, -0.25), 15, 0.3, (30, 40)),
        (22, (0.25, -0.65), -40, 0.55, (60, 20)),
        (32, (0.6, -0.82), -85, 0.4, (95, 10)),
        (45, (0.62, -0.84), -88, 0.35, (100, 8)),
    ]
    for f, (dy, dz), tilt, drop, (sw, el) in keys:
        rig.reset()
        rig.move_root(Vector((0, dy, dz)))
        rig.rot("root", q(X, tilt))
        rig.leg("L", 0.15, 0.0, drop, 0)
        rig.leg("R", 0.05, 0.0, drop * 0.8, 0)
        rig.arm_pose("L", sw, el, lower=34 - sw * 0.2, out=15)
        rig.arm_pose("R", sw * 0.8, el, lower=34 - sw * 0.2, out=20)
        rig.head(pitch=-tilt * 0.15)
        rig.key_all(f)
    finish(rig, act, cyclic=False)


def create_all(arm):
    bpy.context.scene.render.fps = FPS
    rig = Rig(arm)
    bpy.context.view_layer.objects.active = arm
    for p in rig.pb:
        p.rotation_mode = "QUATERNION"
    idle(rig)
    #           nome      ciclo  passada elev. apoio  bob   queda incl. braço cotovelo
    locomotion(rig, "walk", 1.0, 0.9, 0.12, 0.6, 0.025, 0.03, 4, 22, 14)
    locomotion(rig, "run", 0.7, 1.25, 0.22, 0.42, 0.05, 0.07, 9, 38, 70, 25)
    locomotion(rig, "sprint", 0.62, 1.75, 0.32, 0.36, 0.06, 0.1, 16, 55, 85, 30)
    crouch_idle(rig)
    crouch_walk(rig)
    jump(rig)
    death(rig)
    rig.reset()
    print("Animações:", [a.name for a in bpy.data.actions])
