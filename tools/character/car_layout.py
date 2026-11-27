"""Medidas do carro compartilhadas entre o modelo (build_car.py) e as animações do motorista
(survivor_anims.py). Tudo em metros, no referencial do CARRO no Blender:
+Y = frente, +Z = cima, -X = lado esquerdo (motorista). Origem no chão, no centro entre os eixos.

O personagem sentado tem a origem em SEAT. Nas animações (referencial da armadura: -Y frente,
+X esquerda do personagem) um ponto do carro vira:  anim = (-(cx - sx), -(cy - sy), cz - sz).
"""

LENGTH, WIDTH, HEIGHT = 4.1, 1.76, 1.6
WHEELBASE, TRACK = 2.5, 1.5
WHEEL_RADIUS, WHEEL_WIDTH = 0.32, 0.21
AXLE_FRONT, AXLE_REAR = 1.25, -1.25

SEAT = (-0.37, -0.2, 0.15)               # origem do personagem sentado (abaixo do quadril)
STEER_CENTER = (-0.37, 0.18, 1.0)        # centro do volante
STEER_RADIUS = 0.18
STEER_TILT_DEG = 60.0                    # coluna inclinada (eixo do volante: 0, -0.87, 0.5)
DOOR_HINGE = (-0.875, 0.9)               # (x, y) da dobradiça da porta do motorista
DOOR_REAR_Y = -0.6
DOOR_Z = (0.3, 1.5)
DOOR_OPEN_DEG = 68.0
HANDLE_OUT = (-0.9, -0.48, 0.86)         # maçaneta externa (porta fechada)
EXIT = (-1.2, -0.62, 0.0)                # onde o personagem fica em pé ao lado da porta

TRUNK_HINGE = (-1.58, 1.57)              # (y, z) da dobradiça da tampa traseira (eixo X)
TRUNK_Y = (-2.15, -1.59)
TRUNK_Z = (0.9, 1.62)
TRUNK_HALF_W = 0.72
TRUNK_OPEN_DEG = 82.0

# Quadros (30 fps) da animação de entrar: porta abre e fecha nestes intervalos.
# A de sair é a mesma tocada de trás para frente.
ENTER_FRAMES = 56
DOOR_OPEN_F = (3, 12)
DOOR_CLOSE_F = (40, 48)


def to_anim(p):
    sx, sy, sz = SEAT
    return (-(p[0] - sx), -(p[1] - sy), p[2] - sz)


def door_angle(frame):
    """Ângulo de abertura da porta (graus) em cada quadro da animação de entrar."""
    a0, a1 = DOOR_OPEN_F
    c0, c1 = DOOR_CLOSE_F

    def s(t):
        t = min(max(t, 0.0), 1.0)
        return t * t * (3 - 2 * t)
    if frame <= a1:
        return DOOR_OPEN_DEG * s((frame - a0) / (a1 - a0))
    return DOOR_OPEN_DEG * (1 - s((frame - c0) / (c1 - c0)))
