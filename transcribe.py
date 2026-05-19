#!/usr/bin/env python3
"""
Audio transcription with diarization.
Uses mlx-whisper (Apple Neural Engine) for transcription + pyannote for speaker diarization.

Usage:
    uv run transcribe.py <audio_file> [--hf-token TOKEN] [--model large-v3] [--output out.txt]

HuggingFace token is required for pyannote diarization models.
Get one free at https://huggingface.co/settings/tokens
Accept model terms at:
  - https://huggingface.co/pyannote/speaker-diarization-3.1
  - https://huggingface.co/pyannote/segmentation-3.0
"""

import argparse
import os
import sys
from pathlib import Path

from dotenv import load_dotenv
load_dotenv()  # loads .env from current directory

# ── Structured progress for the macOS app ───────────────────────────────────
# Monkey-patch tqdm so mlx-whisper + pyannote emit APP_PROGRESS lines.
# Format: APP_PROGRESS step=<0-3> pct=<0-100>
_APP_STEP = 0

try:
    import tqdm as _tqdm_mod
    from tqdm import tqdm as _OrigTqdm

    class _AppTqdm(_OrigTqdm):
        _prev_pct: int = -1

        def update(self, n=1):
            super().update(n)
            if self.total and self.total > 0:
                pct = int(100 * self.n / self.total)
                if pct != self._prev_pct:
                    self._prev_pct = pct
                    print(f"APP_PROGRESS step={_APP_STEP} pct={pct}", flush=True)

    _tqdm_mod.tqdm = _AppTqdm
    try:
        import tqdm.auto as _tqdm_auto
        _tqdm_auto.tqdm = _AppTqdm
    except Exception:
        pass
except Exception:
    pass
# ────────────────────────────────────────────────────────────────────────────


def parse_args():
    parser = argparse.ArgumentParser(description="Transcribe audio with speaker diarization")
    parser.add_argument("audio", help="Path to audio file (mp3, wav, m4a, mp4, etc.)")
    parser.add_argument(
        "--hf-token",
        default=os.environ.get("HF_TOKEN"),
        help="HuggingFace token (or set HF_TOKEN env var)",
    )
    parser.add_argument(
        "--model",
        default="mlx-community/whisper-large-v3-mlx",
        help="MLX Whisper model (default: mlx-community/whisper-large-v3-mlx)",
    )
    parser.add_argument(
        "--language",
        default=None,
        help="Language code e.g. 'en', 'es'. Auto-detected if not set.",
    )
    parser.add_argument(
        "--output",
        default=None,
        help="Output file path (default: <audio_name>_transcript.txt)",
    )
    parser.add_argument(
        "--speakers",
        type=int,
        default=None,
        help="Number of speakers (optional, auto-detected if not set)",
    )
    return parser.parse_args()


def transcribe_with_mlx(audio_path: str, model: str, language: str | None):
    """Run mlx-whisper transcription with word-level timestamps."""
    import mlx_whisper
    global _APP_STEP
    _APP_STEP = 0

    # initial_prompt nudges Whisper to output punctuation and avoid hallucination
    prompt = (
        "以下是一段多人对话的转录，请包含标点符号（逗号、句号、问号等）。"
        "Example: 大家好，我们今天来讨论一个非常重要的话题。你认为怎么样？我觉得很好！"
        if not language or language.startswith("zh")
        else "Transcript of a multi-speaker conversation with punctuation."
    )

    print(f"🎙️  Transcribing with mlx-whisper ({model})...")
    result = mlx_whisper.transcribe(
        audio_path,
        path_or_hf_repo=model,
        word_timestamps=True,
        language=language,
        verbose=None,
        initial_prompt=prompt,
        condition_on_previous_text=False,  # apply initial_prompt to every 30s chunk
    )
    print(f"APP_PROGRESS step=0 pct=100", flush=True)
    print(f"✅ Transcription done. Detected language: {result.get('language', 'unknown')}")
    return result


def diarize(audio_path: str, hf_token: str, num_speakers: int | None):
    """Run pyannote diarization to identify speakers."""
    from pyannote.audio import Pipeline
    import torch
    global _APP_STEP
    _APP_STEP = 1

    print("👥 Running speaker diarization (pyannote)...")
    device = torch.device("mps" if torch.backends.mps.is_available() else "cpu")
    print(f"   Using device: {device}")

    pipeline = Pipeline.from_pretrained(
        "pyannote/speaker-diarization-3.1",
        token=hf_token,
    )
    pipeline.to(device)

    # Use min/max speakers for a softer constraint (more accurate than hard num_speakers)
    kwargs = {}
    if num_speakers:
        kwargs["min_speakers"] = num_speakers
        kwargs["max_speakers"] = num_speakers

    diarization = pipeline(audio_path, **kwargs)
    print("APP_PROGRESS step=1 pct=100", flush=True)
    print("✅ Diarization done.")
    return diarization


def merge_transcript_and_diarization(whisper_result, diarization):
    """
    Merge word-level timestamps from whisper with speaker segments from pyannote.
    Returns a list of (start, end, speaker, text) tuples grouped by speaker turn.
    """
    # Build list of (start, end, word) from whisper
    words = []
    for segment in whisper_result.get("segments", []):
        for w in segment.get("words", []):
            words.append({
                "start": w["start"],
                "end": w["end"],
                "word": w["word"],
            })

    # Build list of (start, end, speaker) from diarization
    speaker_segments = []
    for turn, _, speaker in diarization.speaker_diarization.itertracks(yield_label=True):
        speaker_segments.append({
            "start": turn.start,
            "end": turn.end,
            "speaker": speaker,
        })

    # Post-process: remove blips and merge close same-speaker segments
    speaker_segments = _clean_speaker_segments(speaker_segments)

    def get_speaker_at(t_start, t_end):
        """Return speaker with most overlap over [t_start, t_end].
        Falls back to nearest segment so we never return UNKNOWN."""
        best_overlap, best_speaker = 0.0, None
        for seg in speaker_segments:
            overlap = max(0.0, min(seg["end"], t_end) - max(seg["start"], t_start))
            if overlap > best_overlap:
                best_overlap = overlap
                best_speaker = seg["speaker"]
        if best_speaker:
            return best_speaker
        if not speaker_segments:
            return "UNKNOWN"
        mid = (t_start + t_end) / 2
        nearest = min(speaker_segments,
                      key=lambda s: min(abs(s["start"] - mid), abs(s["end"] - mid)))
        return nearest["speaker"]

    # Assign each word a speaker using full word duration
    for w in words:
        w["speaker"] = get_speaker_at(w["start"], w["end"])

    # Group consecutive words by same speaker into lines
    lines = []
    if not words:
        return lines

    current_speaker = words[0]["speaker"]
    current_words = [words[0]]

    for w in words[1:]:
        if w["speaker"] == current_speaker:
            current_words.append(w)
        else:
            lines.append({
                "start": current_words[0]["start"],
                "end": current_words[-1]["end"],
                "speaker": current_speaker,
                "text": "".join(cw["word"] for cw in current_words).strip(),
            })
            current_speaker = w["speaker"]
            current_words = [w]

    # Last group
    lines.append({
        "start": current_words[0]["start"],
        "end": current_words[-1]["end"],
        "speaker": current_speaker,
        "text": "".join(cw["word"] for cw in current_words).strip(),
    })

    # Post-process: merge short fragments into neighbours
    lines = _merge_short_fragments(lines)
    # Post-process: strip leading/trailing noise from each line
    for line in lines:
        line["text"] = _strip_noise(line["text"])
    # Post-process: drop noise-only or now-empty lines
    lines = [l for l in lines if l["text"] and not _is_noise(l["text"])]
    # Post-process: split very long lines on sentence boundaries
    lines = _split_long_lines(lines)

    return lines


_MIN_DURATION = 0.8   # seconds — lines shorter than this get merged into the previous

import re as _re

_MAX_LINE_DURATION = 60.0   # seconds — lines longer than this get split
_SENTENCE_SPLIT_RE = _re.compile(r'(?<=[。！？.!?])\s*')  # split after sentence-ending punctuation

def _split_long_lines(lines: list) -> list:
    """Split lines longer than _MAX_LINE_DURATION on sentence boundaries."""
    out = []
    for line in lines:
        duration = line["end"] - line["start"]
        if duration <= _MAX_LINE_DURATION:
            out.append(line)
            continue
        # Split text on sentence boundaries
        sentences = [s.strip() for s in _SENTENCE_SPLIT_RE.split(line["text"]) if s.strip()]
        if len(sentences) <= 1:
            out.append(line)  # can't split, keep as-is
            continue
        # Distribute time proportionally to sentence length
        total_chars = sum(len(s) for s in sentences)
        cursor = line["start"]
        for sentence in sentences:
            ratio = len(sentence) / total_chars if total_chars > 0 else 1 / len(sentences)
            seg_dur = duration * ratio
            out.append({
                "start":   cursor,
                "end":     cursor + seg_dur,
                "speaker": line["speaker"],
                "text":    sentence,
            })
            cursor += seg_dur
    return out
_SEG_MIN_DURATION = 0.3   # drop diarization blips shorter than this
_SEG_MAX_GAP      = 0.5   # merge same-speaker segments with gaps smaller than this

def _clean_speaker_segments(segments):
    """Remove short blips and merge nearby same-speaker segments."""
    if not segments:
        return segments
    segs = sorted(segments, key=lambda s: s["start"])
    # Step 1: remove blips
    segs = [s for s in segs if (s["end"] - s["start"]) >= _SEG_MIN_DURATION]
    if not segs:
        return segs
    # Step 2: merge same-speaker with small gap
    out = [dict(segs[0])]
    for seg in segs[1:]:
        prev = out[-1]
        gap = seg["start"] - prev["end"]
        if seg["speaker"] == prev["speaker"] and gap <= _SEG_MAX_GAP:
            prev["end"] = seg["end"]
        else:
            out.append(dict(seg))
    return out

def _merge_short_fragments(lines):
    """Absorb very short lines (< 0.8s) into the preceding line."""
    if len(lines) <= 1:
        return lines
    out = [lines[0]]
    for line in lines[1:]:
        prev = out[-1]
        duration = line["end"] - line["start"]
        if duration < _MIN_DURATION:
            # Absorb into previous regardless of speaker
            out[-1] = {
                "start":   prev["start"],
                "end":     line["end"],
                "speaker": prev["speaker"],
                "text":    prev["text"] + line["text"],
            }
        else:
            out.append(line)
    return out


_REPEAT_RE = _re.compile(r'^(.)\1{2,}$')  # 3+ repetitions of same char = noise
_NOISE_STRIP_RE = _re.compile(r'^(?:(.)\1{2,})+')  # leading noise runs (3+)

def _is_noise(text):
    return bool(_REPEAT_RE.match(text.strip()))


def _strip_noise(text: str) -> str:
    """Remove leading and trailing runs of 4+ repeated characters."""
    # Strip leading noise (e.g. 这这这这这这...)
    text = _NOISE_STRIP_RE.sub('', text).strip()
    # Strip trailing noise
    text = _re.sub(r'(?:(.)\1{3,})+$', '', text).strip()
    return text


def format_time(seconds: float) -> str:
    h = int(seconds // 3600)
    m = int((seconds % 3600) // 60)
    s = seconds % 60
    if h > 0:
        return f"{h:02d}:{m:02d}:{s:05.2f}"
    return f"{m:02d}:{s:05.2f}"


def format_transcript(lines: list) -> str:
    output = []
    for line in lines:
        ts = f"[{format_time(line['start'])} → {format_time(line['end'])}]"
        output.append(f"{ts}  {line['speaker']}: {line['text']}")
    return "\n".join(output)


def main():
    args = parse_args()

    audio_path = Path(args.audio).expanduser().resolve()
    if not audio_path.exists():
        print(f"❌ Audio file not found: {audio_path}", file=sys.stderr)
        sys.exit(1)

    if not args.hf_token:
        print(
            "❌ HuggingFace token required for diarization.\n"
            "   Pass --hf-token TOKEN or set the HF_TOKEN environment variable.\n"
            "   Get a free token at: https://huggingface.co/settings/tokens\n"
            "   Then accept terms at:\n"
            "     https://huggingface.co/pyannote/speaker-diarization-3.1\n"
            "     https://huggingface.co/pyannote/segmentation-3.0",
            file=sys.stderr,
        )
        sys.exit(1)

    # Output path
    output_path = args.output or audio_path.stem + "_transcript.txt"

    # Step 1: Transcribe (cache is keyed on audio path + model to avoid stale hits)
    model_slug = args.model.replace("/", "_").replace("-", "_")
    cache_path = audio_path.with_name(audio_path.stem + f".{model_slug}.whisper.json")
    if cache_path.exists():
        import json
        print(f"💨 Loading cached transcription from {cache_path}")
        with open(cache_path) as f:
            whisper_result = json.load(f)
    else:
        whisper_result = transcribe_with_mlx(str(audio_path), args.model, args.language)
        import json
        with open(cache_path, "w") as f:
            json.dump(whisper_result, f)
        print(f"💾 Cached transcription to {cache_path}")

    # Step 2: Diarize
    diarization = diarize(str(audio_path), args.hf_token, args.speakers)

    # Step 3: Merge
    print("🔀 Merging transcription + diarization...")
    lines = merge_transcript_and_diarization(whisper_result, diarization)
    print("APP_PROGRESS step=2 pct=100", flush=True)

    # Step 4: Output
    transcript = format_transcript(lines)
    print("\n" + "=" * 60)
    print(transcript)
    print("=" * 60 + "\n")

    with open(output_path, "w") as f:
        f.write(transcript + "\n")
    print("APP_PROGRESS step=3 pct=100", flush=True)
    print(f"💾 Saved to: {output_path}")


if __name__ == "__main__":
    main()
