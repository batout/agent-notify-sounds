#!/usr/bin/env python3
"""
'jersey' theme — original composition, synthesized from scratch.

Nothing here is sampled, filtered, or otherwise derived from any recording.
It's a moody minor-pentatonic bass riff written to sit in the same mood as a
mob-drama cold open: overdriven bass, a little organ, an offbeat hat.
"""
import numpy as np, wave, os

SR = 44100
rng = np.random.default_rng(11)

N = {"A2":110.00,"C3":130.81,"D3":146.83,"E3":164.81,"G3":196.00,
     "A3":220.00,"B3":246.94,"C4":261.63,"E4":329.63}

# ------------------------------------------------------------- primitives --
def saw(f, n):
    """Additive sawtooth, harmonics capped below Nyquist-ish for no aliasing."""
    t = np.arange(n) / SR
    y = np.zeros(n)
    k = 1
    while f * k < 9000 and k <= 24:
        y += ((-1) ** (k + 1)) / k * np.sin(2 * np.pi * f * k * t)
        k += 1
    return y * (2 / np.pi)

def lowpass(x, cutoff):
    a = 1 - np.exp(-2 * np.pi * cutoff / SR)
    y = np.empty_like(x); acc = 0.0
    for i in range(len(x)):
        acc += a * (x[i] - acc)
        y[i] = acc
    return y

def adsr(n, a=0.008, d=0.10, s=0.55, r=0.18):
    e = np.zeros(n)
    ai, di = int(SR*a), int(SR*d)
    ri = min(int(SR*r), max(n - ai - di, 1))
    body = n - ai - di - ri
    if body < 0:
        di = max(n - ai - ri, 1); body = 0
    idx = 0
    e[idx:idx+ai] = np.linspace(0, 1, ai); idx += ai
    e[idx:idx+di] = np.linspace(1, s, di); idx += di
    if body > 0:
        e[idx:idx+body] = s; idx += body
    e[idx:idx+ri] = np.linspace(s, 0, len(e[idx:idx+ri]))
    return e

def bass(freq, dur, amp=1.0, drive=2.6, cutoff=900):
    n = int(SR * dur)
    y = saw(freq, n)
    y = lowpass(y, cutoff + freq * 1.5)
    y = np.tanh(drive * y) / np.tanh(drive)          # valve-ish overdrive
    return y * adsr(n) * amp

def organ(freq, dur, amp=0.28):
    n = int(SR * dur); t = np.arange(n) / SR
    y = (np.sin(2*np.pi*freq*t) + 0.5*np.sin(2*np.pi*freq*2*t)
         + 0.22*np.sin(2*np.pi*freq*3*t) + 0.1*np.sin(2*np.pi*freq*4*t))
    vib = 1 + 0.004 * np.sin(2*np.pi*5.2*t)
    return y * vib * adsr(n, a=0.02, d=0.12, s=0.6, r=0.22) * amp

def hat(dur=0.06, amp=0.12):
    n = int(SR * dur)
    x = rng.normal(0, 1, n)
    x = x - lowpass(x, 6500)                          # crude highpass
    return x * np.exp(-np.arange(n) / (SR * 0.012)) * amp

# ---------------------------------------------------------------- arrange --
def mix(events, total):
    buf = np.zeros(int(SR * total))
    for start, sig in events:
        i = int(SR * start); j = min(len(buf), i + len(sig))
        buf[i:j] += sig[:j - i]
    return buf

def note(t, name, dur, amp=1.0, org=True):
    ev = [(t, bass(N[name], dur, amp))]
    if org:
        ev.append((t, organ(N[name] * 2, dur * 0.85)))
    return ev

def write_wav(path, buf, level=0.80):
    buf = np.asarray(buf, float)
    tail = int(SR * 0.03)
    if len(buf) > tail:
        buf[-tail:] *= np.linspace(1, 0, tail)
    p = np.max(np.abs(buf))
    if p: buf = buf / p * level
    with wave.open(path, "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes((buf * 32767).astype("<i2").tobytes())
    return len(buf) / SR

OUT = os.path.dirname(os.path.abspath(__file__))
os.makedirs(OUT, exist_ok=True)

# done — a confident walk down that lands on the root. It's over, relax.
ev = []
ev += note(0.00, "E3", 0.24, 0.85)
ev += note(0.24, "D3", 0.24, 0.85)
ev += note(0.48, "C3", 0.24, 0.90)
ev += note(0.72, "A2", 0.80, 1.00)
for t in (0.12, 0.36, 0.60, 0.84):
    ev.append((t, hat()))
d1 = write_wav(f"{OUT}/done.wav", mix(ev, 1.60))

# attention — two hard stabs, no groove, no patience. Look up.
ev = []
ev += note(0.00, "E3", 0.16, 1.00, org=False)
ev += note(0.00, "B3", 0.16, 0.45, org=False)
ev += note(0.24, "G3", 0.42, 1.00, org=False)
ev += note(0.24, "D3", 0.42, 0.50, org=False)
ev.append((0.00, hat(0.05, 0.18)))
ev.append((0.24, hat(0.05, 0.18)))
d2 = write_wav(f"{OUT}/attention.wav", mix(ev, 0.85))

# plan — climbs and stops on the 7th. Unresolved on purpose: your move.
ev = []
ev += note(0.00, "A2", 0.22, 0.80)
ev += note(0.22, "C3", 0.22, 0.85)
ev += note(0.44, "E3", 0.22, 0.90)
ev += note(0.66, "G3", 0.82, 1.00)
for t in (0.11, 0.33, 0.55, 0.77):
    ev.append((t, hat()))
d3 = write_wav(f"{OUT}/plan.wav", mix(ev, 1.55))

for e, d in (("done", d1), ("attention", d2), ("plan", d3)):
    print(f"  {e:10s} {d:.2f}s  {os.path.getsize(f'{OUT}/{e}.wav')/1024:6.1f} KB")
