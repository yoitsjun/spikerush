#!/usr/bin/env python3
"""Synthesizes an original sound effect for every key in Assets.Sounds and writes
assets/sfx/<Key>.ogg. Nothing is sampled: every sound is built from sine waves, filtered noise
and envelopes, so you own them outright. Upload the .ogg files to Roblox
(Creator Hub > Development Items > Audio) and paste the ids into src/shared/Assets.lua.

Usage:  python3 tools/generate_sfx.py            (needs numpy, scipy and ffmpeg with libvorbis)
"""
import shutil
import subprocess
import sys
from pathlib import Path

import numpy as np
from scipy.io import wavfile
from scipy.signal import butter, fftconvolve, sosfilt

SR = 44100
rng = np.random.default_rng(1234)
root = Path(__file__).resolve().parent.parent
out = root / "assets" / "sfx"


def t_axis(dur):
    return np.arange(int(SR * dur)) / SR


def env(dur, attack=0.004, decay=None, curve=6.0):
    """Fast attack, exponential decay over the whole duration."""
    t = t_axis(dur)
    a = np.clip(t / max(attack, 1e-4), 0, 1)
    d = np.exp(-curve * t / (decay or dur))
    return a * d


def sweep_sine(f0, f1, dur, shape="exp"):
    t = t_axis(dur)
    if shape == "exp":
        f = f0 * (f1 / f0) ** (t / dur)
    else:
        f = f0 + (f1 - f0) * t / dur
    phase = 2 * np.pi * np.cumsum(f) / SR
    return np.sin(phase)


def noise(dur):
    return rng.standard_normal(int(SR * dur))


def band(x, lo, hi, order=4):
    sos = butter(order, [lo, hi], btype="band", fs=SR, output="sos")
    return sosfilt(sos, x)


def low(x, fc, order=4):
    return sosfilt(butter(order, fc, btype="low", fs=SR, output="sos"), x)


def high(x, fc, order=4):
    return sosfilt(butter(order, fc, btype="high", fs=SR, output="sos"), x)


def mix(*parts):
    n = max(len(p) for p in parts)
    y = np.zeros(n)
    for p in parts:
        y[: len(p)] += p
    return y


def drive(x, amount):
    return np.tanh(x * amount) / np.tanh(amount)


def norm(x, peak=0.9):
    m = np.max(np.abs(x)) or 1.0
    return x / m * peak


def pad(x, dur):
    n = int(SR * dur)
    return np.concatenate([x, np.zeros(max(0, n - len(x)))])


def thump(f0, f1, dur, level=1.0):
    return sweep_sine(f0, f1, dur) * env(dur, 0.002, dur * 0.5) * level


def ping(freq, dur, level=1.0, curve=7.0):
    return np.sin(2 * np.pi * freq * t_axis(dur)) * env(dur, 0.001, dur, curve) * level


def delay(x, seconds):
    return np.concatenate([np.zeros(int(seconds * SR)), x])


def clap(dur=0.12, lo=1000, hi=8000, bursts=3, spread=0.004):
    """A hand smack: a few noise bursts milliseconds apart, like a clap or a palm on leather."""
    parts = []
    for i in range(bursts):
        b = band(noise(dur), lo, hi) * env(dur, 0.0003, dur * (0.25 if i < bursts - 1 else 0.6), 7)
        parts.append(delay(b * (0.7 if i < bursts - 1 else 1.0), i * spread))
    return mix(*parts)


def tear(dur=0.25, lo=2000, hi=9000):
    """The air tearing behind a fast ball: a bright noise swoosh that fades out."""
    t = t_axis(dur)
    return band(noise(dur), lo, hi) * np.exp(-9 * t / dur) * np.clip(t / 0.01, 0, 1)


_IR = None


def room(x, wet=0.1):
    """A short arena room: convolve with a decaying, darkened noise tail."""
    global _IR
    if _IR is None:
        n = int(SR * 0.9)
        t = np.arange(n) / SR
        _IR = low(np.random.default_rng(99).standard_normal(n), 5000) * np.exp(-7.5 * t)
        _IR[: int(0.012 * SR)] = 0  # pre-delay
        _IR /= np.sqrt(np.sum(_IR**2))
    tail = fftconvolve(x, _IR)[: len(x) + len(_IR)]
    return mix(x, tail * wet)


# ---------------------------------------------------------------------------------------------
# recipes
# ---------------------------------------------------------------------------------------------


def bump():
    # forearm pass: a dense "thock" with a little skin slap on top
    body = thump(210, 110, 0.16, 1.0)
    skin = clap(0.06, 1200, 5000, 2, 0.003) * 0.45
    return room(drive(mix(body, skin, low(noise(0.05), 900) * env(0.05, 0.001) * 0.4), 1.6), 0.08)


def receive_perfect():
    # the clean dig: the thock plus a bright metallic "shing" that rings out
    shing = mix(ping(2093, 0.7, 0.35, 5), ping(3322, 0.55, 0.22, 6), ping(5274, 0.4, 0.14, 7))
    shimmer = high(noise(0.5), 6000) * env(0.5, 0.01, 0.5, 5) * 0.12
    return room(mix(bump() * 0.9, delay(shing, 0.012), delay(shimmer, 0.012)), 0.12)


def set_():
    # fingertips: two quick soft taps
    tap = mix(thump(380, 260, 0.07, 0.8), band(noise(0.03), 1500, 5000) * env(0.03, 0.0005) * 0.35)
    return room(mix(tap, delay(tap * 0.7, 0.014)), 0.08)


def spike():
    # the smack: palm on leather, a punchy body, a sub drop and the air tearing behind it
    smack = clap(0.14, 1100, 9000, 3, 0.0035) * 1.4
    body = thump(190, 85, 0.14, 0.9)
    sub = thump(90, 40, 0.35, 0.9)
    return room(drive(mix(smack, body, sub, delay(tear(0.22) * 0.5, 0.02)), 2.4), 0.1)


def spike_heavy():
    # a strong spike hits like an explosion: a bigger smack, a long sub and a crackling blast
    smack = clap(0.2, 800, 10000, 4, 0.004) * 1.5
    sub = thump(85, 30, 0.7, 1.4)
    blast = low(noise(0.6), 900) * env(0.6, 0.002, 0.25) * 0.9
    crackle = high(noise(0.5), 3000) * (rng.random(int(SR * 0.5)) > 0.97) * np.exp(-6 * t_axis(0.5)) * 0.8
    return room(drive(mix(smack, sub, blast, crackle, delay(tear(0.35) * 0.6, 0.03)), 3.2), 0.12)


def thunder():
    dur = 1.4
    t = t_axis(dur)
    crack = clap(0.1, 1500, 12000, 3, 0.002) * 1.6
    zap = np.sign(np.sin(2 * np.pi * 110 * t)) * (rng.random(len(t)) > 0.5) * np.exp(-5 * t) * 0.35
    crackle = high(noise(dur), 1500) * (rng.random(len(t)) > 0.95) * 1.6 * np.exp(-3.0 * t)
    rumble = band(noise(dur), 35, 160) * env(dur, 0.02, dur, 2.6) * 5.5
    return room(drive(mix(crack, low(zap, 4000), crackle, rumble, spike_heavy() * 0.6), 1.8), 0.14)


def azure_charge():
    dur = 0.9
    t = t_axis(dur)
    x = noise(dur)
    # rising band sweep built from overlapping bands
    y = np.zeros(len(t))
    for i in range(8):
        a, b = int(len(t) * i / 8), int(len(t) * (i + 1) / 8)
        lo = 300 * (7 ** (i / 8))
        seg = band(x, lo, lo * 2.2)[a:b]
        y[a:b] = seg
    tone = sweep_sine(200, 620, dur) * (0.5 + 0.5 * np.sin(2 * np.pi * 9 * t)) * 0.35
    return (y * 0.9 + tone) * np.clip(t / 0.6, 0, 1) * np.exp(-0.5 * t)


def azure_release():
    # a dragon's roar: a falling, growling formant over a deep blast
    dur = 0.9
    t = t_axis(dur)
    growl = band(noise(dur), 150, 1400) * (0.6 + 0.4 * np.sin(2 * np.pi * 38 * t)) * env(dur, 0.01, dur, 3.5)
    fall = sweep_sine(520, 60, dur) * env(dur, 0.002, 0.6) * 0.8
    return room(drive(mix(spike_heavy() * 0.8, growl * 0.9, fall), 2.6), 0.14)


def boom():
    # the jump: a heavy whump and a gust of air
    gust = band(noise(0.3), 200, 2500) * env(0.3, 0.004, 0.12) * 0.6
    return room(drive(mix(thump(80, 32, 0.45, 1.4), gust), 2.0), 0.1)


def impact_frame():
    # the impact frame: a quick inhale (reversed swell) that slams into a hit
    swell = band(noise(0.28), 600, 7000) * np.linspace(0, 1, int(SR * 0.28)) ** 3
    slam = spike_heavy()
    return mix(swell * 0.9, delay(slam, 0.28))


def whoosh():
    dur = 0.38
    t = t_axis(dur)
    shape = np.sin(np.pi * np.clip(t / dur, 0, 1)) ** 2
    return band(noise(dur), 500, 3500) * shape


def block():
    # hands on the ball at the net: a flat, hard slap
    return room(drive(mix(clap(0.12, 700, 6000, 2, 0.003) * 1.2, thump(200, 110, 0.18, 0.9)), 1.8), 0.1)


def stuff():
    ring = mix(ping(523, 0.6, 0.35, 5), ping(871, 0.5, 0.25, 6), ping(1307, 0.4, 0.2, 7))
    return room(mix(block() * 1.2, thump(70, 35, 0.4, 1.0), ring), 0.12)


def floor_hit():
    # the ball slamming into the court, with the hall answering
    return room(drive(mix(thump(120, 45, 0.4, 1.3), clap(0.08, 600, 5000, 2, 0.003) * 0.6, low(noise(0.15), 900) * env(0.15, 0.001) * 0.5), 1.8), 0.18)


def net_hit():
    dur = 0.45
    t = t_axis(dur)
    am = 0.5 + 0.5 * np.sin(2 * np.pi * 26 * t)
    return band(noise(dur), 1800, 6500) * am * env(dur, 0.005, dur, 4)


def toss():
    dur = 0.2
    t = t_axis(dur)
    return band(noise(dur), 900, 4200) * np.sin(np.pi * t / dur) * 0.7


def serve():
    return room(mix(clap(0.12, 900, 6000, 2, 0.003), thump(230, 120, 0.2, 0.9)), 0.1)


def slide():
    squeak = sweep_sine(1800, 2700, 0.14) * env(0.14, 0.005, 0.14, 3) * 0.5
    scrape = band(noise(0.45), 400, 2500) * env(0.45, 0.01, 0.45, 3) * 0.6
    return mix(squeak, scrape)


def guard_break():
    dur = 0.9
    y = band(noise(0.12), 2000, 9000) * env(0.12, 0.0005)
    parts = [y]
    for _ in range(40):
        start = rng.random() * 0.5
        p = ping(2000 + rng.random() * 6000, 0.15 + rng.random() * 0.2, 0.3 + rng.random() * 0.3, 9)
        parts.append(np.concatenate([np.zeros(int(start * SR)), p]))
    return pad(mix(*parts), dur)


def whistle():
    dur = 0.6
    t = t_axis(dur)
    trem = 0.6 + 0.4 * np.sin(2 * np.pi * 32 * t)
    tone = np.sin(2 * np.pi * 2850 * t) + 0.3 * np.sin(2 * np.pi * 5700 * t)
    shape = np.clip(t / 0.02, 0, 1) * np.clip((dur - t) / 0.08, 0, 1)
    return (tone * trem + band(noise(dur), 2500, 3500) * 0.2) * shape


def timeout():
    dur = 0.7
    t = t_axis(dur)
    sq = np.sign(np.sin(2 * np.pi * 440 * t)) * 0.5 + np.sign(np.sin(2 * np.pi * 554 * t)) * 0.4
    shape = np.clip(t / 0.01, 0, 1) * np.clip((dur - t) / 0.05, 0, 1)
    return low(sq, 3000) * shape


def ui_click():
    return ping(2100, 0.03, 1.0, 9)


def point():
    notes = [1047, 1319, 1568]
    parts = []
    for i, f in enumerate(notes):
        parts.append(np.concatenate([np.zeros(int(i * 0.08 * SR)), ping(f, 0.45, 0.6, 5)]))
    return mix(*parts)


def crowd_bed(dur, seed_shift=0.0):
    t = t_axis(dur)
    y = np.zeros(len(t))
    for i in range(10):
        lo = 250 + i * 180
        voice = band(noise(dur), lo, lo * 1.8, 2)
        mod = 0.5 + 0.5 * np.sin(2 * np.pi * (0.2 + 0.13 * i) * t + i + seed_shift)
        y += voice * mod
    return y


def crowd_loop():
    dur = 8.0
    y = crowd_bed(dur + 1.0)
    # seamless: crossfade the extra second into the start
    n, f = int(dur * SR), int(1.0 * SR)
    head, tail = y[:n].copy(), y[n : n + f]
    ramp = np.linspace(0, 1, f)
    head[:f] = head[:f] * ramp + tail * (1 - ramp)
    return head * 0.5


def crowd_cheer():
    dur = 2.6
    t = t_axis(dur)
    shape = np.clip(t / 0.25, 0, 1) * np.exp(-1.2 * np.clip(t - 0.4, 0, None))
    whoo = sum(np.sin(2 * np.pi * (380 + 40 * i) * t + i) * 0.04 for i in range(6)) * shape
    return crowd_bed(dur, 2.0) * shape + whoo


def crowd_gasp():
    dur = 1.0
    t = t_axis(dur)
    shape = np.clip(t / 0.1, 0, 1) * np.exp(-3.0 * t)
    return band(noise(dur), 500, 2500) * shape


def music():
    """An original 120 BPM, 8-bar loop: kick, snare, hats, saw bass, square arpeggio."""
    bpm = 120
    beat = 60 / bpm
    bars = 8
    dur = bars * 4 * beat
    n = int(dur * SR)
    y = np.zeros(n)

    def place(sig, at):
        i = int(at * SR)
        j = min(n, i + len(sig))
        y[i:j] += sig[: j - i]

    kick = thump(120, 45, 0.25, 1.0)
    snare = band(noise(0.18), 1200, 7000) * env(0.18, 0.001, 0.08) * 0.6
    hat = high(noise(0.05), 7000) * env(0.05, 0.0005) * 0.25
    for b in range(bars * 4):
        at = b * beat
        if b % 2 == 0:
            place(kick, at)
        else:
            place(snare, at)
        place(hat, at + beat / 2)
    # I - V - vi - IV in A major
    roots = [110.0, 164.81, 185.0, 146.83]
    chords = [[440, 554.37, 659.25], [329.63, 415.3, 493.88], [369.99, 440, 554.37], [293.66, 369.99, 440]]
    for bar in range(bars):
        idx = bar % 4
        f = roots[idx]
        tt = t_axis(4 * beat)
        saw = 2 * ((f * tt) % 1) - 1
        bass = low(saw, 700) * 0.28 * np.clip(1 - (tt % beat) / beat * 0.6, 0, 1)
        place(bass, bar * 4 * beat)
        for k in range(8):
            note = chords[idx][k % 3] * (2 if k >= 4 else 1)
            s = np.sign(np.sin(2 * np.pi * note * t_axis(beat / 2))) * env(beat / 2, 0.003, beat / 2, 4) * 0.08
            place(low(s, 4000), bar * 4 * beat + k * beat / 2)
    return y


RECIPES = {
    "Bump": bump,
    "ReceivePerfect": receive_perfect,
    "Set": set_,
    "Spike": spike,
    "SpikeHeavy": spike_heavy,
    "Thunder": thunder,
    "AzureCharge": azure_charge,
    "AzureRelease": azure_release,
    "Boom": boom,
    "Whoosh": whoosh,
    "Block": block,
    "Stuff": stuff,
    "FloorHit": floor_hit,
    "NetHit": net_hit,
    "Toss": toss,
    "Serve": serve,
    "Slide": slide,
    "GuardBreak": guard_break,
    "Whistle": whistle,
    "Timeout": timeout,
    "UIClick": ui_click,
    "Point": point,
    "CrowdLoop": crowd_loop,
    "CrowdCheer": crowd_cheer,
    "CrowdGasp": crowd_gasp,
    "Music": music,
    "ImpactFrame": impact_frame,
}

PEAK = {"CrowdLoop": 0.5, "Music": 0.7, "UIClick": 0.5, "CrowdGasp": 0.6, "Timeout": 0.45, "Whistle": 0.6}


def main():
    if not shutil.which("ffmpeg"):
        print("ffmpeg not found: install it to encode .ogg files")
        return 1
    out.mkdir(parents=True, exist_ok=True)
    tmp = out / "_tmp.wav"
    for key, fn in RECIPES.items():
        y = norm(fn(), PEAK.get(key, 0.9))
        # tiny fade at both ends: no clicks
        f = min(len(y) // 4, int(0.004 * SR))
        if f > 0:
            y[:f] *= np.linspace(0, 1, f)
            y[-f:] *= np.linspace(1, 0, f)
        wavfile.write(tmp, SR, (y * 32767).astype(np.int16))
        dst = out / (key + ".ogg")
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(tmp), "-c:a", "libvorbis", "-q:a", "5", str(dst)], check=True)
        print(f"{key:15s} {len(y) / SR:5.2f}s -> {dst.relative_to(root)}")
    tmp.unlink(missing_ok=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
