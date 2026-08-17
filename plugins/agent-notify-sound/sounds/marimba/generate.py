#!/usr/bin/env python3
"""Synthesize the marimba theme: warm wooden mallets, soft and short."""
import numpy as np, wave, os, struct

SR = 44100

def env_exp(n, decay, attack=0.004):
    t = np.arange(n) / SR
    e = np.exp(-t / decay)
    a = np.minimum(t / attack, 1.0)
    return e * a

def tone(freq, dur, partials, decay, amp=1.0, detune=0.0):
    n = int(SR * dur)
    t = np.arange(n) / SR
    out = np.zeros(n)
    for ratio, gain, dscale in partials:
        f = freq * ratio * (1.0 + detune)
        out += gain * np.sin(2 * np.pi * f * t) * env_exp(n, decay * dscale)
    return out * amp

# --- timbres -------------------------------------------------------------
def bell(freq, dur=1.1, amp=1.0):
    """Glassy bell: inharmonic partials, long smooth decay."""
    return tone(freq, dur, [
        (1.00, 1.00, 1.00),
        (2.00, 0.42, 0.62),
        (3.01, 0.20, 0.42),
        (4.17, 0.11, 0.28),
        (5.43, 0.05, 0.18),
    ], decay=dur * 0.42, amp=amp)

def marimba(freq, dur=0.55, amp=1.0):
    """Wooden bar: strong 4th-harmonic partial, fast decay, soft click attack."""
    y = tone(freq, dur, [
        (1.00, 1.00, 1.00),
        (3.95, 0.30, 0.35),
        (9.20, 0.08, 0.16),
        (2.00, 0.06, 0.45),
    ], decay=dur * 0.24, amp=amp)
    # soft mallet noise transient
    n = int(SR * 0.012)
    noise = np.random.default_rng(7).normal(0, 1, n) * np.exp(-np.arange(n) / (SR * 0.0035))
    y[:n] += noise * 0.05 * amp
    return y

# --- helpers -------------------------------------------------------------
def mix(events, total):
    """events: list of (start_seconds, samples)"""
    buf = np.zeros(int(SR * total))
    for start, sig in events:
        i = int(SR * start)
        end = min(len(buf), i + len(sig))
        buf[i:end] += sig[:end - i]
    return buf

def write_wav(path, buf):
    # fade out tail + normalize
    buf = np.asarray(buf, dtype=np.float64)
    tail = int(SR * 0.02)
    if len(buf) > tail:
        buf[-tail:] *= np.linspace(1, 0, tail)
    peak = np.max(np.abs(buf))
    if peak > 0:
        buf = buf / peak * 0.82
    data = (buf * 32767).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())
    print(f"  {path}  ({len(buf)/SR:.2f}s, {os.path.getsize(path)/1024:.1f} KB)")

N = lambda name: {
    "E5": 659.26, "G5": 783.99, "A5": 880.00, "B5": 987.77,
    "C6": 1046.50, "D6": 1174.66, "E6": 1318.51, "F#6": 1479.98,
    "G6": 1567.98, "A6": 1760.00, "B6": 1975.53, "C7": 2093.00,
    "D5": 587.33, "C5": 523.25, "A4": 440.00,
}[name]

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# ============ MARIMBA theme (warm wood) ==================================
print("marimba theme:")
write_wav(f"{ROOT}/marimba/done.wav", mix([
    (0.00, marimba(N("E6"), 0.50, 0.70)),
    (0.10, marimba(N("A5"), 0.75, 1.00)),
], 0.90))

write_wav(f"{ROOT}/marimba/attention.wav", mix([
    (0.00, marimba(N("D6"), 0.35, 0.85)),
    (0.11, marimba(N("D6"), 0.30, 0.70)),
    (0.22, marimba(N("A6"), 0.55, 0.95)),
], 0.85))

write_wav(f"{ROOT}/marimba/plan.wav", mix([
    (0.00, marimba(N("A5"), 0.40, 0.75)),
    (0.09, marimba(N("C6"), 0.40, 0.82)),
    (0.18, marimba(N("E6"), 0.70, 1.00)),
    (0.18, marimba(N("A6"), 0.70, 0.35)),
], 1.0))

print("done.")
