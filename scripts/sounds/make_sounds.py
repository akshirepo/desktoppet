"""Synthesize original cartoony pet sound effects (no samples) as 44.1 kHz mono 16-bit WAV files."""
import wave
from pathlib import Path
import numpy as np

SR = 44100
OUT = Path(__file__).resolve().parent.parent / "out"
rng = np.random.default_rng(7)

def t(sec): return np.arange(int(SR * sec)) / SR

def env(n, a=0.01, r=0.1, sustain=1.0):
    """Attack/release envelope over n samples."""
    e = np.ones(n) * sustain
    na, nr = max(1, int(a * SR)), max(1, int(r * SR))
    e[:na] = np.linspace(0, sustain, na)
    e[-nr:] *= np.linspace(1, 0, nr)
    return e

def sweep(f0, f1, sec, shape=1.0):
    """Phase of a tone gliding from f0 to f1 (shape > 1 bends the glide)."""
    x = t(sec) / sec
    f = f0 + (f1 - f0) * x ** shape
    return 2 * np.pi * np.cumsum(f) / SR

def noise(sec): return rng.uniform(-1, 1, int(SR * sec))

def lowpass(x, k):
    return np.convolve(x, np.ones(k) / k, mode="same")

def silence(sec): return np.zeros(int(SR * sec))

def voice(f0, f1, sec, formants, vib=6.0, vib_depth=0.03):
    """Cartoon voice: a buzzy glide shaped by a few vowel-like formant bands."""
    x = t(sec)
    ph = sweep(f0, f1, sec, 0.7) + vib_depth * np.sin(2 * np.pi * vib * x) * 20
    src = sum(np.sin(k * ph) / k for k in range(1, 12))
    out = np.zeros_like(src)
    for fc, g in formants:
        carrier = np.sin(2 * np.pi * fc * x)
        out += g * lowpass(src * carrier, 3)
    return out + 0.6 * src

def save(name, x, gain=0.8):
    x = x / (np.max(np.abs(x)) + 1e-9) * gain
    data = (np.clip(x, -1, 1) * 32767).astype(np.int16)
    with wave.open(str(OUT / f"{name}.wav"), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR); w.writeframes(data.tobytes())

# Petting voices
yip = voice(700, 1300, 0.16, [(1800, 0.5), (2600, 0.3)]) * env(int(SR * 0.16), 0.005, 0.08)
yip2 = voice(900, 1500, 0.12, [(1900, 0.5), (2700, 0.3)]) * env(int(SR * 0.12), 0.005, 0.07)
save("pet_corgi", np.concatenate([yip, silence(0.05), yip2]))
baa = voice(520, 470, 0.5, [(900, 0.6), (1400, 0.4)], vib=11, vib_depth=0.08) * env(int(SR * 0.5), 0.02, 0.2)
save("pet_sheep", baa)

# Happy wiggle: sparkly rising arpeggio
notes = [880, 1109, 1319, 1760]
spark = np.concatenate([np.sin(2 * np.pi * f * t(0.09)) * env(int(SR * 0.09), 0.003, 0.07) for f in notes])
save("happy", spark + 0.3 * np.concatenate([silence(0.03), spark[:-int(SR * 0.03)]]), 0.6)

# Eating: three crunchy chomps
def chomp(f):
    n = noise(0.07) * env(int(SR * 0.07), 0.002, 0.05)
    return lowpass(n, 6) + 0.5 * np.sin(sweep(f, f * 0.6, 0.07)) * env(int(SR * 0.07), 0.002, 0.05)
save("eat", np.concatenate([chomp(260), silence(0.09), chomp(230), silence(0.09), chomp(280)]), 0.7)

# Bath: splash + bubble pops
splash = lowpass(noise(0.3), 4) * env(int(SR * 0.3), 0.005, 0.25)
bubbles = np.zeros(int(SR * 0.7))
for start, f in [(0.05, 900), (0.2, 1200), (0.32, 800), (0.47, 1400), (0.58, 1000)]:
    b = np.sin(sweep(f, f * 1.8, 0.05)) * env(int(SR * 0.05), 0.002, 0.03)
    i = int(SR * start); bubbles[i:i + len(b)] += b
save("bath", np.concatenate([splash, bubbles * 0.7]), 0.7)

# Snore: breathy in, buzzy out
inhale = lowpass(noise(0.6), 30) * env(int(SR * 0.6), 0.3, 0.2) * 0.5
buzz = np.sign(np.sin(sweep(85, 70, 0.7))) * 0.3 + lowpass(noise(0.7), 40)
save("snore", np.concatenate([inhale, buzz * env(int(SR * 0.7), 0.1, 0.4), silence(0.2)]), 0.45)

# Yawn: rising then falling stretchy vowel
yawn = voice(300, 500, 0.35, [(700, 0.6), (1100, 0.4)])
yawn2 = voice(500, 220, 0.6, [(650, 0.6), (1000, 0.4)])
yawn_all = np.concatenate([yawn, yawn2])
save("yawn", yawn_all * env(len(yawn_all), 0.05, 0.35), 0.6)

# Footsteps: soft paw taps
def tap(f): return lowpass(noise(0.025), 3) * env(int(SR * 0.025), 0.001, 0.02) + 0.4 * np.sin(2 * np.pi * f * t(0.025)) * env(int(SR * 0.025), 0.001, 0.02)
save("step", np.concatenate([tap(420), silence(0.01)]), 0.35)

# Hop (boing) and land (thump)
boing = np.sin(sweep(180, 720, 0.28, 0.5) + 6 * np.sin(2 * np.pi * 14 * t(0.28))) * env(int(SR * 0.28), 0.005, 0.15)
save("hop", boing, 0.55)
thump = (np.sin(sweep(150, 60, 0.15)) + 0.4 * lowpass(noise(0.15), 20)) * env(int(SR * 0.15), 0.002, 0.12)
save("land", thump, 0.7)

# Ball: bounce, catch squeak, pop
save("ball_bounce", np.sin(sweep(300, 900, 0.12, 0.6)) * env(int(SR * 0.12), 0.002, 0.08), 0.5)
save("ball_catch", np.sin(sweep(1200, 2000, 0.09)) * env(int(SR * 0.09), 0.002, 0.05), 0.5)
pop = lowpass(noise(0.06), 2) * env(int(SR * 0.06), 0.001, 0.05) + np.sin(sweep(600, 200, 0.06)) * env(int(SR * 0.06), 0.001, 0.05)
save("ball_pop", pop, 0.7)

# Picked up: rising squeak. Let go: slide whistle down.
save("pickup", np.sin(sweep(500, 1800, 0.18, 1.6) + 2 * np.sin(2 * np.pi * 30 * t(0.18))) * env(int(SR * 0.18), 0.005, 0.06), 0.5)
save("letgo", np.sin(sweep(1600, 350, 0.6, 0.8) + 3 * np.sin(2 * np.pi * 7 * t(0.6))) * env(int(SR * 0.6), 0.02, 0.15), 0.5)

print(sorted(p.name for p in OUT.glob("*.wav")))

# Drinking: three soft laps (a wet flick with a little upward chirp)
def lap(f):
    x = t(0.09)
    wet = lowpass(noise(0.09), 5) * env(len(x), 0.002, 0.06)
    chirp = np.sin(sweep(f, f * 1.7, 0.09, 0.5)) * env(len(x), 0.004, 0.06)
    return 0.6 * wet + chirp
save("drink", np.concatenate([lap(500), silence(0.12), lap(560), silence(0.12), lap(520)]), 0.55)
