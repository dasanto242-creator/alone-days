"""Animações do ZUMBI (mesmo esqueleto de jogo do sobrevivente).

Andar lento, mancando da perna direita (ela é arrastada), tronco torto para a esquerda,
cabeça caída de lado, um braço meio erguido e o outro pendurado balançando.
Tudo gerado por código, como as do sobrevivente.
"""
import math

import bpy
from mathutils import Quaternion, Vector

from survivor_anims import FPS, Gait, Rig, arm_pendulum, finish, foot_track, new_action, smooth

WALK_CYCLE = 1.7
# passada / apoio constante nas duas pernas => pés não deslizam (velocidade = passada / (apoio * ciclo))
GAIT_L = Gait(WALK_CYCLE, (0.17, 0.17), 0.52, 0.09, 0.1, 0.0, 0.0, 0.0, 0, 0, 0, 0, 0, "walk", 0,
              heel=10, toe_off=18)
GAIT_R = Gait(WALK_CYCLE, (0.22, 0.22), 0.68, 0.025, 0.12, 0.0, 0.0, 0.0, 0, 0, 0, 0, 0, "walk", 0,
              heel=0, toe_off=-8)  # perna ruim: quase não levanta, ponta do pé arrastando
WALK_SPEED = 0.34 / (0.52 * WALK_CYCLE)


def zombie_walk(rig):
    frames = round(WALK_CYCLE * FPS)
    act = new_action(rig, "z_walk", frames)
    for f in range(frames + 1):
        p = f / frames
        rig.begin()
        # apoio na perna ruim (R, fase 0..0.68): quadril afunda e o corpo tomba para esse lado
        on_bad = 0.5 - 0.5 * math.cos(2 * math.pi * min(p / 0.68, 1.0)) if p < 0.68 else 0.0
        lurch = math.sin(2 * math.pi * p)
        rig.pelvis(Vector((-0.03 - 0.035 * on_bad, 0, -0.05 - 0.045 * on_bad)),
                   yaw=-6 * lurch, roll=-4 + 9 * on_bad, pitch=6)
        rig.torso(lean=18 + 4 * on_bad, yaw=8 * lurch - 6, roll=-11 + 4 * on_bad)
        rig.head(pitch=14 + 6 * on_bad, yaw=-12 + 8 * math.sin(2 * math.pi * p + 1.2),
                 roll=22 + 5 * math.sin(2 * math.pi * p + 0.5))
        for side, g, off, x in (("R", GAIT_R, 0.0, -0.12), ("L", GAIT_L, 0.5, 0.11)):
            fwd, lift, pitch = foot_track(g, (p + off) % 1.0)
            # perna esquerda pisa um pouco para dentro (passo torto)
            cross = 0.035 * math.sin(math.pi * ((p + off) % 1.0)) if side == "L" else 0.0
            rig.foot(side, Vector((x - cross, -fwd, rig.ground_ankle + lift)), pitch,
                     yaw=(-18 if side == "R" else 6))
        # braço esquerdo meio erguido "procurando", direito pendurado e balançando solto
        sw = math.sin(2 * math.pi * (p - 0.12))
        arm_pendulum(rig, "L", 38 + 8 * sw, 30 + 6 * sw, out=0.12, inward=0.08, fist=0.45, palm_in=False)
        arm_pendulum(rig, "R", -2 + 14 * math.sin(2 * math.pi * (p - 0.2)), 8, out=0.1, fist=0.15)
        rig.shoulders(raise_l=6, raise_r=-5 + 3 * on_bad, fwd_l=8, fwd_r=4)
        rig.key(f)
    finish(rig, act)


def zombie_idle(rig):
    frames = 90
    act = new_action(rig, "z_idle", frames)
    for f in range(0, frames + 1, 3):
        p = f / frames
        sway = math.sin(2 * math.pi * p)
        rig.begin()
        rig.pelvis(Vector((0.03 * sway, 0, -0.06)), yaw=4 * sway, roll=-4 + 3 * sway, pitch=5)
        rig.torso(lean=16 + 3 * math.sin(4 * math.pi * p), yaw=-5 * sway, roll=-10 + 4 * sway)
        rig.head(pitch=20 + 5 * math.sin(2 * math.pi * p + 1), yaw=-15 * sway, roll=24 + 4 * sway)
        rig.foot("L", Vector((0.13, -0.08, rig.ground_ankle)), yaw=12)
        rig.foot("R", Vector((-0.14, 0.1, rig.ground_ankle + 0.01)), pitch=-6, yaw=-22)
        arm_pendulum(rig, "L", 14 + 5 * sway, 22, out=0.1, fist=0.3)
        arm_pendulum(rig, "R", -3 - 4 * sway, 8, out=0.09, fist=0.15)
        rig.shoulders(raise_l=3, raise_r=-6)
        rig.key(f)
    finish(rig, act)


def zombie_attack(rig):
    """Avança o tronco e agarra com as duas mãos (o golpe acerta por volta de 45% da animação)."""
    frames = 36
    act = new_action(rig, "z_attack", frames)
    keys = [  # quadro, alcance 0..1, inclinação do tronco, mãos fechadas
        (0, 0.0, 16, 0.2), (8, -0.2, 8, 0.0), (15, 1.0, 34, 0.2), (19, 1.0, 36, 0.85),
        (27, 0.5, 24, 0.85), (36, 0.0, 16, 0.3)]
    for f, reach, lean, fist in keys:
        rig.begin()
        lunge = max(reach, 0.0)
        rig.pelvis(Vector((0, -0.12 * lunge, -0.07 - 0.04 * lunge)), roll=-4, pitch=6 + 8 * lunge)
        rig.torso(lean=lean, roll=-8 * (1 - lunge))
        rig.head(pitch=10 + 14 * lunge, roll=20 * (1 - lunge), yaw=-8)
        rig.foot("L", Vector((0.12, -0.22 * lunge - 0.05, rig.ground_ankle)), yaw=10)
        rig.foot("R", Vector((-0.13, 0.15, rig.ground_ankle + 0.02)), pitch=-15, yaw=-20)
        for side in ("L", "R"):
            sx = 1.0 if side == "L" else -1.0
            up = 70 + 25 * reach
            arm_pendulum(rig, side, up, 50 - 35 * lunge, out=0.2 - 0.06 * lunge, inward=0.03 * lunge,
                         fist=fist, palm_in=False)
        rig.key(f)
    finish(rig, act, cyclic=False)


def zombie_hit(rig):
    """Reação a golpe: cabeça e tronco jogados para trás e para o lado, depois volta."""
    frames = 18
    act = new_action(rig, "z_hit", frames)
    for f, k in ((0, 0.0), (3, 1.0), (8, 0.7), (18, 0.0)):
        rig.begin()
        rig.pelvis(Vector((0.02 * k, 0.06 * k, -0.06)), roll=-4 + 6 * k, pitch=5 - 6 * k)
        rig.torso(lean=16 - 22 * k, yaw=15 * k, roll=-10 + 14 * k)
        rig.head(pitch=20 - 40 * k, yaw=20 * k, roll=24 - 10 * k)
        rig.foot("L", Vector((0.13, -0.08, rig.ground_ankle)), yaw=12)
        rig.foot("R", Vector((-0.14, 0.1 + 0.08 * k, rig.ground_ankle)), yaw=-22)
        arm_pendulum(rig, "L", 14 + 30 * k, 22 + 20 * k, out=0.1 + 0.2 * k, fist=0.2)
        arm_pendulum(rig, "R", -3 + 25 * k, 8 + 25 * k, out=0.09 + 0.2 * k, fist=0.1)
        rig.key(f)
    finish(rig, act, cyclic=False)


def zombie_death(rig):
    """Os joelhos cedem, tomba de lado e cai de costas."""
    frames = 42
    act = new_action(rig, "z_death", frames)
    keys = [  # quadro, (desloc. y, z), inclinação do quadril (para trás), rolagem
        (0, (0.0, -0.06), 5, -4), (8, (0.05, -0.25), -5, -10), (18, (0.15, -0.55), -20, -20),
        (28, (0.45, -0.8), -65, -25), (36, (0.65, -0.86), -86, -15), (42, (0.66, -0.87), -88, -12)]
    for f, (dy, dz), tilt, roll in keys:
        rig.begin()
        rig.pelvis(Vector((0, dy, dz)), pitch=tilt, roll=roll)
        rig.torso(lean=tilt - 6, roll=roll * 0.5)
        rig.head(pitch=tilt - 12, yaw=35 * smooth(f / 30), roll=20)
        k = smooth(f / 18)
        lay = smooth((f - 20) / 18)
        for side, x in (("L", 0.12), ("R", -0.13)):
            hip = rig.pos(f"upperleg01.{side}")
            stand = Vector((x, 0.0, rig.ground_ankle))
            kneel = Vector((x, -0.05, rig.ground_ankle + 0.05))
            flat = hip + rig.world("root") @ Vector((0, 0.0, -0.85))
            flat.x = x * 1.4
            rig.foot(side, stand.lerp(kneel, k).lerp(flat, lay), pitch=30 * k * (1 - lay))
        for side in ("L", "R"):
            fall = smooth((f - 16) / 20)
            arm_pendulum(rig, side, 10 + 80 * fall, 20 * (1 - fall), out=0.15 + 0.5 * fall, fist=0.1)
        rig.key(f)
    finish(rig, act, cyclic=False)


def create_all(arm):
    bpy.context.scene.render.fps = FPS
    rig = Rig(arm)
    bpy.context.view_layer.objects.active = arm
    zombie_idle(rig)
    zombie_walk(rig)
    zombie_attack(rig)
    zombie_hit(rig)
    zombie_death(rig)
    for pb in rig.pb:
        pb.rotation_quaternion = Quaternion()
        pb.location = Vector()
    print("Animações:", sorted(a.name for a in bpy.data.actions))
    print(f"Velocidade nominal z_walk: {WALK_SPEED:.3f} m/s")
