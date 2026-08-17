#!/usr/bin/env python3
"""Zaghlalah theme: two-letter morse codes — DO / NE / PL."""
import numpy as np, wave, os

SR = 44100
DIT = 0.050              # ~24 WPM
DAH = DIT * 3
GAP_EL = DIT             # between elements inside a letter
GAP_CH = DIT * 3         # between letters (standard morse spacing)
RAMP = 0.005             # raised-cosine keying edges

MORSE = {
    "D": "-..", "O": "---", "N": "-.", "E": ".",
    "P": ".--.", "L": ".-..",
}

def element(dur, freq):
    n = int(SR * dur)
    t = np.arange(n) / SR
    y = np.sin(2 * np.pi * freq * t)
    r = int(SR * RAMP)
    if n > 2 * r:
        w = 0.5 * (1 - np.cos(np.pi * np.arange(r) / r))
        y[:r] *= w
        y[-r:] *= w[::-1]
    else:
        y *= np.hanning(n)
    return y

def keyed(text, freq, tail=0.09):
    parts = []
    for li, letter in enumerate(text):
        if li:
            parts.append(np.zeros(int(SR * GAP_CH)))
        pat = MORSE[letter]
        for ei, c in enumerate(pat):
            if ei:
                parts.append(np.zeros(int(SR * GAP_EL)))
            parts.append(element(DIT if c == "." else DAH, freq))
    parts.append(np.zeros(int(SR * tail)))
    return np.concatenate(parts)

def write_wav(path, buf, level=0.75):
    buf = np.asarray(buf, dtype=np.float64)
    peak = np.max(np.abs(buf))
    if peak:
        buf = buf / peak * level
    with wave.open(path, "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes((buf * 32767).astype("<i2").tobytes())
    return len(buf) / SR

OUT = os.path.dirname(os.path.abspath(__file__))

CUES = [
    ("done",      "DO", 620),   # DO — done
    ("attention", "NE", 920),   # NE — needs you
    ("plan",      "PL", 760),   # PL — plan ready
]

for event, text, freq in CUES:
    pat = " ".join(MORSE[c] for c in text)
    d = write_wav(f"{OUT}/{event}.wav", keyed(text, freq))
    size = os.path.getsize(f"{OUT}/{event}.wav") / 1024
    print(f"  {event:10s} {text}  {pat:12s} {freq} Hz  {d:.2f}s  {size:.1f} KB")
