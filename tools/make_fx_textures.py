"""Gera as texturas de efeitos (fogo, faísca, fumaça, calor) por código — sem arquivos de terceiros.
Uso: python3 tools/make_fx_textures.py
"""
import os
import numpy as np
from PIL import Image

OUT = os.path.join(os.path.dirname(__file__), "../assets/textures/fx")
rng = np.random.default_rng(3)


def value_noise(h, w, cells, seed):
    r = np.random.default_rng(seed)
    g = r.random((cells[0] + 3, cells[1] + 3))
    ys = np.linspace(0, cells[0], h, endpoint=False)
    xs = np.linspace(0, cells[1], w, endpoint=False)
    yi, xi = np.floor(ys).astype(int), np.floor(xs).astype(int)
    yf, xf = ys - yi, xs - xi
    yf = yf * yf * (3 - 2 * yf)
    xf = xf * xf * (3 - 2 * xf)
    a = g[yi][:, xi]
    b = g[yi][:, xi + 1]
    c = g[yi + 1][:, xi]
    d = g[yi + 1][:, xi + 1]
    top = a + (b - a) * xf[None, :]
    bot = c + (d - c) * xf[None, :]
    return top + (bot - top) * yf[:, None]


def fbm(h, w, base, seed, octaves=4):
    out = np.zeros((h, w))
    amp, tot = 1.0, 0.0
    for o in range(octaves):
        out += amp * value_noise(h, w, (base[0] * 2 ** o, base[1] * 2 ** o), seed + o * 17)
        tot += amp
        amp *= 0.5
    return out / tot


def flame_frame(i, n, W=64, H=128):
    """Uma língua de fogo: larga embaixo, afinando e tremulando em cima (brilho no canal R/G/B iguais;
    a cor vem do gradiente da partícula)."""
    y = np.linspace(0, 1, H)[:, None]          # 1 = base (linha de baixo), 0 = topo
    x = np.linspace(-1, 1, W)[None, :]
    t = i / n * 2 * np.pi
    nz = fbm(H, W, (3, 2), 100 + i * 7)
    sway = 0.18 * np.sin(t + (1 - y) * 4.0) * (1 - y) + (nz - 0.5) * 0.45 * (1 - y)
    width = 0.95 * y ** 0.6 * (0.8 + 0.25 * (nz - 0.5))
    d = np.abs(x - sway) / np.maximum(width, 1e-3)
    body = np.clip(1 - d, 0, 1) ** 1.3
    # o topo se desfaz em lambidas
    tongues = fbm(H, W, (6, 3), 300 + i * 5)
    body *= np.clip((y * 1.4 + tongues * 0.6 - 0.25), 0, 1)
    body *= np.clip(y * 6, 0, 1) * np.clip((1 - y) * 8 + 0.2, 0, 1)   # some na base
    core = np.clip(1 - d * 1.6, 0, 1) * np.clip(y * 1.6 - 0.2, 0, 1)
    return np.clip(body * 0.85 + core * 0.5, 0, 1)


def save_gray_alpha(arr, name, color=(255, 255, 255)):
    a = (np.clip(arr, 0, 1) * 255).astype(np.uint8)
    img = np.zeros(arr.shape + (4,), np.uint8)
    img[..., 0], img[..., 1], img[..., 2] = color
    img[..., 3] = a
    Image.fromarray(img, "RGBA").save(os.path.join(OUT, name))
    print(name, arr.shape)


def main():
    os.makedirs(OUT, exist_ok=True)
    # fogo: folha 4x4 quadros (flipbook)
    n = 16
    sheet = np.zeros((128 * 4, 64 * 4))
    for i in range(n):
        r, c = divmod(i, 4)
        sheet[r * 128:(r + 1) * 128, c * 64:(c + 1) * 64] = flame_frame(i, n)
    save_gray_alpha(sheet, "flame_sheet.png")
    # faísca / brasa voando: ponto com brilho
    s = 32
    yy, xx = np.mgrid[-1:1:s * 1j, -1:1:s * 1j]
    r = np.sqrt(xx ** 2 + yy ** 2)
    save_gray_alpha(np.clip(1 - r, 0, 1) ** 2.5, "spark.png")
    # brilho suave (núcleo da fogueira)
    save_gray_alpha(np.clip(1 - r, 0, 1) ** 1.8, "glow.png")
    # fumaça: nuvem irregular
    s = 96
    yy, xx = np.mgrid[-1:1:s * 1j, -1:1:s * 1j]
    r = np.sqrt(xx ** 2 + yy ** 2)
    puff = np.clip(1 - r, 0, 1) ** 1.2 * (0.55 + 0.45 * fbm(s, s, (4, 4), 9))
    save_gray_alpha(puff, "smoke.png")
    # ruído para a distorção do ar quente (normal "suja" em RG)
    s = 128
    nx = fbm(s, s, (4, 4), 51)
    ny = fbm(s, s, (4, 4), 77)
    img = np.zeros((s, s, 4), np.uint8)
    img[..., 0] = (nx * 255).astype(np.uint8)
    img[..., 1] = (ny * 255).astype(np.uint8)
    img[..., 3] = 255
    Image.fromarray(img, "RGBA").save(os.path.join(OUT, "heat_noise.png"))
    print("heat_noise.png")


if __name__ == "__main__":
    main()
