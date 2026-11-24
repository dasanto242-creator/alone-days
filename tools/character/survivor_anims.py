"""Animações do sobrevivente, geradas por código (keyframes próprios, sem captura de terceiros).

Sistema:
- Cada osso recebe uma rotação no ESPAÇO DO MUNDO (da armadura); o script converte para o
  espaço local considerando o pai. Assim dá para pensar em "inclinar o tronco 10° para a frente"
  sem se preocupar com a orientação interna dos ossos.
- Pernas e braços usam IK de dois ossos: definimos onde o pé/mão deve estar e o joelho/cotovelo
  se resolve sozinho (com direção de dobra controlada).
- Peso e impacto: o quadril afunda depois que o pé toca o chão, o tronco flexiona e a cabeça
  compensa; o quadril gira com as pernas e os ombros giram ao contrário.

Convenções (armadura no Blender): frente = -Y, cima = +Z, esquerda do personagem = +X.
"""
import math

import bpy
from mathutils import Matrix, Quaternion, Vector

FPS = 30
X = Vector((1, 0, 0))
Y = Vector((0, 1, 0))
Z = Vector((0, 0, 1))
FWD = Vector((0, -1, 0))


def q(axis, deg):
    return Quaternion(axis, math.radians(deg))


def smooth(t):
    t = max(0.0, min(1.0, t))
    return t * t * (3 - 2 * t)


def basis(direction, ref):
    """Rotação cuja base tem Y = direção e Z = referência (ortogonalizada)."""
    yv = direction.normalized()
    zv = ref - yv * ref.dot(yv)
    if zv.length < 1e-6:
        zv = Z - yv * Z.dot(yv) if abs(yv.dot(Z)) < 0.95 else X - yv * X.dot(yv)
    zv.normalize()
    xv = yv.cross(zv)
    return Matrix((xv, yv, zv)).transposed().to_quaternion()


def two_bone(a, l1, l2, target, pole):
    """IK de dois ossos: retorna (posição do meio, alvo alcançável)."""
    d = target - a
    dist = max(1e-4, min(d.length, (l1 + l2) * 0.999))
    dn = d.normalized()
    t = a + dn * dist
    along = (l1 * l1 - l2 * l2 + dist * dist) / (2 * dist)
    h = math.sqrt(max(l1 * l1 - along * along, 0.0))
    pp = pole - dn * pole.dot(dn)
    if pp.length < 1e-6:
        pp = Z.cross(dn)
    pp.normalize()
    return a + dn * along + pp * h, t


class Rig:
    def __init__(self, arm):
        self.arm = arm
        self.pb = arm.pose.bones
        b = arm.data.bones
        self.parent = {n: (bone.parent.name if bone.parent else None) for n, bone in b.items()}
        self.rest_head = {n: bone.head_local.copy() for n, bone in b.items()}
        self.rest_q = {n: bone.matrix_local.to_quaternion() for n, bone in b.items()}

        def depth(n):
            return 0 if self.parent[n] is None else 1 + depth(self.parent[n])
        self.order = sorted(b.keys(), key=depth)
        h = self.rest_head
        self.ground_ankle = h["foot.L"].z
        self.leg = {}
        self.arm_rest = {}
        for s in ("L", "R"):
            hip, knee, ankle = h[f"upperleg01.{s}"], h[f"lowerleg01.{s}"], h[f"foot.{s}"]
            self.leg[s] = ((knee - hip).length, (ankle - knee).length, knee - hip, ankle - knee)
            sh, el, wr = h[f"upperarm01.{s}"], h[f"lowerarm01.{s}"], h[f"wrist.{s}"]
            thumb = (h[f"finger2-1.{s}"] - h[f"finger5-1.{s}"]).normalized()
            fore = (wr - el).normalized()
            fore_o = (fore - thumb * fore.dot(thumb)).normalized()
            palm = wr + (h[f"finger3-1.{s}"] - wr) * 0.55
            self.arm_rest[s] = {
                "l1": (el - sh).length, "l2": (wr - el).length, "up": el - sh, "fore": wr - el,
                "n": (el - sh).cross(wr - el), "thumb": thumb, "fwd": fore_o, "grip": palm - wr,
            }
        self.begin()

    # ------------------------------------------------------------ estado do quadro
    def begin(self):
        self.W = {}
        self.root_off = Vector()
        self.local_extra = {}

    def world(self, bone):
        while bone is not None:
            if bone in self.W:
                return self.W[bone]
            bone = self.parent[bone]
        return Quaternion()

    def set(self, bone, quat):
        self.W[bone] = quat

    def pos(self, bone):
        p = self.parent[bone]
        if p is None:
            return self.rest_head[bone] + self.root_off
        return self.pos(p) + self.world(p) @ (self.rest_head[bone] - self.rest_head[p])

    def key(self, frame):
        for name in self.order:
            pb = self.pb[name]
            r = self.rest_q[name]
            wp = self.world(self.parent[name]) if self.parent[name] else Quaternion()
            local = r.inverted() @ (wp.inverted() @ self.world(name)) @ r
            if name in self.local_extra:
                local = local @ self.local_extra[name]
            pb.rotation_mode = "QUATERNION"
            pb.rotation_quaternion = local
            pb.keyframe_insert("rotation_quaternion", frame=frame)
        self.pb["root"].location = self.rest_q["root"].inverted() @ self.root_off
        self.pb["root"].keyframe_insert("location", frame=frame)

    # ------------------------------------------------------------ corpo
    def pelvis(self, offset=Vector(), yaw=0.0, roll=0.0, pitch=0.0):
        self.root_off = offset
        self.set("root", q(Z, yaw) @ q(Y, roll) @ q(X, pitch))

    def torso(self, lean=0.0, yaw=0.0, roll=0.0):
        """lean > 0: inclina para a frente. Distribuído pela coluna, a partir do quadril."""
        base = self.world("root")
        names = ("spine05", "spine04", "spine03", "spine02", "spine01")
        for i, n in enumerate(names):
            f = (i + 1) / len(names)
            self.set(n, base.slerp(q(Z, yaw) @ q(X, lean) @ q(Y, roll), f))

    def head(self, pitch=0.0, yaw=0.0, roll=0.0):
        """Rotação da cabeça no mundo (pitch > 0: olha para baixo)."""
        chest = self.world("spine01")
        target = q(Z, yaw) @ q(X, pitch) @ q(Y, roll)
        self.set("neck01", chest.slerp(target, 0.4))
        self.set("neck02", chest.slerp(target, 0.6))
        self.set("neck03", chest.slerp(target, 0.8))
        self.set("head", target)

    def shoulders(self, raise_l=0.0, raise_r=0.0, fwd_l=0.0, fwd_r=0.0):
        chest = self.world("spine01")
        self.set("clavicle.L", chest @ q(Y, -raise_l) @ q(Z, fwd_l))
        self.set("clavicle.R", chest @ q(Y, raise_r) @ q(Z, -fwd_r))

    # ------------------------------------------------------------ pernas
    def foot(self, side, target, pitch=0.0, yaw=0.0):
        """target: posição do tornozelo no mundo. pitch > 0: ponta do pé para cima."""
        l1, l2, rest_up, rest_low = self.leg[side]
        hip = self.pos(f"upperleg01.{side}")
        lateral = self.world("root") @ X
        pole = self.world("root") @ FWD
        knee, ankle = two_bone(hip, l1, l2, target, pole)
        self.set(f"upperleg01.{side}", basis(knee - hip, lateral) @ basis(rest_up, X).inverted())
        self.set(f"lowerleg01.{side}", basis(ankle - knee, lateral) @ basis(rest_low, X).inverted())
        self.set(f"foot.{side}", q(Z, yaw) @ q(X, -pitch))

    # ------------------------------------------------------------ braços
    def hand(self, side, grip, fwd=None, thumb=None, pole=None, fist=0.35):
        """grip: centro da palma (mundo). fwd/thumb: orientação desejada da mão (opcional)."""
        a = self.arm_rest[side]
        s = 1.0 if side == "L" else -1.0
        chest = self.world("spine01")
        if pole is None:
            pole = chest @ Vector((s * 0.5, 0.8, -0.3))  # cotovelo para trás e um pouco para fora
        if fwd is not None:
            hand_q = basis(fwd, thumb) @ basis(a["fwd"], a["thumb"]).inverted()
            wrist_target = grip - hand_q @ a["grip"]
        else:
            hand_q = None
            wrist_target = grip - chest @ a["grip"]
        sh = self.pos(f"upperarm01.{side}")
        elbow, wrist = two_bone(sh, a["l1"], a["l2"], wrist_target, pole)
        n_new = (elbow - sh).cross(wrist - elbow)
        if n_new.length < 1e-5:
            n_new = chest @ a["n"]
        self.set(f"upperarm01.{side}", basis(elbow - sh, n_new) @ basis(a["up"], a["n"]).inverted())
        fore_q = basis(wrist - elbow, n_new) @ basis(a["fore"], a["n"]).inverted()
        self.set(f"lowerarm01.{side}", fore_q)
        if hand_q is not None:
            self.set(f"lowerarm02.{side}", fore_q.slerp(hand_q, 0.5))  # torção distribuída
            self.set(f"wrist.{side}", hand_q)
        self.fingers(side, fist)

    def fingers(self, side, fist):
        """0 = mão aberta relaxada, 1 = punho fechado."""
        s = 1.0 if side == "L" else -1.0
        for f in range(2, 6):
            for j in range(1, 4):
                self.local_extra[f"finger{f}-{j}.{side}"] = q(X, (8 + 8 * j) + fist * (50 + 12 * j))
        self.local_extra[f"finger1-2.{side}"] = q(Z, s * (10 + 30 * fist))
        self.local_extra[f"finger1-3.{side}"] = q(X, 15 + 40 * fist)

    def shoulder_pos(self, side):
        return self.pos(f"upperarm01.{side}")

    def chest_vec(self, v):
        """Vetor no referencial do peito (x esquerda, y trás, z cima) -> mundo."""
        return self.world("spine01") @ v


# ---------------------------------------------------------------- ações

def new_action(rig, name, frames):
    arm = rig.arm
    act = bpy.data.actions.new(name)
    act.use_fake_user = True
    if arm.animation_data is None:
        arm.animation_data_create()
    arm.animation_data.action = act
    act.frame_range = (0, frames)
    act.use_frame_range = True
    return act


def _fcurves(act):
    if hasattr(act, "fcurves") and len(act.fcurves):
        return act.fcurves
    curves = []
    for layer in getattr(act, "layers", []):
        for strip in layer.strips:
            for bag in strip.channelbags:
                curves.extend(bag.fcurves)
    return curves


def finish(rig, act, cyclic=True):
    for fc in _fcurves(act):
        for kp in fc.keyframe_points:
            kp.interpolation = "BEZIER"
        if cyclic:
            fc.modifiers.new("CYCLES")
    rig.arm.animation_data.action = None


# ---------------------------------------------------------------- locomoção

class Gait:
    """stride = (alcance à frente, alcance atrás) do pé durante o apoio, em metros."""
    def __init__(self, cycle, stride, duty, lift, width, drop, bob, bob_phase, lean, pelvis_yaw, pelvis_roll,
                 sway, impact, arm_mode, arm_amp, heel=12.0, toe_off=25.0, knee_kick=0.0):
        self.reach_f, self.reach_b = stride
        self.cycle, self.stride, self.duty, self.lift, self.width = cycle, sum(stride), duty, lift, width
        self.drop, self.bob, self.bob_phase, self.lean = drop, bob, bob_phase, lean
        self.pelvis_yaw, self.pelvis_roll, self.sway, self.impact = pelvis_yaw, pelvis_roll, sway, impact
        self.arm_mode, self.arm_amp, self.heel, self.toe_off, self.knee_kick = arm_mode, arm_amp, heel, toe_off, knee_kick


def foot_track(g, ph):
    """(frente, altura, inclinação) do pé numa fase 0..1 do seu próprio ciclo (0 = toca o chão)."""
    if ph < g.duty:  # apoio: pé parado no chão (desliza para trás em relação ao quadril)
        t = ph / g.duty
        fwd = g.reach_f - g.stride * t
        pitch = g.heel * max(0.0, 1 - t / 0.15) - g.toe_off * smooth((t - 0.7) / 0.3)
        lift = 0.03 * smooth((t - 0.75) / 0.25)  # calcanhar sobe no fim do apoio
        return fwd, lift, pitch
    t = (ph - g.duty) / (1 - g.duty)  # balanço
    # o pé fica para trás enquanto sobe (calcanhar vai em direção ao glúteo) e só depois avança
    fwd = -g.reach_b + g.stride * smooth(t ** 1.4)
    lift = g.lift * math.sin(math.pi * min(1.0, t * 1.2)) ** 0.7
    fwd -= g.knee_kick * math.sin(math.pi * t) * (1 - t)
    pitch = -g.toe_off * (1 - smooth(t / 0.4)) + g.heel * smooth((t - 0.7) / 0.3)
    return fwd, lift, pitch


def impact_pulse(p):
    """Pulso logo após cada contato com o chão (fases 0 e 0.5 do ciclo)."""
    v = 0.0
    for c in (0.0, 0.5, 1.0):
        d = p - c
        if 0 <= d < 0.25:
            v += math.exp(-((d - 0.06) / 0.05) ** 2)
    return v


def locomotion(rig, name, g):
    frames = round(g.cycle * FPS)
    act = new_action(rig, name, frames)
    for f in range(0, frames + 1):
        p = f / frames
        rig.begin()
        imp = impact_pulse(p)
        bob = g.bob * math.cos(4 * math.pi * (p - g.duty * 0.5) + g.bob_phase)
        z = -g.drop + bob - g.impact * 0.035 * imp
        s = math.sin(2 * math.pi * p)  # > 0: perna direita indo à frente
        rig.pelvis(Vector((-g.sway * math.cos(2 * math.pi * p), 0, z)),
                   yaw=-g.pelvis_yaw * s, roll=g.pelvis_roll * math.sin(2 * math.pi * p + 0.6))
        rig.torso(lean=g.lean + g.impact * 4 * imp, yaw=g.pelvis_yaw * 1.4 * s, roll=-g.pelvis_roll * 0.4 * s)
        rig.head(pitch=-g.lean * 0.55 + g.impact * 2.0 * imp, yaw=-g.pelvis_yaw * 0.2 * s)
        for side, off, x in (("R", 0.0, -g.width), ("L", 0.5, g.width)):
            fwd, lift, pitch = foot_track(g, (p + off) % 1.0)
            rig.foot(side, Vector((x, -fwd, rig.ground_ankle + lift)), pitch, yaw=-g.pelvis_yaw * 0.3 * s)
        for side, sign in (("L", 1.0), ("R", -1.0)):
            arm_cycle(rig, side, g, sign * s, imp)
        rig.shoulders(raise_l=1.5 * imp * g.impact, raise_r=1.5 * imp * g.impact, fwd_l=3 * s, fwd_r=-3 * s)
        rig.key(f)
    finish(rig, act)


def arm_cycle(rig, side, g, swing, imp):
    sx = 1.0 if side == "L" else -1.0
    sh = rig.shoulder_pos(side)
    t = 0.5 + 0.5 * swing  # 0 = atrás, 1 = à frente
    if g.arm_mode == "walk":
        ang = math.radians(-g.arm_amp + 2 * g.arm_amp * t + 4)
        local = Vector((sx * 0.05, math.sin(ang) * -0.56, -math.cos(ang) * 0.56))
        rig.hand(side, sh + rig.chest_vec(Vector((local.x, local.y, local.z))), fist=0.3)
    else:
        # cotovelo ~90° colado ao corpo; mão vai do quadril (atrás) até a altura do peito (frente)
        amp = g.arm_amp
        back = Vector((sx * 0.02, 0.16 * amp, -0.42))
        front = Vector((-sx * 0.08, -0.26 * amp, -0.2 - 0.06 * (amp - 1)))
        local = back.lerp(front, smooth(t))
        local.z -= 0.02 * imp * g.impact
        pole = rig.chest_vec(Vector((sx * 0.25, 1.0, -0.4)))
        rig.hand(side, sh + rig.chest_vec(local), pole=pole, fist=0.75)


def idle(rig):
    frames = 120
    act = new_action(rig, "idle", frames)
    for f in range(0, frames + 1, 4):
        p = f / frames
        b = math.sin(2 * math.pi * p)
        breath = math.sin(4 * math.pi * p)
        rig.begin()
        rig.pelvis(Vector((0.018 * b, 0, -0.025 + 0.004 * breath)), roll=2.0 * b, yaw=2 * b)
        rig.torso(lean=2 + 1.2 * breath, roll=-1.5 * b, yaw=-2 * b)
        rig.head(pitch=1 + 1.5 * math.sin(4 * math.pi * p + 1), yaw=8 * math.sin(2 * math.pi * p + 0.7))
        rig.foot("L", Vector((0.12, -0.04, rig.ground_ankle)), yaw=8)
        rig.foot("R", Vector((-0.12, 0.05, rig.ground_ankle)), yaw=-10)
        for side in ("L", "R"):
            sx = 1.0 if side == "L" else -1.0
            grip = rig.shoulder_pos(side) + rig.chest_vec(Vector((sx * 0.07, -0.06, -0.58 + 0.005 * breath)))
            rig.hand(side, grip, fist=0.25)
        rig.shoulders(raise_l=0.8 * breath, raise_r=0.8 * breath)
        rig.key(f)
    finish(rig, act)


def crouch_idle(rig):
    frames = 80
    act = new_action(rig, "crouch_idle", frames)
    for f in range(0, frames + 1, 4):
        p = f / frames
        b = math.sin(2 * math.pi * p)
        rig.begin()
        rig.pelvis(Vector((0.01 * b, 0.05, -0.44)), pitch=8)
        rig.torso(lean=26 + 1.5 * math.sin(4 * math.pi * p))
        rig.head(pitch=-8 + 3 * b, yaw=15 * math.sin(2 * math.pi * p + 1))
        rig.foot("L", Vector((0.15, -0.2, rig.ground_ankle)), yaw=10)
        rig.foot("R", Vector((-0.15, 0.12, rig.ground_ankle + 0.05)), pitch=-30, yaw=-8)
        for side in ("L", "R"):
            sx = 1.0 if side == "L" else -1.0
            rig.hand(side, rig.shoulder_pos(side) + rig.chest_vec(Vector((sx * 0.02, -0.28, -0.4))), fist=0.4)
        rig.key(f)
    finish(rig, act)


def jump(rig):
    """Impulso + pose no ar (fica no último quadro enquanto estiver no ar)."""
    act = new_action(rig, "jump", 16)
    keys = [  # quadro, quadril z, inclinação, pés (frente, altura, pitch), mãos (frente, altura)
        (0, -0.03, 4, ((0.0, 0.0, 0), (0.0, 0.0, 0)), (0.0, -0.55)),
        (5, -0.2, 22, ((0.02, 0.0, 0), (-0.02, 0.0, 0)), (0.18, -0.5)),
        (9, 0.02, 2, ((0.0, 0.02, -35), (-0.03, 0.03, -35)), (-0.25, -0.15)),
        (16, -0.08, 8, ((0.15, 0.28, 5), (-0.12, 0.2, -15)), (-0.18, -0.25)),
    ]
    for f, z, lean, feet, (hf, hz) in keys:
        rig.begin()
        rig.pelvis(Vector((0, 0, z)))
        rig.torso(lean=lean)
        rig.head(pitch=-lean * 0.5)
        for (side, x), (fw, up, pt) in zip((("L", 0.11), ("R", -0.11)), feet):
            rig.foot(side, Vector((x, -fw, rig.ground_ankle + up)), pt)
        for side in ("L", "R"):
            sx = 1.0 if side == "L" else -1.0
            rig.hand(side, rig.shoulder_pos(side) + rig.chest_vec(Vector((sx * 0.1, hf, hz))), fist=0.5)
        rig.key(f)
    finish(rig, act, cyclic=False)


def death(rig):
    """Cambaleia, cai de joelhos e desaba de bruços."""
    act = new_action(rig, "death", 50)
    keys = [  # quadro, deslocamento do quadril (y, z), inclinação do quadril, tronco
        (0, (0.0, -0.03), 0, 4),
        (8, (0.03, -0.12), 5, 20),
        (18, (0.05, -0.5), 10, 30),
        (30, (-0.25, -0.62), 55, 25),
        (40, (-0.55, -0.8), 85, 5),
        (50, (-0.6, -0.84), 88, 0),
    ]
    for f, (dy, dz), tilt, lean in keys:
        rig.begin()
        rig.pelvis(Vector((0, dy, dz)), pitch=tilt, roll=6 * (f > 20))
        rig.torso(lean=tilt + lean, roll=-8 * (f > 20))
        rig.head(pitch=tilt + lean + 10, yaw=25 * (f > 30))
        k = smooth(f / 18)
        lay = smooth((f - 25) / 20)
        for side, x in (("L", 0.12), ("R", -0.12)):
            hip = rig.pos(f"upperleg01.{side}")
            stand = Vector((x, 0.0, rig.ground_ankle))
            kneel = Vector((x, hip.y + 0.3, rig.ground_ankle + 0.07))
            back = hip + rig.world("root") @ Vector((0, 0.0, -0.85))
            back.x = x * 1.3
            rig.foot(side, stand.lerp(kneel, k).lerp(back, lay), pitch=-60 * k * (1 - lay))
        for side in ("L", "R"):
            sx = 1.0 if side == "L" else -1.0
            fall = smooth((f - 22) / 15)
            local = Vector((sx * (0.1 + 0.25 * fall), -0.2 - 0.25 * fall, -0.5 + 0.3 * fall))
            rig.hand(side, rig.shoulder_pos(side) + rig.chest_vec(local), fist=0.1)
        rig.key(f)
    finish(rig, act, cyclic=False)


# ---------------------------------------------------------------- armas (corpo superior)

def stand_base(rig, lean=3.0, yaw=0.0, width=0.14, stagger=0.12):
    rig.pelvis(Vector((0, 0, -0.035)), yaw=yaw * 0.3)
    rig.torso(lean=lean, yaw=yaw * 0.7)
    rig.foot("L", Vector((width, -stagger, rig.ground_ankle)), yaw=10)
    rig.foot("R", Vector((-width, stagger, rig.ground_ankle)), yaw=-15)


def melee_grip(rig, grip_r, weapon_dir, palm_fwd):
    """Mão direita segura a arma; a esquerda segura logo abaixo no cabo (duas mãos)."""
    w = weapon_dir.normalized()
    rig.hand("R", grip_r, fwd=palm_fwd, thumb=w, fist=1.0)
    rig.hand("L", grip_r - w * 0.09, fwd=palm_fwd, thumb=w, fist=1.0)


MELEE_REST = (Vector((-0.02, -0.22, -0.42)), Vector((0.35, -0.35, 0.85)))


def hold_melee(rig):
    frames = 60
    act = new_action(rig, "hold_melee", frames)
    for f in range(0, frames + 1, 6):
        b = math.sin(2 * math.pi * f / frames)
        rig.begin()
        stand_base(rig)
        rig.head(pitch=2)
        local, wdir = MELEE_REST
        grip = rig.shoulder_pos("R") + rig.chest_vec(local + Vector((0, 0, 0.005 * b)))
        melee_grip(rig, grip, rig.chest_vec(wdir), rig.chest_vec(Vector((0.0, -0.3, -1.0))))
        rig.key(f)
    finish(rig, act)


def attack_melee(rig):
    """Golpe com as duas mãos: prepara sobre o ombro direito, gira o quadril e atravessa."""
    act = new_action(rig, "attack_melee", 24)
    keys = [  # quadro, giro do tronco, inclinação, mão (referencial do peito), direção da arma
        (0, 0, 3) + MELEE_REST,
        (7, 42, -3, Vector((-0.22, 0.06, 0.1)), Vector((0.05, 0.8, 0.55))),
        (10, 30, 2, Vector((-0.2, -0.08, 0.0)), Vector((-0.35, 0.1, 1.0))),
        (13, -15, 10, Vector((0.0, -0.5, -0.2)), Vector((0.9, -0.45, 0.05))),
        (16, -45, 12, Vector((0.25, -0.3, -0.38)), Vector((0.9, 0.2, -0.35))),
        (24, 0, 3) + MELEE_REST,
    ]
    for f, yaw, lean, local, wdir in keys:
        rig.begin()
        stand_base(rig, lean=lean, yaw=yaw)
        rig.head(pitch=3, yaw=-yaw * 0.6)
        grip = rig.shoulder_pos("R") + rig.chest_vec(local)
        melee_grip(rig, grip, rig.chest_vec(wdir), rig.chest_vec(Vector((0.0, -0.3, -1.0))))
        rig.key(f)
    finish(rig, act, cyclic=False)


def pistol_pose(rig, kick=0.0, lower=0.0, left_to_hip=0.0):
    stand_base(rig, lean=6, width=0.15, stagger=0.1)
    rig.head(pitch=-4)
    chest_c = (rig.shoulder_pos("L") + rig.shoulder_pos("R")) * 0.5
    grip = chest_c + Vector((-0.03, -0.5 + kick * 0.04, -0.06 + kick * 0.05 - lower * 0.25))
    fwd = (FWD + Vector((0, 0, kick * 0.35 - lower * 0.5))).normalized()
    rig.hand("R", grip, fwd=fwd, thumb=Z.copy(), fist=0.95)
    # mão de apoio envolve a direita (ou vai até a cintura buscar o carregador)
    support = grip + Vector((0.035, 0.015, -0.03))
    hip_mag = rig.pos("pelvis.L") + Vector((0.05, -0.05, 0.05))
    rig.hand("L", support.lerp(hip_mag, left_to_hip), fwd=fwd.lerp(Vector((0, 0, -1)), left_to_hip).normalized(),
             thumb=Z.copy(), fist=0.85)


def hold_pistol(rig):
    frames = 60
    act = new_action(rig, "hold_pistol", frames)
    for f in range(0, frames + 1, 6):
        rig.begin()
        pistol_pose(rig, lower=0.03 * math.sin(2 * math.pi * f / frames))
        rig.key(f)
    finish(rig, act)


def fire_pistol(rig):
    act = new_action(rig, "fire_pistol", 8)
    for f, kick in ((0, 0.0), (1, 1.0), (3, 0.6), (8, 0.0)):
        rig.begin()
        pistol_pose(rig, kick=kick)
        rig.key(f)
    finish(rig, act, cyclic=False)


def reload_pistol(rig):
    act = new_action(rig, "reload_pistol", 36)
    for f, lower, hip in ((0, 0, 0), (6, 0.5, 0.0), (12, 0.5, 1.0), (20, 0.5, 1.0), (27, 0.5, 0.0), (36, 0, 0)):
        rig.begin()
        pistol_pose(rig, lower=lower, left_to_hip=hip)
        rig.key(f)
    finish(rig, act, cyclic=False)


def create_all(arm):
    bpy.context.scene.render.fps = FPS
    rig = Rig(arm)
    bpy.context.view_layer.objects.active = arm
    idle(rig)
    #                      ciclo passada apoio elev. larg. queda bob  fase  incl. q.yaw q.roll sway impacto braço amp
    locomotion(rig, "walk", Gait(1.05, (0.4, 0.45), 0.62, 0.1, 0.09, 0.035, 0.018, math.pi, 4, 5, 3, 0.02, 0.3,
                                 "walk", 18, heel=14, toe_off=20))
    locomotion(rig, "run", Gait(0.7, (0.3, 0.6), 0.36, 0.32, 0.06, 0.07, 0.035, 0.0, 10, 8, 4, 0.012, 1.0,
                                "run", 1.0, heel=6, toe_off=30, knee_kick=0.1))
    locomotion(rig, "sprint", Gait(0.6, (0.32, 0.72), 0.3, 0.45, 0.05, 0.095, 0.045, 0.0, 16, 10, 4, 0.008, 1.2,
                                   "run", 1.35, heel=2, toe_off=35, knee_kick=0.15))
    crouch_idle(rig)
    locomotion(rig, "crouch_walk", Gait(1.2, (0.35, 0.35), 0.66, 0.08, 0.13, 0.42, 0.012, math.pi, 26, 6, 3, 0.02, 0.2,
                                        "walk", 14, heel=8, toe_off=15))
    jump(rig)
    death(rig)
    hold_melee(rig)
    attack_melee(rig)
    hold_pistol(rig)
    fire_pistol(rig)
    reload_pistol(rig)
    for pb in rig.pb:
        pb.rotation_quaternion = Quaternion()
        pb.location = Vector()
    print("Animações:", sorted(a.name for a in bpy.data.actions))
