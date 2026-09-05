"""Deterministically generate the four Wanpan motion sound cues.

Each cue stays silent until the selected D rising pair is aligned to its
Lottie scene. The synthesis deliberately uses only Python's standard library
so the checked-in assets can be reproduced without external audio tooling.
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import math
import struct
import wave


ROOT = Path(__file__).resolve().parents[1]
OUTPUT_DIRECTORIES = (
    ROOT / "flutter_app" / "assets" / "sounds",
    ROOT / "miniprogram" / "assets" / "sounds",
)
SAMPLE_RATE = 44_100
PCM_MAX = 32_767


@dataclass(frozen=True)
class Cue:
    filename: str
    duration: float
    peak_dbfs: float
    renderer: str
    compatibility_filenames: tuple[str, ...] = ()


CUES = (
    Cue(
        "send-success.wav",
        0.82,
        -10.0,
        "_render_send_success",
        ("success.wav",),
    ),
    Cue("route-published.wav", 0.84, -10.0, "_render_route_published"),
    Cue(
        "grade-milestone.wav",
        1.05,
        -10.0,
        "_render_grade_milestone",
        ("milestone.wav",),
    ),
    Cue(
        "ranking-encouragement.wav",
        0.84,
        -10.0,
        "_render_ranking_encouragement",
    ),
)


def _sample_count(seconds: float) -> int:
    return round(seconds * SAMPLE_RATE)


def _buffer(seconds: float) -> list[float]:
    return [0.0] * _sample_count(seconds)


def _smooth_edge(value: float) -> float:
    value = max(0.0, min(1.0, value))
    return value * value * (3.0 - 2.0 * value)


def _mix_short_note(
    samples: list[float],
    *,
    start: float,
    duration: float,
    frequency: float,
    amplitude: float,
) -> None:
    offset = _sample_count(start)
    count = min(_sample_count(duration), len(samples) - offset)
    if count <= 0:
        return

    phase = 0.0
    for index in range(count):
        elapsed = index / SAMPLE_RATE
        remaining = (count - 1 - index) / SAMPLE_RATE
        attack = _smooth_edge(elapsed / 0.002)
        release = _smooth_edge(remaining / min(0.035, duration * 0.6))
        decay = math.exp(-5.5 * index / max(1, count - 1))
        phase += 2.0 * math.pi * frequency / SAMPLE_RATE
        tone = math.sin(phase) + 0.12 * math.sin(phase * 2.0)
        samples[offset + index] += amplitude * attack * release * decay * tone


def _mix_selected_d(samples: list[float], *, start: float) -> None:
    """Mix the user-selected D rising pair without any additional layer."""

    _mix_short_note(
        samples,
        start=start,
        duration=0.052,
        frequency=659.25,
        amplitude=0.86,
    )
    _mix_short_note(
        samples,
        start=start + 0.061,
        duration=0.058,
        frequency=1_046.50,
        amplitude=1.0,
    )


def _render_send_success(duration: float) -> list[float]:
    samples = _buffer(duration)
    _mix_selected_d(samples, start=0.450)
    return samples


def _render_route_published(duration: float) -> list[float]:
    samples = _buffer(duration)
    _mix_selected_d(samples, start=0.683)
    return samples


def _render_grade_milestone(duration: float) -> list[float]:
    samples = _buffer(duration)
    _mix_selected_d(samples, start=0.633)
    return samples


def _render_ranking_encouragement(duration: float) -> list[float]:
    samples = _buffer(duration)
    _mix_selected_d(samples, start=0.400)
    return samples


def _normalize(samples: list[float], peak_dbfs: float) -> tuple[list[int], float]:
    peak = max(abs(sample) for sample in samples)
    if peak == 0.0:
        raise ValueError("Cannot normalize a silent cue")
    target_peak = 10.0 ** (peak_dbfs / 20.0)
    gain = target_peak / peak
    pcm = [
        max(-32_768, min(PCM_MAX, round(sample * gain * PCM_MAX)))
        for sample in samples
    ]
    rendered_peak = max(abs(sample) for sample in pcm) / PCM_MAX
    return pcm, 20.0 * math.log10(rendered_peak)


def _write_wave(path: Path, pcm: list[int]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    frames = b"".join(struct.pack("<h", sample) for sample in pcm)
    with wave.open(str(path), "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(SAMPLE_RATE)
        output.writeframes(frames)


def main() -> None:
    renderers = {
        name: value
        for name, value in globals().items()
        if name.startswith("_render_") and callable(value)
    }
    for cue in CUES:
        renderer = renderers[cue.renderer]
        pcm, rendered_peak_dbfs = _normalize(
            renderer(cue.duration), cue.peak_dbfs
        )
        filenames = (cue.filename, *cue.compatibility_filenames)
        for directory in OUTPUT_DIRECTORIES:
            for filename in filenames:
                _write_wave(directory / filename, pcm)
        print(
            f"{cue.filename}: {len(pcm) / SAMPLE_RATE:.3f}s, "
            f"{SAMPLE_RATE}Hz, PCM16 mono, peak {rendered_peak_dbfs:.2f}dBFS"
        )


if __name__ == "__main__":
    main()
