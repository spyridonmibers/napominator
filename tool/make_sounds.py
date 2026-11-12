#!/usr/bin/env python3
"""Синтезирует мелодии будильника (свои, без авторских прав).

Звук: стерео 44.1 кГц, модальный/FM/струнный синтез, реверберация, мягкая компрессия.
Нужны numpy, scipy и ffmpeg. Результат:
  tool/sounds/android/alarm_<key>.ogg  — для Android (res/raw)
  tool/sounds/ios/alarm_<key>.caf      — для iPhone (IMA4 в CAF, бандл приложения)
Запуск: python3 tool/make_sounds.py
"""
import pathlib
import subprocess
import tempfile
import wave

import numpy as np
from scipy.signal import butter, fftconvolve, sosfilt

SR = 44100
OUT = pathlib.Path(__file__).resolve().parent / "sounds"
RNG = np.random.default_rng(42)


# ----------------------------------------------------------------- утилиты

def midi(n):
    return 440.0 * 2 ** ((n - 69) / 12)


def t_axis(sec):
    return np.arange(int(SR * sec)) / SR


def lowpass(x, f, order=2):
    return sosfilt(butter(order, f, "low", fs=SR, output="sos"), x)


def highpass(x, f, order=2):
    return sosfilt(butter(order, f, "high", fs=SR, output="sos"), x)


class Track:
    """Стерео-дорожка: кладём моно-звуки с панорамой и громкостью."""

    def __init__(self, sec):
        self.buf = np.zeros((2, int(SR * sec)))

    def add(self, sig, start, gain=1.0, pan=0.0):
        i = int(start * SR)
        if i >= self.buf.shape[1] or len(sig) == 0:
            return
        j = min(self.buf.shape[1], i + len(sig))
        l = np.cos((pan + 1) * np.pi / 4) * gain
        r = np.sin((pan + 1) * np.pi / 4) * gain
        self.buf[0, i:j] += sig[: j - i] * l
        self.buf[1, i:j] += sig[: j - i] * r

    def mix(self, other, gain=1.0):
        self.buf += other.buf * gain


def reverb_ir(seconds=2.4, predelay=0.012, damp=6000, width=1.0):
    """Импульсная характеристика «зала»: ранние отражения + затухающий шум."""
    n = int(SR * seconds)
    t = np.arange(n) / SR
    ir = np.zeros((2, n))
    for ch in range(2):
        noise = RNG.standard_normal(n)
        noise = lowpass(noise, damp, 1)
        decay = np.exp(-6.9 * t / seconds)  # −60 дБ за seconds
        ir[ch] = noise * decay
        # ранние отражения
        for k in range(8):
            d = int((predelay + RNG.uniform(0.005, 0.045)) * SR)
            ir[ch, d] += RNG.uniform(0.3, 0.7) * (1 if RNG.random() > 0.5 else -1)
    # декорреляция каналов
    mid = (ir[0] + ir[1]) / 2
    side = (ir[0] - ir[1]) / 2 * width
    ir = np.stack([mid + side, mid - side])
    return ir / np.max(np.abs(ir))


def apply_reverb(track, wet=0.25, seconds=2.4, damp=6000):
    ir = reverb_ir(seconds, damp=damp)
    dry = track.buf
    out = np.zeros_like(dry)
    for ch in range(2):
        w = fftconvolve(dry[ch], ir[ch])[: dry.shape[1]]
        out[ch] = w
    out /= (np.max(np.abs(out)) or 1)
    peak = np.max(np.abs(dry)) or 1
    track.buf = dry * (1 - wet) + out * peak * wet


def master(track, peak=0.89, drive=1.4):
    x = track.buf
    x = highpass(x, 35)
    m = np.max(np.abs(x)) or 1
    x = np.tanh(x / m * drive) / np.tanh(drive)  # мягкая компрессия
    fade_in = int(0.004 * SR)
    fade_out = int(0.25 * SR)
    x[:, :fade_in] *= np.linspace(0, 1, fade_in)
    x[:, -fade_out:] *= np.linspace(1, 0, fade_out) ** 2
    return x / (np.max(np.abs(x)) or 1) * peak


# --------------------------------------------------------------- инструменты

def mallet(freq, dur=1.6, vel=1.0, bright=1.0):
    """Маримба/вибрафон: модальный синтез + удар колотушки."""
    t = t_axis(dur)
    modes = [(1.0, 1.0, 0.9), (3.99, 0.32 * bright, 0.22), (10.65, 0.09 * bright, 0.07)]
    s = np.zeros_like(t)
    for ratio, amp, dec in modes:
        f = freq * ratio
        if f > SR / 2.2:
            continue
        s += amp * np.sin(2 * np.pi * f * t + RNG.uniform(0, 1)) * np.exp(-t / (dec * (440 / freq) ** 0.3))
    click = lowpass(RNG.standard_normal(int(0.006 * SR)), 3500) * np.hanning(int(0.006 * SR)) * 0.25
    s[: len(click)] += click
    att = np.clip(t / 0.002, 0, 1)
    return s * att * vel


def epiano(freq, dur=2.5, vel=1.0):
    """Электропиано (Rhodes): FM с затухающим индексом + «язычок» на атаке."""
    t = t_axis(dur)
    idx = (1.6 * vel + 0.4) * np.exp(-t / 0.35)
    mod = np.sin(2 * np.pi * freq * t)
    body = np.sin(2 * np.pi * freq * t + idx * mod)
    tine = 0.18 * vel * np.sin(2 * np.pi * freq * 14 * t) * np.exp(-t / 0.05)
    amp = np.exp(-t / (1.4 * (440 / freq) ** 0.25)) * np.clip(t / 0.003, 0, 1)
    trem = 1 + 0.06 * np.sin(2 * np.pi * 4.5 * t)
    return (body + tine) * amp * trem * vel


def bell(freq, dur=4.0, vel=1.0):
    """Стеклянный колокольчик / челеста: негармонические обертоны."""
    t = t_axis(dur)
    partials = [(1.0, 1.0, 2.2), (2.0, 0.55, 1.4), (3.01, 0.32, 0.9), (4.17, 0.22, 0.6),
                (5.43, 0.14, 0.45), (6.8, 0.08, 0.3), (8.21, 0.05, 0.2)]
    s = np.zeros_like(t)
    for ratio, amp, dec in partials:
        f = freq * ratio
        if f > SR / 2.2:
            continue
        beat = 1 + 0.002 * RNG.standard_normal()
        s += amp * np.sin(2 * np.pi * f * beat * t + RNG.uniform(0, 6.28)) * np.exp(-t / dec)
    return s * np.clip(t / 0.001, 0, 1) * vel


def pluck(freq, dur=2.0, vel=1.0, bright=0.5):
    """Щипковая струна (Karplus–Strong) — гитара/арфа."""
    n = int(SR * dur)
    p = max(2, int(round(SR / freq - 0.5)))
    buf = np.zeros(n + p + 1)
    noise = lowpass(RNG.uniform(-1, 1, p), 1500 + 6000 * bright, 1)
    buf[1:p + 1] = noise
    damp = 0.996
    i = p + 1
    while i < len(buf):
        j = min(len(buf), i + p)
        buf[i:j] = damp * 0.5 * (buf[i - p:j - p] + buf[i - p - 1:j - p - 1])
        i = j
    body = lowpass(buf[1:n + 1], 5000, 2)
    return body / (np.max(np.abs(body)) or 1) * vel


def pad(freqs, dur, attack=1.2, release=1.5, bright=1800, detune=0.12):
    """Тёплый пэд: расстроенные «пилы» (аддитивно) через фильтр."""
    t = t_axis(dur)
    s = np.zeros_like(t)
    for f in freqs:
        for d in (-detune, 0, detune):
            ff = f * 2 ** (d / 12)
            ph = RNG.uniform(0, 6.28)
            for h in range(1, 14):
                if ff * h > SR / 2.2:
                    break
                s += np.sin(2 * np.pi * ff * h * t + ph * h) / h
    env = np.clip(t / attack, 0, 1) * np.clip((dur - t) / release, 0, 1)
    s = lowpass(s, bright, 2)
    return s * env / (len(freqs) * 3)


def kick(dur=0.35, vel=1.0):
    t = t_axis(dur)
    f = 45 + 90 * np.exp(-t / 0.04)
    ph = 2 * np.pi * np.cumsum(f) / SR
    return np.sin(ph) * np.exp(-t / 0.12) * vel


def shaker(dur=0.08, vel=1.0):
    n = int(SR * dur)
    s = highpass(RNG.standard_normal(n), 6000, 2)
    return s * np.exp(-np.arange(n) / SR / 0.025) * vel * 0.4


def synth_pluck(freq, dur=0.5, vel=1.0, cutoff=2500):
    """Плотный синт-плак (для «Красного»): пила, фильтр быстро «закрывается»."""
    t = t_axis(dur)
    s = np.zeros_like(t)
    for d in (-0.08, 0.08):
        ff = freq * 2 ** (d / 12)
        for h in range(1, 24):
            if ff * h > SR / 2.2:
                break
            s += np.sin(2 * np.pi * ff * h * t) / h
    bright = lowpass(s, min(cutoff, SR / 2.5), 2)
    dark = lowpass(s, 350, 2)
    k = np.exp(-t / 0.06)
    out = dark + (bright - dark) * k
    return out * np.exp(-t / 0.18) * np.clip(t / 0.002, 0, 1) * vel * 0.5


def chirp_bird(dur=0.12, f0=3200, f1=4800, vel=1.0):
    t = t_axis(dur)
    f = f0 + (f1 - f0) * (t / dur) ** 0.7
    ph = 2 * np.pi * np.cumsum(f) / SR
    am = 1 + 0.5 * np.sin(2 * np.pi * 60 * t)
    return np.sin(ph) * np.hanning(len(t)) * am * vel


# ------------------------------------------------------------------ мелодии

def soft_morning():
    """Мягкое утро — тот же мотив, звучание как у настоящей маримбы в зале."""
    tr = Track(9)
    seq = [72, 76, 79, 84, 79, 76, 74, 77, 81, 86, 81, 77]
    for i, n in enumerate(seq):
        vel = 0.85 + 0.15 * np.sin(i)
        tr.add(mallet(midi(n), vel=vel), i * 0.32, pan=-0.35 + 0.7 * (i % 4) / 3)
    for i, n in enumerate(seq[:8]):
        tr.add(mallet(midi(n), vel=0.8), 4.2 + i * 0.32, pan=0.35 - 0.7 * (i % 4) / 3)
    # мягкий бас-маримба на сильные доли
    for start, n in [(0, 48), (1.92, 50), (4.2, 48), (5.48, 53)]:
        tr.add(mallet(midi(n), dur=2.0, vel=0.45, bright=0.5), start)
    apply_reverb(tr, wet=0.28, seconds=2.2)
    return master(tr)


def bells():
    """Колокольчики — хрустальная челеста над тёплым пэдом."""
    tr = Track(11)
    tr.add(pad([midi(48), midi(55), midi(64)], 11, attack=1.5, release=2.5, bright=1200), 0, gain=0.55)
    melody = [(0.0, 88), (0.5, 91), (1.0, 93), (1.5, 96), (2.25, 93), (3.0, 91),
              (4.0, 88), (4.5, 86), (5.0, 84), (5.75, 86), (6.5, 88), (7.5, 91), (8.0, 84)]
    for k, (st, n) in enumerate(melody):
        tr.add(bell(midi(n), vel=0.75), st, pan=(-0.5 if k % 2 else 0.5))
        tr.add(bell(midi(n + 12), dur=2.0, vel=0.12), st + 0.01, pan=(0.6 if k % 2 else -0.6))
    apply_reverb(tr, wet=0.38, seconds=3.2, damp=7000)
    return master(tr, drive=1.2)


def energetic():
    """Бодрый — акустическая гитара, бочка, шейкер и бас. 116 BPM."""
    bpm = 116
    beat = 60 / bpm
    bars = 4
    tr = Track(bars * 4 * beat + 2)
    chords = [[52, 59, 64, 68, 71], [47, 54, 59, 63, 66], [49, 56, 61, 64, 68], [45, 52, 57, 61, 64]]  # E B C#m A
    bass = [40, 35, 37, 33]
    strum = [0, 0.75, 1.5, 2, 2.75, 3.5]
    for b in range(bars):
        t0 = b * 4 * beat
        ch = chords[b % 4]
        for k, pos in enumerate(strum):
            down = k % 2 == 0
            notes = ch if down else ch[::-1][:3]
            for j, n in enumerate(notes):
                tr.add(pluck(midi(n), dur=1.4, vel=0.5 if down else 0.32, bright=0.6),
                       t0 + pos * beat + j * 0.012, pan=-0.3 + 0.15 * j)
        for q in range(4):
            tr.add(kick(vel=0.9), t0 + q * beat)
            tr.add(pluck(midi(bass[b % 4]), dur=0.6, vel=0.7, bright=0.2), t0 + q * beat)
        for e in range(8):
            tr.add(shaker(vel=0.7 if e % 2 else 0.4), t0 + e * beat / 2, pan=0.4)
    apply_reverb(tr, wet=0.15, seconds=1.4)
    return master(tr, drive=1.6)


def classic():
    """Классический звон — благородные трубчатые колокола, мотив повторяется."""
    tr = Track(10)
    motif = [76, 72, 74, 67]  # «вестминстерский» ход
    for rep in range(2):
        base = rep * 4.6
        for i, n in enumerate(motif):
            tr.add(bell(midi(n), dur=4.5, vel=0.9), base + i * 0.75, pan=-0.2 + 0.13 * i)
            tr.add(bell(midi(n - 12), dur=4.5, vel=0.25), base + i * 0.75)
    apply_reverb(tr, wet=0.35, seconds=3.0, damp=5000)
    return master(tr, drive=1.3)


def rising():
    """Нарастающий — электропиано, к которому постепенно добавляются слои."""
    tr = Track(14)
    prog = [[60, 64, 67, 71], [57, 60, 64, 67], [53, 57, 60, 64], [55, 59, 62, 65]]
    step = 0.22
    for bar in range(6):
        t0 = bar * 2.2
        ch = prog[bar % 4]
        vol = 0.35 + bar * 0.13
        arp = ch + [ch[2] + 12, ch[1] + 12]
        for i, n in enumerate(arp + arp[::-1][1:4]):
            tr.add(epiano(midi(n), dur=1.6, vel=vol), t0 + i * step, pan=-0.4 + 0.8 * (i % 5) / 4)
        if bar >= 2:
            tr.add(pad([midi(n - 12) for n in ch[:3]], 2.4, attack=0.6, release=0.8, bright=1500),
                   t0, gain=0.25 + 0.08 * bar)
        if bar >= 3:
            tr.add(bell(midi(ch[0] + 24), dur=2.5, vel=0.25 + 0.05 * bar), t0, pan=0.5)
        if bar >= 4:
            for q in range(4):
                tr.add(kick(vel=0.6), t0 + q * 0.55)
    apply_reverb(tr, wet=0.25, seconds=2.4)
    return master(tr)


def red():
    """Красный — тревожный и настойчивый: минорный синт-арпеджиатор, пульс баса, сигнальный мотив."""
    bpm = 128
    s16 = 60 / bpm / 4
    bars = 4
    tr = Track(bars * 16 * s16 + 1.5)
    seq = [57, 60, 64, 69, 64, 60, 57, 64]  # A-минор
    for b in range(bars):
        t0 = b * 16 * s16
        shift = [0, 0, -2, -4][b]
        for i in range(16):
            n = seq[i % 8] + shift
            tr.add(synth_pluck(midi(n + 12), dur=0.3, vel=0.55 if i % 4 else 0.8, cutoff=3500),
                   t0 + i * s16, pan=(-0.35 if i % 2 else 0.35))
        for q in range(4):
            tr.add(kick(vel=1.0), t0 + q * 4 * s16)
            tr.add(synth_pluck(midi(33 + shift), dur=0.45, vel=0.9, cutoff=900), t0 + q * 4 * s16 + 2 * s16)
        # сигнальный «пинг» — две ноты в конце такта
        for k, n in enumerate([88, 84]):
            tr.add(bell(midi(n + shift), dur=1.2, vel=0.45), t0 + (12 + 2 * k) * s16, pan=0.0)
    apply_reverb(tr, wet=0.18, seconds=1.6, damp=8000)
    return master(tr, drive=1.9)


def green():
    """Зелёный — спокойный: тёплый пэд, мягкое электропиано, птицы и лёгкий ветер."""
    tr = Track(14)
    chords = [[53, 57, 60, 64], [57, 60, 64, 67], [50, 53, 57, 60], [55, 59, 62, 65]]  # Fmaj7 Am7 Dm7 G7sus
    for i, ch in enumerate(chords):
        tr.add(pad([midi(n) for n in ch], 4.2, attack=1.4, release=1.6, bright=1400), i * 3.3, gain=0.8)
        for k, n in enumerate(ch[1:] + [ch[0] + 12]):
            tr.add(epiano(midi(n + 12), dur=3.0, vel=0.35), i * 3.3 + 0.4 + k * 0.45,
                   pan=-0.4 + 0.27 * k)
    wind = lowpass(RNG.standard_normal(int(14 * SR)), 500, 2)
    wind *= 0.5 + 0.5 * np.sin(2 * np.pi * 0.11 * t_axis(14))
    tr.add(wind / (np.max(np.abs(wind)) or 1), 0, gain=0.06)
    for k in range(9):
        st = 0.9 + k * 1.4 + RNG.uniform(0, 0.4)
        pan = RNG.uniform(-0.8, 0.8)
        for c in range(int(RNG.integers(2, 5))):
            f0 = RNG.uniform(2800, 3600)
            tr.add(chirp_bird(0.08, f0, f0 + RNG.uniform(800, 1600), vel=0.18), st + c * 0.11, pan=pan)
    apply_reverb(tr, wet=0.35, seconds=3.0, damp=6000)
    return master(tr, drive=1.1)


SOUNDS = {
    "soft": soft_morning,
    "bells": bells,
    "energetic": energetic,
    "classic": classic,
    "rising": rising,
    "red": red,
    "green": green,
}


def write_wav(path, x):
    pcm = (np.clip(x.T, -1, 1) * 32767).astype(np.int16)
    with wave.open(str(path), "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())


def main():
    (OUT / "android").mkdir(parents=True, exist_ok=True)
    (OUT / "ios").mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        for key, fn in SOUNDS.items():
            wav = pathlib.Path(tmp) / f"{key}.wav"
            write_wav(wav, fn())
            run = lambda *a: subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(wav), *a], check=True)
            run("-c:a", "libvorbis", "-q:a", "7", str(OUT / "android" / f"alarm_{key}.ogg"))
            # iOS для звуков будильника/уведомлений принимает PCM или IMA4 (AAC — нет)
            run("-c:a", "adpcm_ima_qt", "-f", "caf", str(OUT / "ios" / f"alarm_{key}.caf"))
            run("-c:a", "libmp3lame", "-b:a", "256k", str(OUT / f"preview_{key}.mp3"))
            print("  ", key)
    print("Мелодии готовы:", OUT)


if __name__ == "__main__":
    main()
