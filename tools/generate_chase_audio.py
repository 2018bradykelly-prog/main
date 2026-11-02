#!/usr/bin/env python3
"""Generate an original eight-second, mono chase loop using only math and wave.

No recordings, samples, third-party music, or external Python packages are used.
The pulse is deliberately modest; chase intensity is mixed by the game client.
"""

from array import array
import math
from pathlib import Path
import sys
import wave


SAMPLE_RATE = 44100
DURATION = 8
DESTINATION = Path(__file__).resolve().parents[1] / "assets/audio/chase-placeholder.wav"


def pulse(time: float, start: float, strength: float) -> float:
    elapsed = time - start
    if not 0 <= elapsed < 0.28:
        return 0.0
    attack = min(1.0, elapsed / 0.008)
    envelope = attack * math.exp(-elapsed * 22)
    pitch_phase = 2 * math.pi * (62 * elapsed + 7 * (1 - math.exp(-15 * elapsed)))
    return strength * envelope * math.sin(pitch_phase)


def main() -> None:
    samples = []
    for frame in range(SAMPLE_RATE * DURATION):
        time = frame / SAMPLE_RATE
        beat = math.floor(time / 0.5) * 0.5
        heartbeat = pulse(time, beat, 0.68) + pulse(time, beat + 0.18, 0.35)
        drone = 0.10 * math.sin(2 * math.pi * 55 * time)
        drone += 0.055 * math.sin(2 * math.pi * 58.5 * time)
        drone += 0.035 * math.sin(2 * math.pi * 110.125 * time)
        shimmer = 0.022 * math.sin(2 * math.pi * 440.5 * time) * (0.5 + 0.5 * math.sin(2 * math.pi * 2 * time))
        # Endpoints approach zero to avoid a click at Sound.Looped boundaries.
        edge = min(1.0, time / 0.012, (DURATION - time) / 0.012)
        samples.append((heartbeat + drone + shimmer) * edge)
    peak = max(abs(value) for value in samples)
    pcm = array("h", (round(value * 0.78 / peak * 32767) for value in samples))
    if sys.byteorder != "little":
        pcm.byteswap()
    DESTINATION.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(DESTINATION), "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(SAMPLE_RATE)
        output.writeframes(pcm.tobytes())
    print(f"Generated {DESTINATION.name}: {DURATION}s, {SAMPLE_RATE} Hz, mono PCM16")


if __name__ == "__main__":
    main()
