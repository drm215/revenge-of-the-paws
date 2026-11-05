"""Synthesizes the game's chiptune sound effects and music into audio/*.wav (22 kHz, mono, 16-bit).
Everything is made here from square, triangle, saw and noise waves, so it's all original.

    python tools/make_audio.py

The same input always makes the same files.
"""
import math
import random
import struct
import wave
from pathlib import Path

RATE = 22050
OUT = Path(__file__).resolve().parent.parent / "audio"


def square(phase, duty=0.5):
    return 1.0 if phase % 1.0 < duty else -1.0


def triangle(phase):
    return 4.0 * abs((phase % 1.0) - 0.5) - 1.0


def saw(phase):
    return 2.0 * (phase % 1.0) - 1.0


def note(midi):
    return 440.0 * 2.0 ** ((midi - 69) / 12.0)


class Track:
    def __init__(self, seconds):
        self.samples = [0.0] * int(seconds * RATE)

    def tone(self, start, length, freq, wave_fn=square, volume=0.5, slide=0.0, attack=0.004, decay=None, duty=0.5, vibrato=0.0):
        """A note from `start` for `length` seconds. `slide`: Hz per second. `decay`: fades to nothing
        over the whole note when None; else the seconds it takes to halve."""
        first = int(start * RATE)
        count = int(length * RATE)
        phase = 0.0
        for k in range(count):
            at = first + k
            if at >= len(self.samples):
                break
            t = k / RATE
            f = max(10.0, freq + slide * t)
            if vibrato:
                f *= 1.0 + 0.03 * math.sin(2 * math.pi * vibrato * t)
            phase += f / RATE
            env = min(1.0, t / attack) * min(1.0, (length - t) / 0.004)
            env *= (1.0 - t / length) if decay is None else 0.5 ** (t / decay)
            value = square(phase, duty) if wave_fn is square else wave_fn(phase)
            self.samples[at] += value * volume * env

    def noise(self, start, length, volume=0.5, period=1, decay=None, rng=None):
        """Noise; a larger `period` holds each value longer, for a lower, crunchier sound."""
        rng = rng or random.Random(int(start * 1000) + 1)
        first = int(start * RATE)
        count = int(length * RATE)
        value = 0.0
        for k in range(count):
            at = first + k
            if at >= len(self.samples):
                break
            if k % period == 0:
                value = rng.uniform(-1.0, 1.0)
            t = k / RATE
            env = min(1.0, (length - t) / 0.004)
            env *= (1.0 - t / length) if decay is None else 0.5 ** (t / decay)
            self.samples[at] += value * volume * env

    def write(self, name, peak):
        top = max(1e-6, max(abs(s) for s in self.samples))
        scale = peak / top
        OUT.mkdir(exist_ok=True)
        with wave.open(str(OUT / f"{name}.wav"), "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(RATE)
            w.writeframes(b"".join(struct.pack("<h", int(s * scale * 32000)) for s in self.samples))


def sfx():
    t = Track(0.14)  # a hit: a thump under a burst of noise
    t.tone(0, 0.12, 170, square, 0.6, slide=-900)
    t.noise(0, 0.09, 0.6, period=2)
    t.write("hit", 0.8)

    t = Track(0.34)  # a crit: a harder hit with a bright ring
    t.tone(0, 0.2, 240, square, 0.7, slide=-900)
    t.noise(0, 0.16, 0.7, period=1)
    for k, m in enumerate([76, 83, 88]):
        t.tone(0.03 + k * 0.05, 0.2, note(m), square, 0.3, duty=0.25)
    t.write("crit", 0.95)

    t = Track(0.42)  # a heal: rising and soft
    for k, m in enumerate([72, 76, 79, 84]):
        t.tone(k * 0.07, 0.2, note(m), triangle, 0.6)
    t.write("heal", 0.7)

    t = Track(0.5)  # an animal goes down
    t.tone(0, 0.45, 520, square, 0.5, slide=-950, duty=0.25)
    t.tone(0.02, 0.4, 130, triangle, 0.6, slide=-180)
    t.write("down", 0.8)

    t = Track(0.42)  # a zombie destroyed: a wet burst and a dying groan
    t.noise(0, 0.2, 0.7, period=3)
    t.tone(0.02, 0.38, 150, saw, 0.5, slide=-260)
    t.write("zombie_die", 0.8)

    t = Track(0.4)  # a zombie's groan
    t.tone(0, 0.38, 92, saw, 0.5, slide=-40, attack=0.05, vibrato=9)
    t.noise(0, 0.3, 0.09, period=6)
    t.write("groan", 0.45)

    t = Track(0.16)  # an attack's swoosh
    t.noise(0, 0.13, 0.5, period=1, decay=0.05)
    t.tone(0, 0.12, 300, triangle, 0.25, slide=2400)
    t.write("swoosh", 0.4)

    t = Track(0.3)  # a dog's two barks
    for at in (0, 0.15):
        t.tone(at, 0.09, 520, square, 0.5, slide=-2200, duty=0.3)
        t.noise(at, 0.05, 0.15, period=2)
    t.write("bark", 0.6)

    t = Track(0.34)  # a cat's meow
    t.tone(0, 0.32, 620, square, 0.5, slide=700, attack=0.03, duty=0.25, vibrato=7)
    t.write("meow", 0.5)

    t = Track(0.3)  # a combo: three fast rising notes
    for k, m in enumerate([79, 84, 91]):
        t.tone(k * 0.06, 0.14, note(m), square, 0.5, duty=0.25)
    t.write("combo", 0.75)

    t = Track(0.2)  # a weak spot found
    t.tone(0, 0.18, note(88), triangle, 0.6)
    t.tone(0.04, 0.14, note(95), square, 0.2, duty=0.125)
    t.write("weak", 0.6)

    t = Track(0.6)  # a wave cleared
    for k, m in enumerate([67, 72, 76]):
        t.tone(k * 0.1, 0.3, note(m), square, 0.45, duty=0.25)
    t.write("wave_clear", 0.75)

    t = Track(1.7)  # victory
    for at, m, length in [(0, 67, 0.14), (0.14, 67, 0.14), (0.28, 67, 0.14), (0.42, 72, 0.42), (0.84, 76, 0.14), (0.98, 79, 0.7)]:
        t.tone(at, length, note(m), square, 0.5, duty=0.25, decay=0.6)
        t.tone(at, length, note(m - 12), triangle, 0.45, decay=0.6)
    t.noise(0.98, 0.1, 0.25, period=1)
    t.write("victory", 0.85)

    t = Track(1.3)  # defeat
    for at, m in [(0, 64), (0.28, 60), (0.56, 57), (0.84, 52)]:
        t.tone(at, 0.42, note(m), square, 0.4, duty=0.25, decay=0.3)
        t.tone(at, 0.42, note(m - 12), triangle, 0.5, decay=0.3)
    t.write("defeat", 0.75)

    t = Track(1.3)  # a legend's roar
    t.tone(0, 1.25, 75, saw, 0.6, slide=-28, attack=0.12, vibrato=11)
    t.tone(0, 1.25, 112, square, 0.25, slide=-40, attack=0.12, vibrato=13, duty=0.3)
    t.noise(0, 1.2, 0.55, period=5, decay=0.5)
    t.write("roar", 1.0)

    t = Track(0.42)  # zombies arrive
    for at in (0, 0.18):
        t.tone(at, 0.2, 110, square, 0.6, slide=-260)
        t.noise(at, 0.12, 0.4, period=4)
    t.write("arrive", 0.8)

    t = Track(0.9)  # a big attack winding up: an alarm climbing
    for k in range(4):
        t.tone(k * 0.22, 0.2, 330 + k * 110, square, 0.45, slide=500, duty=0.25)
    t.noise(0, 0.88, 0.14, period=2)
    t.write("windup", 0.8)

    t = Track(0.8)  # the last blow of a battle
    t.tone(0, 0.7, 150, square, 0.7, slide=-180, decay=0.25)
    t.tone(0, 0.5, 75, triangle, 0.8, decay=0.3)
    t.noise(0, 0.5, 0.8, period=2, decay=0.16)
    for k, m in enumerate([84, 88, 91, 96]):
        t.tone(0.04 + k * 0.06, 0.34, note(m), square, 0.22, duty=0.125)
    t.write("finish", 1.0)


def music(name, bpm, chords, bass, arp, lead, kick, snare, peak, lead_duty=0.25):
    """A seamless loop: one bar per chord, 16 steps a bar. Chords are lists of MIDI notes; `lead` is
    [(step from the loop's start, MIDI note, steps long)]; `bass`, `arp`, `kick` and `snare` are the
    steps of a bar they play on, with `bass` and `arp` as indexes into the chord."""
    step = 60.0 / bpm / 4.0
    bars = len(chords)
    total = bars * 16 * step
    t = Track(total)
    rng = random.Random(name)
    for b, chord in enumerate(chords):
        at = b * 16 * step
        for s, index in bass.items():
            t.tone(at + s * step, step * 1.8, note(chord[index] - 24), triangle, 0.6, decay=0.5)
        for s, index in arp.items():
            t.tone(at + s * step, step * 0.9, note(chord[index % len(chord)]), square, 0.14, duty=0.5)
        for s in kick:
            t.tone(at + s * step, 0.09, 130, square, 0.4, slide=-1100)
        for s in snare:
            t.noise(at + s * step, 0.1, 0.32, period=1, rng=rng)
    for s, m, length in lead:
        t.tone(s * step, length * step * 0.95, note(m), square, 0.26, duty=lead_duty, decay=0.8, vibrato=5)
    t.write(name, peak)


def songs():
    # The map: unhurried and a little hopeful. A minor, resolving upward.
    am, f, c, g = [57, 60, 64], [53, 57, 60], [55, 60, 64], [55, 59, 62]
    music("music_map", 92, [am, f, c, g, am, f, g, c],
          bass={0: 0, 8: 0, 12: 2},
          arp={0: 0, 2: 1, 4: 2, 6: 1, 8: 0, 10: 1, 12: 2, 14: 1},
          lead=[(0, 76, 6), (6, 74, 2), (8, 72, 8), (16, 72, 6), (22, 74, 2), (24, 69, 8), (32, 67, 6), (38, 72, 2), (40, 76, 8),
                (48, 74, 12), (60, 71, 4), (64, 76, 6), (70, 79, 2), (72, 76, 8), (80, 72, 6), (86, 74, 2), (88, 77, 8),
                (96, 79, 6), (102, 77, 2), (104, 74, 8), (112, 72, 12), (124, 67, 4)],
          kick=[0, 8], snare=[], peak=0.55)

    # A battle: driving, E minor.
    em, cm, d, b7 = [52, 55, 59], [48, 52, 55], [50, 54, 57], [47, 51, 54]
    music("music_battle", 144, [em, em, cm, d, em, em, cm, b7],
          bass={0: 0, 3: 0, 6: 0, 8: 0, 11: 0, 14: 2},
          arp={k: (k // 2) % 3 for k in range(0, 16, 2)},
          lead=[(0, 76, 3), (3, 79, 3), (6, 83, 2), (8, 81, 4), (12, 79, 4), (16, 76, 3), (19, 74, 3), (22, 71, 2), (24, 74, 8),
                (32, 72, 3), (35, 76, 3), (38, 79, 2), (40, 84, 8), (48, 83, 3), (51, 81, 3), (54, 78, 2), (56, 74, 8),
                (64, 76, 3), (67, 79, 3), (70, 83, 2), (72, 88, 4), (76, 86, 4), (80, 83, 3), (83, 81, 3), (86, 79, 2), (88, 76, 8),
                (96, 72, 3), (99, 76, 3), (102, 79, 2), (104, 84, 8), (112, 83, 3), (115, 78, 3), (118, 75, 2), (120, 71, 8)],
          kick=[0, 6, 8, 14], snare=[4, 12], peak=0.6)

    # A legend: fast and menacing, D minor with a tritone that won't settle.
    dm, bb, ab, a7 = [50, 53, 57], [46, 50, 53], [44, 48, 51], [45, 49, 52]
    music("music_boss", 168, [dm, dm, bb, ab, dm, dm, bb, a7],
          bass={k: 0 for k in range(0, 16, 2)},
          arp={k: k % 3 for k in range(16)},
          lead=[(0, 74, 2), (2, 74, 2), (4, 77, 2), (6, 74, 2), (8, 80, 4), (12, 77, 4), (16, 74, 2), (18, 74, 2), (20, 72, 2), (22, 69, 2), (24, 68, 8),
                (32, 70, 2), (34, 74, 2), (36, 77, 2), (38, 82, 2), (40, 80, 8), (48, 79, 4), (52, 75, 4), (56, 72, 4), (60, 68, 4),
                (64, 86, 2), (66, 86, 2), (68, 89, 2), (70, 86, 2), (72, 92, 4), (76, 89, 4), (80, 86, 2), (82, 84, 2), (84, 81, 2), (86, 80, 2), (88, 77, 8),
                (96, 82, 4), (100, 77, 4), (104, 74, 4), (108, 70, 4), (112, 73, 4), (116, 76, 4), (120, 81, 4), (124, 85, 4)],
          kick=[0, 4, 8, 10, 12], snare=[4, 12, 15], peak=0.6, lead_duty=0.125)


if __name__ == "__main__":
    sfx()
    songs()
    for f in sorted(OUT.glob("*.wav")):
        print(f"{f.name}: {f.stat().st_size / 1000:.0f} KB")
