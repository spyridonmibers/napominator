#!/usr/bin/env python3
"""Синтезирует мелодии будильника (свои, без авторских прав).

Нужны numpy и ffmpeg. Результат:
  tool/sounds/android/alarm_<key>.ogg  — для Android (res/raw)
  tool/sounds/ios/alarm_<key>.caf      — для iPhone (бандл приложения)
Запуск: python3 tool/make_sounds.py
"""
import pathlib
import subprocess
import tempfile
import wave

import numpy as np

SR = 44100
OUT = pathlib.Path(__file__).resolve().parent / "sounds"


def t_axis(sec):
    return np.arange(int(SR * sec)) / SR


def env(n, attack=0.01, decay=0.4):
    t = np.arange(n) / SR
    a = np.clip(t / attack, 0, 1)
    return a * np.exp(-t / decay)


def note(freq, dur, decay=0.4, harmonics=((1, 1.0),), attack=0.005):
    t = t_axis(dur)
    s = sum(a * np.sin(2 * np.pi * freq * h * t) for h, a in harmonics)
    return s * env(len(t), attack, decay)


def place(buf, sig, start):
    i = int(start * SR)
    if i >= len(buf):
        return
    j = min(len(buf), i + len(sig))
    buf[i:j] += sig[: j - i]


def midi(n):
    return 440.0 * 2 ** ((n - 69) / 12)


MARIMBA = ((1, 1.0), (4, 0.25), (10, 0.05))
BELL = ((1, 1.0), (2.76, 0.5), (5.4, 0.25), (8.93, 0.1))
WARM = ((1, 1.0), (2, 0.3), (3, 0.12))


def soft_morning():
    """Мягкое утро — маримба, светлое арпеджио."""
    buf = np.zeros(SR * 8)
    seq = [72, 76, 79, 84, 79, 76, 74, 77, 81, 86, 81, 77]
    for i, n in enumerate(seq):
        place(buf, note(midi(n), 1.2, 0.35, MARIMBA), i * 0.32)
    for i, n in enumerate(seq[:8]):
        place(buf, note(midi(n), 1.2, 0.35, MARIMBA) * 0.9, 4.2 + i * 0.32)
    return buf


def bells():
    """Колокольчики — нежный перезвон."""
    buf = np.zeros(SR * 8)
    seq = [88, 84, 91, 86, 88, 93, 91, 84]
    for i, n in enumerate(seq):
        place(buf, note(midi(n), 2.5, 0.9, BELL) * 0.6, i * 0.45)
    for i, n in enumerate(seq[:4]):
        place(buf, note(midi(n), 2.5, 0.9, BELL) * 0.5, 4.5 + i * 0.45)
    return buf


def energetic():
    """Бодрый — ритмичный и весёлый."""
    buf = np.zeros(SR * 8)
    bpm = 132
    beat = 60 / bpm / 2
    pattern = [72, 0, 76, 79, 0, 76, 84, 0, 79, 0, 76, 74, 76, 0, 72, 0]
    for rep in range(3):
        for i, n in enumerate(pattern):
            if n:
                place(buf, note(midi(n), 0.4, 0.12, ((1, 1), (3, 0.3), (5, 0.12))) * 0.8,
                      rep * len(pattern) * beat + i * beat)
        for i in range(0, len(pattern), 4):
            place(buf, note(midi(48), 0.3, 0.1, WARM) * 0.7, rep * len(pattern) * beat + i * beat)
    return buf


def classic():
    """Классический звон — «дзынь-дзынь» механического будильника."""
    buf = np.zeros(SR * 8)
    t = t_axis(1.0)
    ring = (np.sin(2 * np.pi * 2350 * t) * 0.5 + np.sin(2 * np.pi * 3150 * t) * 0.35)
    tremolo = (np.sign(np.sin(2 * np.pi * 22 * t)) + 1) / 2
    burst = ring * tremolo * np.clip(t / 0.01, 0, 1) * np.clip((1.0 - t) / 0.05, 0, 1)
    for k in range(4):
        place(buf, burst * 0.7, k * 2.0)
    return buf


def rising():
    """Нарастающий — каждый повтор выше и громче."""
    buf = np.zeros(SR * 9)
    base = [67, 71, 74]
    for step in range(6):
        vol = 0.35 + step * 0.12
        for i, n in enumerate(base):
            place(buf, note(midi(n + step * 2), 0.6, 0.25, MARIMBA) * vol, step * 1.4 + i * 0.18)
    return buf


def red():
    """Красный — тревожный, настойчивый: резкие пульсирующие сигналы."""
    buf = np.zeros(SR * 8)
    t = t_axis(0.12)
    def pulse(f):
        s = sum(np.sin(2 * np.pi * f * h * t) / h for h in (1, 3, 5, 7))  # «квадрат»
        return s * np.clip(t / 0.004, 0, 1) * np.clip((0.12 - t) / 0.01, 0, 1)
    hi, lo = pulse(1046), pulse(784)
    for group in range(5):
        start = group * 1.6
        for k in range(4):
            place(buf, hi * 0.55, start + k * 0.2)
        place(buf, lo * 0.55, start + 0.85)
        place(buf, lo * 0.55, start + 1.05)
    return buf


def green():
    """Зелёный — спокойный, природный: тёплые аккорды и птичьи трели."""
    buf = np.zeros(SR * 10)
    chords = [[60, 64, 67, 71], [57, 60, 64, 67], [53, 57, 60, 64], [55, 59, 62, 67]]
    for i, ch in enumerate(chords):
        for n in ch:
            for det in (-0.6, 0.6):
                sig = note(midi(n) + det, 3.0, 1.6, WARM, attack=0.6) * 0.18
                place(buf, sig, i * 2.4)
    rng = np.random.default_rng(7)
    for k in range(7):
        start = 0.8 + k * 1.3 + rng.uniform(0, 0.3)
        for c in range(rng.integers(2, 4)):
            tt = t_axis(0.09)
            f = np.linspace(3200, 4600, len(tt)) if c % 2 == 0 else np.linspace(4400, 3300, len(tt))
            ph = 2 * np.pi * np.cumsum(f) / SR
            chirp = np.sin(ph) * np.hanning(len(tt)) * 0.12
            place(buf, chirp, start + c * 0.12)
    return buf


SOUNDS = {
    "soft": soft_morning,
    "bells": bells,
    "energetic": energetic,
    "classic": classic,
    "rising": rising,
    "red": red,
    "green": green,
}


def normalize(x, peak=0.85):
    # мягкое затухание в конце — для бесшовного повтора
    fade = int(0.05 * SR)
    x[-fade:] *= np.linspace(1, 0, fade)
    m = np.max(np.abs(x)) or 1
    return x / m * peak


def write_wav(path, x):
    pcm = (x * 32767).astype(np.int16)
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())


def main():
    (OUT / "android").mkdir(parents=True, exist_ok=True)
    (OUT / "ios").mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        for key, fn in SOUNDS.items():
            wav = pathlib.Path(tmp) / f"{key}.wav"
            write_wav(wav, normalize(fn()))
            subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(wav),
                            "-c:a", "libvorbis", "-q:a", "4",
                            str(OUT / "android" / f"alarm_{key}.ogg")], check=True)
            subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(wav),
                            "-c:a", "adpcm_ima_qt", "-f", "caf",
                            str(OUT / "ios" / f"alarm_{key}.caf")], check=True)
            # превью для прослушивания в чате
            subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(wav),
                            "-c:a", "libmp3lame", "-q:a", "4",
                            str(OUT / f"preview_{key}.mp3")], check=True)
    print("Мелодии готовы:", OUT)


if __name__ == "__main__":
    main()
