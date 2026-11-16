#!/usr/bin/env python3
"""Synthesize an original, upbeat backing track for the daily clip (no samples, no third-party audio).

Usage: make_music.py OUT.wav SECONDS [DAY]
The day number picks the key and chord progression, so each day's clip sounds a little different.
Everything is generated here from sine/saw/noise oscillators, so the music is ours to use anywhere.
"""
import sys
import wave

import numpy as np

SR = 44100
BPM = 118

out, seconds = sys.argv[1], float(sys.argv[2])
day = int(sys.argv[3]) if len(sys.argv) > 3 else 1
rng = np.random.default_rng(1986 + day)

n = int(seconds * SR)
beat = 60.0 / BPM
mix = np.zeros((n, 2))

# Key and progression (scale degrees of a minor key; i-VI-III-VII and friends)
root = 45 + [0, 2, 3, 5, 7, 8, 10][day % 7]  # A2 and up
PROGRESSIONS = [[0, 8, 3, 10], [0, 5, 8, 7], [0, 10, 8, 7], [0, 3, 8, 10]]
prog = PROGRESSIONS[day % len(PROGRESSIONS)]
MINOR = [0, 3, 7]
MAJOR = [0, 4, 7]


def hz(midi):
    return 440.0 * 2 ** ((midi - 69) / 12)


def env(length, attack=0.005, release=0.1):
    t = np.arange(length) / SR
    a = np.clip(t / attack, 0, 1)
    r = np.clip((length / SR - t) / release, 0, 1)
    return a * r


def lowpass(x, cutoff):
    # one-pole low-pass, vectorised enough for a minute of audio
    a = np.exp(-2 * np.pi * cutoff / SR)
    y = np.empty_like(x)
    acc = 0.0
    for i in range(0, len(x), 4096):
        seg = x[i:i + 4096]
        out_seg = np.empty_like(seg)
        for j, v in enumerate(seg):
            acc = (1 - a) * v + a * acc
            out_seg[j] = acc
        y[i:i + 4096] = out_seg
    return y


def saw(f, length):
    t = np.arange(length) / SR
    return 2 * ((t * f) % 1.0) - 1


def add(sig, start_s, gain=1.0, pan=0.0):
    i = int(start_s * SR)
    if i >= n:
        return
    sig = sig[: n - i]
    mix[i:i + len(sig), 0] += sig * gain * (1 - pan) / 2 * 2 ** 0.5
    mix[i:i + len(sig), 1] += sig * gain * (1 + pan) / 2 * 2 ** 0.5


def chord_of(bar):
    deg = prog[bar % 4]
    quality = MINOR if deg in (0, 5) else MAJOR
    return [root + deg + q for q in quality]


# Pre-render a few drum sounds
kl = int(0.35 * SR)
kt = np.arange(kl) / SR
kick = np.sin(2 * np.pi * (45 * kt + 90 * (1 - np.exp(-kt * 30)) / 30)) * np.exp(-kt * 9)
hl = int(0.05 * SR)
hat = rng.uniform(-1, 1, hl) * np.exp(-np.arange(hl) / SR * 90)
hat = hat - np.concatenate([[0], hat[:-1]])  # crude high-pass: brighter tick
cl = int(0.2 * SR)
clap = rng.uniform(-1, 1, cl) * np.exp(-np.arange(cl) / SR * 22)

bars = int(seconds / (4 * beat)) + 1
intro_bars = 2  # drums come in after two bars of pads, so the hook line reads over a calm start
for bar in range(bars):
    t0 = bar * 4 * beat
    notes = chord_of(bar)
    # Pad: detuned saws, filtered later as a group
    for k, m in enumerate(notes):
        for det in (-0.08, 0.08):
            length = int(4 * beat * SR)
            add(saw(hz(m + 12 + det), length) * env(length, 0.3, 0.4), t0, 0.045, pan=(k - 1) * 0.5)
    # Bass: eighth-note root pulse
    if bar >= intro_bars - 1:
        for e in range(8):
            length = int(beat / 2 * SR * 0.9)
            m = notes[0] - 12 + (12 if e % 4 == 3 else 0)
            sig = np.sign(np.sin(2 * np.pi * hz(m) * np.arange(length) / SR)) * env(length, 0.003, 0.05)
            add(sig, t0 + e * beat / 2, 0.11)
    # Arpeggio pluck: sixteenth notes walking the chord
    if bar >= intro_bars:
        pattern = [0, 1, 2, 1, 2, 0, 1, 2]
        for s in range(16):
            if rng.random() < 0.15:
                continue
            length = int(0.18 * SR)
            m = notes[pattern[s % 8]] + 24
            tt = np.arange(length) / SR
            sig = (np.sin(2 * np.pi * hz(m) * tt) + 0.3 * np.sin(4 * np.pi * hz(m) * tt)) * np.exp(-tt * 18)
            add(sig, t0 + s * beat / 4, 0.07, pan=0.35 if s % 2 else -0.35)
    # Drums
    if bar >= intro_bars:
        for b in range(4):
            add(kick, t0 + b * beat, 0.55)
            add(hat, t0 + b * beat + beat / 2, 0.12, pan=0.2)
            if b % 2 == 1:
                add(clap, t0 + b * beat, 0.16)
        if bar % 4 == 3:  # little fill into the next phrase
            for s in (12, 13, 14, 15):
                add(hat, t0 + s * beat / 4, 0.09, pan=-0.2)

# Gentle low-pass on the whole mix to take the edge off the saws, then fade in/out and normalise
for c in range(2):
    mix[:, c] = lowpass(mix[:, c], 5000)
fade = np.ones(n)
fi, fo = int(0.5 * SR), int(2.5 * SR)
fade[:fi] = np.linspace(0, 1, fi)
fade[-fo:] = np.linspace(1, 0, fo)
mix *= fade[:, None]
mix = np.tanh(mix * 1.4)  # soft clip glues it together
mix /= max(1e-6, np.abs(mix).max()) / 0.89

pcm = (mix * 32767).astype("<i2")
with wave.open(out, "wb") as w:
    w.setnchannels(2)
    w.setsampwidth(2)
    w.setframerate(SR)
    w.writeframes(pcm.tobytes())
print(f"{out}: {seconds:.1f}s, root {root}, progression {prog}")
