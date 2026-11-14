#!/usr/bin/env python3
"""Generate deterministic, peak-normalized chiptune UI/game sounds."""
import math
import random
import struct
import wave
from pathlib import Path

RATE = 44100
OUT = Path(__file__).resolve().parents[2] / "assets/audio/sfx"
SOUNDS = {
    "ui_tap": (0.07, [880], "square"), "buy": (0.16, [520, 780], "square"),
    "buy_bulk": (0.24, [440, 660, 880], "triangle"), "cant_afford": (0.18, [300, 220], "square"),
    "tab_switch": (0.10, [440, 660], "triangle"), "training_start": (0.32, [330, 440, 660], "square"),
    "training_success": (0.42, [523, 659, 784, 1047], "triangle"), "training_fail": (0.34, [440, 330, 220], "square"),
    "new_best": (0.48, [660, 880, 1100, 1320], "triangle"), "paper_offered": (0.24, [660, 880], "triangle"),
    "paper_choice": (0.20, [523, 784], "square"), "benchmark": (0.5, [523, 659, 784, 1047], "triangle"),
    "upgrade": (0.26, [440, 660, 880], "square"), "launch": (0.38, [220, 440, 880], "square"),
    "news_chip": (0.14, [880, 1175], "square"), "moonshot_start": (0.4, [220, 330, 440], "triangle"),
    "moonshot_done": (0.56, [440, 587, 784, 1175], "triangle"), "hire": (0.22, [440, 587, 784], "square"),
    "reset_small": (0.75, [880, 660, 523, 784], "triangle"), "reset_big": (1.15, [330, 440, 660, 880, 1320], "triangle"),
    "unlock_reveal": (0.5, [392, 523, 784, 1047], "triangle"), "offline_card": (0.36, [440, 554, 659], "triangle"),
    "event_good": (0.25, [523, 659, 880], "triangle"), "event_bad": (0.3, [440, 330, 247], "square"),
    "agi_stage": (0.66, [392, 523, 659, 784, 1047], "triangle"), "ending": (1.35, [392, 523, 659, 784, 1047, 1319], "triangle"),
}


def synth(name, spec):
    duration, notes, shape = spec
    n = int(RATE * duration)
    rng = random.Random(20261113 + sum(map(ord, name)))
    samples = []
    for i in range(n):
        t = i / RATE
        pos = min(len(notes) - 1, int(t / duration * len(notes)))
        local = (t * len(notes) / duration) % 1
        freq = notes[pos] * (1 + 0.035 * (1 - local))
        phase = (t * freq) % 1
        if shape == "square":
            wavev = 1.0 if phase < 0.5 else -1.0
        else:
            wavev = 1 - 4 * abs(phase - 0.5)
        if name in ("cant_afford", "event_bad"):
            wavev = 0.72 * wavev + 0.28 * rng.uniform(-1, 1)
        env = min(1.0, t / 0.004, (duration - t) / 0.008) * math.exp(-2.2 * t / duration)
        samples.append(wavev * max(0.0, env))
    peak = max(map(abs, samples)) or 1
    gain = 10 ** (-3 / 20) / peak
    return [max(-32768, min(32767, round(x * gain * 32767))) for x in samples]


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for name, spec in SOUNDS.items():
        data = synth(name, spec)
        with wave.open(str(OUT / f"{name}.wav"), "wb") as f:
            f.setnchannels(1)
            f.setsampwidth(2)
            f.setframerate(RATE)
            f.writeframes(b"".join(struct.pack("<h", x) for x in data))
    print(f"Generated {len(SOUNDS)} effects in {OUT}")


if __name__ == "__main__":
    main()
