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


def basis_z(z_dir, y_ref):
    """Rotação cuja base tem Z = z_dir exato e Y = referência (ortogonalizada).
    Usada nas mãos com arma: a direção da arma manda, a palma se ajusta."""
    zv = z_dir.normalized()
    yv = y_ref - zv * y_ref.dot(zv)
    if yv.length < 1e-6:
        yv = Y - zv * Y.dot(zv)
    yv.normalize()
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
        self.rest_tail = {n: bone.tail_local.copy() for n, bone in b.items()}

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
            # eixo de dobra de cada dedo: em repouso os dedos já curvam levemente para a palma;
            # essa curvatura revela de que lado fica a palma (sem depender da orientação dos ossos)
            curl = {}
            for f in range(1, 6):
                j0 = 2 if f == 1 else 1
                prox = (self.rest_tail[f"finger{f}-{j0}.{s}"] - h[f"finger{f}-{j0}.{s}"]).normalized()
                dist = (self.rest_tail[f"finger{f}-3.{s}"] - h[f"finger{f}-3.{s}"]).normalized()
                palm_dir = dist - prox * dist.dot(prox)
                if palm_dir.length < 1e-4:
                    palm_dir = (h[f"finger3-1.{s}"] - h[f"finger2-1.{s}"]).cross(prox)
                curl[f] = prox.cross(palm_dir.normalized()).normalized()
            self.arm_rest[s] = {
                "curl": curl,
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
            hand_q = basis_z(thumb, fwd) @ basis_z(a["thumb"], a["fwd"]).inverted()
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
            # metade da torção da mão vai para o osso de torção do antebraço (só gira em volta do
            # eixo do antebraço, sem dobrá-lo — assim o punho não sai do lugar)
            r = fore_q.inverted() @ hand_q
            axis = a["fore"].normalized()
            proj = Vector((r.x, r.y, r.z)).dot(axis) * axis
            twist = Quaternion((r.w, proj.x, proj.y, proj.z))
            if twist.magnitude > 1e-6:
                twist.normalize()
                self.set(f"lowerarm02.{side}", fore_q @ Quaternion().slerp(twist, 0.5))
            self.set(f"wrist.{side}", hand_q)
        self.fingers(side, fist)

    def fingers(self, side, fist):
        """0 = mão aberta relaxada, 1 = punho fechado. A dobra é feita em torno do eixo calculado
        a partir da curvatura natural dos dedos (sempre em direção à palma)."""
        hand = self.world(f"wrist.{side}")
        curl = self.arm_rest[side]["curl"]
        for f in range(2, 6):
            total = 0.0
            for j in range(1, 4):
                total += (4 + 4 * j) + fist * (45 + 15 * j)
                self.set(f"finger{f}-{j}.{side}", hand @ Quaternion(curl[f], math.radians(total)))
        total = 0.0
        for j, (relaxed, closed) in ((2, (6, 22)), (3, (8, 35))):
            total += relaxed + fist * closed
            self.set(f"finger1-{j}.{side}", hand @ Quaternion(curl[1], math.radians(total)))

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
                 sway, impact, arm_mode, arm_amp, heel=12.0, toe_off=25.0, knee_kick=0.0, direction=(0.0, 1.0)):
        self.reach_f, self.reach_b = stride
        # direção do movimento no referencial do corpo: x = direita, y = frente
        self.dir_x, self.dir_y = direction
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
        rig.head(pitch=3 + 0.4 * g.lean + g.impact * 2.0 * imp, yaw=-g.pelvis_yaw * 0.2 * s)
        # direção do passo no mundo da armadura (frente = -Y, direita = -X)
        move = Vector((-g.dir_x, -g.dir_y, 0.0))
        targets = {}
        for side, off, x in (("R", 0.0, -g.width), ("L", 0.5, g.width)):
            fwd, lift, pitch = foot_track(g, (p + off) % 1.0)
            if g.dir_y < -0.5:
                pitch = -pitch * 0.5  # andando de costas: apoia a ponta primeiro
            elif abs(g.dir_x) > 0.5:
                pitch *= 0.3          # de lado: pé mais plano
            targets[side] = [Vector((x, 0.0, rig.ground_ankle + lift)) + move * fwd, pitch]
        # de lado as pernas nunca se cruzam: mantém o pé esquerdo sempre à esquerda do direito
        gap = targets["L"][0].x - targets["R"][0].x
        if gap < 0.12:
            push = (0.12 - gap) * 0.5
            targets["L"][0].x += push
            targets["R"][0].x -= push
        for side in ("R", "L"):
            rig.foot(side, targets[side][0], targets[side][1], yaw=-g.pelvis_yaw * 0.3 * s)
        for side, sign in (("L", 1.0), ("R", -1.0)):
            arm_cycle(rig, side, g, p, sign, imp)
        rig.shoulders(raise_l=1.5 * imp * g.impact, raise_r=1.5 * imp * g.impact, fwd_l=3 * s, fwd_r=-3 * s)
        rig.key(f)
    finish(rig, act)


def arm_pendulum(rig, side, swing_deg, elbow_deg, out=0.06, inward=0.0, fist=0.2, palm_in=True):
    """Braço pendurado como pêndulo: ângulo do braço (frente +) e dobra do cotovelo, em graus.
    Calcula onde a mão fica e deixa a IK resolver; a palma fica virada para a coxa."""
    a = rig.arm_rest[side]
    sx = 1.0 if side == "L" else -1.0
    sh = rig.shoulder_pos(side)
    # referencial do peito: x esquerda, y trás, z cima (frente = -y)
    def dir_at(deg):
        r = math.radians(deg)
        return rig.chest_vec(Vector((0.0, -math.sin(r), -math.cos(r))))
    lateral = rig.chest_vec(Vector((sx, 0, 0)))
    upper = (dir_at(swing_deg) + lateral * out).normalized()
    elbow = sh + upper * a["l1"]
    fore = (dir_at(swing_deg + elbow_deg) + lateral * (out * 0.5 - inward)).normalized()
    grip = elbow + fore * (a["l2"] + 0.07)
    thumb = rig.chest_vec(Vector((-sx * 0.25, -1.0, 0.0))) if palm_in else None
    pole = rig.chest_vec(Vector((sx * 0.3, 1.0, 0.0)))
    if thumb is not None:
        rig.hand(side, grip, fwd=fore, thumb=thumb, pole=pole, fist=fist)
    else:
        rig.hand(side, grip, pole=pole, fist=fist)


def arm_cycle(rig, side, g, p, sign, imp):
    """Braços opostos às pernas, com atraso (o braço é arrastado pelo ombro, não dirigido)."""
    lag = 0.07 if g.arm_mode != "run" else 0.04
    swing = sign * math.sin(2 * math.pi * (p - lag))        # +1: braço à frente
    if g.arm_mode == "walk":
        fwd = max(swing, 0.0)
        rig_deg = 4 + g.arm_amp * swing
        elbow = 10 + 22 * fwd + 4 * math.sin(2 * math.pi * (p - lag - 0.1))
        arm_pendulum(rig, side, rig_deg, elbow, out=0.07, inward=0.06 * fwd, fist=0.18)
    elif g.arm_mode == "crouch":
        # braços à frente e afastados para equilíbrio, balanço curto
        arm_pendulum(rig, side, 28 + 9 * swing, 48 + 8 * max(swing, 0.0), out=0.16, inward=0.05, fist=0.35)
    else:
        # corrida: cotovelo ~90° colado ao corpo; mão vai do quadril (atrás) até a altura do peito (frente)
        sx = 1.0 if side == "L" else -1.0
        sh = rig.shoulder_pos(side)
        t = 0.5 + 0.5 * swing
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
            arm_pendulum(rig, side, 3 + 1.5 * breath + sx * b, 14 + sx * 3, out=0.08, fist=0.22)
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
            # um antebraço apoiado sobre o joelho, o outro solto à frente
            arm_pendulum(rig, side, 32 + 4 * b * sx, 55 if side == "L" else 40, out=0.15, inward=0.04, fist=0.35)
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
    """Duas mãos no cabo: direita em cima, esquerda 10 cm abaixo (perto do pomo)."""
    w = weapon_dir.normalized()
    rig.hand("R", grip_r, fwd=palm_fwd, thumb=w, fist=1.0)
    rig.hand("L", grip_r - w * 0.1, fwd=palm_fwd, thumb=w, fist=1.0)


def chest_center(rig):
    return (rig.shoulder_pos("L") + rig.shoulder_pos("R")) * 0.5


# mãos na frente do corpo, taco apoiado sobre o ombro direito (referencial do peito: x esq, y trás, z cima)
MELEE_REST = (Vector((0.0, -0.27, -0.34)), Vector((-0.35, 0.3, 0.88)))
PALM_FWD = Vector((0.0, -1.0, -0.4))


def _melee_frame(rig, local, wdir, yaw=0.0, lean=3.0):
    rig.begin()
    stand_base(rig, lean=lean, yaw=yaw)
    rig.head(pitch=3, yaw=-yaw * 0.6)
    grip = chest_center(rig) + rig.chest_vec(local)
    melee_grip(rig, grip, rig.chest_vec(wdir), rig.chest_vec(PALM_FWD))


def hold_melee(rig):
    frames = 60
    act = new_action(rig, "hold_melee", frames)
    for f in range(0, frames + 1, 6):
        b = math.sin(2 * math.pi * f / frames)
        local, wdir = MELEE_REST
        _melee_frame(rig, local + Vector((0, 0, 0.006 * b)), wdir)
        rig.key(f)
    finish(rig, act)


def attack_melee(rig):
    """Golpe com as duas mãos: leva o taco para trás do ombro, gira o quadril e atravessa na frente."""
    act = new_action(rig, "attack_melee", 24)
    keys = [  # quadro, giro do tronco, inclinação, mãos (peito), direção da arma
        (0, 0, 3) + MELEE_REST,
        (7, 40, -2, Vector((-0.16, -0.12, -0.18)), Vector((-0.25, 0.75, 0.6))),
        (10, 25, 3, Vector((-0.12, -0.28, -0.26)), Vector((-0.75, -0.1, 0.65))),
        (13, -15, 10, Vector((0.0, -0.42, -0.3)), Vector((0.75, -0.65, 0.05))),
        (16, -40, 12, Vector((0.12, -0.3, -0.38)), Vector((0.9, 0.3, -0.25))),
        (24, 0, 3) + MELEE_REST,
    ]
    for f, yaw, lean, local, wdir in keys:
        _melee_frame(rig, local, wdir, yaw, lean)
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


# ---------------------------------------------------------------- ações do dia a dia

def mouth_pos(rig, forward=0.1):
    return rig.pos("head") + rig.world("head") @ Vector((0.0, -forward, 0.035))


def consume_anim(rig, name, frames, keys):
    """Leva o item à boca. keys: (quadro, 0..1 = quanto a mão está na boca, inclinação da cabeça, inclinação do item)."""
    act = new_action(rig, name, frames)
    for f, t, head_tilt, item_tilt in keys:
        rig.begin()
        rig.pelvis(Vector((0, 0, -0.025)))
        rig.torso(lean=2 - head_tilt * 0.15)
        rig.head(pitch=-head_tilt)
        rig.foot("L", Vector((0.12, -0.04, rig.ground_ankle)), yaw=8)
        rig.foot("R", Vector((-0.12, 0.05, rig.ground_ankle)), yaw=-10)
        arm_pendulum(rig, "L", 4, 14, out=0.08, fist=0.22)
        rest = rig.shoulder_pos("R") + rig.chest_vec(Vector((-0.05, -0.28, -0.42)))
        at_mouth = mouth_pos(rig) + rig.chest_vec(Vector((-0.02, -0.02, -0.03)))
        grip = rest.lerp(at_mouth, smooth(t))
        # item em pé na mão; ao beber inclina com o topo para a boca
        up = rig.chest_vec(Vector((0.0, item_tilt, 1.0)))
        rig.hand("R", grip, fwd=rig.chest_vec(Vector((0.0, -1.0, 0.2))), thumb=up, fist=0.85)
        rig.key(f)
    finish(rig, act, cyclic=False)


def drink(rig):
    consume_anim(rig, "drink", 48, [
        (0, 0.0, 0, 0.0), (10, 1.0, 10, 0.4), (16, 1.0, 20, 1.1), (34, 1.0, 22, 1.2),
        (40, 0.9, 8, 0.4), (48, 0.0, 0, 0.0)])


def eat(rig):
    consume_anim(rig, "eat", 48, [
        (0, 0.0, 0, 0.0), (9, 1.0, -6, 0.2), (14, 0.75, -4, 0.1), (19, 1.0, -6, 0.2),
        (25, 0.75, -4, 0.1), (31, 1.0, -6, 0.2), (40, 0.5, 0, 0.0), (48, 0.0, 0, 0.0)])


def pickup(rig):
    """Agacha dobrando os joelhos, alcança o chão à frente com a mão direita e levanta."""
    act = new_action(rig, "pickup", 33)
    keys = [  # quadro, queda do quadril, inclinação do tronco, mão (0 = solta, 1 = no chão), mão fechada
        (0, 0.03, 3, 0.0, 0.2), (8, 0.36, 36, 0.6, 0.2), (13, 0.52, 50, 1.0, 0.3),
        (17, 0.52, 50, 1.0, 0.9), (25, 0.25, 22, 0.4, 0.9), (33, 0.03, 3, 0.0, 0.3)]
    for f, drop, lean, reach, fist in keys:
        rig.begin()
        rig.pelvis(Vector((0, 0.1 * drop / 0.52, -drop)), pitch=lean * 0.3)
        rig.torso(lean=lean)
        rig.head(pitch=lean * 0.5)
        rig.foot("L", Vector((0.15, -0.12, rig.ground_ankle)), yaw=10)
        rig.foot("R", Vector((-0.15, 0.14, rig.ground_ankle + 0.05 * drop / 0.52)), pitch=-35 * drop / 0.52, yaw=-12)
        ground = Vector((-0.1, -0.42, 0.12))
        rest = rig.shoulder_pos("R") + rig.chest_vec(Vector((-0.05, -0.05, -0.56)))
        grip = rest.lerp(ground, smooth(reach))
        rig.hand("R", grip, fist=fist)
        arm_pendulum(rig, "L", 15 + 25 * reach, 30 + 30 * reach, out=0.12, fist=0.3)
        rig.key(f)
    finish(rig, act, cyclic=False)


# ---------------------------------------------------------------- parkour
# Trajetória do personagem (frente, altura) em metros por quadro-chave. O jogo usa EXATAMENTE
# estas tabelas (scripts/player/parkour.gd) para mover o corpo, escalando para o obstáculo real.
# Salto (vault): muro padrão de 1,0 m de altura, face a 0,5 m, espessura 0,3 m.
VAULT_PATH = [(0, 0.0, 0.0), (6, 0.22, 0.0), (10, 0.42, 0.2), (14, 0.68, 0.32), (19, 1.0, 0.15),
              (24, 1.3, 0.0), (28, 1.4, 0.0)]
VAULT_H, VAULT_FACE, VAULT_THICK = 1.0, 0.5, 0.3
# Escalada (climb): borda padrão de 1,5 m, face a 0,45 m.
CLIMB_PATH = [(0, 0.0, 0.0), (5, 0.08, 0.0), (9, 0.2, 0.25), (16, 0.25, 0.75), (22, 0.35, 1.15),
              (30, 0.6, 1.45), (37, 0.85, 1.5), (44, 0.9, 1.5)]
CLIMB_H, CLIMB_FACE = 1.5, 0.45


def path_at(path, f):
    for (f0, a0, b0), (f1, a1, b1) in zip(path, path[1:]):
        if f0 <= f <= f1:
            t = (f - f0) / (f1 - f0)
            return a0 + (a1 - a0) * t, b0 + (b1 - b0) * t
    return path[-1][1], path[-1][2]


def keyed(keys, f):
    """Interpola (suave) tuplas numéricas entre quadros-chave: keys = [(quadro, (valores...)), ...]."""
    for (f0, v0), (f1, v1) in zip(keys, keys[1:]):
        if f0 <= f <= f1:
            t = smooth((f - f0) / (f1 - f0))
            return [a + (b - a) * t for a, b in zip(v0, v1)]
    return list(keys[-1][1])


def world_to_local(rig, pf, pu, x, fwd, up, ankle=False):
    """Ponto fixo no mundo (relativo ao início do movimento) -> espaço da armadura no quadro atual."""
    return Vector((x, -(fwd - pf), (rig.ground_ankle if ankle else 0.0) + up - pu))


def vault(rig):
    """Salto lateral sobre muro baixo (speed vault): mão esquerda apoia no topo, pernas passam de lado."""
    frames = VAULT_PATH[-1][0]
    act = new_action(rig, "vault", frames)
    top = VAULT_H + 0.03
    hand_l = (0.1, VAULT_FACE + 0.12, top)
    # quadro: (queda do quadril, inclinação, rolagem, apoio da mão esq 0..1,
    #          pé esq (x, frente local, altura local), pé dir (x, frente, altura))
    keys = [
        (0, (0.03, 6, 0, 0.0, 0.11, 0.05, 0.0, -0.11, -0.1, 0.0)),
        (6, (0.14, 24, 0, 0.3, 0.12, 0.12, 0.0, -0.1, -0.15, 0.05)),
        (10, (0.08, 30, -6, 1.0, 0.12, 0.15, 0.0, -0.2, -0.25, 0.45)),
        (14, (0.0, 22, -14, 1.0, -0.12, -0.1, 0.62, -0.32, -0.25, 0.7)),
        (19, (0.02, 12, -8, 0.4, -0.02, -0.15, 0.35, -0.2, -0.2, 0.3)),
        (24, (0.22, 20, 0, 0.0, 0.12, 0.05, 0.0, -0.12, -0.12, 0.0)),
        (28, (0.05, 6, 0, 0.0, 0.11, 0.02, 0.0, -0.11, -0.05, 0.0)),
    ]
    for f in range(frames + 1):
        pf, pu = path_at(VAULT_PATH, f)
        drop, lean, roll, plant, lx, ly, lz, rx, ry, rz = keyed(keys, f)
        rig.begin()
        rig.pelvis(Vector((0, 0, -drop)), roll=roll * 0.5)
        rig.torso(lean=lean, roll=roll)
        rig.head(pitch=lean * 0.4)
        # pés: no apoio ficam no chão do mundo; no ar seguem a pose (relativa ao corpo)
        on_ground = pu < 0.02
        for side, x, y, z in (("L", lx, ly, lz), ("R", rx, ry, rz)):
            target = Vector((x, -y, rig.ground_ankle + z - (0.0 if not on_ground else 0.0)))
            if f >= 9 and pu > 0.0:
                target.z = max(target.z, rig.ground_ankle + z)
            rig.foot(side, target, pitch=-20 * min(z * 3, 1.0))
        # mão esquerda: sobe até o topo do muro e fica apoiada enquanto o corpo passa
        free_l = rig.shoulder_pos("L") + rig.chest_vec(Vector((0.12, -0.3, -0.3)))
        planted = world_to_local(rig, pf, pu, *hand_l)
        rig.hand("L", free_l.lerp(planted, plant), fist=0.1)
        # mão direita: vai à frente para equilíbrio e aterrissagem
        bal = keyed([(0, (-0.12, -0.25, -0.45)), (10, (-0.2, -0.45, -0.1)), (19, (-0.35, -0.3, -0.25)),
                     (24, (-0.2, -0.35, -0.45)), (28, (-0.08, -0.05, -0.56))], f)
        rig.hand("R", rig.shoulder_pos("R") + rig.chest_vec(Vector(bal)), fist=0.2)
        rig.key(f)
    finish(rig, act, cyclic=False)


def climb(rig):
    """Escalada de borda alta (mantle): pula, agarra a borda, empurra, sobe um joelho e fica de pé."""
    frames = CLIMB_PATH[-1][0]
    act = new_action(rig, "climb", frames)
    top = CLIMB_H + 0.02
    edge = CLIMB_FACE + 0.06
    # quadro: (queda do quadril, inclinação, mãos na borda 0..1, pés: modo parede/joelho)
    keys = [
        (0, (0.03, 4, 0.0)), (5, (0.2, 22, 0.0)), (9, (0.05, 10, 1.0)), (16, (0.0, 28, 1.0)),
        (22, (0.12, 38, 1.0)), (30, (0.25, 30, 0.5)), (37, (0.12, 12, 0.0)), (44, (0.03, 4, 0.0))]
    # pés no mundo (x, frente, altura): pé esq e dir em cada quadro-chave
    feet_keys = [
        (0, (0.11, 0.0, 0.0, -0.11, 0.0, 0.0)),
        (5, (0.12, 0.05, 0.0, -0.12, 0.1, 0.0)),
        (9, (0.12, 0.3, 0.3, -0.12, 0.38, 0.55)),
        (16, (0.12, 0.38, 0.55, -0.12, 0.4, 0.85)),
        (22, (0.12, 0.38, 0.75, -0.12, 0.62, top)),
        (30, (0.12, 0.6, top + 0.15, -0.12, 0.66, top)),
        (37, (0.12, 0.86, top, -0.12, 0.8, top)),
        (44, (0.11, 0.9, top, -0.11, 0.9, top)),
    ]
    for f in range(frames + 1):
        pf, pu = path_at(CLIMB_PATH, f)
        drop, lean, grab = keyed(keys, f)
        rig.begin()
        rig.pelvis(Vector((0, 0, -drop)), pitch=lean * 0.2)
        rig.torso(lean=lean)
        rig.head(pitch=-10 + lean * 0.5)
        lx, ly, lz, rx, ry, rz = keyed(feet_keys, f)
        for side, x, y, z in (("L", lx, ly, lz), ("R", rx, ry, rz)):
            near_wall = z > 0.05 and z < top - 0.05
            rig.foot(side, world_to_local(rig, pf, pu, x, y, z, ankle=True), pitch=-30 if near_wall else 0)
        for side in ("L", "R"):
            sx = 1.0 if side == "L" else -1.0
            reach = rig.shoulder_pos(side) + rig.chest_vec(Vector((sx * 0.15, -0.35, 0.25)))
            hold = world_to_local(rig, pf, pu, sx * 0.22, edge, top)
            rest = rig.shoulder_pos(side) + rig.chest_vec(Vector((sx * 0.08, -0.05, -0.55)))
            target = reach.lerp(hold, grab) if f <= 9 else (hold if grab > 0.99 else rest.lerp(hold, grab))
            if f < 5:
                target = rest.lerp(reach, smooth(f / 5))
            rig.hand(side, target, fist=0.35 + 0.4 * grab)
        rig.key(f)
    finish(rig, act, cyclic=False)


def hold_item(rig):
    """Segurando um item na mão direita, à frente do corpo (camada do tronco/braços)."""
    act = new_action(rig, "hold_item", 60)
    for f in (0, 30, 60):
        b = math.sin(2 * math.pi * f / 60)
        rig.begin()
        rig.pelvis(Vector((0, 0, -0.025)))
        rig.torso(lean=3)
        rig.head(pitch=6)
        rig.foot("L", Vector((0.11, 0.0, rig.ground_ankle)))
        rig.foot("R", Vector((-0.11, 0.0, rig.ground_ankle)))
        arm_pendulum(rig, "L", 4, 14, out=0.08, fist=0.22)
        grip = rig.shoulder_pos("R") + rig.chest_vec(Vector((-0.02, -0.3, -0.36 + 0.005 * b)))
        rig.hand("R", grip, fwd=rig.chest_vec(Vector((0.3, -1.0, 0.3))), thumb=rig.chest_vec(Vector((0.0, 0.0, 1.0))),
                 fist=0.85)
        rig.key(f)
    finish(rig, act)


def create_all(arm):
    bpy.context.scene.render.fps = FPS
    rig = Rig(arm)
    bpy.context.view_layer.objects.active = arm
    idle(rig)
    #                      ciclo passada apoio elev. larg. queda bob  fase  incl. q.yaw q.roll sway impacto braço amp
    locomotion(rig, "walk", Gait(1.05, (0.4, 0.45), 0.62, 0.1, 0.09, 0.035, 0.018, math.pi, 4, 5, 3, 0.02, 0.3,
                                 "walk", 20, heel=14, toe_off=20))
    locomotion(rig, "run", Gait(0.7, (0.3, 0.6), 0.36, 0.32, 0.06, 0.07, 0.035, 0.0, 10, 8, 4, 0.012, 1.0,
                                "run", 1.0, heel=6, toe_off=30, knee_kick=0.1))
    locomotion(rig, "sprint", Gait(0.6, (0.32, 0.72), 0.3, 0.45, 0.05, 0.095, 0.045, 0.0, 16, 10, 4, 0.008, 1.2,
                                   "run", 1.35, heel=2, toe_off=35, knee_kick=0.15))
    # direcionais (usados com arma em mãos, corpo virado para a câmera)
    #                         ciclo  passada      apoio elev. larg. queda bob  fase  incl. q.yaw q.roll sway imp.
    for name, d in (("left", (-1.0, 0.0)), ("right", (1.0, 0.0))):
        locomotion(rig, f"walk_{name}", Gait(0.9, (0.25, 0.25), 0.55, 0.08, 0.15, 0.04, 0.012, math.pi, 3, 2, 4,
                                            0.015, 0.3, "walk", 8, heel=4, toe_off=10, direction=d))
        locomotion(rig, f"run_{name}", Gait(0.7, (0.35, 0.35), 0.4, 0.2, 0.15, 0.08, 0.03, 0.0, 7, 3, 5,
                                           0.01, 0.8, "run", 0.6, heel=2, toe_off=15, direction=d))
    locomotion(rig, "walk_back", Gait(1.1, (0.35, 0.35), 0.62, 0.09, 0.1, 0.04, 0.015, math.pi, -2, 4, 3, 0.02, 0.3,
                                      "walk", 12, heel=8, toe_off=12, direction=(0.0, -1.0)))
    locomotion(rig, "run_back", Gait(0.7, (0.3, 0.3), 0.4, 0.2, 0.08, 0.07, 0.03, 0.0, 2, 5, 3, 0.012, 0.7,
                                     "run", 0.7, heel=4, toe_off=15, direction=(0.0, -1.0)))
    crouch_idle(rig)
    locomotion(rig, "crouch_walk", Gait(1.2, (0.35, 0.35), 0.66, 0.08, 0.13, 0.42, 0.012, math.pi, 26, 6, 3, 0.02, 0.2,
                                        "crouch", 9, heel=8, toe_off=15))
    jump(rig)
    death(rig)
    hold_melee(rig)
    attack_melee(rig)
    hold_pistol(rig)
    fire_pistol(rig)
    reload_pistol(rig)
    drink(rig)
    eat(rig)
    pickup(rig)
    vault(rig)
    climb(rig)
    hold_item(rig)
    for pb in rig.pb:
        pb.rotation_quaternion = Quaternion()
        pb.location = Vector()
    print("Animações:", sorted(a.name for a in bpy.data.actions))
