"""Prepare AUDIO1.WAV .. AUDIO4.WAV for the FPGA's read-only FAT32 player.

Examples:
  python prepare_scene_audio.py --demo --output ./card_audio
  python prepare_scene_audio.py --slot 1 --input narration.wav --output ./card_audio

Input: uncompressed integer PCM WAV (8/16/24/32 bit, mono/stereo).
Output: 48 kHz, 16-bit mono WAV. Resampling is offline linear interpolation.
This utility only writes the specified output folder; it never discovers cards,
formats disks, or copies/deletes pictures. Final filenames map to on-screen PIC
numbers, not alphabetical BMP order. Use the OSD to identify each picture slot.
"""
from pathlib import Path
import argparse
import math
import struct
import wave

RATE = 48000


def write_wave(path, samples):
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "wb") as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(RATE)
        block = bytearray()
        for value in samples:
            block.extend(struct.pack("<h", max(-32768, min(32767, round(value)))))
            if len(block) >= 16384:
                out.writeframesraw(block)
                block.clear()
        if block:
            out.writeframesraw(block)


def demo(slot):
    # Six seconds of distinct pitched phrases, with quiet head/tail and
    # smooth note envelopes. These are generated tones, not recorded speech.
    notes = [(262, 330, 392, 523), (294, 370, 440, 587),
             (330, 415, 494, 659), (349, 440, 523, 698)][slot - 1]
    for i in range(6 * RATE):
        t = i / RATE
        phrase = int(t * 2)
        u = t * 2 - phrase
        env = min(1.0, u / .06, (1.0 - u) / .12)
        head_tail = min(1.0, t / .08, (6.0 - t) / .12)
        f = notes[phrase % len(notes)]
        yield 14000 * env * head_tail * (
            .8 * math.sin(2 * math.pi * f * t) + .2 * math.sin(2 * math.pi * 2 * f * t))


def converted(source):
    with wave.open(str(source), "rb") as inp:
        channels, width, rate, frames, compression, _ = inp.getparams()
        if compression != "NONE" or channels not in (1, 2) or width not in (1, 2, 3, 4) or rate <= 0:
            raise ValueError("Expected uncompressed PCM WAV, 8/16/24/32-bit, mono/stereo")
        if frames == 0 or frames * RATE // rate * 2 + 44 > 64 * 1024 * 1024:
            raise ValueError("Audio must be nonempty and fit in the FPGA's 64 MiB file limit")

        def mono_frames():
            while True:
                raw = inp.readframes(4096)
                if not raw:
                    return
                for pos in range(0, len(raw), channels * width):
                    total = 0.0
                    for channel in range(channels):
                        data = raw[pos + channel * width:pos + (channel + 1) * width]
                        sample = (data[0] - 128) * 256 if width == 1 else int.from_bytes(data, "little", signed=True) / (2 ** (8 * width - 16))
                        total += sample
                    yield total / channels

        values = iter(mono_frames())
        left = next(values)
        right = next(values, left)
        at = 0
        for i in range(max(1, frames * RATE // rate)):
            numerator = i * rate
            index, remainder = divmod(numerator, RATE)
            while at < index:
                left, right = right, next(values, right)
                at += 1
            yield left + (right - left) * remainder / RATE


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--demo", action="store_true")
    parser.add_argument("--input", type=Path)
    parser.add_argument("--slot", type=int, choices=range(1, 5))
    parser.add_argument("--overwrite", action="store_true")
    args = parser.parse_args()
    if args.demo == (args.input is not None) or (not args.demo and args.slot is None):
        parser.error("Use --demo, or --input FILE --slot 1..4")
    slots = range(1, 5) if args.demo else [args.slot]
    targets = [args.output / f"AUDIO{slot}.WAV" for slot in slots]
    for target in targets:
        if target.exists() and not args.overwrite:
            parser.error(f"Refusing to overwrite {target}; use --overwrite deliberately")
        if args.input and target.resolve() == args.input.resolve():
            parser.error("Input and output must be different files")
    for slot, target in zip(slots, targets):
        write_wave(target, demo(slot) if args.demo else converted(args.input))
        with wave.open(str(target), "rb") as check:
            print(f"{target}: PCM16 mono, {check.getframerate()} Hz, {check.getnframes() / RATE:.2f} seconds")


if __name__ == "__main__":
    main()
