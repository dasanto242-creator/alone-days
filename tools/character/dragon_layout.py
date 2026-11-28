"""Medidas do DRAGÃO (metros, eixos do Blender: +Y frente, +Z cima, +X direita).

Serpe (wyvern) de montaria: asas são os braços (como morcegos e pterossauros), anda em
quatro apoios usando os pulsos das asas como patas da frente. Envergadura ~16,6 m,
comprimento do focinho à ponta da cauda ~14 m, altura do dorso ~2,9 m.
Usado pelo build_dragon.py (modelo + animações) e espelhado em scripts/dragon/dragon.gd.
"""

# Linha central (y, z, meia-largura, meia-altura, expoente da seção, fator da barriga)
# da ponta da cauda até a ponta do focinho.
CENTER = [
    (-8.05, 0.86, 0.012, 0.012, 2.0, 1.0),
    (-7.6, 0.9, 0.035, 0.03, 2.0, 1.0),
    (-6.3, 1.06, 0.075, 0.07, 2.1, 1.0),
    (-5.0, 1.27, 0.13, 0.13, 2.1, 0.95),
    (-3.8, 1.5, 0.2, 0.2, 2.2, 0.95),
    (-2.6, 1.76, 0.3, 0.3, 2.2, 0.95),
    (-1.6, 1.96, 0.43, 0.41, 2.3, 0.95),
    (-0.9, 2.06, 0.58, 0.53, 2.4, 0.95),
    (-0.4, 2.06, 0.72, 0.7, 2.4, 1.08),
    (0.4, 2.1, 0.82, 0.8, 2.4, 1.18),
    (1.3, 2.17, 0.8, 0.84, 2.4, 1.12),
    (2.0, 2.36, 0.6, 0.66, 2.3, 1.05),
    (2.5, 2.6, 0.43, 0.46, 2.2, 1.0),
    (3.0, 2.86, 0.33, 0.38, 2.2, 1.0),
    (3.5, 3.1, 0.27, 0.32, 2.2, 1.0),
    (4.0, 3.35, 0.245, 0.29, 2.2, 1.0),
    (4.42, 3.53, 0.25, 0.27, 2.3, 1.0),
    (4.72, 3.64, 0.33, 0.3, 2.6, 0.85),
    (5.05, 3.63, 0.31, 0.26, 2.8, 0.7),
    (5.45, 3.55, 0.23, 0.2, 2.8, 0.6),
    (5.85, 3.45, 0.19, 0.15, 2.6, 0.6),
    (6.03, 3.4, 0.11, 0.09, 2.4, 0.7),
    (6.1, 3.38, 0.02, 0.02, 2.0, 1.0),
]

# Mandíbula (mesma convenção), dobradiça perto do fundo do crânio
JAW = [
    (4.58, 3.42, 0.24, 0.13, 2.4, 1.0),
    (5.0, 3.36, 0.23, 0.11, 2.4, 1.0),
    (5.5, 3.29, 0.18, 0.08, 2.4, 1.0),
    (5.93, 3.23, 0.1, 0.055, 2.2, 1.0),
    (6.0, 3.23, 0.03, 0.03, 2.0, 1.0),
]

ROOT_HEAD = (0.0, -0.4, 2.05)
SPINE = [(0.0, 0.3, 2.1), (0.0, 1.3, 2.2), (0.0, 2.1, 2.42)]          # spine1, chest
NECK = [(0.0, 2.1, 2.42), (0.0, 2.62, 2.66), (0.0, 3.12, 2.9), (0.0, 3.6, 3.14),
        (0.0, 4.05, 3.37), (0.0, 4.5, 3.56)]                             # neck1..5
HEAD_TAIL = (0.0, 5.95, 3.42)
JAW_BONE = ((0.0, 4.68, 3.4), (0.0, 5.85, 3.24))
TAIL = [(0.0, -0.4, 2.05), (0.0, -1.2, 1.97), (0.0, -2.0, 1.86), (0.0, -2.8, 1.72),
        (0.0, -3.6, 1.56), (0.0, -4.4, 1.39), (0.0, -5.15, 1.25), (0.0, -5.85, 1.12),
        (0.0, -6.5, 1.03), (0.0, -7.15, 0.95), (0.0, -7.75, 0.89)]       # tail1..10

# Perna direita (espelhar X para a esquerda): quadril, joelho, tornozelo, base dos dedos, ponta
LEG = [(0.55, -0.5, 1.85), (0.72, 0.15, 1.15), (0.74, -0.45, 0.5), (0.74, -0.2, 0.1), (0.74, 0.35, 0.05)]

# Asa direita aberta (pose de repouso): ombro, cotovelo, pulso, base dos dedos
SHOULDER = (0.62, 1.45, 2.55)
ELBOW = (2.35, 1.2, 2.65)
WRIST = (4.5, 1.75, 2.7)
HAND = (4.75, 1.8, 2.7)
FINGERS = [  # (meio, ponta) de cada dedo; o 1º é o bordo de ataque
    ((6.55, 1.25, 2.73), (8.3, 0.45, 2.76)),
    ((6.05, 0.15, 2.72), (7.05, -1.45, 2.72)),
    ((5.35, -0.55, 2.71), (5.55, -2.75, 2.69)),
    ((4.35, -0.85, 2.7), (3.5, -2.55, 2.66)),
]
THUMB = (4.62, 2.18, 2.58)
BODY_ATTACH = (0.55, -1.05, 2.2)   # onde a membrana termina no flanco

# Sela (na base do pescoço, à frente das asas) e o ponto onde o cavaleiro senta
SADDLE_Y = (1.95, 2.72)
SEAT = (0.0, 2.3, 3.04)
SEAT_BONE = "neck1"
# Onde o jogador fica para montar/desmontar (ao lado do ombro esquerdo, no chão)
MOUNT_SPOT = (-1.75, 2.2, 0.0)
