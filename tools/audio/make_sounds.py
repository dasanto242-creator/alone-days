"""Gera todos os efeitos sonoros do ALONE DAYS por síntese (numpy + scipy).
Nada é gravado ou baixado: cada som nasce de ruído, osciladores e filtros, então não há
problema de licença. Saída: WAV 16 bits mono 22050 Hz em assets/audio/sfx/.

Uso: python3 tools/audio/make_sounds.py [pasta de saída]
"""
import os
import sys
import wave

import numpy as np
from scipy import signal

SR = 22050
OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), "../../assets/audio/sfx")
rng = np.random.default_rng(42)


# ---------------------------------------------------------------- blocos básicos

def t_axis(dur):
    return np.arange(int(dur * SR)) / SR


def noise(dur):
    return rng.uniform(-1, 1, int(dur * SR))


def brown(dur):
    x = np.cumsum(rng.uniform(-1, 1, int(dur * SR)))
    x = signal.lfilter([1, -1], [1, -0.995], x)
    return x / (np.max(np.abs(x)) + 1e-9)


def bp(x, lo, hi, order=2):
    sos = signal.butter(order, [lo, hi], btype="bandpass", fs=SR, output="sos")
    return signal.sosfilt(sos, x)


def lp(x, f, order=2):
    return signal.sosfilt(signal.butter(order, f, btype="lowpass", fs=SR, output="sos"), x)


def hp(x, f, order=2):
    return signal.sosfilt(signal.butter(order, f, btype="highpass", fs=SR, output="sos"), x)


def env(n, attack, decay, sustain_level=0.0, curve=4.0):
    """Envelope: sobe em `attack` s e cai exponencialmente em `decay` s."""
    t = np.arange(n) / SR
    a = np.clip(t / max(attack, 1e-4), 0, 1)
    d = np.exp(-curve * np.clip(t - attack, 0, None) / max(decay, 1e-4))
    return a * (sustain_level + (1 - sustain_level) * d)


def fade(x, fin=0.003, fout=0.02):
    n = len(x)
    a, b = int(fin * SR), int(fout * SR)
    if a:
        x[:a] *= np.linspace(0, 1, a)
    if b:
        x[-b:] *= np.linspace(1, 0, b)
    return x


def mix(length, *parts):
    """parts: (sinal, início em s)."""
    out = np.zeros(int(length * SR))
    for x, start in parts:
        i = int(start * SR)
        n = min(len(x), len(out) - i)
        if n > 0:
            out[i:i + n] += x[:n]
    return out


def norm(x, peak=0.9):
    return x * (peak / (np.max(np.abs(x)) + 1e-9))


def tone(freqs, dur, kind="saw"):
    """Oscilador com frequência variável (array ou constante)."""
    n = int(dur * SR)
    f = np.broadcast_to(np.asarray(freqs, dtype=float), (n,)) if np.ndim(freqs) else np.full(n, float(freqs))
    phase = np.cumsum(f) / SR
    if kind == "saw":
        return 2 * (phase % 1.0) - 1
    if kind == "square":
        return np.sign(np.sin(2 * np.pi * phase))
    return np.sin(2 * np.pi * phase)


def formants(x, fs_list, q=6.0):
    out = np.zeros_like(x)
    for f, g in fs_list:
        b, a = signal.iirpeak(f, q, fs=SR)
        out += g * signal.lfilter(b, a, x)
    return out


def save(name, x, peak=0.9):
    x = norm(fade(np.asarray(x, dtype=float)), peak)
    data = (np.clip(x, -1, 1) * 32767).astype("<i2")
    os.makedirs(OUT, exist_ok=True)
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())
    print(f"{name:16s} {len(x) / SR:5.2f} s")


# ---------------------------------------------------------------- sons

def footsteps():
    for i in range(4):
        # grama/terra: amassado abafado + estalinhos de folhas
        d = 0.22
        n = int(d * SR)
        thump = lp(noise(d), 300 + 60 * i) * env(n, 0.004, 0.05) * 1.6
        crunch = bp(noise(d), 1500, 5000) * env(n, 0.01, 0.08) * (rng.uniform(0, 1, n) > 0.6) * 0.5
        save(f"step_grass_{i}", thump + crunch, 0.55)
        # piso duro (calçada, madeira): estalo seco curto
        heel = bp(noise(0.12), 400, 2500) * env(int(0.12 * SR), 0.001, 0.025)
        body = lp(noise(0.12), 180) * env(int(0.12 * SR), 0.002, 0.04) * 2
        scuff = bp(noise(0.12), 2000, 6000) * env(int(0.12 * SR), 0.02, 0.04) * 0.25
        save(f"step_hard_{i}", mix(0.16, (heel + body, 0.0), (scuff, 0.03 + 0.01 * i)), 0.5)


def gunshot():
    d = 1.4
    n = int(d * SR)
    crack = hp(noise(0.03), 1500) * env(int(0.03 * SR), 0.0005, 0.008) * 3
    blast = lp(noise(d), 2500) * env(n, 0.001, 0.12) * 1.5
    boom = lp(brown(d), 160) * env(n, 0.002, 0.35) * 2.5
    tail = bp(noise(d), 300, 1500) * env(n, 0.05, 0.9, curve=3) * 0.35  # eco
    save("gunshot", mix(d, (blast + boom + tail, 0.0), (crack, 0.0)), 0.98)


def gun_mech():
    def click(f, d=0.05, g=1.0):
        n = int(d * SR)
        return (bp(noise(d), f, f * 2.5) * env(n, 0.0005, 0.01) + tone(f * 0.7, d, "sin") * env(n, 0.0005, 0.015) * 0.3) * g
    save("gun_empty", mix(0.12, (click(2500), 0.0)), 0.5)
    # recarga: carregador sai, entra, ferrolho puxa e volta
    rustle = bp(noise(0.2), 800, 3000) * env(int(0.2 * SR), 0.05, 0.1) * 0.2
    slide = bp(noise(0.08), 1500, 5000) * env(int(0.08 * SR), 0.02, 0.04) * 0.5
    save("reload", mix(1.2, (click(1800), 0.05), (rustle, 0.15), (click(1200, 0.07, 1.4), 0.55),
                       (slide, 0.85), (click(2600, 0.05, 1.2), 0.95)), 0.7)


def melee():
    d = 0.35
    n = int(d * SR)
    t = t_axis(d)
    whoosh = noise(d)
    # varredura de filtro (sobe e desce): sensação de objeto cortando o ar
    out = np.zeros(n)
    for k in range(0, n, 256):
        c = 400 + 1600 * np.sin(np.pi * min(k / n, 1.0))
        seg = whoosh[k:k + 256]
        out[k:k + len(seg)] = bp(seg, c * 0.6, c * 1.4, 1)[: len(seg)]
    save("swing", out * np.sin(np.pi * t / d) ** 2, 0.45)
    # golpe na carne: baque grave + estalo úmido
    thud = lp(brown(0.3), 220) * env(int(0.3 * SR), 0.002, 0.08) * 2
    squish = bp(noise(0.3), 600, 2200) * env(int(0.3 * SR), 0.005, 0.06) * 0.6
    save("hit_flesh", thud + squish, 0.85)
    # pancada em madeira (taco/grifo na árvore)
    knock = sum(tone(f, 0.3, "sin") * env(int(0.3 * SR), 0.001, 0.07 + 0.02 * i) * g
                for i, (f, g) in enumerate(((180, 1.0), (410, 0.5), (760, 0.25))))
    save("wood_knock", knock + bp(noise(0.3), 1000, 4000) * env(int(0.3 * SR), 0.0005, 0.01) * 0.6, 0.75)


def axe_and_tree():
    # machadada: lâmina crava (estalo agudo) + madeira ressoa + lascas
    d = 0.45
    n = int(d * SR)
    bite = hp(noise(d), 2000) * env(n, 0.0005, 0.012) * 1.5
    body = sum(tone(f, d, "sin") * env(n, 0.001, 0.09) * g for f, g in ((140, 1.0), (330, 0.6), (620, 0.3)))
    chips = bp(noise(d), 2500, 7000) * env(n, 0.03, 0.12) * (rng.uniform(0, 1, n) > 0.85) * 0.6
    save("axe_chop", bite + body + chips, 0.9)
    # árvore estalando antes de cair: rangido com estalos que aceleram
    d = 2.0
    n = int(d * SR)
    t = t_axis(d)
    creak_f = 70 + 40 * np.sin(2 * np.pi * 0.7 * t) + 30 * t
    creak = formants(tone(creak_f, d, "saw"), [(300, 1.0), (800, 0.5)], 4) * 0.4 * np.clip(t / 0.3, 0, 1)
    cracks = np.zeros(n)
    k = 0.2
    while k < d - 0.05:
        c = bp(noise(0.04), 800, 6000) * env(int(0.04 * SR), 0.0005, 0.01)
        i = int(k * SR)
        cracks[i:i + len(c)] += c[: n - i] * (0.4 + k / d)
        k += max(0.03, 0.3 * (1 - k / d)) * rng.uniform(0.5, 1.2)
    save("tree_crack", creak + cracks, 0.8)
    # queda: baque enorme + galhos e folhas chacoalhando
    d = 2.2
    n = int(d * SR)
    impact = lp(brown(d), 120) * env(n, 0.003, 0.5) * 3
    branches = bp(noise(d), 1500, 5000) * env(n, 0.01, 1.2, curve=3) * 0.6
    snaps = mix(d, *[(bp(noise(0.03), 1000, 5000) * env(int(0.03 * SR), 0.0005, 0.008), rng.uniform(0.0, 0.8))
                     for _ in range(14)])
    save("tree_fall", impact + branches + snaps, 0.95)


def voice(f0, dur, formant_set, rough=0.3, breath=0.25, jitter=0.08, bend=None):
    """Voz rouca: dente de serra com tremor irregular passando por filtros de formantes."""
    n = int(dur * SR)
    t = t_axis(dur)
    wobble = 1 + jitter * lp(rng.normal(0, 1, n), 12) * 4
    f = f0 * wobble * (bend(t) if bend else 1.0)
    src = tone(f, dur, "saw")
    src += rough * lp(noise(dur), 900) * (0.5 + 0.5 * np.sin(2 * np.pi * f * t))  # aspereza
    src += breath * bp(noise(dur), 500, 3500)
    return formants(src, formant_set, 5)


def zombie():
    vowels = [[(450, 1.0), (850, 0.6), (2400, 0.15)], [(600, 1.0), (1000, 0.5), (2500, 0.1)],
              [(350, 1.0), (650, 0.7), (2300, 0.12)]]
    for i, fs in enumerate(vowels):
        d = 1.4 + 0.3 * i
        x = voice(85 + 12 * i, d, fs, rough=0.5, breath=0.35, jitter=0.12,
                  bend=lambda t, d=d: 1 + 0.15 * np.sin(np.pi * t / d) - 0.1 * t / d)
        save(f"zombie_groan_{i}", x * env(len(x), 0.25, d * 0.8, 0.0, 2.5), 0.7)
    d = 0.8
    x = voice(140, d, [(700, 1.0), (1200, 0.6), (2800, 0.2)], rough=0.9, breath=0.5, jitter=0.2,
              bend=lambda t: 1 + 0.4 * np.exp(-t * 5))
    save("zombie_attack", x * env(len(x), 0.03, 0.6, 0.0, 2.5), 0.85)
    d = 0.45
    x = voice(110, d, [(500, 1.0), (900, 0.5)], rough=0.7, breath=0.4, jitter=0.15,
              bend=lambda t: 1.3 - 0.6 * t / 0.45)
    save("zombie_hurt", x * env(len(x), 0.01, 0.35), 0.8)
    d = 1.2
    x = voice(95, d, [(400, 1.0), (750, 0.5)], rough=0.6, breath=0.5, jitter=0.15,
              bend=lambda t: 1.1 - 0.4 * t / 1.2)
    save("zombie_death", x * env(len(x), 0.02, 1.0, 0.0, 2.0) + lp(brown(d), 150) * env(len(x), 0.6, 0.3) * 0.0, 0.8)


def player_sounds():
    d = 0.35
    x = voice(160, d, [(550, 1.0), (1100, 0.4)], rough=0.3, breath=0.4, jitter=0.05,
              bend=lambda t: 1.15 - 0.3 * t / 0.35)
    save("player_hurt", x * env(len(x), 0.01, 0.25), 0.75)
    # esforço ao escalar
    d = 0.5
    x = voice(150, d, [(500, 1.0), (1000, 0.4)], rough=0.2, breath=0.6, jitter=0.04)
    save("player_effort", x * env(len(x), 0.05, 0.4) * 0.8, 0.55)
    # aterrissagem
    land = lp(brown(0.35), 200) * env(int(0.35 * SR), 0.002, 0.09) * 2 + \
        bp(noise(0.35), 800, 3000) * env(int(0.35 * SR), 0.003, 0.06) * 0.4
    save("land", land, 0.7)
    # mãos raspando na borda ao escalar
    save("climb_scrape", bp(noise(0.5), 1200, 5000) * env(int(0.5 * SR), 0.05, 0.3) *
         (0.6 + 0.4 * np.sin(2 * np.pi * 9 * t_axis(0.5))), 0.45)


def consumables():
    # comer: mordidas crocantes e mastigação
    d = 1.6
    parts = []
    for k in (0.3, 0.75, 1.15):
        c = bp(noise(0.12), 1200, 6000) * env(int(0.12 * SR), 0.002, 0.04) * (rng.uniform(0, 1, int(0.12 * SR)) > 0.4)
        parts.append((c, k))
        for j in range(3):
            chew = lp(noise(0.1), 500) * env(int(0.1 * SR), 0.02, 0.05) * 0.5
            parts.append((chew, k + 0.12 + 0.11 * j))
    save("eat", mix(d, *parts), 0.6)
    # beber: goles (tom grave que sobe) + líquido
    parts = []
    for k in (0.45, 0.85, 1.25):
        g = tone(np.linspace(180, 380, int(0.14 * SR)), 0.14, "sin") * env(int(0.14 * SR), 0.01, 0.08)
        parts.append((g, k))
        parts.append((bp(noise(0.25), 300, 1500) * env(int(0.25 * SR), 0.03, 0.15) * 0.25, k - 0.05))
    save("drink", mix(1.6, *parts), 0.6)
    # pegar item / guardar na mochila: roupa e zíper
    save("pickup", bp(noise(0.3), 700, 4000) * env(int(0.3 * SR), 0.03, 0.15), 0.4)
    d = 0.5
    zip_ = bp(noise(d), 2000, 7000) * (np.sin(2 * np.pi * np.linspace(30, 60, int(d * SR)) * t_axis(d)) > 0.3) \
        * env(int(d * SR), 0.05, 0.4, 0.3)
    save("bag", zip_ * 0.6 + bp(noise(d), 500, 2000) * env(int(d * SR), 0.02, 0.2) * 0.3, 0.45)


def world():
    # porta rangendo
    d = 0.9
    t = t_axis(d)
    f = 220 + 180 * np.sin(np.pi * t / d) + 40 * np.sin(2 * np.pi * 7 * t)
    creak = formants(tone(f, d, "saw"), [(900, 1.0), (1800, 0.5)], 6)
    save("door", creak * env(len(creak), 0.05, 0.7, 0.2, 2), 0.45)
    # vento ambiente em loop (começo e fim iguais para emendar sem estalo)
    d = 10.0
    n = int(d * SR)
    t = t_axis(d)
    base = lp(noise(d), 600) * 0.6 + bp(noise(d), 200, 1200) * 0.4
    gust = 0.55 + 0.25 * np.sin(2 * np.pi * t / d) + 0.2 * np.sin(2 * np.pi * 3 * t / d + 1)
    wind = base * gust
    x = int(1.0 * SR)  # crossfade de 1 s entre fim e começo
    w = np.linspace(0, 1, x)
    wind[:x] = wind[:x] * w + wind[-x:] * (1 - w)
    wind = wind[: n - x]
    data = norm(wind, 0.35)
    data = (data * 32767).astype("<i2")
    with wave.open(os.path.join(OUT, "ambient_wind.wav"), "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(SR)
        wf.writeframes(data.tobytes())
    print("ambient_wind      9.00 s (loop)")
    # botão da interface
    save("ui_click", bp(noise(0.04), 1500, 5000) * env(int(0.04 * SR), 0.0005, 0.008), 0.35)


def car():
    # motor em marcha lenta-média (loop perfeito: 1 s = 50 ciclos de 50 Hz); o jogo muda o tom pela rotação
    d = 1.0
    t = t_axis(d)
    f0 = 50.0
    x = np.zeros_like(t)
    for k, g in ((1, 1.0), (2, 0.6), (3, 0.35), (4, 0.25), (6, 0.12), (8, 0.08)):
        x += g * np.sin(2 * np.pi * f0 * k * t + k * 0.7)
    pulses = (np.sin(2 * np.pi * f0 * t) > 0.6).astype(float)
    rumble = lp(noise(d), 300) * 0.5 * (0.6 + 0.4 * pulses)
    x = lp(x * (0.8 + 0.2 * pulses) + rumble, 1800)
    n = len(x)
    xf = int(0.05 * SR)
    x[:xf] = x[:xf] * np.linspace(0, 1, xf) + x[-xf:] * np.linspace(1, 0, xf)
    x = x[: n - xf]
    _save_raw("engine_loop", x, 0.7)
    # pneu cantando (loop)
    d = 1.3
    t = t_axis(d)
    squeal = np.sin(2 * np.pi * (950 + 60 * np.sin(2 * np.pi * 3 * t)) * t) * 0.5
    sk = bp(noise(d), 600, 2500) * 0.6 + squeal * (0.6 + 0.4 * lp(rng.uniform(0, 1, len(t)), 6))
    xf = int(0.1 * SR)
    sk[:xf] = sk[:xf] * np.linspace(0, 1, xf) + sk[-xf:] * np.linspace(1, 0, xf)
    _save_raw("tire_skid", sk[: len(sk) - xf], 0.6)
    # porta do carro: trinco + batida abafada
    latch = bp(noise(0.05), 1500, 6000) * env(int(0.05 * SR), 0.0005, 0.01)
    thunk = lp(brown(0.5), 180) * env(int(0.5 * SR), 0.002, 0.12) * 2 + \
        bp(noise(0.5), 300, 1200) * env(int(0.5 * SR), 0.002, 0.06) * 0.5
    save("car_door", mix(0.55, (latch, 0.0), (thunk, 0.03)), 0.8)
    # batida: impacto metálico com chacoalhar de peças
    d = 1.2
    impact = lp(brown(d), 250) * env(int(d * SR), 0.002, 0.25) * 2.5
    metal = sum(tone(f, d, "sin") * env(int(d * SR), 0.001, 0.3 + 0.1 * i) * g
                for i, (f, g) in enumerate(((310, 0.5), (523, 0.35), (811, 0.25), (1290, 0.15))))
    rattle = bp(noise(d), 2000, 6000) * env(int(d * SR), 0.01, 0.4) * (rng.uniform(0, 1, int(d * SR)) > 0.9) * 0.6
    save("car_crash", impact + metal + rattle, 0.95)


def fire():
    """Fogueira: ronco grave do fogo + estalos de madeira (loop) e o "fuuf" de acender."""
    d = 6.0
    n = int(d * SR)
    t = t_axis(d)
    roar = lp(brown(d), 300) * (0.7 + 0.3 * lp(rng.normal(0, 1, n), 2) * 3)
    hiss = bp(noise(d), 1500, 6000) * 0.12 * (0.6 + 0.4 * np.sin(2 * np.pi * 0.37 * t))
    pops = np.zeros(n)
    k = 0.05
    while k < d - 0.1:
        dur = rng.uniform(0.004, 0.03)
        c = bp(noise(dur + 0.02), rng.uniform(900, 2500), 7000) * env(int((dur + 0.02) * SR), 0.0003, dur)
        i = int(k * SR)
        pops[i:i + len(c)] += c[: n - i] * rng.uniform(0.3, 1.0)
        k += rng.exponential(0.12)
    x = roar * 0.9 + hiss + pops * 1.3
    xf = int(0.3 * SR)
    x[:xf] = x[:xf] * np.linspace(0, 1, xf) + x[-xf:] * np.linspace(1, 0, xf)
    _save_raw("fire_loop", x[: n - xf], 0.6)
    d = 1.2
    whoosh = lp(noise(d), 900) * env(int(d * SR), 0.15, 0.8) + lp(brown(d), 200) * env(int(d * SR), 0.2, 0.7)
    save("fire_ignite", whoosh, 0.7)
    # tora caindo no fogo: baque surdo + faíscas
    thud = lp(brown(0.5), 220) * env(int(0.5 * SR), 0.002, 0.1) * 2 + \
        bp(noise(0.5), 2000, 7000) * env(int(0.5 * SR), 0.02, 0.2) * (rng.uniform(0, 1, int(0.5 * SR)) > 0.8) * 0.5
    save("fire_log", thud, 0.7)


def dragon():
    """Dragão: batida de asa (golpe de ar grave + couro da membrana), vento do voo (loop),
    rugido (voz enorme e grave com rosnado), passo pesado."""
    d = 0.9
    n = int(d * SR)
    t = t_axis(d)
    gust = lp(brown(d), 160) * env(n, 0.12, 0.55) * 1.6
    whoosh = bp(noise(d), 180, 1400) * env(n, 0.18, 0.5) * 0.7
    snap = bp(noise(d), 300, 2600) * env(n, 0.005, 0.07) * (t > 0.16) * 0.5
    save("dragon_flap", gust + whoosh + snap, 0.85)
    # vento contínuo (aumenta com a velocidade no jogo)
    d = 6.0
    n = int(d * SR)
    t = t_axis(d)
    swell = 0.65 + 0.35 * lp(rng.normal(0, 1, n), 0.6) * 6
    wind = (bp(noise(d), 120, 900) * 0.8 + bp(noise(d), 900, 3500) * 0.18) * np.clip(swell, 0.2, 1.4)
    xf = int(0.4 * SR)
    wind[:xf] = wind[:xf] * np.linspace(0, 1, xf) + wind[-xf:] * np.linspace(1, 0, xf)
    _save_raw("dragon_wind", wind[: n - xf], 0.6)
    # rugido: começa rosnando, abre num urro longo e cai
    d = 2.6
    n = int(d * SR)
    bend = lambda tt: 0.75 + 0.45 * np.sin(np.pi * np.clip(tt / d, 0, 1)) ** 0.7  # noqa: E731
    v = voice(42, d, [(320, 1.0), (750, 0.7), (1900, 0.35), (2900, 0.15)], rough=1.1, breath=0.7, jitter=0.18, bend=bend)
    growl = lp(noise(d), 500) * (0.5 + 0.5 * np.sign(np.sin(2 * np.pi * 31 * t_axis(d)))) * 0.6
    sub = tone(28 * bend(t_axis(d)), d, "sine") * 0.5
    x = (v + growl + sub) * env(n, 0.25, 2.2, 0.0, 2.2)
    save("dragon_roar", x, 0.95)
    # passo: baque grave e um pouco de terra
    d = 0.6
    n = int(d * SR)
    thud = lp(brown(d), 120) * env(n, 0.004, 0.25) * 2.2 + bp(noise(d), 400, 2500) * env(n, 0.01, 0.15) * 0.25
    save("dragon_step", thud, 0.8)


def _save_raw(name, x, peak):
    """Salva sem fade (loops precisam emendar sem cortar o volume)."""
    x = norm(np.asarray(x, dtype=float), peak)
    data = (np.clip(x, -1, 1) * 32767).astype("<i2")
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())
    print(f"{name:16s} {len(x) / SR:5.2f} s (loop)")


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    footsteps()
    gunshot()
    gun_mech()
    melee()
    axe_and_tree()
    zombie()
    player_sounds()
    consumables()
    world()
    car()
    fire()
    dragon()
