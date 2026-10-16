"""Alternative petting sounds: cute non-voice cues, each with a corgi (higher) and sheep (lower, wobblier) variant."""
import sys
sys.path.insert(0, __import__("os").path.dirname(__file__))
from make_sounds import t, env, sweep, noise, lowpass, silence, save, SR
import numpy as np

def squeak(f0, f1, sec, wob):
    """Rubber squeaky-toy: a fast up-down glide with a nasal second harmonic."""
    x = t(sec)
    ph = sweep(f0, f1, sec, 0.6) + wob * np.sin(2 * np.pi * 28 * x)
    return (np.sin(ph) + 0.35 * np.sin(2 * ph) + 0.15 * np.sin(3 * ph)) * env(len(x), 0.004, sec * 0.5)

def coo(f, sec, wob, bend):
    """Soft happy coo: a pure, rounded tone that lifts then settles."""
    x = t(sec)
    ph = 2 * np.pi * np.cumsum(f * (1 + bend * np.sin(np.pi * x / sec)) + wob * np.sin(2 * np.pi * 7 * x)) / SR
    return (np.sin(ph) + 0.2 * np.sin(2 * ph)) * env(len(x), 0.03, sec * 0.6)

def boop(f, sec):
    """Bubbly 'boop': quick downward pluck with a soft body."""
    x = t(sec)
    return (np.sin(sweep(f * 1.6, f, sec, 0.3)) + 0.3 * np.sin(sweep(f * 3.2, f * 2, sec, 0.3))) * env(len(x), 0.002, sec * 0.8)

def chime(base, ratios, step):
    notes = [np.sin(2 * np.pi * base * r * t(0.18)) * np.exp(-t(0.18) * 18) for r in ratios]
    out = np.zeros(int(SR * (step * len(notes) + 0.2)))
    for i, n in enumerate(notes):
        s = int(SR * step * i); out[s:s + len(n)] += n
    return out

def purr(f, sec):
    """Gentle happy rumble: low tone pulsed ~24 times a second."""
    x = t(sec)
    am = 0.55 + 0.45 * np.sin(2 * np.pi * 24 * x)
    tone = np.sin(2 * np.pi * f * x) + 0.4 * np.sin(2 * np.pi * 2 * f * x) + 0.15 * lowpass(noise(sec), 25)
    return tone * am * env(len(x), 0.08, 0.25)

opts = {
    "A_squeaky_toy": (lambda: np.concatenate([squeak(900, 1500, 0.11, 2), silence(0.04), squeak(1000, 1700, 0.09, 2)]),
                      lambda: np.concatenate([squeak(600, 950, 0.14, 4), silence(0.05), squeak(650, 1050, 0.12, 4)])),
    "B_happy_coo": (lambda: coo(880, 0.35, 8, 0.35), lambda: coo(520, 0.5, 18, 0.25)),
    "C_double_boop": (lambda: np.concatenate([boop(700, 0.09), silence(0.03), boop(900, 0.11)]),
                      lambda: np.concatenate([boop(420, 0.11), silence(0.04), boop(520, 0.13)])),
    "D_heart_chime": (lambda: chime(1046, [1, 1.26, 1.5], 0.07), lambda: chime(784, [1, 1.26, 1.5], 0.09)),
    "E_content_purr": (lambda: purr(110, 0.7), lambda: purr(80, 0.9)),
}
for name, (corgi, sheep) in opts.items():
    save(f"petopt_{name}_corgi", corgi(), 0.6)
    save(f"petopt_{name}_sheep", sheep(), 0.6)
print("ok")
