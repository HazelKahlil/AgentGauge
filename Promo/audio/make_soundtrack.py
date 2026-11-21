#!/usr/bin/env python3
"""Original soundtrack + SFX for the AgentGauge promo v2 (fully synthesized, royalty-free).

Timeline (seconds) mirrors src/Promo.tsx (62s):
  0-4 hook | 4-8 brand | 8-16 HD showcase | 16-25 dock demo | 25-31 macro
  31-36 styles | 36-42 dashboard | 42-48 menu bar | 48-53 settings | 53-57 apps | 57-62 outro
"""
import json
import sys
import numpy as np
from scipy import signal
from scipy.io import wavfile

SR = 48000
TOTAL = 62.0
BPM = 120.0
BEAT = 60.0 / BPM
N = int(SR * TOTAL)
rng = np.random.default_rng(7)

L = np.zeros(N)
R = np.zeros(N)
SEND_L = np.zeros(N)
SEND_R = np.zeros(N)


def midi(m):
    return 440.0 * 2 ** ((m - 69) / 12.0)


def place(buf_l, buf_r, sig_l, sig_r, t0):
    i0 = int(t0 * SR)
    if i0 >= N:
        return
    n = min(len(sig_l), N - i0)
    if i0 < 0:
        sig_l, sig_r = sig_l[-i0:], sig_r[-i0:]
        n = min(len(sig_l), N)
        i0 = 0
    buf_l[i0:i0 + n] += sig_l[:n]
    buf_r[i0:i0 + n] += sig_r[:n]


def add(sig, t0, gain=1.0, pan=0.0, send=0.0):
    gl = gain * np.cos((pan + 1) * np.pi / 4)
    gr = gain * np.sin((pan + 1) * np.pi / 4)
    place(L, R, sig * gl, sig * gr, t0)
    if send > 0:
        place(SEND_L, SEND_R, sig * gl * send, sig * gr * send, t0)


def env_adsr(n, a, d, s, r):
    a_n, d_n, r_n = int(a * SR), int(d * SR), int(r * SR)
    s_n = max(0, n - a_n - d_n - r_n)
    e = np.concatenate([
        np.linspace(0, 1, max(1, a_n)) ** 1.6,
        np.linspace(1, s, max(1, d_n)),
        np.full(s_n, s),
        np.linspace(s, 0, max(1, r_n)) ** 1.3,
    ])
    return e[:n] if len(e) >= n else np.pad(e, (0, n - len(e)))


def lp(x, fc, order=2):
    b, a = signal.butter(order, min(0.99, fc / (SR / 2)), "low")
    return signal.lfilter(b, a, x)


def hp(x, fc, order=2):
    b, a = signal.butter(order, min(0.99, fc / (SR / 2)), "high")
    return signal.lfilter(b, a, x)


def bp(x, lo, hi):
    b, a = signal.butter(2, [lo / (SR / 2), min(0.99, hi / (SR / 2))], "band")
    return signal.lfilter(b, a, x)


def saw(freq, n, phase=0.0):
    t = np.arange(n) / SR
    return 2.0 * ((freq * t + phase) % 1.0) - 1.0


# ---------------------------------------------------------------- instruments

def pad_chord(notes, t0, dur, gain=0.11, cutoff=1500):
    n = int(dur * SR)
    out_l = np.zeros(n)
    out_r = np.zeros(n)
    for m in notes:
        f = midi(m)
        for det, side in ((-0.09, -1), (0.0, 0), (0.08, 1)):
            ff = f * 2 ** (det / 12.0)
            v = saw(ff, n, rng.random())
            pan = 0.55 * side
            out_l += v * np.cos((pan + 1) * np.pi / 4)
            out_r += v * np.sin((pan + 1) * np.pi / 4)
    e = env_adsr(n, 0.9, 0.4, 0.85, 1.1)
    out_l = lp(out_l, cutoff, 3) * e
    out_r = lp(out_r, cutoff, 3) * e
    scale = gain / max(1, len(notes))
    place(L, R, out_l * scale, out_r * scale, t0)
    place(SEND_L, SEND_R, out_l * scale * 0.55, out_r * scale * 0.55, t0)


def sub_bass(m, t0, dur, gain=0.20):
    n = int(dur * SR)
    t = np.arange(n) / SR
    v = np.sin(2 * np.pi * midi(m) * t) + 0.18 * np.sin(2 * np.pi * midi(m) * 2 * t)
    v *= env_adsr(n, 0.03, 0.2, 0.75, 0.25)
    add(v, t0, gain)


def kick(t0, gain=0.55):
    n = int(0.42 * SR)
    t = np.arange(n) / SR
    f = 46 + 110 * np.exp(-t * 32)
    ph = 2 * np.pi * np.cumsum(f) / SR
    v = np.sin(ph) * np.exp(-t * 7.5)
    v += 0.25 * np.exp(-t * 180) * rng.standard_normal(n) * 0.3
    add(np.tanh(v * 1.4), t0, gain)


def hat(t0, gain=0.05, pan=0.25):
    n = int(0.05 * SR)
    v = hp(rng.standard_normal(n), 7500, 2) * np.exp(-np.arange(n) / SR * 90)
    add(v, t0, gain, pan)


def pluck(m, t0, gain=0.07, pan=0.0, send=0.5):
    n = int(0.55 * SR)
    t = np.arange(n) / SR
    f = midi(m)
    v = np.sin(2 * np.pi * f * t) + 0.35 * np.sin(2 * np.pi * 2 * f * t) * np.exp(-t * 18)
    v *= np.exp(-t * 7.0) * np.minimum(1, t * 400)
    add(lp(v, 5200), t0, gain, pan, send)


def bloop(t0, gain=0.22, base=420, top=1280, pan=0.0):
    n = int(0.32 * SR)
    t = np.arange(n) / SR
    f = base + (top - base) * (1 - np.exp(-t * 55))
    ph = 2 * np.pi * np.cumsum(f) / SR
    v = np.sin(ph) * np.exp(-t * 16) * np.minimum(1, t * 600)
    add(v, t0, gain, pan, send=0.7)


def bubble_pop(t0, gain=0.08, pan=0.0):
    n = int(0.06 * SR)
    t = np.arange(n) / SR
    f0 = rng.uniform(900, 1500)
    f = f0 * (1 + 1.4 * t / t[-1])
    ph = 2 * np.pi * np.cumsum(f) / SR
    v = np.sin(ph) * np.exp(-t * 60) * np.minimum(1, t * 900)
    add(v, t0, gain, pan, send=0.5)


def tick(t0, gain=0.06, freq=2600, pan=0.0):
    n = int(0.03 * SR)
    t = np.arange(n) / SR
    v = np.sin(2 * np.pi * freq * t) * np.exp(-t * 160)
    add(v, t0, gain, pan, send=0.3)


def whoosh(t_end, dur=0.7, gain=0.16):
    n = int(dur * SR)
    t = np.arange(n) / SR
    noise = rng.standard_normal(n)
    out = np.zeros(n)
    seg = 512
    for i in range(0, n, seg):
        x = i / n
        fc = 300 + 5200 * x ** 1.8
        blk = noise[i:i + seg]
        if len(blk) < 16:
            continue
        out[i:i + seg] = bp(blk, fc * 0.6, fc * 1.6)
    e = np.sin(np.pi * np.clip(t / dur, 0, 1)) ** 2 * (t / dur) ** 0.6
    v = out * e
    v = lp(v, 9000)
    add(v, t_end - dur, gain, send=0.35)


def impact(t0, gain=0.5):
    n = int(2.2 * SR)
    t = np.arange(n) / SR
    boom = np.sin(2 * np.pi * (38 + 40 * np.exp(-t * 9)) * t) * np.exp(-t * 2.2)
    noise = lp(rng.standard_normal(n), 2400) * np.exp(-t * 14) * 0.35
    shimmer = sum(np.sin(2 * np.pi * midi(m) * t + rng.random() * 6) for m in (86, 90, 93, 98)) * 0.05
    shimmer *= np.exp(-t * 1.6) * np.minimum(1, t * 30)
    add(np.tanh((boom + noise) * 1.2), t0, gain)
    add(shimmer, t0, gain * 0.9, send=0.9)


def riser(t0, dur, gain=0.12):
    n = int(dur * SR)
    t = np.arange(n) / SR
    x = t / dur
    noise = hp(rng.standard_normal(n), 1200) * x ** 2.2
    tone = np.sin(2 * np.pi * np.cumsum(220 + 660 * x ** 2) / SR) * 0.25 * x ** 2
    add((noise * 0.6 + tone) * 0.8, t0, gain, send=0.6)


# ---------------------------------------------------------------- arrangement
# Key: D major. Bar = 2s @120bpm.
CH = {
    "Dmaj9": [50, 57, 61, 64, 66],
    "Bm9": [47, 54, 57, 61, 62],
    "Gmaj9": [43, 50, 54, 57, 62],
    "A6sus": [45, 52, 54, 59, 62],
    "Em9": [40, 47, 50, 54, 57],
}
ROOT = {"Dmaj9": 38, "Bm9": 35, "Gmaj9": 31, "A6sus": 33, "Em9": 28}
progression = ["Dmaj9", "Bm9", "Gmaj9", "A6sus"]

# Pads all the way, gentle intro (darker cutoff) then open up
for bar in range(32):
    t0 = bar * 2.0
    if t0 >= TOTAL:
        break
    name = progression[bar % 4]
    if 57 <= t0 < 62:
        name = "Dmaj9" if t0 < 59 else "Gmaj9"
    cutoff = 900 if t0 < 4 else (1300 if t0 < 8 else (1650 if t0 < 16 else 1850))
    gain = 0.075 if t0 < 4 else 0.10
    pad_chord(CH[name], t0, 2.35, gain=gain, cutoff=cutoff)

# Hook question blips (0.3, 0.95, 1.6, 2.25)
for i, t in enumerate([0.30, 0.95, 1.60, 2.25]):
    pluck(74 + [0, 2, 4, 7][i], t, gain=0.09, pan=[-0.4, 0.4, -0.2, 0.2][i], send=0.8)
riser(2.4, 1.6)
impact(4.0, gain=0.55)
bloop(4.15, gain=0.18, base=380, top=1100)

# Beat section 8 -> 57 (half-time feel in HD showcase 8-16 & macro 25-31)
for b in range(int(8 / BEAT), int(57 / BEAT)):
    t = b * BEAT
    in_half = (8 <= t < 16) or (25 <= t < 31)
    if in_half:
        if b % 2 == 0:
            kick(t, 0.36 if 8 <= t < 16 else 0.38)
        if 8 <= t < 16 and b % 2 == 1:
            hat(t + BEAT / 2, 0.032, pan=0.25 if b % 4 == 1 else -0.25)
    else:
        kick(t, 0.42 if b % 2 == 0 else 0.30)
        hat(t + BEAT / 2, 0.045, pan=0.3 if b % 2 else -0.3)

# Sub bass following progression from 8s
for bar in range(4, 29):
    t0 = bar * 2.0
    if t0 >= 57:
        break
    name = progression[bar % 4]
    sub_bass(ROOT[name], t0, 1.9, gain=0.16)
sub_bass(ROOT["Dmaj9"], 57.0, 3.8, gain=0.14)

# Arp plucks (16ths) in HD showcase (subtle), dock demo, styles, menu bar, apps
ARP = {name: [n + 12 for n in notes[1:]] for name, notes in CH.items()}
for start, end, g in ((8.0, 16.0, 0.032), (16.0, 25.0, 0.045), (31.0, 36.0, 0.045), (42.0, 48.0, 0.036), (53.0, 57.0, 0.048)):
    t = start
    k = 0
    while t < end - 0.01:
        bar = int(t // 2.0)
        name = progression[bar % 4]
        pat = ARP[name]
        m = pat[[0, 2, 1, 3, 2, 1, 3, 0][k % 8] % len(pat)]
        pluck(m, t, gain=g, pan=0.35 * np.sin(k * 0.9), send=0.45)
        t += BEAT / 2
        k += 1

# HD showcase hero entrances (Grok Bot 8.15, Cursor 10.25, Antigravity 12.45, Trio 14.65)
for t, b0, b1, p in (
    (8.15, 360, 1080, -0.15),
    (10.25, 420, 1200, 0.0),
    (12.45, 460, 1340, 0.15),
    (14.65, 500, 1460, 0.0),
):
    bloop(t, gain=0.22, base=b0, top=b1, pan=p)
    for j in range(4):
        bubble_pop(t + 0.16 + j * 0.11 + rng.uniform(0, 0.04), gain=0.055, pan=p + (j - 1.5) * 0.12)

# Dock hover water bloops (Antigravity 16.85, ChatGPT 19.65, Grok Bot 22.45)
for t, p in ((16.85, -0.3), (19.65, 0.0), (22.45, 0.3)):
    bloop(t, gain=0.26, pan=p)
    for j in range(5):
        bubble_pop(t + 0.18 + j * 0.09 + rng.uniform(0, 0.04), gain=0.05, pan=p)

# Scene transitions
for t in (8.0, 16.0, 25.0, 31.0, 36.0, 42.0, 48.0, 53.0, 57.0):
    whoosh(t, dur=0.72, gain=0.13)

# Macro drain (25-31): descending gentle tones + callout ticks
for i, t in enumerate([25.6, 26.8, 28.2, 29.4]):
    tick(t, gain=0.07, freq=2400 + i * 180)
for i in range(10):
    pluck(86 - i, 25.5 + i * 0.45, gain=0.025, pan=0.2 * np.sin(i), send=0.9)
bloop(29.4, gain=0.14, base=900, top=500)  # low-water dodge cue

# Style grid pops (31-36)
for i in range(12):
    bubble_pop(31.25 + i * 0.11, gain=0.07, pan=-0.6 + (i % 6) * 0.24)

# Dashboard callouts (36-42)
for i, t in enumerate([37.0, 38.2, 39.4, 40.4]):
    tick(t, gain=0.07, freq=2650 + i * 140)

# Menu Bar popover open + sidebar hover sweeps (42-48)
tick(42.38, gain=0.09, freq=2200, pan=0.22)
bloop(42.42, gain=0.15, base=480, top=1080, pan=0.2)
tick(44.20, gain=0.08, freq=2600, pan=0.12)
bubble_pop(44.24, gain=0.055, pan=0.12)
tick(46.00, gain=0.08, freq=2900, pan=0.12)
bubble_pop(46.04, gain=0.055, pan=0.12)

# Settings / sheet slide (48-53)
bloop(48.30, gain=0.11, base=500, top=900)
bloop(49.60, gain=0.11, base=600, top=1040)

# App count ticks (53-57, counting to 50)
for i in range(20):
    tick(53.2 + i * 0.085, gain=0.032, freq=2900 + i * 45, pan=-0.5 + i / 20)

# Outro (57-62)
impact(57.0, gain=0.44)
pad_chord([50, 57, 62, 66, 69, 74], 57.0, 5.0, gain=0.095, cutoff=2200)
bloop(57.2, gain=0.16, base=380, top=1150)

# ---------------------------------------------------------------- reverb + master
ir_len = int(2.6 * SR)
tt = np.arange(ir_len) / SR
ir_l = rng.standard_normal(ir_len) * np.exp(-tt * 2.6)
ir_r = rng.standard_normal(ir_len) * np.exp(-tt * 2.6)
ir_l = lp(ir_l, 6500)
ir_r = lp(ir_r, 6500)
ir_l /= np.sqrt(np.sum(ir_l ** 2))
ir_r /= np.sqrt(np.sum(ir_r ** 2))
wet_l = signal.fftconvolve(SEND_L, ir_l)[:N]
wet_r = signal.fftconvolve(SEND_R, ir_r)[:N]

mix_l = L + wet_l * 0.55
mix_r = R + wet_r * 0.55
mix_l = hp(mix_l, 28)
mix_r = hp(mix_r, 28)

fade = np.ones(N)
fo = int(2.2 * SR)
fade[-fo:] = np.linspace(1, 0, fo) ** 1.5
fi = int(0.25 * SR)
fade[:fi] = np.linspace(0, 1, fi)
mix_l *= fade
mix_r *= fade

peak = max(np.max(np.abs(mix_l)), np.max(np.abs(mix_r)))
mix_l = np.tanh(mix_l / peak * 1.25) / np.tanh(1.25) * 0.89
mix_r = np.tanh(mix_r / peak * 1.25) / np.tanh(1.25) * 0.89

out = np.stack([mix_l, mix_r], axis=1).astype(np.float32)
path = sys.argv[1] if len(sys.argv) > 1 else "soundtrack.wav"
wavfile.write(path, SR, out)
print(json.dumps({"path": path, "seconds": TOTAL, "peak": float(np.max(np.abs(out)))}))
