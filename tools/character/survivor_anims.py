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
    def foot(self, side, target, pitch=0.0, yaw=0.0, knee_out=0.0, knee_back=0.0):
        """target: posição do tornozelo no mundo. pitch > 0: ponta do pé para cima.
        knee_out: 0 = joelho para a frente; 1 = joelho para o lado (pé apoiado na parede, sem
        o joelho entrar nela)."""
        l1, l2, rest_up, rest_low = self.leg[side]
        hip = self.pos(f"upperleg01.{side}")
        lateral = self.world("root") @ X
        out = lateral * (1.0 if side == "L" else -1.0)
        pole = (self.world("root") @ FWD) * (1.0 - knee_out) + out * knee_out - (self.world("root") @ Z) * 0.25 * knee_out
        if knee_back > 0.0:
            # perna arrastada atrás do corpo: joelho aponta para trás e para baixo
            pole = pole.lerp(-(self.world("root") @ FWD) - (self.world("root") @ Z) * 0.6, knee_back)
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


def _catmull(pts, t):
    """Curva suave (Catmull-Rom) que passa por todos os pontos (t, valores...) com t crescente."""
    for i in range(len(pts) - 1):
        t0, t1 = pts[i][0], pts[i + 1][0]
        if t <= t1 or i == len(pts) - 2:
            u = min(max((t - t0) / (t1 - t0), 0.0), 1.0)
            p0 = pts[max(i - 1, 0)][1:]
            p1 = pts[i][1:]
            p2 = pts[i + 1][1:]
            p3 = pts[min(i + 2, len(pts) - 1)][1:]
            out = []
            for a, b, c, d in zip(p0, p1, p2, p3):
                out.append(0.5 * ((2 * b) + (-a + c) * u + (2 * a - 5 * b + 4 * c - d) * u * u
                                  + (-a + 3 * b - 3 * c + d) * u ** 3))
            return out
    return list(pts[-1][1:])


def run_swing(g, t):
    """Balanço da perna na corrida, como um corredor de verdade: logo depois de tirar o pé do chão o
    calcanhar sobe em direção ao glúteo (o pé ainda atrás), o joelho é puxado para a frente e para
    cima, a perna se estende e o pé desce para pisar logo à frente do quadril (sem passada esticada).
    Retorna (frente, altura, inclinação)."""
    rf, rb, h = g.reach_f, g.reach_b, g.lift
    fwd, lift, pitch = _catmull([
        (0.0, -rb, 0.02, -g.toe_off),
        (0.28, -0.5 * rb, h, -45.0),
        (0.55, 0.55 * rf, 0.72 * h, -25.0),
        (0.8, 1.15 * rf, 0.22 * h, -2.0),
        (1.0, rf, 0.0, g.heel),
    ], t)
    return fwd, max(lift, 0.0), pitch


def foot_track(g, ph):
    """(frente, altura, inclinação) do pé numa fase 0..1 do seu próprio ciclo (0 = toca o chão)."""
    if ph >= g.duty and g.arm_mode == "run" and g.dir_y > 0.5:
        return run_swing(g, (ph - g.duty) / (1 - g.duty))
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


def arm_pendulum(rig, side, swing_deg, elbow_deg, out=0.06, inward=0.0, fist=0.2, palm_in=True, pole_out=0.3):
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
    pole = rig.chest_vec(Vector((sx * pole_out, 1.0, 0.0)))
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
        # corrida: o braço balança a partir do ombro com o cotovelo dobrado em ~90° (abre um pouco
        # atrás, fecha na frente); a mão vai do lado do quadril até a altura do peito, sem cruzar o
        # meio do corpo; mãos relaxadas, semifechadas
        amp = g.arm_amp
        front = max(swing, 0.0)
        back = max(-swing, 0.0)
        upper = amp * (-10 + 35 * swing)                 # graus: atrás -45, frente +25 (corrida)
        elbow = 94 + 14 * front - 2 * back               # cotovelo ~90° atrás, mais fechado na frente
        arm_pendulum(rig, side, upper, elbow, out=0.015, inward=0.12 * front + 0.03,
                     fist=0.55, palm_in=True, pole_out=0.08)


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


def pistol_pose(rig, kick=0.0, lower=0.0, left_to_hip=0.0, aim=0.0):
    """aim = 1: arma na altura dos olhos, cabeça baixa encostando a bochecha (mirando pela alça)."""
    stand_base(rig, lean=6 + 2 * aim, width=0.15, stagger=0.1)
    rig.head(pitch=-4 + 10 * aim, roll=-6 * aim, yaw=-4 * aim)
    rig.shoulders(raise_l=4 * aim, raise_r=6 * aim, fwd_l=6 * aim, fwd_r=4 * aim)
    chest_c = (rig.shoulder_pos("L") + rig.shoulder_pos("R")) * 0.5
    grip = chest_c + Vector((-0.03 + 0.005 * aim, -0.5 + kick * 0.04 + 0.04 * aim,
                             -0.06 + kick * 0.05 - lower * 0.25 + 0.2 * aim))
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


def aim_pistol(rig):
    """Mirando: pistola na linha dos olhos, braços quase esticados, respiração mexe pouco a mira."""
    frames = 60
    act = new_action(rig, "aim_pistol", frames)
    for f in range(0, frames + 1, 6):
        rig.begin()
        pistol_pose(rig, lower=0.012 * math.sin(2 * math.pi * f / frames), aim=1.0)
        rig.key(f)
    finish(rig, act)


def fire_pistol_aim(rig):
    act = new_action(rig, "fire_pistol_aim", 8)
    for f, kick in ((0, 0.0), (1, 0.8), (3, 0.45), (8, 0.0)):
        rig.begin()
        pistol_pose(rig, kick=kick, aim=1.0)
        rig.key(f)
    finish(rig, act, cyclic=False)


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


def hand_item_pose(rig, t, tilt):
    """Mão direita segurando um item: t=0 à frente da barriga, t=1 junto à boca.
    O cotovelo fica sempre para baixo e para fora (nunca cruza o corpo), o antebraço sobe
    por fora até a boca e o eixo do item (polegar) aponta para a boca, inclinando com `tilt`."""
    sh = rig.shoulder_pos("R")
    rest = sh + rig.chest_vec(Vector((-0.05, -0.3, -0.42)))
    mouth = mouth_pos(rig, 0.11)
    at_mouth = mouth + rig.chest_vec(Vector((-0.05, -0.11, -0.05)))
    k = smooth(t)
    # caminho em arco: sobe por fora e um pouco à frente (não atravessa o peito)
    mid = rest.lerp(at_mouth, k) + rig.chest_vec(Vector((-0.05, -0.06, 0.0))) * math.sin(math.pi * k)
    elbow_guess = sh + rig.chest_vec(Vector((-0.06, -0.12 - 0.08 * k, -0.27 + 0.05 * k)))
    fwd = (mid - elbow_guess).normalized()
    up = rig.chest_vec(Vector((0.0, 0.0, 1.0)))
    to_mouth = (mouth - mid)
    to_mouth = (to_mouth - up * to_mouth.dot(up) * 0.3).normalized()
    thumb = up.lerp(to_mouth, min(tilt * k, 1.0)).normalized()
    pole = rig.chest_vec(Vector((-0.45, -0.35 - 0.3 * k, -0.85)))
    rig.hand("R", mid, fwd=fwd, thumb=thumb, pole=pole, fist=0.85)


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
        hand_item_pose(rig, t, item_tilt)
        rig.shoulders(raise_r=4 * t)
        rig.key(f)
    finish(rig, act, cyclic=False)


def drink(rig):
    consume_anim(rig, "drink", 48, [
        (0, 0.0, 0, 0.0), (10, 0.9, 6, 0.5), (15, 1.0, 18, 0.9), (34, 1.0, 22, 1.0),
        (40, 0.85, 6, 0.4), (48, 0.0, 0, 0.0)])


def eat(rig):
    consume_anim(rig, "eat", 48, [
        (0, 0.0, 0, 0.0), (9, 1.0, -6, 0.35), (14, 0.8, -3, 0.25), (19, 1.0, -6, 0.35),
        (25, 0.8, -3, 0.25), (31, 1.0, -6, 0.35), (40, 0.5, 0, 0.1), (48, 0.0, 0, 0.0)])


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
VAULT_PATH = [(0, 0.0, 0.0), (6, 0.22, 0.0), (10, 0.4, 0.34), (14, 0.68, 0.5), (19, 1.0, 0.24),
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
        (10, (0.08, 30, -6, 1.0, 0.12, -0.08, 0.06, -0.3, 0.05, 0.4)),
        (12, (0.04, 26, -10, 1.0, 0.02, -0.08, 0.88, -0.38, -0.05, 0.75)),
        (14, (0.0, 22, -14, 1.0, -0.15, 0.06, 0.88, -0.42, 0.06, 0.88)),
        (19, (0.02, 12, -8, 0.4, -0.02, -0.05, 0.35, -0.2, -0.08, 0.3)),
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
            trailing = side == "L" and 8 <= f <= 14
            rig.foot(side, target, pitch=-20 * min(z * 3, 1.0), knee_out=0.8 if pu > 0.05 and not trailing else 0.0,
                     knee_back=0.9 if trailing else 0.0)
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
        (9, (0.12, 0.28, 0.25, -0.12, 0.33, 0.38)),
        (16, (0.12, 0.33, 0.55, -0.12, 0.33, 0.85)),
        (19, (0.12, 0.33, 0.65, -0.12, 0.38, top + 0.14)),
        (22, (0.12, 0.33, 0.75, -0.12, 0.62, top)),
        (26, (0.12, 0.36, top + 0.16, -0.12, 0.64, top)),
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
            rig.foot(side, world_to_local(rig, pf, pu, x, y, z, ankle=True), pitch=-30 if near_wall else 0,
                     knee_out=0.9 if z > 0.05 else 0.0)
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
        hand_item_pose(rig, 0.05 + 0.01 * b, 0.0)
        rig.key(f)
    finish(rig, act)


# ---------------------------------------------------------------- porta-malas e fogueira

def _lid_anim(rig, name, keys):
    """Mãos no porta-malas: keys = (quadro, altura das mãos (m, do chão), frente, inclinação)."""
    frames = keys[-1][0]
    act = new_action(rig, name, frames)
    for f, h, fwd, lean in keys:
        rig.begin()
        stand_base(rig, lean=lean, width=0.15, stagger=0.06)
        rig.head(pitch=-10 if h > 1.4 else 12)
        for side in ("L", "R"):
            sx = 1.0 if side == "L" else -1.0
            rig.hand(side, Vector((sx * 0.22, -fwd, h)), fist=0.6)
        rig.key(f)
    finish(rig, act, cyclic=False)


def trunk_open(rig):
    """Abre a tampa traseira: pega embaixo da tampa, destrava e empurra para cima."""
    _lid_anim(rig, "trunk_open", [(0, 0.75, 0.15, 3), (8, 0.95, 0.42, 14), (14, 1.0, 0.45, 12),
                                  (22, 1.55, 0.38, 2), (28, 1.85, 0.3, -4), (36, 0.8, 0.1, 3)])


def trunk_close(rig):
    """Fecha: alcança a borda da tampa no alto e puxa para baixo com força."""
    _lid_anim(rig, "trunk_close", [(0, 0.8, 0.1, 3), (8, 1.85, 0.3, -4), (14, 1.7, 0.35, 0),
                                   (22, 1.05, 0.45, 16), (26, 0.95, 0.42, 14), (34, 0.75, 0.12, 3)])


def build_fire(rig):
    """Ajoelhado, monta a fogueira: arruma as pedras e encosta as toras, uma mão de cada vez."""
    frames = 72
    act = new_action(rig, "build_fire", frames)
    keys = [0, 10, 20, 30, 40, 50, 60, 72]
    for i, f in enumerate(keys):
        k = 0.0 if f in (0, 72) else 1.0
        rig.begin()
        rig.pelvis(Vector((0, 0.08 * k, -0.48 * k - 0.03)), pitch=12 * k)
        rig.torso(lean=4 + 34 * k)
        rig.head(pitch=30 * k)
        rig.foot("L", Vector((0.15, -0.28 * k, rig.ground_ankle)), yaw=8)
        # joelho direito no chão: pé para trás, apoiado na ponta
        rig.foot("R", Vector((-0.14, 0.3 * k, rig.ground_ankle + 0.06 * k)), pitch=-55 * k, yaw=-8)
        a = i % 2
        reach_r = Vector((-0.1 - 0.08 * a, -0.55, 0.12 + 0.1 * (1 - a)))
        reach_l = Vector((0.12 + 0.06 * (1 - a), -0.5, 0.12 + 0.1 * a))
        rest_r = rig.shoulder_pos("R") + rig.chest_vec(Vector((-0.06, -0.05, -0.56)))
        rest_l = rig.shoulder_pos("L") + rig.chest_vec(Vector((0.06, -0.05, -0.56)))
        rig.hand("R", rest_r.lerp(reach_r, k), fist=0.4)
        rig.hand("L", rest_l.lerp(reach_l, k * (0.7 + 0.3 * a)), fist=0.4)
        rig.key(f)
    finish(rig, act, cyclic=False)


# ---------------------------------------------------------------- pulos, quedas e aterrissagens

def _air_pose(rig, drop, lean, feet, hands, fist=0.4, head=None):
    """feet: ((x, frente, altura, pitch) esq, dir) relativos ao corpo; hands: (frente, altura) relativos
    ao ombro no referencial do peito, por lado (esq, dir)."""
    rig.pelvis(Vector((0, 0, -drop)))
    rig.torso(lean=lean)
    rig.head(pitch=head if head is not None else -lean * 0.4)
    for side, (x, fw, up, pt) in zip(("L", "R"), feet):
        rig.foot(side, Vector((x, -fw, rig.ground_ankle + up)), pt)
    for side, (hf, hz, hx) in zip(("L", "R"), hands):
        sx = 1.0 if side == "L" else -1.0
        rig.hand(side, rig.shoulder_pos(side) + rig.chest_vec(Vector((sx * hx, -hf, hz))), fist=fist)


def jump(rig):
    """Pulo parado: agacha (preparação), estende o corpo jogando os braços para cima e encolhe no ar.
    O jogo aplica o impulso no quadro 4 (0,13 s), quando as pernas começam a estender."""
    act = new_action(rig, "jump", 18)
    keys = [  # quadro, queda quadril, inclinação, pés (x, frente, altura, pitch), mãos (frente, altura, lado)
        (0, (0.03, 3, (0.11, 0.0, 0.0, 0), (-0.11, 0.0, 0.0, 0), (0.0, -0.55, 0.08), (0.0, -0.55, 0.08))),
        (4, (0.24, 26, (0.12, 0.02, 0.0, 0), (-0.12, -0.02, 0.0, 0), (-0.22, -0.45, 0.12), (-0.22, -0.45, 0.12))),
        (7, (-0.02, 4, (0.11, 0.0, 0.04, -40), (-0.11, -0.03, 0.06, -45), (0.3, -0.05, 0.12), (0.28, -0.08, 0.12))),
        (12, (0.06, 8, (0.12, 0.08, 0.26, -10), (-0.12, -0.05, 0.2, -20), (0.22, -0.22, 0.16), (0.2, -0.25, 0.16))),
        (18, (0.08, 6, (0.12, 0.06, 0.22, 0), (-0.12, -0.02, 0.16, -10), (0.15, -0.3, 0.18), (0.15, -0.3, 0.18))),
    ]
    for f, (drop, lean, fl, fr, hl, hr) in keys:
        rig.begin()
        _air_pose(rig, drop, lean, (fl, fr), (hl, hr))
        rig.key(f)
    finish(rig, act, cyclic=False)


def jump_run(rig):
    """Pulo correndo: impulso com a perna esquerda, joelho direito sobe, braços em oposição; no ar as
    pernas fazem uma passada larga e se juntam para aterrissar."""
    act = new_action(rig, "jump_run", 18)
    keys = [
        (0, (0.06, 10, (0.11, -0.25, 0.0, -20), (-0.11, 0.2, 0.12, 0), (-0.25, -0.4, 0.1), (0.3, -0.2, 0.12))),
        (4, (0.0, 12, (0.11, -0.38, 0.08, -50), (-0.11, 0.35, 0.42, 10), (-0.3, -0.35, 0.12), (0.35, -0.05, 0.14))),
        (10, (0.02, 10, (0.11, -0.4, 0.3, -20), (-0.11, 0.4, 0.35, 10), (-0.15, -0.3, 0.2), (0.35, -0.1, 0.18))),
        (18, (0.08, 8, (0.11, 0.05, 0.25, 5), (-0.11, 0.15, 0.2, 5), (0.15, -0.3, 0.2), (0.2, -0.3, 0.2))),
    ]
    for f, (drop, lean, fl, fr, hl, hr) in keys:
        rig.begin()
        _air_pose(rig, drop, lean, (fl, fr), (hl, hr), fist=0.6)
        rig.key(f)
    finish(rig, act, cyclic=False)


def fall(rig):
    """Queda longa: braços abertos se equilibrando, pernas dobradas se preparando para o impacto."""
    frames = 24
    act = new_action(rig, "fall", frames)
    for f in range(0, frames + 1, 3):
        p = f / frames
        w = math.sin(2 * math.pi * p)
        rig.begin()
        _air_pose(rig, 0.06, 4 + 3 * w,
                  ((0.13, 0.1 + 0.05 * w, 0.22, -5), (-0.13, -0.05 - 0.05 * w, 0.28, -15)),
                  ((0.1 + 0.08 * w, -0.05, 0.4), (0.1 - 0.08 * w, -0.08, 0.4)), fist=0.2, head=12)
        rig.key(f)
    finish(rig, act)


def land(rig):
    """Aterrissagem leve: os joelhos absorvem o impacto e o corpo volta."""
    act = new_action(rig, "land", 12)
    keys = [(0, 0.1, 8, 0.1), (3, 0.24, 16, 0.25), (6, 0.2, 12, 0.2), (12, 0.03, 3, 0.0)]
    for f, drop, lean, arms in keys:
        rig.begin()
        _air_pose(rig, drop, lean, ((0.12, 0.03, 0.0, 0), (-0.12, -0.03, 0.0, 0)),
                  ((0.15 * arms + 0.05, -0.5 + arms * 0.2, 0.1), (0.15 * arms + 0.05, -0.5 + arms * 0.2, 0.1)), fist=0.3)
        rig.key(f)
    finish(rig, act, cyclic=False)


def land_hard(rig):
    """Queda alta: agacha fundo, apoia a mão direita no chão e levanta devagar."""
    act = new_action(rig, "land_hard", 30)
    keys = [(0, 0.2, 15, 0.0), (4, 0.5, 40, 1.0), (10, 0.52, 42, 1.0), (18, 0.35, 30, 0.4), (30, 0.03, 3, 0.0)]
    for f, drop, lean, touch in keys:
        rig.begin()
        rig.pelvis(Vector((0, 0.05, -drop)), pitch=lean * 0.3)
        rig.torso(lean=lean)
        rig.head(pitch=lean * 0.3)
        rig.foot("L", Vector((0.14, -0.08, rig.ground_ankle)), yaw=10)
        rig.foot("R", Vector((-0.14, 0.1, rig.ground_ankle + 0.03 * touch)), pitch=-25 * touch, yaw=-10)
        ground = Vector((-0.2, -0.32, 0.05))
        free = rig.shoulder_pos("R") + rig.chest_vec(Vector((-0.12, -0.2, -0.5)))
        rig.hand("R", free.lerp(ground, smooth(touch)), fist=0.1)
        rig.hand("L", rig.shoulder_pos("L") + rig.chest_vec(Vector((0.25, -0.15, -0.35))), fist=0.3)
        rig.key(f)
    finish(rig, act, cyclic=False)


# ---------------------------------------------------------------- escaladas por altura
# Subir em bloco baixo (caixas, capô): apoia as mãos, sobe um pé e fica de pé. Padrão: 0,9 m, face a 0,4 m.
MANTLE_PATH = [(0, 0.0, 0.0), (5, 0.15, 0.0), (10, 0.3, 0.35), (16, 0.42, 0.72), (22, 0.62, 0.9),
               (28, 0.72, 0.9)]
MANTLE_H, MANTLE_FACE = 0.9, 0.4
# Escalada alta: pula, agarra a borda com os braços esticados, fica pendurado se esforçando (pés
# raspando na parede), puxa o corpo, passa os cotovelos, engancha a perna e sobe. Padrão: 2,2 m.
CLIMB_HIGH_PATH = [(0, 0.0, 0.0), (6, 0.06, 0.0), (11, 0.14, 0.55), (16, 0.14, 0.22), (24, 0.15, 0.3),
                   (32, 0.15, 0.24), (42, 0.2, 0.85), (50, 0.3, 1.3), (58, 0.5, 1.75), (68, 0.78, 2.2),
                   (78, 0.9, 2.2)]
CLIMB_HIGH_H, CLIMB_HIGH_FACE = 2.2, 0.45


def mantle_low(rig):
    frames = MANTLE_PATH[-1][0]
    act = new_action(rig, "mantle_low", frames)
    top = MANTLE_H + 0.02
    keys = [(0, (0.03, 5, 0.0)), (5, (0.2, 30, 0.6)), (10, (0.15, 38, 1.0)), (16, (0.25, 30, 1.0)),
            (22, (0.15, 12, 0.3)), (28, (0.03, 4, 0.0))]
    feet_keys = [  # mundo: pé esq (x, frente, altura), pé dir
        (0, (0.11, 0.0, 0.0, -0.11, 0.0, 0.0)), (5, (0.12, 0.08, 0.0, -0.12, 0.15, 0.0)),
        (8, (0.12, 0.1, 0.0, -0.12, 0.3, top + 0.2)), (11, (0.12, 0.12, 0.0, -0.12, 0.5, top)),
        (16, (0.12, 0.27, 0.42, -0.12, 0.55, top)), (19, (0.12, 0.32, top + 0.16, -0.12, 0.58, top)),
        (22, (0.12, 0.62, top, -0.12, 0.62, top)), (28, (0.11, 0.72, top, -0.11, 0.72, top))]
    for f in range(frames + 1):
        pf, pu = path_at(MANTLE_PATH, f)
        drop, lean, hands = keyed(keys, f)
        rig.begin()
        rig.pelvis(Vector((0, 0, -drop)), pitch=lean * 0.2)
        rig.torso(lean=lean)
        rig.head(pitch=lean * 0.3)
        lx, ly, lz, rx, ry, rz = keyed(feet_keys, f)
        for side, x, y, z in (("L", lx, ly, lz), ("R", rx, ry, rz)):
            rig.foot(side, world_to_local(rig, pf, pu, x, y, z, ankle=True), pitch=-20 if 0.05 < z < top - 0.05 else 0,
                     knee_out=0.85 if z > 0.05 else 0.0)
        for side in ("L", "R"):
            sx = 1.0 if side == "L" else -1.0
            on_top = world_to_local(rig, pf, pu, sx * 0.2, MANTLE_FACE + 0.12, top)
            rest = rig.shoulder_pos(side) + rig.chest_vec(Vector((sx * 0.08, -0.1, -0.55)))
            rig.hand(side, rest.lerp(on_top, hands), fist=0.15)
        rig.key(f)
    finish(rig, act, cyclic=False)


def climb_high(rig):
    frames = CLIMB_HIGH_PATH[-1][0]
    act = new_action(rig, "climb_high", frames)
    top = CLIMB_HIGH_H + 0.02
    edge = CLIMB_HIGH_FACE + 0.05
    # quadro: (queda do quadril, inclinação do tronco, mãos na borda 0..1, cotovelo sobre a borda 0..1)
    keys = [(0, (0.03, 4, 0.0, 0.0)), (6, (0.24, 24, 0.0, 0.0)), (11, (0.0, -4, 1.0, 0.0)),
            (16, (0.0, -6, 1.0, 0.0)), (24, (0.04, -2, 1.0, 0.0)), (32, (0.0, -6, 1.0, 0.0)),
            (42, (0.06, 8, 1.0, 0.3)), (50, (0.1, 30, 1.0, 1.0)), (58, (0.18, 42, 1.0, 1.0)),
            (68, (0.25, 28, 0.3, 0.0)), (78, (0.03, 4, 0.0, 0.0))]
    # pés (mundo): no chão, depois raspando na parede (alternando) e por fim em cima
    feet_keys = [
        (0, (0.11, 0.0, 0.0, -0.11, 0.0, 0.0)), (6, (0.12, 0.06, 0.0, -0.12, 0.12, 0.0)),
        (11, (0.12, 0.2, 0.3, -0.12, 0.24, 0.2)), (16, (0.12, 0.33, 0.35, -0.12, 0.3, 0.12)),
        (20, (0.12, 0.31, 0.22, -0.12, 0.33, 0.45)), (24, (0.12, 0.33, 0.5, -0.12, 0.31, 0.3)),
        (28, (0.12, 0.31, 0.32, -0.12, 0.33, 0.52)), (32, (0.12, 0.33, 0.55, -0.12, 0.32, 0.38)),
        (42, (0.12, 0.32, 0.7, -0.12, 0.33, 0.9)), (50, (0.12, 0.33, 1.1, -0.12, 0.33, 1.3)),
        (54, (0.12, 0.33, 1.25, -0.12, 0.4, top + 0.2)), (58, (0.12, 0.32, 1.45, -0.12, 0.62, top)),
        (63, (0.12, 0.36, top + 0.18, -0.12, 0.7, top)), (68, (0.12, 0.7, top, -0.12, 0.78, top)),
        (78, (0.11, 0.9, top, -0.11, 0.9, top))]
    for f in range(frames + 1):
        pf, pu = path_at(CLIMB_HIGH_PATH, f)
        drop, lean, grab, over = keyed(keys, f)
        # esforço: tremor nos ombros enquanto pendurado e puxando
        strain = 1.0 if 14 <= f <= 48 else 0.0
        shake = strain * 2.5 * math.sin(f * 2.3)
        rig.begin()
        rig.pelvis(Vector((0, 0, -drop)), pitch=lean * 0.2, roll=shake * 0.5)
        rig.torso(lean=lean, roll=shake)
        rig.head(pitch=-25 + lean * 0.6 if f < 44 else lean * 0.4, yaw=shake * 2)
        lx, ly, lz, rx, ry, rz = keyed(feet_keys, f)
        for side, x, y, z in (("L", lx, ly, lz), ("R", rx, ry, rz)):
            near_wall = 0.05 < z < top - 0.05
            rig.foot(side, world_to_local(rig, pf, pu, x, y, z, ankle=True), pitch=-35 if near_wall else 0,
                     knee_out=0.9 if near_wall or z > 0.05 else 0.0)
        for side in ("L", "R"):
            sx = 1.0 if side == "L" else -1.0
            hold = world_to_local(rig, pf, pu, sx * 0.24, edge, top)
            # cotovelos sobre a borda: as mãos avançam e empurram para baixo
            push = world_to_local(rig, pf, pu, sx * 0.2, edge + 0.25, top)
            reach = rig.shoulder_pos(side) + rig.chest_vec(Vector((sx * 0.15, -0.2, 0.5)))
            rest = rig.shoulder_pos(side) + rig.chest_vec(Vector((sx * 0.08, -0.05, -0.55)))
            target = hold.lerp(push, over)
            if f < 11:
                target = rest.lerp(reach, smooth(f / 11))
            elif grab < 0.99:
                target = rest.lerp(target, grab)
            pole = rig.chest_vec(Vector((sx * 0.6, 0.6, -0.4)))
            rig.hand(side, target, pole=pole, fist=0.5 + 0.4 * grab)
        rig.shoulders(raise_l=8 * strain, raise_r=8 * strain)
        rig.key(f)
    finish(rig, act, cyclic=False)


# ---------------------------------------------------------------- carro (motorista)
# Origem da armadura = marcador "Seat" do carro; posições vêm de car_layout.py (mesmas do modelo).
import car_layout as CAR  # noqa: E402


def _car(p):
    return Vector(CAR.to_anim(p))


def _rot_door(p, deg):
    """Gira um ponto da porta em volta da dobradiça (porta abre para fora, para a esquerda)."""
    hx, hy = CAR.DOOR_HINGE
    a = math.radians(-deg)
    dx, dy = p[0] - hx, p[1] - hy
    return (hx + dx * math.cos(a) - dy * math.sin(a), hy + dx * math.sin(a) + dy * math.cos(a), p[2])


STEER_C = None


def _wheel_point(angle_deg):
    """Ponto no aro do volante. 0° = topo; positivo = sentido horário visto pelo motorista."""
    c = _car(CAR.STEER_CENTER)
    t = math.radians(CAR.STEER_TILT_DEG)
    up_plane = Vector((0.0, -math.cos(t), math.sin(t)))   # sobe e vai para frente no plano do volante
    right = Vector((-1.0, 0.0, 0.0))                       # direita do motorista
    a = math.radians(angle_deg)
    return c + (up_plane * math.cos(a) + right * math.sin(a)) * CAR.STEER_RADIUS


SEATED_PELVIS = Vector((0.0, 0.15, -0.45))
FLOOR_Z = 0.31 - CAR.SEAT[2]


def seated_base(rig, yaw=0.0, lean=-12.0, roll=0.0):
    rig.pelvis(SEATED_PELVIS, yaw=yaw, pitch=-8)
    rig.torso(lean=lean, roll=roll, yaw=yaw * 0.3)


def seated_feet(rig, left_out=0.0):
    rig.foot("R", Vector((-0.16, -0.62, FLOOR_Z + rig.ground_ankle + 0.02)), pitch=25)
    pedal = Vector((0.14, -0.6, FLOOR_Z + rig.ground_ankle + 0.02))
    rig.foot("L", pedal, pitch=25)


def drive_pose(rig, name, steer):
    """Sentado dirigindo: mãos no volante (10 e 2 horas) giradas `steer` graus, corpo acompanha a curva."""
    act = new_action(rig, name, 2)
    for f in (0, 2):
        rig.begin()
        seated_base(rig, lean=-12 + abs(steer) * 0.03, roll=-steer * 0.05)
        rig.head(pitch=6, yaw=-steer * 0.15)
        seated_feet(rig)
        for side, base in (("L", -60.0), ("R", 60.0)):
            sx = 1.0 if side == "L" else -1.0
            pole = rig.chest_vec(Vector((sx * 0.6, 0.2, -0.8)))
            rig.hand(side, _wheel_point(base + steer), pole=pole, fist=0.9)
        rig.key(f)
    finish(rig, act)


def car_enter_pose(rig, f):
    """Pose do quadro f (0..ENTER_FRAMES) da animação de entrar no carro pela porta do motorista."""
    ex = _car(CAR.EXIT)
    ground = ex.z
    door = CAR.door_angle(f)
    # quadro: pélvis (x, y, z relativos à origem), giro do corpo, inclinação, cabeça
    keys = [
        (0, (ex.x, ex.y, ground - 0.03, 0, 3, 0)),
        (12, (ex.x, ex.y - 0.05, ground - 0.05, 8, 6, 0)),
        (20, (0.42, 0.28, -0.28, 30, 24, 28)),
        (30, (0.04, 0.16, -0.45, 32, 2, 10)),
        (40, (0.0, 0.15, -0.45, 6, -10, 4)),
        (56, (0.0, 0.15, -0.45, 0, -12, 6)),
    ]
    px, py, pz, yaw, lean, head = keyed(keys, f)
    rig.begin()
    rig.pelvis(Vector((px, py, pz)), yaw=yaw, pitch=-8 * smooth((f - 20) / 10))
    rig.torso(lean=lean, yaw=yaw * 0.3)
    rig.head(pitch=head)
    gz = ground + rig.ground_ankle
    fz = FLOOR_Z + rig.ground_ankle + 0.02
    # pé direito: chão de fora -> entra no carro (passo) -> pedal
    rf = keyed([(0, (ex.x - 0.11, ex.y, gz)), (12, (ex.x - 0.11, ex.y - 0.05, gz)),
                (17, (0.3, -0.05, max(gz, fz) + 0.25)), (22, (0.0, -0.4, fz)), (56, (-0.16, -0.62, fz))], f)
    # pé esquerdo: fica fora até sentar, depois sobe e entra
    lf = keyed([(0, (ex.x + 0.11, ex.y, gz)), (30, (ex.x - 0.05, ex.y - 0.2, gz)),
                (35, (0.45, -0.3, fz + 0.35)), (40, (0.14, -0.6, fz)), (56, (0.14, -0.6, fz))], f)
    rig.foot("R", Vector(rf), pitch=20 * smooth((f - 22) / 8))
    rig.foot("L", Vector(lf), pitch=20 * smooth((f - 38) / 6))
    # mão direita: maçaneta externa (abre a porta) -> apoio no banco -> volante
    handle = _car(_rot_door(CAR.HANDLE_OUT, door))
    rest_r = rig.shoulder_pos("R") + rig.chest_vec(Vector((-0.08, -0.05, -0.55)))
    if f <= 3:
        rh = rest_r.lerp(handle, smooth(f / 3))
    elif f <= 10:
        rh = handle
    elif f <= 20:
        seat_edge = _car((CAR.SEAT[0] - 0.2, CAR.SEAT[1] + 0.05, 0.66))
        rh = handle.lerp(seat_edge, smooth((f - 10) / 10))
    elif f <= 46:
        seat_edge = _car((CAR.SEAT[0] - 0.2, CAR.SEAT[1] + 0.05, 0.66))
        rh = seat_edge.lerp(_wheel_point(60.0), smooth((f - 26) / 12))
    else:
        rh = _wheel_point(60.0)
    rig.hand("R", rh, fist=0.8)
    # mão esquerda: apoio no teto ao abaixar -> puxa a porta pela maçaneta interna -> volante
    roof = _car((-0.7, CAR.SEAT[1] + 0.05, 1.5))
    inner = _car(_rot_door((-0.8, -0.3, 0.86), door))
    rest_l = rig.shoulder_pos("L") + rig.chest_vec(Vector((0.08, -0.05, -0.55)))
    if f <= 12:
        lh = rest_l
    elif f <= 30:
        lh = rest_l.lerp(roof, smooth((f - 12) / 6))
    elif f <= 40:
        lh = roof.lerp(_car(_rot_door((-0.8, -0.3, 0.86), CAR.DOOR_OPEN_DEG)), smooth((f - 30) / 8))
    elif f <= 48:
        lh = inner
    else:
        lh = inner.lerp(_wheel_point(-60.0), smooth((f - 48) / 8))
    rig.hand("L", lh, pole=rig.chest_vec(Vector((0.6, 0.3, -0.6))), fist=0.75)


def car_enter(rig):
    frames = CAR.ENTER_FRAMES
    act = new_action(rig, "car_enter", frames)
    for f in range(0, frames + 1, 2):
        car_enter_pose(rig, f)
        rig.key(f)
    finish(rig, act, cyclic=False)
    # sair = entrar de trás para frente (abre a porta por dentro, põe a perna para fora, levanta, fecha)
    act = new_action(rig, "car_exit", frames)
    for f in range(0, frames + 1, 2):
        car_enter_pose(rig, frames - f)
        rig.key(f)
    finish(rig, act, cyclic=False)


# ---------------------------------------------------------------- montaria (dragão)
# Origem da armadura = assento da sela (superfície). O dragão deitado deixa a sela ~1,95 m acima
# do chão; o jogador sobe pelo lado esquerdo (pisa no antebraço da asa dobrada).
RIDE_GROUND = -1.87
RIDE_SPOT = (1.75, 0.1)       # x (+ = esquerda), y (+ = trás) do lugar de montar, em relação à sela


def _ride_hips(rig):
    return Vector((0.0, 0.02, 0.1 - rig.rest_head["root"].z))


def ride_pose(rig, roll=0.0, lean=16.0, look=0.0):
    rig.pelvis(_ride_hips(rig), roll=roll * 0.5, pitch=6)
    rig.torso(lean=lean, roll=roll)
    rig.head(pitch=-lean * 0.6 + 4, yaw=look)
    # pernas abertas em volta do pescoço, joelhos para fora, pés soltos ao lado do corpo
    for side, sx in (("L", 1.0), ("R", -1.0)):
        rig.foot(side, Vector((sx * 0.5, -0.1, -0.68 + rig.ground_ankle * 0.3)), pitch=10, yaw=sx * 12, knee_out=0.75)
    horn = Vector((0.0, -0.36, 0.3))
    for side, sx in (("L", 1.0), ("R", -1.0)):
        rig.hand(side, horn + Vector((sx * 0.05, 0.0, -0.02 * sx)), pole=rig.chest_vec(Vector((sx * 0.7, 0.1, -0.6))), fist=0.9)


def ride(rig):
    for name, roll in (("ride", 0.0), ("ride_left", -14.0), ("ride_right", 14.0)):
        act = new_action(rig, name, 2)
        for f in (0, 2):
            rig.begin()
            ride_pose(rig, roll=roll, lean=16 + abs(roll) * 0.2, look=-roll * 1.2)
            rig.key(f)
        finish(rig, act)


def mount_dragon_pose(rig, f):
    gx, gy = RIDE_SPOT
    g = RIDE_GROUND
    hips = _ride_hips(rig)
    # quadro: pélvis (x, y, z), giro do corpo, inclinação
    keys = [
        (0, (gx, gy, g, -90, 4)),
        (8, (gx - 0.05, gy, g - 0.12, -90, 18)),
        (18, (gx - 0.25, gy, g + 0.7, -90, 30)),
        (28, (gx - 0.75, gy - 0.05, g + 1.45, -80, 40)),
        (38, (0.45, 0.02, hips.z + rig.rest_head["root"].z * 0 + 0.25, -40, 34)),
        (46, (0.05, hips.y, hips.z + 0.05, -6, 20)),
        (54, (0.0, hips.y, hips.z, 0, 16)),
    ]
    px, py, pz, yaw, lean = keyed(keys, f)
    rig.begin()
    rig.pelvis(Vector((px, py, pz)), yaw=yaw, pitch=6 * smooth((f - 40) / 10))
    rig.torso(lean=lean, yaw=yaw * 0.25)
    rig.head(pitch=-20 + 30 * smooth((f - 30) / 16))
    ga = g + rig.ground_ankle
    arm_step = (gx - 0.4, gy - 0.15, g + 0.62)       # antebraço da asa dobrada (degrau)
    ride_ankle = -0.68 + rig.ground_ankle * 0.3
    # virado para o dragão, o pé esquerdo fica à frente (-y) e o direito atrás (+y).
    # Esquerdo: pisa no antebraço da asa dobrada (degrau) e termina do lado esquerdo do pescoço.
    lf = keyed([(0, (gx, gy - 0.12, ga)), (8, (gx, gy - 0.12, ga)), (14, (arm_step[0], arm_step[1], arm_step[2] + rig.ground_ankle)),
                (26, (arm_step[0], arm_step[1], arm_step[2] + rig.ground_ankle)), (36, (0.62, -0.05, -0.5)),
                (46, (0.5, -0.1, ride_ankle)), (54, (0.5, -0.1, ride_ankle))], f)
    # Direito: sai do chão, passa por cima da sela por trás e desce do lado direito
    rf = keyed([(0, (gx, gy + 0.12, ga)), (18, (gx, gy + 0.12, ga)), (28, (gx - 0.55, gy + 0.35, g + 1.35)),
                (36, (0.1, 0.5, 0.42)), (42, (-0.45, 0.05, -0.2)), (48, (-0.5, -0.1, ride_ankle)), (54, (-0.5, -0.1, ride_ankle))], f)
    ko = 0.75 * smooth((f - 34) / 10)
    rig.foot("L", Vector(lf), pitch=10 * smooth((f - 44) / 6), knee_out=ko)
    rig.foot("R", Vector(rf), pitch=10 * smooth((f - 44) / 6), knee_out=ko, knee_back=0.4 * math.sin(math.pi * min(max((f - 20) / 22, 0), 1)))
    # mãos: alcança a borda da sela, puxa o corpo, depois segura o pito
    edge = Vector((0.45, -0.05, 0.12))
    horn = Vector((0.0, -0.36, 0.3))
    rest_r = rig.shoulder_pos("R") + rig.chest_vec(Vector((-0.08, -0.05, -0.55)))
    rest_l = rig.shoulder_pos("L") + rig.chest_vec(Vector((0.08, -0.05, -0.55)))
    k_reach = smooth(f / 8)
    k_horn = smooth((f - 40) / 10)
    rh = rest_r.lerp(edge + Vector((0, -0.25, 0.05)), k_reach).lerp(horn + Vector((-0.05, 0, 0.02)), k_horn)
    lh = rest_l.lerp(edge + Vector((0.05, 0.25, 0.0)), k_reach).lerp(horn + Vector((0.05, 0, -0.02)), k_horn)
    rig.hand("R", rh, fist=0.85)
    rig.hand("L", lh, fist=0.85)


def mount_dragon(rig):
    frames = 54
    act = new_action(rig, "mount_dragon", frames)
    for f in range(0, frames + 1, 2):
        mount_dragon_pose(rig, f)
        rig.key(f)
    finish(rig, act, cyclic=False)
    act = new_action(rig, "dismount_dragon", frames)
    for f in range(0, frames + 1, 2):
        mount_dragon_pose(rig, frames - f)
        rig.key(f)
    finish(rig, act, cyclic=False)


def create_all(arm):
    bpy.context.scene.render.fps = FPS
    rig = Rig(arm)
    bpy.context.view_layer.objects.active = arm
    idle(rig)
    #                      ciclo passada apoio elev. larg. queda bob  fase  incl. q.yaw q.roll sway impacto braço amp
    locomotion(rig, "walk", Gait(1.05, (0.4, 0.45), 0.62, 0.1, 0.09, 0.035, 0.018, math.pi, 4, 5, 3, 0.02, 0.3,
                                 "walk", 20, heel=14, toe_off=20))
    # corrida: cadência ~170 passos/min, pé pisa pouco à frente do quadril, voo curto entre os passos,
    # tronco levemente inclinado, ombros girando contra o quadril
    locomotion(rig, "run", Gait(0.7, (0.3, 0.6), 0.36, 0.4, 0.06, 0.07, 0.035, 0.0, 9, 7, 3, 0.01, 0.9,
                                "run", 1.0, heel=4, toe_off=28))
    locomotion(rig, "sprint", Gait(0.62, (0.34, 0.74), 0.3, 0.52, 0.05, 0.09, 0.045, 0.0, 15, 9, 3, 0.008, 1.1,
                                   "run", 1.3, heel=0, toe_off=35))
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
    #                                     ciclo  passada  apoio elev. larg. queda bob   fase  incl. q.yaw q.roll sway imp.
    locomotion(rig, "crouch_walk_back", Gait(1.25, (0.28, 0.28), 0.66, 0.07, 0.13, 0.42, 0.01, math.pi, 22, 4, 3,
                                             0.02, 0.2, "crouch", 6, heel=4, toe_off=10, direction=(0.0, -1.0)))
    for name, d in (("left", (-1.0, 0.0)), ("right", (1.0, 0.0))):
        locomotion(rig, f"crouch_walk_{name}", Gait(1.1, (0.22, 0.22), 0.6, 0.07, 0.18, 0.42, 0.01, math.pi, 24, 2,
                                                    4, 0.015, 0.2, "crouch", 5, heel=3, toe_off=8, direction=d))
    # andar mirando: joelhos levemente dobrados, passos curtos e "rolados", quase sem sobe-e-desce
    locomotion(rig, "walk_aim", Gait(1.0, (0.3, 0.32), 0.6, 0.07, 0.12, 0.07, 0.006, math.pi, 8, 2, 2, 0.015,
                                     0.12, "walk", 4, heel=10, toe_off=15))
    locomotion(rig, "walk_aim_back", Gait(1.05, (0.27, 0.27), 0.6, 0.07, 0.12, 0.07, 0.006, math.pi, 4, 2, 2,
                                          0.015, 0.12, "walk", 3, heel=4, toe_off=10, direction=(0.0, -1.0)))
    for name, d in (("left", (-1.0, 0.0)), ("right", (1.0, 0.0))):
        locomotion(rig, f"walk_aim_{name}", Gait(0.95, (0.22, 0.22), 0.55, 0.06, 0.17, 0.07, 0.006, math.pi, 6, 1,
                                                 3, 0.012, 0.12, "walk", 3, heel=3, toe_off=8, direction=d))
    jump(rig)
    jump_run(rig)
    fall(rig)
    land(rig)
    land_hard(rig)
    death(rig)
    hold_melee(rig)
    attack_melee(rig)
    hold_pistol(rig)
    fire_pistol(rig)
    reload_pistol(rig)
    aim_pistol(rig)
    fire_pistol_aim(rig)
    drink(rig)
    eat(rig)
    pickup(rig)
    vault(rig)
    climb(rig)
    mantle_low(rig)
    climb_high(rig)
    hold_item(rig)
    trunk_open(rig)
    trunk_close(rig)
    build_fire(rig)
    car_enter(rig)
    drive_pose(rig, "drive", 0.0)
    drive_pose(rig, "drive_left", -90.0)
    drive_pose(rig, "drive_right", 90.0)
    ride(rig)
    mount_dragon(rig)
    for pb in rig.pb:
        pb.rotation_quaternion = Quaternion()
        pb.location = Vector()
    print("Animações:", sorted(a.name for a in bpy.data.actions))
