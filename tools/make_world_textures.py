"""Gera as texturas do cenário (tudo por código, sem fotos): repetíveis (tileable), com mapa de
normais. Saída: assets/textures/world/*.png

Uso: python3 tools/make_world_textures.py
"""
import os

import numpy as np
from PIL import Image

OUT = os.path.join(os.path.dirname(__file__), "../assets/textures/world")
os.makedirs(OUT, exist_ok=True)


# ---------------------------------------------------------------- blocos (tudo periódico)

def fbm(n, beta=2.0, seed=0, lo=1.0):
    """Ruído fractal periódico (espectro 1/f^beta), normalizado 0..1."""
    rng = np.random.default_rng(seed)
    w = rng.normal(size=(n, n))
    f = np.fft.fftfreq(n)[:, None] ** 2 + np.fft.fftfreq(n)[None, :] ** 2
    f[0, 0] = 1.0
    amp = 1.0 / np.power(f, beta / 2.0)
    amp[0, 0] = 0.0
    if lo > 1.0:
        amp[np.sqrt(f) * n < lo] = 0.0
    x = np.real(np.fft.ifft2(np.fft.fft2(w) * amp))
    x -= x.min()
    return x / (x.max() + 1e-9)


def voronoi(n, cells, seed=0, stretch=(1.0, 1.0)):
    """Distâncias F1, F2 e id da célula (periódico). stretch alonga as células."""
    rng = np.random.default_rng(seed)
    pts = rng.uniform(0, 1, (cells, 2))
    yy, xx = np.mgrid[0:n, 0:n] / n
    f1 = np.full((n, n), 9.0)
    f2 = np.full((n, n), 9.0)
    ident = np.zeros((n, n), dtype=int)
    for i, (px, py) in enumerate(pts):
        dx = np.abs(xx - px)
        dx = np.minimum(dx, 1 - dx) * stretch[0]
        dy = np.abs(yy - py)
        dy = np.minimum(dy, 1 - dy) * stretch[1]
        d = np.sqrt(dx * dx + dy * dy)
        closer = d < f1
        f2 = np.where(closer, f1, np.minimum(f2, d))
        ident = np.where(closer, i, ident)
        f1 = np.where(closer, d, f1)
    return f1, f2, ident


def normal_map(h, strength):
    dx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * strength
    dy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * strength
    nz = np.ones_like(h)
    ln = np.sqrt(dx * dx + dy * dy + nz)
    # convenção OpenGL (Y para cima), a que o Godot usa
    return np.stack([(-dx / ln) * 0.5 + 0.5, (dy / ln) * 0.5 + 0.5, nz / ln * 0.5 + 0.5], -1)


def mix(a, b, t):
    t = np.clip(t, 0, 1)[..., None] if np.ndim(t) == 2 else t
    return a * (1 - t) + b * t


def col(c):
    return np.array(c, dtype=float)[None, None, :]


def save(name, rgb, alpha=None):
    rgb = np.clip(rgb, 0, 1)
    arr = (rgb * 255 + 0.5).astype(np.uint8)
    if alpha is not None:
        a = (np.clip(alpha, 0, 1) * 255 + 0.5).astype(np.uint8)
        Image.fromarray(np.dstack([arr, a]), "RGBA").save(os.path.join(OUT, name + ".png"))
    else:
        Image.fromarray(arr, "RGB").save(os.path.join(OUT, name + ".png"))
    print("  ", name)


def smoothstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


# ---------------------------------------------------------------- chão

def grass(n=1024):
    big = fbm(n, 2.4, 1)
    mid = fbm(n, 1.6, 2)
    fine = fbm(n, 0.6, 3)
    # tufos: muitos riscos curtos (folhas vistas de cima)
    rng = np.random.default_rng(4)
    blades = np.zeros((n, n))
    for _ in range(26000):
        x, y = rng.integers(0, n, 2)
        ln = rng.integers(4, 13)
        ang = rng.uniform(0, np.pi)
        dx, dy = np.cos(ang), np.sin(ang)
        v = rng.uniform(0.5, 1.0)
        for k in range(ln):
            blades[int(y + dy * k) % n, int(x + dx * k) % n] = max(v * (1 - k / ln * 0.5), blades[int(y + dy * k) % n, int(x + dx * k) % n])
    h = blades * 0.6 + fine * 0.3 + mid * 0.1
    c = mix(col((0.16, 0.22, 0.08)), col((0.27, 0.33, 0.12)), mid)
    c = mix(c, col((0.42, 0.4, 0.2)), smoothstep(0.55, 0.85, big) * 0.8)     # manchas secas
    c = mix(c, col((0.2, 0.17, 0.11)), smoothstep(0.62, 0.9, 1 - big) * 0.5)  # terra aparecendo
    c = c * (0.62 + 0.55 * blades[..., None]) * (0.9 + 0.2 * fine[..., None])
    save("grass_albedo", c)
    save("grass_normal", normal_map(h, 2.5))


def dirt(n=1024):
    big = fbm(n, 2.2, 11)
    fine = fbm(n, 0.9, 12)
    f1, f2, ident = voronoi(n, 900, 13)
    pebble = smoothstep(0.011, 0.003, f1) * (np.random.default_rng(14).uniform(0.3, 1, 900)[ident] > 0.8) \
        * np.random.default_rng(15).uniform(0.4, 1.0, 900)[ident]
    h = fine * 0.4 + big * 0.3 + pebble * 0.6
    c = mix(col((0.3, 0.23, 0.16)), col((0.4, 0.32, 0.22)), big)
    c = mix(c, col((0.22, 0.17, 0.12)), fine * 0.5)
    c = mix(c, col((0.42, 0.38, 0.33)), pebble * 0.7)
    save("dirt_albedo", c)
    save("dirt_normal", normal_map(h, 3.0))


def rock(n=1024):
    big = fbm(n, 2.3, 21)
    mid = fbm(n, 1.7, 22)
    fine = fbm(n, 0.8, 23)
    ridge = 1 - np.abs(fbm(n, 1.9, 24) * 2 - 1)
    yy = np.mgrid[0:n, 0:n][0] / n
    strata = 0.5 + 0.5 * np.sin((yy * 9 + big * 1.6) * 2 * np.pi)
    f1, f2, _ = voronoi(n, 22, 25, (1.0, 2.2))
    crack = smoothstep(0.008, 0.0, f2 - f1) * smoothstep(0.45, 0.7, fbm(n, 1.8, 26))
    h = mid * 0.5 + fine * 0.25 + strata * 0.15 + ridge * 0.2 - crack * 0.4
    c = mix(col((0.34, 0.33, 0.31)), col((0.5, 0.49, 0.46)), mid)
    c = mix(c, col((0.42, 0.38, 0.32)), strata * 0.35)
    c = mix(c, col((0.29, 0.33, 0.22)), smoothstep(0.6, 0.85, big) * 0.45)   # musgo/líquen
    c = c * (0.75 + 0.35 * fine[..., None]) * (1 - 0.55 * crack[..., None])
    save("rock_albedo", c)
    save("rock_normal", normal_map(h, 4.0))


def asphalt(n=1024):
    fine = fbm(n, 0.3, 31)
    mid = fbm(n, 1.5, 32)
    rng = np.random.default_rng(33)
    speck = (rng.uniform(size=(n, n)) > 0.985) * rng.uniform(0.4, 1, (n, n))
    f1, f2, _ = voronoi(n, 14, 34)
    crack = smoothstep(0.004, 0.0, f2 - f1) * (fbm(n, 1.4, 35) > 0.55)
    h = fine * 0.5 + speck * 0.4 - crack * 0.8
    c = mix(col((0.13, 0.13, 0.13)), col((0.2, 0.2, 0.19)), mid)
    c = c + speck[..., None] * 0.12 + (fine[..., None] - 0.5) * 0.06
    c = c * (1 - 0.6 * crack[..., None])
    save("asphalt_albedo", c)
    save("asphalt_normal", normal_map(h, 2.0))


def concrete(n=1024):
    fine = fbm(n, 0.5, 41)
    mid = fbm(n, 1.8, 42)
    stain = smoothstep(0.55, 0.9, fbm(n, 2.3, 43))
    rng = np.random.default_rng(44)
    pores = (rng.uniform(size=(n, n)) > 0.992).astype(float)
    h = fine * 0.5 + mid * 0.2 - pores * 0.5
    c = mix(col((0.5, 0.49, 0.46)), col((0.6, 0.59, 0.56)), mid)
    c = mix(c, col((0.36, 0.35, 0.31)), stain * 0.6)
    c = c * (0.9 + 0.15 * fine[..., None]) * (1 - 0.4 * pores[..., None])
    save("concrete_albedo", c)
    save("concrete_normal", normal_map(h, 2.2))


def plaster(n=1024):
    fine = fbm(n, 0.7, 51)
    mid = fbm(n, 1.9, 52)
    yy = np.mgrid[0:n, 0:n][0] / n
    # escorridos de sujeira verticais e reboco descascado mostrando tijolo
    drip = fbm(n, 2.0, 53)
    drip = np.clip(np.roll(drip, 0, 0) * (0.3 + 0.7 * yy), 0, 1)
    peel = smoothstep(0.9, 0.94, fbm(n, 2.6, 54))
    brick_rows = (np.floor(yy * 16) % 2)
    xx = np.mgrid[0:n, 0:n][1] / n
    bx = (xx * 8 + brick_rows * 0.5) % 1
    by = (yy * 16) % 1
    mortar = ((bx < 0.06) | (by < 0.1)).astype(float)
    brick = mix(col((0.45, 0.24, 0.17)), col((0.7, 0.68, 0.62)), mortar)
    h = fine * 0.35 + mid * 0.25 - peel * 0.5 + peel * (1 - mortar) * 0.2
    c = mix(col((0.62, 0.58, 0.5)), col((0.7, 0.67, 0.6)), mid)
    c = mix(c, col((0.42, 0.38, 0.32)), smoothstep(0.45, 0.85, drip) * 0.6)
    c = mix(c, brick, peel)
    c = c * (0.92 + 0.12 * fine[..., None])
    save("plaster_albedo", c)
    save("plaster_normal", normal_map(h, 2.5))


def wood_planks(n=1024):
    yy, xx = np.mgrid[0:n, 0:n] / n
    rows = 6
    plank = np.floor(yy * rows)
    rng = np.random.default_rng(61)
    offs = rng.uniform(0, 1, rows)[plank.astype(int)]
    tone = rng.uniform(0.75, 1.15, rows)[plank.astype(int)]
    v = (yy * rows) % 1
    warp = fbm(n, 1.6, 62)
    grain = 0.5 + 0.5 * np.sin((v * 7 + warp * 3 + xx * 0.4) * 2 * np.pi * 3)
    grain2 = fbm(n, 0.6, 63)
    seam_y = smoothstep(0.03, 0.0, v) + smoothstep(0.97, 1.0, v)
    ends = ((xx + offs) % 0.5) < 0.006
    seam = np.clip(seam_y + ends, 0, 1)
    knots = smoothstep(0.02, 0.0, voronoi(n, 40, 64)[0])
    h = grain * 0.2 + grain2 * 0.2 - seam * 0.8 - knots * 0.2
    c = mix(col((0.3, 0.2, 0.12)), col((0.45, 0.32, 0.2)), grain * 0.6 + grain2 * 0.4)
    c = c * tone[..., None]
    c = mix(c, col((0.12, 0.08, 0.05)), np.clip(seam + knots * 0.25, 0, 1))
    worn = smoothstep(0.6, 0.85, fbm(n, 2.2, 65))
    c = mix(c, col((0.38, 0.34, 0.3)), worn * 0.35)
    save("wood_albedo", c)
    save("wood_normal", normal_map(h, 3.0))


def roof_tiles(n=1024):
    yy, xx = np.mgrid[0:n, 0:n] / n
    rows, cols = 10, 8
    r = np.floor(yy * rows)
    v = (yy * rows) % 1
    u = (xx * cols + (r % 2) * 0.5) % 1
    # telha curva (capa e canal) com sombra na borda de baixo
    arch = np.abs(np.sin(u * np.pi))
    lip = smoothstep(0.88, 1.0, v)
    h = arch * 0.6 + v * 0.3 - lip * 0.6
    rng = np.random.default_rng(71)
    tile_id = (r * cols + np.floor(xx * cols + (r % 2) * 0.5)).astype(int) % 997
    tone = rng.uniform(0.75, 1.2, 997)[tile_id]
    moss = smoothstep(0.6, 0.85, fbm(n, 2.1, 72)) * (1 - arch)
    c = col((0.48, 0.22, 0.14)) * tone[..., None] * (0.6 + 0.5 * arch[..., None])
    c = mix(c, col((0.24, 0.27, 0.15)), moss * 0.8)
    c = mix(c, col((0.1, 0.06, 0.05)), lip * 0.7)
    c = c * (0.9 + 0.15 * fbm(n, 0.6, 73)[..., None])
    save("roof_albedo", c)
    save("roof_normal", normal_map(h, 5.0))


def bark(n=512):
    yy, xx = np.mgrid[0:n, 0:n] / n
    warp = fbm(n, 1.8, 81)
    fur = np.abs(np.sin((xx * 9 + warp * 0.9) * np.pi))
    plates = voronoi(n, 120, 82, (1.0, 0.35))
    ridges = smoothstep(0.0, 0.05, plates[1] - plates[0])
    h = fur * 0.5 + ridges * 0.5 + fbm(n, 0.7, 83) * 0.2
    c = mix(col((0.12, 0.09, 0.07)), col((0.34, 0.27, 0.2)), h * 0.85)
    c = mix(c, col((0.3, 0.32, 0.22)), smoothstep(0.7, 0.9, fbm(n, 2.2, 84)) * 0.4)
    save("bark_albedo", c)
    save("bark_normal", normal_map(h, 5.0))


# ---------------------------------------------------------------- folhagem (com alfa)

def pine_needles(w=512, h=512):
    """Ramo de pinheiro visto de lado: galho no meio e agulhas em leque (com transparência)."""
    rng = np.random.default_rng(91)
    alpha = np.zeros((h, w))
    shade = np.zeros((h, w))
    yy, xx = np.mgrid[0:h, 0:w]

    def stroke(x0, y0, x1, y1, width, value):
        n = int(max(abs(x1 - x0), abs(y1 - y0))) + 1
        for k in range(n):
            t = k / max(n - 1, 1)
            x = x0 + (x1 - x0) * t
            y = y0 + (y1 - y0) * t
            wd = width * (1 - 0.6 * t)
            x_lo, x_hi = int(max(x - wd - 1, 0)), int(min(x + wd + 2, w))
            y_lo, y_hi = int(max(y - wd - 1, 0)), int(min(y + wd + 2, h))
            if x_lo >= x_hi or y_lo >= y_hi:
                continue
            sub = (xx[y_lo:y_hi, x_lo:x_hi] - x) ** 2 + (yy[y_lo:y_hi, x_lo:x_hi] - y) ** 2
            m = np.clip(wd + 0.6 - np.sqrt(sub), 0, 1)
            alpha[y_lo:y_hi, x_lo:x_hi] = np.maximum(alpha[y_lo:y_hi, x_lo:x_hi], m)
            shade[y_lo:y_hi, x_lo:x_hi] = np.where(m > 0.3, value, shade[y_lo:y_hi, x_lo:x_hi])
    # galho principal de baixo (base) para cima (ponta), com galhinhos
    stroke(w * 0.5, h * 0.98, w * 0.5, h * 0.04, 4.5, 0.15)
    for k in range(14):
        y0 = h * (0.9 - k * 0.06)
        side = -1 if k % 2 else 1
        ln = w * (0.4 - k * 0.022)
        stroke(w * 0.5, y0, w * 0.5 + side * ln, y0 - ln * 0.45, 2.2, 0.2)
    # agulhas
    for _ in range(7000):
        t = rng.uniform(0.02, 0.97)
        y0 = h * (0.98 - t * 0.94)
        if rng.uniform() < 0.3:
            x0 = w * 0.5
        else:
            k = int(rng.integers(0, 14))
            side = -1 if k % 2 else 1
            ln = w * (0.4 - k * 0.022) * rng.uniform(0, 1)
            x0 = w * 0.5 + side * ln
            y0 = h * (0.9 - k * 0.06) - ln * 0.45
            t = (0.9 - (y0 / h)) / 0.9
        width_max = w * 0.47 * (1 - t * 0.6)
        ang = rng.uniform(-np.pi, 0.0) + rng.normal(0, 0.4)
        ln = rng.uniform(18, 42)
        x1 = np.clip(x0 + np.cos(ang) * ln, w * 0.5 - width_max, w * 0.5 + width_max)
        y1 = y0 + np.sin(ang) * ln * 0.8
        stroke(x0, y0, x1, y1, 1.1, rng.uniform(0.45, 1.0))
    base = col((0.1, 0.17, 0.08))
    tip = col((0.22, 0.32, 0.13))
    c = mix(base, tip, shade)
    c = mix(c, col((0.23, 0.17, 0.11)), (shade < 0.25) * alpha)
    save("pine_needles", c, alpha)


def grass_blades(w=512, h=256):
    rng = np.random.default_rng(95)
    alpha = np.zeros((h, w))
    shade = np.zeros((h, w))
    yy, xx = np.mgrid[0:h, 0:w]
    for _ in range(140):
        x0 = rng.uniform(w * 0.05, w * 0.95)
        hgt = rng.uniform(0.45, 0.98) * h
        bend = rng.uniform(-0.35, 0.35) * hgt
        wd = rng.uniform(2.0, 4.5)
        v = rng.uniform(0.5, 1.0)
        n = int(hgt)
        for k in range(n):
            t = k / n
            x = x0 + bend * t * t
            y = h - 1 - k
            r = wd * (1 - t) + 0.4
            lo, hi = int(max(x - r - 1, 0)), int(min(x + r + 2, w))
            m = np.clip(r + 0.5 - np.abs(xx[y, lo:hi] - x), 0, 1)
            alpha[y, lo:hi] = np.maximum(alpha[y, lo:hi], m)
            shade[y, lo:hi] = np.where(m > 0.3, v * (0.55 + 0.45 * t), shade[y, lo:hi])
    c = mix(col((0.09, 0.13, 0.04)), col((0.36, 0.42, 0.16)), shade)
    dry = rng.uniform(size=(h, w)) > 2
    save("grass_blades", c, alpha)
    del dry


def snow(n=512):
    fine = fbm(n, 0.9, 101)
    mid = fbm(n, 1.8, 102)
    c = mix(col((0.82, 0.85, 0.9)), col((0.95, 0.96, 0.98)), mid) * (0.95 + 0.08 * fine[..., None])
    save("snow_albedo", c)
    save("snow_normal", normal_map(fine * 0.5 + mid * 0.5, 1.5))


def noise_maps(n=512):
    """Ruído suave para as nuvens e para variar a cor do terreno em grande escala."""
    a = fbm(n, 2.1, 111)
    b = fbm(n, 1.6, 112)
    save("cloud_noise", np.dstack([a * 0.7 + b * 0.3] * 3))
    save("macro_noise", np.dstack([fbm(n, 2.4, 113)] * 3))


if __name__ == "__main__":
    grass()
    dirt()
    rock()
    asphalt()
    concrete()
    plaster()
    wood_planks()
    roof_tiles()
    bark()
    pine_needles()
    grass_blades()
    snow()
    noise_maps()
