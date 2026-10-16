#!/usr/bin/env python3
"""Synthesize ChessCoach UI sounds (44.1 kHz mono 16-bit WAV).

Wood clicks are modal synthesis: a short filtered-noise transient excites a
handful of exponentially damped sine "body" modes (a wooden piece landing on
a wooden board). Chimes are soft additive bells. All sounds are generated
here, so there are no licensing concerns.

Usage: python3 scripts/make_sounds.py [out_dir]
Default out_dir: ChessCoach/Resources/Sounds (relative to repo root).
"""
import sys
import wave
from pathlib import Path

import numpy as np

SR = 44_100
RNG = np.random.default_rng(7)  # deterministic output


def t(dur):
    return np.arange(int(SR * dur)) / SR


def lowpass(x, cutoff):
    """One-pole low-pass."""
    a = np.exp(-2 * np.pi * cutoff / SR)
    y = np.empty_like(x)
    acc = 0.0
    for i, v in enumerate(x):
        acc = (1 - a) * v + a * acc
        y[i] = acc
    return y


def highpass(x, cutoff):
    return x - lowpass(x, cutoff)


def modes(dur, freqs_decays_amps, jitter=0.0):
    """Sum of damped sines: [(freq Hz, decay seconds, amplitude), ...]."""
    tt = t(dur)
    out = np.zeros_like(tt)
    for f, d, a in freqs_decays_amps:
        f *= 1 + jitter * RNG.uniform(-1, 1)
        out += a * np.sin(2 * np.pi * f * tt + RNG.uniform(0, 2 * np.pi)) * np.exp(-tt / d)
    return out


def noise_burst(dur, lo, hi, decay):
    tt = t(dur)
    n = RNG.standard_normal(len(tt))
    n = lowpass(highpass(n, lo), hi)
    return n * np.exp(-tt / decay)


def wood(dur=0.12, pitch=1.0, body=1.0, click=1.0, brightness=1.0):
    """A wooden 'thock': sharp transient + resonant body (~180-400 Hz)."""
    m = modes(dur, [
        (190 * pitch, 0.030, 1.00 * body),
        (310 * pitch, 0.022, 0.75 * body),
        (420 * pitch, 0.016, 0.45 * body),
        (780 * pitch, 0.010, 0.30 * brightness),
        (1450 * pitch, 0.006, 0.18 * brightness),
    ], jitter=0.02)
    n = noise_burst(dur, 600, 5000 * brightness, 0.0025) * 2.2 * click
    return pad(n, len(m)) + m


def bell(freq, dur, amp=1.0, decay=0.35):
    """Soft additive bell: fundamental + slightly inharmonic partials."""
    tt = t(dur)
    attack = np.minimum(1.0, tt / 0.004)
    s = np.zeros_like(tt)
    for ratio, a, d in [(1.0, 1.0, decay), (2.01, 0.35, decay * 0.6), (3.02, 0.12, decay * 0.4), (4.17, 0.06, decay * 0.25)]:
        s += a * np.sin(2 * np.pi * freq * ratio * tt) * np.exp(-tt / d)
    return amp * s * attack


def pad(x, n):
    return np.pad(x, (0, max(0, n - len(x))))[:max(n, len(x))]


def mix(*parts):
    """parts: (signal, offset_seconds, gain)."""
    n = max(int(o * SR) + len(s) for s, o, _ in parts)
    out = np.zeros(n)
    for s, o, g in parts:
        i = int(o * SR)
        out[i:i + len(s)] += g * s
    return out


def finish(x, peak_db=-3.0, fade_in=0.0005, fade_out=0.008):
    x = x - np.mean(x)
    fi, fo = int(SR * fade_in), int(SR * fade_out)
    if fi:
        x[:fi] *= np.linspace(0, 1, fi)
    if fo:
        x[-fo:] *= np.linspace(1, 0, fo)
    return x / np.max(np.abs(x)) * 10 ** (peak_db / 20)


def make_all():
    move = wood()
    capture = mix(
        (wood(0.14, pitch=0.88, body=1.3, click=1.4), 0.0, 1.0),
        (wood(0.08, pitch=1.6, body=0.4, click=1.8, brightness=1.4), 0.018, 0.7),
    )
    return {
        "move": finish(move, -3.0),
        "capture": finish(capture, -1.5),  # louder than move
        "castle": finish(mix((wood(), 0.0, 1.0), (wood(pitch=0.95), 0.09, 0.9)), -3.0),
        "check": finish(mix((wood(), 0.0, 1.0), (bell(1200, 0.35, decay=0.12), 0.02, 0.35)), -3.0),
        "promote": finish(mix((bell(784, 0.30, decay=0.12), 0.0, 1.0), (bell(1175, 0.45, decay=0.18), 0.11, 0.9)), -6.0),
        "illegal": finish(lowpass(modes(0.16, [(100, 0.045, 1.0), (165, 0.025, 0.5)]) + noise_burst(0.16, 60, 600, 0.004), 900), -6.0),
        "premove": finish(wood(0.06, pitch=1.9, body=0.5, click=0.8), -14.0),
        "gameStart": finish(mix((bell(523, 0.45, decay=0.18), 0.0, 1.0), (bell(784, 0.7, decay=0.28), 0.14, 0.9)), -6.0),
        "gameEnd": finish(mix((bell(784, 0.45, decay=0.18), 0.0, 1.0), (bell(523, 0.8, decay=0.32), 0.16, 0.9)), -6.0),
        "lowTime": finish(mix((wood(0.05, pitch=2.6, body=0.6), 0.0, 1.0), (wood(0.05, pitch=2.1, body=0.6), 0.16, 0.85)), -8.0),
    }


def write_wav(path, x):
    pcm = np.clip(np.round(x * 32767), -32768, 32767).astype("<i2")
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())


def main():
    out = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent / "ChessCoach/Resources/Sounds"
    out.mkdir(parents=True, exist_ok=True)
    for name, x in make_all().items():
        assert np.max(np.abs(x)) <= 1.0 and len(x) > 0, name
        write_wav(out / f"{name}.wav", x)
        print(f"{name:10s} {len(x) / SR * 1000:6.0f} ms  peak {20 * np.log10(np.max(np.abs(x))):6.1f} dBFS")


if __name__ == "__main__":
    main()
