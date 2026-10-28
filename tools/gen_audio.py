# -*- coding: utf-8 -*-
"""gen_audio.py - 合成《霓虹回廊》全部音效与 BGM。

设计要点（针对上一版"刺耳/单调/吵"的问题）：
  * 音色：不用白噪声高通踩镲，不用原始锯齿波；镲改为三个高频正弦，贝斯/铺底用三角波+正弦
  * 滤波：频域巴特沃斯（零相位、循环友好），取代原来的滑动平均
  * 空间：FFT 卷积混响（左右去相关）+ 乒乓延迟，输出立体声
  * 编曲：每首 32 小节 A→A'→B→A''，带主旋律、段落动态、B 段转调
  * 混音：分级增益 + 软饱和 + 目标 RMS，不再全部压到同一峰值
"""
from __future__ import annotations
import math, os, wave
import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "audio")
SR_SFX = 44100
SR_MUS = 32000
SR = SR_SFX


def set_sr(v: int) -> None:
    global SR
    SR = v


def n_of(sec: float) -> int:
    return int(sec * SR)


def t_arr(n: int) -> np.ndarray:
    return np.arange(n, dtype=np.float64) / SR


# ---------------------------------------------------------------- 基础
def sine(f, n, ph=0.0):
    return np.sin(2 * np.pi * (f * t_arr(n) + ph))


def tri(f, n, ph=0.0):
    x = (f * t_arr(n) + ph) % 1.0
    return 4.0 * np.abs(x - 0.5) - 1.0


def saw(f, n, ph=0.0):
    return 2.0 * ((f * t_arr(n) + ph) % 1.0) - 1.0


def sqr(f, n, duty=0.5, ph=0.0):
    return np.where(((f * t_arr(n) + ph) % 1.0) < duty, 1.0, -1.0)


def noise(n, rng=None):
    return (rng or np.random.default_rng(7)).uniform(-1.0, 1.0, n)


def fftfilt(x, hp=None, lp=None, order=2):
    """零相位巴特沃斯幅度滤波（用 FFT，天然对循环友好）"""
    n = len(x)
    if n < 8:
        return x
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(n, 1.0 / SR)
    H = np.ones_like(f)
    if lp:
        H = H / np.sqrt(1.0 + (f / float(lp)) ** (2 * order))
    if hp:
        H = H / np.sqrt(1.0 + (float(hp) / np.maximum(f, 1e-6)) ** (2 * order))
    return np.fft.irfft(X * H, n)


def fftconv(x, h):
    n = len(x) + len(h) - 1
    N = 1 << (n - 1).bit_length()
    return np.fft.irfft(np.fft.rfft(x, N) * np.fft.rfft(h, N), N)[:n]


def soft(x, drive=1.0):
    """软饱和，代替硬削波"""
    return np.tanh(x * drive) / np.tanh(drive) if drive > 0.01 else x


def env(n, a=0.005, d=0.15, curve=2.0):
    e = np.zeros(n)
    na = max(1, min(n, n_of(a)))
    e[:na] = np.linspace(0, 1, na) ** 0.6
    if n > na:
        e[na:] = np.linspace(1, 0, n - na) ** curve
    return e


def sweep(f0, f1, n, kind="sin"):
    f = np.linspace(f0, f1, n)
    ph = np.cumsum(f) / SR
    if kind == "sin":
        return np.sin(2 * np.pi * ph)
    if kind == "tri":
        return 4.0 * np.abs((ph % 1.0) - 0.5) - 1.0
    return 2.0 * (ph % 1.0) - 1.0


def pad_to(x, n):
    if len(x) >= n:
        return x[:n]
    return np.concatenate([x, np.zeros(n - len(x))])


def norm(x, peak=0.9):
    m = float(np.max(np.abs(x))) if len(x) else 1.0
    return x * (peak / m) if m > 1e-9 else x


def tail_fade(x, ms=4.0):
    k = min(n_of(ms / 1000.0), len(x) // 2)
    if k > 0:
        x[:k] *= np.linspace(0, 1, k)
        x[-k:] *= np.linspace(1, 0, k)
    return x


def write_wav(name, x, sr=None):
    os.makedirs(OUT, exist_ok=True)
    sr = sr or SR
    x = np.asarray(x, dtype=np.float64)
    if x.ndim == 1:
        data = np.clip(x, -1.0, 1.0)
        ch = 1
    else:
        data = np.clip(x.T, -1.0, 1.0)
        ch = x.shape[0]
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(ch)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes((data * 32767.0).astype("<i2").tobytes())
    return len(x[0]) if x.ndim > 1 else len(x)


def note(m):
    return 440.0 * (2.0 ** ((m - 69) / 12.0))


# ================================================================ SFX 音源
def drum_kick(dur=0.26):
    """战斗底鼓：低频更沉、音头更短更硬，但高频成分仍然被限制在 3kHz 以下"""
    n = n_of(dur)
    body = sweep(58, 38, n) * env(n, 0.0015, dur * 0.46, 2.0)
    thump = sweep(165, 55, n) * env(n, 0.001, 0.045, 2.8) * 0.60
    # 关键：40Hz 的周期是 25ms，物理上做不出 1ms 的音头。
    # 真实的"锤击感"来自中频敲击点（1~3kHz），它不刺耳但决定了 punch。
    rng = np.random.default_rng(7)
    beater = fftfilt(noise(n, rng), hp=1100, lp=3000, order=4) * env(n, 0.0003, 0.010, 3.4)
    tone = fftfilt(tri(330, n=n), lp=2800, order=2) * env(n, 0.0004, 0.010, 3.0)
    return soft(body * 1.10 + thump + beater * 0.80 + tone * 0.30, 1.1)


def drum_snare(dur=0.18):
    """军鼓：加 200Hz 体腔 + 更锐利的瞬态（瞬态来自包络，不是高频）"""
    n = n_of(dur)
    rng = np.random.default_rng(11)
    body = sine(205, n) * env(n, 0.0008, 0.055, 2.2) * 0.6
    ratt = fftfilt(noise(n, rng), hp=260, lp=3600, order=3) * env(n, 0.0006, 0.075, 2.1)
    crack = fftfilt(noise(n, rng), hp=600, lp=3000, order=4) * env(n, 0.0003, 0.014, 3.0) * 0.5
    return soft(body + ratt * 0.62 + crack, 1.05)


def drum_hat(dur=0.05, open_=False):
    """踩镲：音头更短更脆（靠包络而非提高频率），并整体压低避免刺耳"""
    n = n_of(dur * (3.4 if open_ else 1.0))
    e = env(n, 0.0003, 0.014 if not open_ else 0.085, 3.0)
    s = (sine(7100, n) * 0.5 + sine(9200, n) * 0.3 + sine(11400, n) * 0.18)
    rng = np.random.default_rng(23)
    s = s + fftfilt(noise(n, rng), hp=4800, lp=12000, order=3) * 0.16
    return fftfilt(s * e, lp=12500, order=2) * 0.30


def drum_clap(dur=0.24):
    n = n_of(dur)
    rng = np.random.default_rng(31)
    out = np.zeros(n)
    for k in range(3):
        seg = fftfilt(noise(n_of(0.02), rng), hp=900, lp=4200, order=3) * env(n_of(0.02), 0.0005, 0.012, 2.2)
        i = n_of(0.008 * k)
        out[i:i + len(seg)] += seg
    return out * 0.5


def sfx_shoot_pistol():
    n = n_of(0.15)
    a = fftfilt(sweep(1250, 300, n, "tri") * env(n, 0.001, 0.05, 2.4), lp=3600)
    b = fftfilt(noise(n, np.random.default_rng(2)), hp=400, lp=5200, order=3) * env(n, 0.0008, 0.022, 2.8)
    c = sine(170, n) * env(n, 0.001, 0.06, 2.0) * 0.35
    return fftfilt(a * 0.6 + b * 0.28 + c, lp=6000)


def sfx_shoot_shotgun():
    n = n_of(0.32)
    lo = fftfilt(noise(n, np.random.default_rng(3)), hp=120, lp=1400, order=2) * env(n, 0.001, 0.14, 1.8)
    hi = fftfilt(noise(n, np.random.default_rng(4)), hp=700, lp=4200, order=2) * env(n, 0.001, 0.07, 2.2)
    th = sweep(150, 52, n) * env(n, 0.001, 0.16, 1.9)
    return fftfilt(lo * 0.5 + hi * 0.35 + th * 0.6, lp=6500)


def sfx_shoot_laser():
    n = n_of(0.25)
    a = sweep(2100, 620, n) * env(n, 0.002, 0.10, 1.7)
    b = fftfilt(sweep(1050, 310, n, "tri") * env(n, 0.002, 0.085, 1.9), lp=3000)
    s = fftfilt(noise(n, np.random.default_rng(5)), hp=900, lp=4800, order=3) * env(n, 0.002, 0.05, 2.2) * 0.14
    return fftfilt(a * 0.7 + b * 0.35 + s, lp=7000)


def sfx_shoot_boomerang():
    n = n_of(0.30)
    rng = np.random.default_rng(6)
    wob = 0.55 + 0.45 * np.sin(2 * np.pi * 12 * t_arr(n))
    w = fftfilt(noise(n, rng), hp=300, lp=2400, order=3) * wob * env(n, 0.02, 0.20, 1.4)
    t = sine(330, n) * env(n, 0.02, 0.16, 1.6) * 0.22
    return fftfilt(w * 0.8 + t, lp=5200)


def sfx_shoot_orb():
    n = n_of(0.30)
    a = sine(420, n) * env(n, 0.012, 0.18, 1.5)
    b = sine(630, n) * env(n, 0.012, 0.135, 1.7) * 0.35
    c = sine(210, n) * env(n, 0.012, 0.20, 1.5) * 0.5
    lfo = 1.0 + 0.12 * np.sin(2 * np.pi * 6.2 * t_arr(n))
    return fftfilt((a + b + c) * lfo, lp=2600)


def sfx_shoot_rocket():
    n = n_of(0.42)
    rng = np.random.default_rng(8)
    th = fftfilt(noise(n, rng), hp=180, lp=2000, order=2) * env(n, 0.015, 0.30, 1.2)
    lo = sweep(210, 88, n) * env(n, 0.012, 0.28, 1.3) * 0.5
    return fftfilt(th * 0.7 + lo, lp=4200)


def sfx_hit_enemy():
    n = n_of(0.085)
    a = fftfilt(noise(n, np.random.default_rng(9)), hp=380, lp=3200, order=3) * env(n, 0.0006, 0.030, 2.8)
    b = sweep(820, 400, n) * env(n, 0.0006, 0.026, 2.6) * 0.3
    return fftfilt(a * 0.7 + b, lp=5000)


def sfx_hit_player():
    n = n_of(0.30)
    a = sweep(230, 68, n) * env(n, 0.001, 0.15, 1.8)
    b = fftfilt(noise(n, np.random.default_rng(10)), hp=150, lp=2200, order=2) * env(n, 0.001, 0.10, 1.9) * 0.45
    return fftfilt(a * 0.85 + b, lp=4200)


def sfx_enemy_die():
    n = n_of(0.24)
    a = fftfilt(sweep(660, 130, n, "tri") * env(n, 0.001, 0.13, 1.8), lp=2600) * 0.65
    b = fftfilt(noise(n, np.random.default_rng(12)), hp=250, lp=3000, order=2) * env(n, 0.001, 0.11, 1.9) * 0.7
    return fftfilt(a + b, lp=4600)


def sfx_explode():
    n = n_of(0.62)
    a = sweep(150, 36, n) * env(n, 0.003, 0.34, 1.5)
    b = fftfilt(noise(n, np.random.default_rng(13)), hp=120, lp=2600, order=2) * env(n, 0.002, 0.22, 1.6)
    c = fftfilt(noise(n, np.random.default_rng(14)), hp=1500, lp=5200, order=2) * env(n, 0.001, 0.05, 2.4) * 0.35
    return fftfilt(a * 0.85 + b * 0.7 + c, lp=5200)


def sfx_explode_big():
    n = n_of(1.30)
    a = sweep(112, 26, n) * env(n, 0.005, 0.75, 1.3)
    b = fftfilt(noise(n, np.random.default_rng(15)), hp=80, lp=2200, order=2) * env(n, 0.003, 0.50, 1.4)
    c = fftfilt(noise(n, np.random.default_rng(16)), hp=1200, lp=4600, order=2) * env(n, 0.001, 0.06, 2.4) * 0.35
    return fftfilt(a * 0.9 + b * 0.8 + c, lp=4600)


def _blip(f, dur, kind="tri", dec=0.08):
    n = n_of(dur)
    o = {"sine": sine, "tri": tri, "sqr": sqr}[kind](f, n)
    return fftfilt(o * env(n, 0.003, dec, 2.0), lp=4200)


def sfx_pickup_xp():
    n = n_of(0.11)
    a = pad_to(_blip(note(84), 0.10, "tri", 0.055) * 0.7, n)
    b = pad_to(_blip(note(91), 0.09, "sine", 0.045) * 0.3, n)
    return a + b


def sfx_pickup_gear():
    n = n_of(0.20)
    a = pad_to(_blip(note(88), 0.15, "tri", 0.06) * 0.55, n)
    b = np.roll(pad_to(_blip(note(95), 0.14, "tri", 0.05) * 0.42, n), n_of(0.05))
    return a + b


def sfx_pickup_hp():
    n = n_of(0.55)
    out = np.zeros(n)
    for i, m in enumerate((72, 79, 84)):
        out += np.roll(pad_to(_blip(note(m), 0.32, "tri", 0.15) * (0.6 - i * 0.13), n), n_of(0.045 * i))
    return out


def sfx_levelup():
    n = n_of(1.0)
    out = np.zeros(n)
    for i, m in enumerate((64, 68, 71, 76, 83)):
        out += np.roll(pad_to(_blip(note(m), 0.42, "tri", 0.19) * (0.7 - i * 0.09), n), n_of(0.07 * i))
    out += pad_to(sine(note(96), n_of(1.0)) * env(n_of(1.0), 0.15, 0.55, 1.6), n) * 0.14
    return out


def sfx_evolve():
    n = n_of(1.7)
    out = np.zeros(n)
    for i, m in enumerate((57, 64, 69, 72, 76, 81, 88)):
        seg = _blip(note(m), 0.7, "tri", 0.30)
        out += np.roll(pad_to(seg * (0.5 - i * 0.045), n), n_of(0.075 * i))
    out += pad_to(sweep(170, 48, n_of(0.6)) * env(n_of(0.6), 0.003, 0.35, 1.4), n) * 0.45
    return out


def sfx_elite_spawn():
    n = n_of(1.0)
    a = fftfilt(sweep(80, 260, n, "tri") * env(n, 0.30, 0.60, 1.2), lp=1400) * 0.5
    b = sine(56, n) * env(n, 0.22, 0.70, 1.2) * 0.5
    return a + b


def sfx_boss_roar():
    n = n_of(1.7)
    a = fftfilt(sweep(105, 40, n, "tri") * env(n, 0.06, 0.95, 1.3), lp=1100)
    rng = np.random.default_rng(17)
    b = fftfilt(noise(n, rng), hp=90, lp=1800, order=2) * env(n, 0.06, 0.70, 1.3)
    wob = 1.0 + 0.22 * np.sin(2 * np.pi * 6.0 * t_arr(n))
    return fftfilt(a * 0.85 * wob + b * 0.5, lp=2600)


def sfx_dash():
    n = n_of(0.24)
    a = fftfilt(noise(n, np.random.default_rng(18)), hp=250, lp=2400, order=2) * env(n, 0.012, 0.13, 1.6)
    b = sweep(420, 1100, n) * env(n, 0.012, 0.09, 1.9) * 0.2
    return fftfilt(a * 0.75 + b, lp=4200)


def sfx_death():
    n = n_of(1.7)
    a = fftfilt(sweep(360, 52, n, "tri") * env(n, 0.012, 0.95, 1.2), lp=1600)
    b = pad_to(sine(66, n_of(1.7)) * env(n_of(1.7), 0.02, 0.85, 1.2), n) * 0.45
    return a * 0.8 + b


def sfx_ui_click():
    n = n_of(0.07)
    a = pad_to(_blip(note(88), 0.045, "tri", 0.018) * 0.5, n)
    b = fftfilt(noise(n, np.random.default_rng(19)), hp=700, lp=4000, order=3) * env(n, 0.0005, 0.014, 2.6) * 0.22
    return a + b


def sfx_ui_hover():
    return _blip(note(96), 0.035, "sine", 0.016) * 0.3


def sfx_chest():
    n = n_of(1.1)
    out = np.zeros(n)
    for i, m in enumerate((76, 81, 84, 88, 93, 96)):
        out += np.roll(pad_to(_blip(note(m), 0.35, "tri", 0.16) * 0.42, n), n_of(0.045 * i))
    return out


def sfx_warn():
    n = n_of(0.62)
    out = np.zeros(n)
    for i in range(3):
        seg = fftfilt(sine(note(79), n_of(0.10)) * env(n_of(0.10), 0.005, 0.07, 1.7), lp=3000) * 0.42
        out += np.roll(pad_to(seg, n), n_of(0.18 * i))
    return out


SFX = {
    "sfx_shoot_pistol": sfx_shoot_pistol, "sfx_shoot_shotgun": sfx_shoot_shotgun,
    "sfx_shoot_laser": sfx_shoot_laser, "sfx_shoot_boomerang": sfx_shoot_boomerang,
    "sfx_shoot_orb": sfx_shoot_orb, "sfx_shoot_rocket": sfx_shoot_rocket,
    "sfx_hit_enemy": sfx_hit_enemy, "sfx_hit_player": sfx_hit_player,
    "sfx_enemy_die": sfx_enemy_die, "sfx_explode": sfx_explode,
    "sfx_explode_big": sfx_explode_big, "sfx_pickup_xp": sfx_pickup_xp,
    "sfx_pickup_gear": sfx_pickup_gear, "sfx_pickup_hp": sfx_pickup_hp,
    "sfx_levelup": sfx_levelup, "sfx_evolve": sfx_evolve,
    "sfx_elite_spawn": sfx_elite_spawn, "sfx_boss_roar": sfx_boss_roar,
    "sfx_dash": sfx_dash, "sfx_death": sfx_death,
    "sfx_ui_click": sfx_ui_click, "sfx_ui_hover": sfx_ui_hover,
    "sfx_chest": sfx_chest, "sfx_warn": sfx_warn,
}

# 音量分级（不再一律 0.9）
SFX_PEAK = {
    "sfx_hit_player": 0.88, "sfx_levelup": 0.85, "sfx_evolve": 0.88,
    "sfx_boss_roar": 0.88, "sfx_chest": 0.82, "sfx_death": 0.88,
    "sfx_explode_big": 0.80, "sfx_explode": 0.72, "sfx_elite_spawn": 0.70,
    "sfx_shoot_shotgun": 0.62, "sfx_shoot_rocket": 0.62, "sfx_shoot_pistol": 0.55,
    "sfx_shoot_laser": 0.52, "sfx_shoot_orb": 0.52, "sfx_shoot_boomerang": 0.52,
    "sfx_enemy_die": 0.50, "sfx_pickup_xp": 0.44, "sfx_pickup_gear": 0.50,
    "sfx_pickup_hp": 0.58, "sfx_hit_enemy": 0.46, "sfx_dash": 0.52,
    "sfx_warn": 0.58, "sfx_ui_click": 0.34, "sfx_ui_hover": 0.28,
}


# ================================================================ 混响
def make_ir(dur=1.5, decay=3.6, lp=4200, seed=1, spread=0.0):
    n = int(dur * SR)
    rng = np.random.default_rng(seed)
    t = np.arange(n) / SR
    ir = rng.normal(0, 1, n) * np.exp(-decay * t)
    ir = fftfilt(ir, hp=140, lp=lp, order=2)
    pre = int(SR * (0.012 + spread))
    if pre < n:
        ir[pre:] = ir[:n - pre]
        ir[:pre] = 0.0
    ir[0] = 1.0
    return ir / max(np.sqrt((ir ** 2).sum()), 1e-9)


def apply_reverb(x, ir, mix=0.3):
    wet = fftconv(x, ir)[:len(x)]
    return x * (1.0 - mix) + wet * mix


# ================================================================ 编曲
def scale_of(root_midi, minor=True):
    steps = [0, 2, 3, 5, 7, 8, 10] if minor else [0, 2, 4, 5, 7, 9, 11]
    return [root_midi + s for s in steps]


def make_melody(chord_seq, bars, seed, octave=24, density=0.55, rest=0.32):
    """按和弦音 + 音阶生成一条可听的主旋律"""
    rng = np.random.default_rng(seed)
    out = []
    beat = 0.0
    while beat < bars * 4.0:
        bar = int(beat // 4)
        _root, chord = chord_seq[bar % len(chord_seq)]
        sc = scale_of(_root - 12, True)
        pool = [m + octave for m in chord] + [sc[i % 7] + octave for i in range(3, 6)]
        if rng.random() < rest:
            beat += rng.choice([0.5, 1.0])
            continue
        dur = float(rng.choice([0.5, 0.5, 1.0, 1.0, 1.5, 2.0]))
        midi = int(pool[rng.integers(0, len(pool))])
        out.append((beat, midi, dur))
        beat += dur * float(rng.uniform(0.75, 1.05))
    return out


def voice_pad(midis, dur, lp=1500, detune=0.005, amp=0.10, phase=0.0):
    n = n_of(dur)
    out = np.zeros(n)
    for m in midis:
        f = note(m)
        out += tri(f * (1 - detune), n, phase) * 0.6
        out += tri(f * (1 + detune), n, phase * 1.7) * 0.6
        out += sine(f, n, phase * 0.5) * 0.5
    lfo = 1.0 + 0.10 * np.sin(2 * np.pi * 0.19 * t_arr(n) + phase)
    e = env(n, dur * 0.28, dur * 0.55, 1.0)
    return fftfilt(out * lfo * e, lp=lp, order=2) * amp / max(len(midis), 1)


def voice_bass(m, dur, lp=900):
    """垫底长音贝斯（氛围层）"""
    n = n_of(dur)
    f = note(m)
    o = tri(f, n) * 0.8 + sine(f, n) * 0.35 + sine(f * 2, n) * 0.08
    e = env(n, 0.006, dur * 0.85, 1.35)
    return fftfilt(soft(o * e, 1.3), lp=lp, order=2) * 0.5


def voice_bass_drive(m, dur, lp=1150):
    """驱动贝斯：音头锐利、衰减快，8 分音符也要有推动力"""
    n = n_of(dur)
    f = note(m)
    o = tri(f, n) * 0.7 + saw(f, n) * 0.45 + sine(f * 0.5, n) * 0.35
    e = env(n, 0.0025, dur * 0.40, 2.3)
    return fftfilt(soft(o * e, 1.6), lp=lp, order=2) * 0.62


def voice_pluck(m, dur, lp=2800, kind="tri"):
    n = n_of(dur)
    f = note(m)
    o = {"tri": tri, "sqr": lambda ff, nn, p=0.0: sqr(ff, nn, 0.35, p), "sine": sine}[kind](f, n)
    e = env(n, 0.004, dur * 0.5, 2.0)
    return fftfilt(o * e, lp=lp, order=2)


def voice_lead(m, dur, lp=2600):
    n = n_of(dur)
    f = note(m)
    vib = 1.0 + 0.006 * np.sin(2 * np.pi * 5.2 * t_arr(n))
    o = sqr(f * vib, n, 0.32) * 0.55 + tri(f * vib, n) * 0.45
    e = env(n, 0.012, dur * 0.62, 1.5)
    return fftfilt(o * e, lp=lp, order=2) * 0.42


def voice_bell(m, dur, lp=5200):
    n = n_of(dur)
    f = note(m)
    o = sine(f, n) * 0.7 + sine(f * 2.76, n) * 0.2 + sine(f * 5.4, n) * 0.06
    e = env(n, 0.004, dur * 0.35, 2.4)
    return fftfilt(o * e, lp=lp, order=2) * 0.4


def render_song_stems(bpm, prog_a, prog_b, style, seed, bars=32):
    """返回 (base, drive) 两条**等长同速**音轨（Godot 端同步播放、交叉淡化）。
    base  = 氛围铺底（一直播放）
    drive = 战斗层（鼓组 + 驱动贝斯 + 主旋律，按战斗强度淡入）
    拆轨的用意：一首曲子用同一强度循环 4 分钟必然疲劳，
    而"战斗时该有的激昂"应该由战斗本身来驱动。
    """
    set_sr(SR_MUS)
    rng = np.random.default_rng(seed)
    beat = 60.0 / bpm
    bar_len = beat * 4
    total = n_of(bar_len * bars)

    B = {"pad": np.zeros(total), "arp": np.zeros(total), "bass": np.zeros(total), "soft": np.zeros(total)}
    D = {"kick": np.zeros(total), "snare": np.zeros(total), "hat": np.zeros(total),
         "bass": np.zeros(total), "lead": np.zeros(total), "stab": np.zeros(total)}

    def place(buses, bus, x, at_sec, gain=1.0):
        i = n_of(at_sec)
        if i >= total or i < 0:
            return
        seg = x[:max(0, min(len(x), total - i))]
        buses[bus][i:i + len(seg)] += seg * gain

    chord_list = []
    for b in range(bars):
        if 16 <= b < 24:
            chord_list.append(prog_b[b % len(prog_b)])
        else:
            chord_list.append(prog_a[b % len(prog_a)])

    mel = make_melody(chord_list, bars, seed + 5, octave=24, density=0.55, rest=0.30)
    mel_b = make_melody(prog_b, 8, seed + 9, octave=31, density=0.4, rest=0.42)

    for b in range(bars):
        root, chord = chord_list[b]
        t0 = b * bar_len
        sec = "A" if b < 8 else ("A2" if b < 16 else ("B" if b < 24 else "A3"))
        sg = {"A": 0.85, "A2": 1.0, "B": 0.60, "A3": 1.0}[sec]

        # ===================== base：氛围层 =====================
        place(B, "pad", voice_pad(chord, bar_len * 1.02, lp=1450, amp=0.30,
                                  phase=float(rng.random() * 6.28)), t0, 0.95 * sg)
        place(B, "bass", voice_bass(root - 24, bar_len * 0.98), t0, 0.55 * sg)
        for i in range(8):
            if rng.random() < 0.60:
                m = chord[[0, 2, 1, 3][i % 4] % len(chord)] + 12
                place(B, "arp", voice_pluck(m, beat * 0.75, lp=2500), t0 + beat * 0.5 * i, 0.24 * sg)
        if b % 2 == 0:
            place(B, "soft", drum_kick(0.30), t0, 0.30)
            place(B, "soft", drum_hat(open_=True), t0 + beat * 2.0, 0.16)
        if sec == "B":
            place(B, "soft", drum_hat(open_=True), t0 + beat * 3.5, 0.22)

        # ===================== drive：战斗层 =====================
        if sec != "B":
            for k in (0, 2):
                place(D, "kick", drum_kick(), t0 + beat * k, 1.0)
            if style == "drive":
                place(D, "kick", drum_kick(), t0 + beat * 2.75, 0.62)
            for k in (1, 3):
                place(D, "snare", drum_snare(), t0 + beat * k, 0.70)
            dense = b >= 24
            hstep = 0.25 if dense else 0.5
            for i in range(int(4 / hstep)):
                st = i * hstep
                g = 0.34 if abs(st - round(st)) < 0.01 else 0.52
                place(D, "hat", drum_hat(open_=(abs(st - 3.5) < 0.01)), t0 + beat * st, g)
            for i in range(8):
                st = i * 0.5
                m = root - 12
                if abs(st - 3.5) < 0.01 and len(chord) > 2:
                    m = root - 12 + (chord[2] - chord[0])
                place(D, "bass", voice_bass_drive(m, beat * 0.42), t0 + beat * st, 0.88)
            for k in (0.0, 2.5):
                place(D, "stab", voice_lead(chord[1] + 12, beat * 0.22, lp=3000), t0 + beat * k, 0.20)
        else:
            place(D, "kick", drum_kick(), t0, 0.60)
            place(D, "hat", drum_hat(open_=True), t0 + beat * 3.5, 0.30)

        if sec in ("A2", "A3"):
            lo, hi = b * 4.0, (b + 1) * 4.0
            for (st, m, du) in mel:
                if lo <= st < hi:
                    place(D, "lead", voice_lead(m, beat * du * 0.95), t0 + beat * (st - lo), 0.52)
        if sec == "B":
            lo = (b - 16) * 4.0
            for (st, m, du) in mel_b:
                if lo <= st < lo + 4:
                    place(D, "lead", voice_bell(m, beat * du * 1.4), t0 + beat * (st - lo), 0.52)

    drop = n_of(bar_len * 16) - n_of(beat * 2)
    if drop > 0:
        k = n_of(beat * 2)
        for bus in ("kick", "snare", "bass"):
            D[bus][drop:drop + k] *= np.linspace(1.0, 0.15, k)
        i2 = n_of(bar_len * 24)
        k2 = min(n_of(beat * 2), max(0, total - i2))
        if k2 > 0:
            for bus in ("kick", "snare", "bass"):
                D[bus][i2:i2 + k2] *= np.linspace(0.35, 1.0, k2)

    lo_ir = make_ir(1.6, 3.4, 4200, seed=101)
    ro_ir = make_ir(1.6, 3.4, 4200, seed=202, spread=0.004)

    def finish(buses, level, mix):
        padn = n_of(1.8)
        dry = sum(buses[b] * level[b] for b in buses)
        dry_ext = np.concatenate([dry, dry[:padn]])
        acc_l = np.zeros_like(dry_ext)
        acc_r = np.zeros_like(dry_ext)
        for b in buses:
            seg = np.concatenate([buses[b] * level[b], (buses[b] * level[b])[:padn]])
            acc_l += apply_reverb(seg, lo_ir, mix[b])
            acc_r += apply_reverb(seg, ro_ir, mix[b])
        haas = n_of(0.006)
        acc_l += np.concatenate([np.zeros(haas), dry_ext[:-haas]]) * 0.06
        acc_r += np.concatenate([np.zeros(haas * 2), dry_ext[:-haas * 2]]) * 0.06
        Lf = soft(acc_l, 1.15)
        Rf = soft(acc_r, 1.15)
        L = Lf[:total].copy()
        R = Rf[:total].copy()
        tl = Lf[total:total + padn]
        tr = Rf[total:total + padn]
        k = min(padn, len(tl), total)
        L[:k] += tl[:k]
        R[:k] += tr[:k]
        return L, R

    base = finish(B, {"pad": 0.85, "arp": 0.55, "bass": 0.45, "soft": 0.50},
                  {"pad": 0.42, "arp": 0.34, "bass": 0.05, "soft": 0.10})
    drive = finish(D, {"kick": 1.45, "snare": 0.78, "hat": 0.50, "bass": 1.25, "lead": 0.68, "stab": 0.46},
                   {"kick": 0.07, "snare": 0.16, "hat": 0.10, "bass": 0.03, "lead": 0.30, "stab": 0.12})

    # 联合定电平：**按 RMS 而不是峰值**。
    # 按峰值归一会让"瞬态越强 → 整轨越轻"，等于把刚做出来的 punch 又削掉。
    def _rms(x):
        return max(float(np.sqrt((x ** 2).mean())), 1e-9)

    # base 是背景氛围（比旧版更轻，符合"平时不吵"），
    # base+drive 是战斗时的实际听感（比旧版更响、更有推动力）
    # 这种素材 crest 很高（稀疏鼓点 + 安静铺底，crest 9~11），
    # 直接峰值归一会把整轨压得很轻。改用「软限幅 + 补偿增益」：
    # 压住零星尖峰、抬高整体 RMS —— 这才是"更有劲"而不是"更响一下就削顶"。
    def _limit(x, ceil=0.60, drive=2.0):
        pk = max(float(np.max(np.abs(x))), 1e-9)
        y = soft(x * (0.70 / pk), drive)
        pk2 = max(float(np.max(np.abs(y))), 1e-9)
        return y * (ceil / pk2)

    base = (_limit(base[0]), _limit(base[1]))
    drive = (_limit(drive[0]), _limit(drive[1]))
    sL = base[0] + drive[0]
    sR = base[1] + drive[1]
    spk = max(float(np.max(np.abs(sL))), float(np.max(np.abs(sR))), 1e-9)
    k = min(1.0 / spk, 0.115 / max(_rms(sL), 1e-9))
    return (base[0] * k, base[1] * k), (drive[0] * k, drive[1] * k)


def mix_stems(s1, s2, peak=0.72):
    L = s1[0] + s2[0]
    R = s1[1] + s2[1]
    pk = max(float(np.max(np.abs(L))), float(np.max(np.abs(R))), 1e-9)
    return L * (peak / pk), R * (peak / pk)


def bgm_menu():
    a = [(45, [57, 60, 64]), (52, [55, 60, 64]), (41, [53, 57, 60]), (43, [55, 59, 62])]
    b = [(45, [57, 64, 69]), (48, [60, 64, 67]), (43, [55, 62, 67]), (40, [52, 59, 64])]
    base, drive = render_song_stems(82, a, b, "ambient", 101, bars=24)
    return {"bgm_menu": mix_stems(base, drive, 0.70)}


def bgm_stage1():
    a = [(45, [57, 60, 64]), (41, [53, 57, 60]), (48, [55, 60, 64]), (43, [55, 59, 62])]
    b = [(45, [57, 64, 69]), (43, [55, 62, 67]), (36, [48, 55, 60]), (40, [52, 59, 64])]
    base, drive = render_song_stems(128, a, b, "groove", 202)
    return {"bgm_stage1_base": base, "bgm_stage1_drive": drive}


def bgm_stage2():
    a = [(38, [50, 53, 57]), (34, [46, 50, 53]), (41, [53, 57, 60]), (36, [48, 52, 55])]
    b = [(38, [50, 57, 62]), (36, [48, 55, 60]), (31, [43, 50, 55]), (34, [46, 53, 58])]
    base, drive = render_song_stems(138, a, b, "drive", 303)
    return {"bgm_stage2_base": base, "bgm_stage2_drive": drive}


def bgm_stage3():
    a = [(36, [48, 51, 55]), (32, [44, 48, 51]), (39, [51, 55, 58]), (34, [46, 50, 53])]
    b = [(36, [48, 55, 60]), (34, [46, 53, 58]), (29, [41, 48, 53]), (32, [44, 51, 56])]
    base, drive = render_song_stems(152, a, b, "drive", 404)
    return {"bgm_stage3_base": base, "bgm_stage3_drive": drive}


BGM = {"bgm_menu": bgm_menu, "bgm_stage1": bgm_stage1,
       "bgm_stage2": bgm_stage2, "bgm_stage3": bgm_stage3}


def main():
    os.makedirs(OUT, exist_ok=True)
    set_sr(SR_SFX)
    total = 0.0
    for name in sorted(SFX):
        set_sr(SR_SFX)
        d = write_wav(name, norm(SFX[name](), SFX_PEAK.get(name, 0.4)), SR_SFX)
        total += d / SR_SFX
    print("SFX:", len(SFX), "files, %.2fs" % total)
    tt = 0.0
    for key in sorted(BGM):
        for name, (L, R) in sorted(BGM[key]().items()):
            d = write_wav(name, np.vstack([L, R]), SR_MUS)
            tt += d / SR_MUS
            print("  %s  %.1fs" % (name, d / SR_MUS))
    print("BGM total: %.1fs" % tt)


if __name__ == "__main__":
    main()
