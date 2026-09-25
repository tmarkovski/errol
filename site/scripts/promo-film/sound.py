"""Sound design for the promo film, synthesized from the cues promo.html exports (window.CUES).

Every sound sits on a beat of the picture, so retiming the film in promo.html retimes the sound too.
Panning follows the picture: in the wide film ChatGPT is on the left and Claude on the right.
render.py calls synthesize(); this module has no command of its own.
"""
import numpy as np
from scipy.io import wavfile
from scipy.signal import butter, fftconvolve, sosfilt

SR = 48000
NOTE = {"G2": 98.0, "A2": 110.0, "B2": 123.47, "D3": 146.83, "E3": 164.81, "F#3": 185.0, "A3": 220.0, "B3": 246.94,
        "C#4": 277.18, "D4": 293.66, "E4": 329.63, "F#4": 369.99, "D5": 587.33, "E5": 659.25, "F#5": 739.99,
        "A5": 880.0, "B5": 987.77, "D6": 1174.66, "E6": 1318.51, "F#6": 1479.98, "A6": 1760.0}
# Each delivery chimes one step higher on a D major pentatonic ladder.
LADDER = ["D5", "E5", "F#5", "A5", "B5", "D6", "E6", "F#6", "A6"]


def db(x):
    return 10 ** (x / 20)


def secs(n):
    return np.arange(n) / SR


def band(x, lo, hi):
    return sosfilt(butter(2, [lo, hi], btype="band", fs=SR, output="sos"), x)


def lowpass(x, f):
    return sosfilt(butter(2, f, btype="low", fs=SR, output="sos"), x)


def highpass(x, f):
    return sosfilt(butter(2, f, btype="high", fs=SR, output="sos"), x)


def fade(sig, a=0.003, r=0.01):
    env = np.ones(len(sig))
    na, nr = int(a * SR), int(r * SR)
    if na:
        env[:na] = np.linspace(0, 1, na)
    if nr:
        env[-nr:] *= np.linspace(1, 0, nr)
    return sig * env


def eased(u):
    """The page's io3 easing, so whooshes swell where the dot is fastest."""
    return np.where(u < 0.5, 4 * u ** 3, 1 - (-2 * u + 2) ** 3 / 2)


class Mix:
    def __init__(self, dur, width, seed=7):
        self.n = int(SR * dur)
        self.width = width
        self.dry = np.zeros((self.n, 2))
        self.wet = np.zeros((self.n, 2))  # the reverb send
        self.rng = np.random.default_rng(seed)

    def pan(self, x):
        return float(np.clip((x - self.width / 2) / (self.width * 0.55), -0.9, 0.9))

    def place(self, sig, at, pan=0.0, send=0.0):
        i = int(round(at * SR))
        if sig.ndim == 1:
            a = (pan + 1) * np.pi / 4
            sig = np.stack([sig * np.cos(a), sig * np.sin(a)], axis=1)
        j = min(self.n, i + len(sig))
        if j > i >= 0:
            self.dry[i:j] += sig[: j - i]
            self.wet[i:j] += sig[: j - i] * send

    # ------------------------------------------------------------ instruments
    def click(self, level, bright=1.0):
        t = secs(int(0.03 * SR))
        noise = highpass(self.rng.standard_normal(len(t)), 1800) * np.exp(-t / 0.0014)
        tock = np.sin(2 * np.pi * 2300 * bright * t) * np.exp(-t / 0.006) * 0.35
        return fade((noise * 0.6 + tock) * db(level), 0.0005, 0.005)

    def key(self, level):
        t = secs(int(0.06 * SR))
        f = 1 + self.rng.uniform(-0.06, 0.06)
        top = band(self.rng.standard_normal(len(t)), 1400 * f, 5200 * f) * np.exp(-t / 0.0025)
        body = np.sin(2 * np.pi * 190 * f * t) * np.exp(-t / 0.012) * 0.5
        return fade((top * 0.8 + body) * db(level + self.rng.uniform(-1.5, 1.5)), 0.0003, 0.01)

    @staticmethod
    def thump(level, f0=130, f1=55, tau=0.16, length=0.45):
        t = secs(int(length * SR))
        f = f1 + (f0 - f1) * np.exp(-t / 0.035)
        return fade(np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / tau) * db(level), 0.002, 0.05)

    @staticmethod
    def chime(freq, level, tau=0.9, length=2.2):
        t = secs(int(length * SR))
        out = np.zeros((len(t), 2))
        for mult, amp, tt in [(1, 1.0, tau), (2, 0.28, tau * 0.55), (3, 0.1, tau * 0.35), (4.07, 0.05, tau * 0.2)]:
            env = np.exp(-t / tt)
            out[:, 0] += amp * np.sin(2 * np.pi * freq * mult * t) * env
            out[:, 1] += amp * np.sin(2 * np.pi * freq * mult * 1.0015 * t + 0.4) * env
        return out * np.minimum(1, t / 0.004)[:, None] * db(level)

    def whoosh(self, path, t0, t1, level, lo=350, hi=3200):
        """Air along a flight: loud where the dot is fast, panned where the dot is."""
        pre, post = 0.05, 0.22
        t = secs(int((t1 - t0 + pre + post) * SR)) - pre
        u = np.clip(t / (t1 - t0), 0, 1)
        e = eased(u)
        speed = np.clip(np.gradient(e) * SR * (t1 - t0), 0, None)
        env = (speed / (speed.max() + 1e-9)) ** 0.8 * np.where(t > t1 - t0, np.exp(-(t - (t1 - t0)) / 0.06), 1.0)
        noise = self.rng.standard_normal(len(t))
        sig = (band(noise, lo, lo * 3) * (1 - env * 0.6) + band(noise, hi * 0.5, hi * 1.6) * env * 0.9) * env
        p = np.array(path, float)
        x = (1 - e) ** 3 * p[0, 0] + 3 * (1 - e) ** 2 * e * p[1, 0] + 3 * (1 - e) * e ** 2 * p[2, 0] + e ** 3 * p[3, 0]
        a = (np.clip((x - self.width / 2) / (self.width * 0.55), -0.9, 0.9) + 1) * np.pi / 4
        st = np.stack([sig * np.cos(a), sig * np.sin(a)], axis=1) * db(level) / (np.abs(sig).max() + 1e-9)
        return st, t0 - pre

    def swell(self, length, level, f0=300, f1=5000):
        t = secs(int(length * SR))
        k = t / length
        noise = self.rng.standard_normal(len(t))
        sig = band(noise, f0, f0 * 3) * (1 - k) + band(noise, f1 * 0.3, f1) * k
        return fade(sig * k ** 2.4 / (np.abs(sig).max() + 1e-9) * db(level), 0.01, 0.004)

    @staticmethod
    def shimmer(freqs, length, level, attack):
        t = secs(int(length * SR))
        out = np.zeros((len(t), 2))
        for i, f in enumerate(freqs):
            trem = 1 + 0.25 * np.sin(2 * np.pi * (5.3 + i) * t + i)
            env = np.minimum(1, t / attack) * np.exp(-np.maximum(0, t - attack) / (length * 0.45))
            out[:, i % 2] += np.sin(2 * np.pi * f * t) * env * trem
            out[:, (i + 1) % 2] += 0.5 * np.sin(2 * np.pi * f * 1.002 * t) * env * trem
        return out * db(level)

    def fly(self, path, t0, t1, level, send, **kw):
        sig, at = self.whoosh(path, t0, t1, level, **kw)
        self.place(sig, at, send=send)


def pad_voice(freq, n, bright):
    t = secs(n)
    sig = np.zeros(n)
    for det in (-0.0045, 0.0, 0.0045):
        f = freq * (1 + det)
        for h in range(1, 14):
            if f * h > 9000:
                break
            sig += np.sin(2 * np.pi * f * h * t + h * 1.3 + det * 900) * np.exp(-h / (4.5 * bright)) / h
    return sig


def synthesize(cues, path):
    b = cues["beat"]
    dur, width = cues["dur"], cues["W"]
    m = Mix(dur, width)
    pen, courier = b["pen"], b["courier"]
    cx, cy = cues["console"]
    gx, gy = cues["glyph"]
    rx, ry = cues["reveal"]
    dot1, dot2 = cues["wordmarkDots"]
    t = secs(m.n)

    # ------------------------------------------------------------ the pad: silent in the hook, one chord per scene
    scenes = [
        (pen["f0"] - 0.07, b["toMenuBar"] + 0.32, ["D3", "A3", "E4", "F#4"], 1.0),
        (b["toMenuBar"] + 0.32, b["run"], ["G2", "D3", "B3", "F#4"], 1.0),
        (b["run"], b["pause"] - 0.02, ["B2", "F#3", "A3", "D4"], 1.1),
        (b["pause"] - 0.02, b["endRecede"], ["A2", "E3", "A3", "C#4"], 0.9),
        (b["endRecede"], dur, ["D3", "A3", "D4", "E4", "F#4"], 1.25),
    ]
    pad = np.zeros((m.n, 2))
    for i, (a, z, notes, bright) in enumerate(scenes):
        xa, xb = a - 0.35, z + 0.35
        ia, ib = max(0, int(xa * SR)), min(m.n, int(xb * SR))
        tt = secs(ib - ia) + ia / SR
        env = np.clip((tt - (a if i == 0 else xa)) / (1.6 if i == 0 else 0.7), 0, 1) * np.clip((xb - tt) / 0.7, 0, 1)
        voices = sum(pad_voice(NOTE[nm], ib - ia, bright) * (0.9 if k == 0 else 0.6) for k, nm in enumerate(notes))
        pad[ia:ib, 0] += voices * env
        pad[ia:ib, 1] += np.roll(voices, 90) * env
    start = pen["f0"] - 0.07
    contour = (np.clip((t - start) / 1.2, 0, 1) * 0.85 + 0.15 * np.clip((t - pen["land"] + 0.06) / 0.8, 0, 1)
               - 0.25 * np.clip((t - b["pause"]) / 0.3, 0, 1) * np.clip((b["send"] + 0.05 - t) / 0.3, 0, 1)
               + 0.35 * np.clip((t - b["endRecede"] - 0.2) / 0.9, 0, 1))
    contour *= np.clip((dur - t) / 1.4, 0, 1) ** 1.3
    for c in range(2):
        pad[:, c] = highpass(lowpass(pad[:, c], 1800), 120) * contour
    pad /= np.abs(pad).max() + 1e-9
    m.dry += pad * db(-25)
    m.wet += pad * db(-25) * 0.5

    # ------------------------------------------------------------ hook: the relay by hand, and tension under it
    for k in cues["hook"]["keys"]:
        m.place(m.key(-15), k, pan=m.rng.uniform(-0.15, 0.15))
    for c in cues["hook"]["clicks"]:
        m.place(m.click(-19), c - 0.004, pan=-0.3 + 0.4 * m.rng.random())
    for i, s in enumerate(cues["hook"]["sends"]):
        m.place(m.thump(-22, 420, 180, 0.03, 0.12), s + 0.02, pan=0.1 if i % 2 == 0 else -0.1)
    n = int(pen["f0"] * SR)
    th = secs(n)
    hum = (np.sin(2 * np.pi * 73.4 * th) + 0.6 * np.sin(2 * np.pi * 110 * th + 1)
           + 0.3 * np.sin(2 * np.pi * 146.8 * th * (1 + 0.002 * np.sin(2 * np.pi * 0.7 * th))))
    air = band(m.rng.standard_normal(n), 900, 2600) * 0.35
    m.place(fade((hum * 0.7 + air) * (th / pen["f0"]) ** 1.6 / 1.6 * db(-21), 0.02, 0.03), 0.0, send=0.15)

    # ------------------------------------------------------------ reveal: a breath in, the pen draws the mark
    m.place(m.swell(0.62, -25), pen["f0"] - 0.62, send=0.4)
    m.place(m.thump(-17, 90, 42, 0.35, 0.9), pen["f0"] - 0.02, send=0.2)
    m.place(m.shimmer([NOTE["A5"], NOTE["D6"], NOTE["F#6"]], 1.8, -33, 0.35), pen["f0"], send=0.7)
    m.fly([[rx - 110, ry + 40], [rx - 160, ry - 150], [rx + 120, ry - 150], [rx - 110, ry + 40]], pen["f0"], pen["f1"], -31, 0.3, lo=600, hi=3000)
    m.fly([[rx + 100, ry - 40], [rx + 220, ry + 50], [rx + 80, ry + 150], [rx - 40, ry + 110]], pen["h1"], pen["r1"], -33, 0.3, lo=600, hi=3000)
    m.fly([[rx - 40, ry + 110], [rx - 70, ry + 230], [dot1[0] + 10, dot1[1] - 190], dot1], pen["r1"], pen["land"], -29, 0.3)
    m.place(m.thump(-19, 260, 90, 0.07, 0.3), pen["land"])
    for note, level, dt in [("D5", -21, 0.0), ("A5", -25, 0.03), ("E6", -29, 0.06), ("F#5", -26, 0.045)]:
        m.place(m.chime(NOTE[note], level, 1.3, 2.6), pen["land"] + dt, send=0.55)

    # ------------------------------------------------------------ setup: menu bar, console, topic, Start relay
    m.fly([[rx, ry], [rx + 100, ry - 50], [gx - 30, gy + 20], [gx, gy]], b["toMenuBar"], b["toMenuBar"] + 0.44, -30, 0.2)
    m.place(m.click(-25), b["glyphPress"] + 0.01, pan=m.pan(gx))
    m.fly([[gx, gy], [gx - 50, gy + 70], [cx + 20, gy + 170], [cx, gy + 240]], b["drop"], b["drop"] + 0.26, -30, 0.2, lo=250, hi=1600)
    m.place(m.thump(-22, 150, 70, 0.08, 0.3), b["drop"] + 0.14, pan=0.1)
    m.place(m.chime(NOTE["E6"], -31, 0.25, 0.8), b["readyA"], pan=-0.55, send=0.3)
    m.place(m.chime(NOTE["A6"], -32, 0.25, 0.8), b["readyB"], pan=0.55, send=0.3)
    t0, t1 = b["topic"]
    n = cues["typing"]["topic"]
    for i in range(1, n + 1):
        m.place(m.key(-31), t0 + (t1 - t0) * (i - 0.5) / n, pan=m.rng.uniform(-0.2, 0.2))
    m.place(m.click(-23), b["start"] - 0.005, pan=0.25)
    m.place(m.thump(-20, 180, 60, 0.12, 0.45), b["start"] + 0.01, pan=0.2, send=0.2)
    m.place(m.swell(0.35, -30, 400, 3000), b["start"] + 0.03, send=0.3)

    # ------------------------------------------------------------ relay: Errol copies, carries, delivers
    for f in cues["flights"]:
        note = f["kind"] == "note"
        m.fly(f["path"], f["t0"], f["t1"], -27 if note else -22, 0.25)
        pan = m.pan(f["path"][-1][0])
        rung = NOTE[LADDER[min(len(LADDER) - 1, f["delivery"] + (1 if note else 0))]]
        if note:  # the note arrives with the reply: a second voice on that delivery
            m.place(m.chime(rung, -25, 0.8, 2.0), f["t1"] + 0.015, pan=pan, send=0.55)
        else:
            m.place(m.chime(rung, -21, 0.8, 2.0), f["t1"], pan=pan, send=0.5)
            m.place(m.thump(-27, 300, 140, 0.04, 0.15), f["t1"], pan=pan)
    for c in cues["copies"]:
        m.place(m.click(-30, 1.3), c - 0.01, pan=-0.6)
    for s in cues["sends"]:
        m.place(m.thump(-31, 460, 200, 0.025, 0.1), s, pan=0.45)

    # ------------------------------------------------------------ steer: pause, a note, continue
    m.place(m.click(-23), b["pause"] - 0.005, pan=0.3)
    m.place(m.thump(-24, 140, 80, 0.06, 0.25), b["pause"] + 0.01, pan=0.25)
    t0, t1 = b["note"]
    n = cues["typing"]["note"]
    for i in range(1, n + 1):
        m.place(m.key(-31), t0 + (t1 - t0) * (i - 0.5) / n, pan=m.rng.uniform(-0.2, 0.2))
    m.place(m.click(-23), b["send"] - 0.005, pan=0.25)
    m.place(m.thump(-21, 190, 70, 0.1, 0.4), b["send"] + 0.01, pan=0.2, send=0.2)

    # ------------------------------------------------------------ end card
    er = b["endRecede"]
    m.fly([[cx, cy], [cx, cy - 45], [cx, cy - 125], [cx, cy - 165]], er, er + 0.5, -28, 0.4, lo=200, hi=1400)
    m.fly([[cx, cy], [cx - 160, cy - 125], [dot2[0] - 40, dot2[1] - 260], dot2], courier["go"], courier["land"], -25, 0.35)
    m.place(m.thump(-24, 170, 90, 0.07, 0.3), b["meet"] + 0.18, pan=-0.3)
    m.place(m.thump(-24, 190, 95, 0.07, 0.3), b["meet"] + 0.26, pan=0.3)
    m.place(m.thump(-17, 110, 45, 0.4, 1.0), courier["land"], send=0.25)
    for note, level, dt in [("D5", -19, 0.0), ("F#5", -24, 0.035), ("A5", -23, 0.06), ("E6", -28, 0.09), ("D6", -27, 0.12)]:
        m.place(m.chime(NOTE[note], level, 1.6, 2.8), courier["land"] + dt, send=0.6)
    m.place(m.chime(NOTE["A6"], -32, 0.3, 0.8), b["cta"] + 0.02, pan=0.1, send=0.4)
    m.place(m.shimmer([NOTE["D6"] * 2, NOTE["A6"] * 1.5, NOTE["F#6"] * 2], 1.2, -36, 0.2), b["sheen"], send=0.6)

    # ------------------------------------------------------------ reverb and master
    n_ir = int(1.6 * SR)
    ir = np.stack([m.rng.standard_normal(n_ir), m.rng.standard_normal(n_ir)], axis=1) * np.exp(-secs(n_ir) / 0.42)[:, None]
    ir = np.stack([lowpass(ir[:, c], 5500) for c in range(2)], axis=1)
    ir /= np.sqrt((ir ** 2).sum(axis=0))
    rev = np.stack([fftconvolve(m.wet[:, c], ir[:, c])[: m.n] for c in range(2)], axis=1)
    mix = m.dry + rev * db(-4)
    mix = highpass(mix.T, 28).T
    mix -= mix.mean(axis=0)
    mix = mix / np.abs(mix).max() * db(-3)
    mix = np.tanh(mix * 1.4) / np.tanh(1.4)
    tail = int(0.05 * SR)
    mix[-tail:] *= np.linspace(1, 0, tail)[:, None]
    wavfile.write(str(path), SR, (mix * 32767 * db(-1)).astype(np.int16))
