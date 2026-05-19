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

    print(f"🎙️  Transcribing with mlx-whisper ({model})...")
    result = mlx_whisper.transcribe(
        audio_path,
        path_or_hf_repo=model,
        word_timestamps=True,
        language=language,
        verbose=False,
    )
    print(f"✅ Transcription done. Detected language: {result.get('language', 'unknown')}")
    return result


def diarize(audio_path: str, hf_token: str, num_speakers: int | None):
    """Run pyannote diarization to identify speakers."""
    from pyannote.audio import Pipeline
    import torch

    print("👥 Running speaker diarization (pyannote)...")
    device = torch.device("mps" if torch.backends.mps.is_available() else "cpu")
    print(f"   Using device: {device}")

    pipeline = Pipeline.from_pretrained(
        "pyannote/speaker-diarization-3.1",
        token=hf_token,
    )
    pipeline.to(device)

    kwargs = {}
    if num_speakers:
        kwargs["num_speakers"] = num_speakers

    diarization = pipeline(audio_path, **kwargs)
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

    def get_speaker_at(t):
        """Find which speaker is talking at time t."""
        best = None
        best_overlap = 0
        for seg in speaker_segments:
            if seg["start"] <= t <= seg["end"]:
                overlap = min(seg["end"], t) - max(seg["start"], t)
                if overlap >= best_overlap:
                    best = seg["speaker"]
                    best_overlap = overlap
        return best or "UNKNOWN"

    # Assign each word a speaker
    for w in words:
        mid = (w["start"] + w["end"]) / 2
        w["speaker"] = get_speaker_at(mid)

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

    return lines


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

    # Step 1: Transcribe (with cache to avoid re-running on retry)
    cache_path = audio_path.with_suffix(".whisper.json")
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

    # Step 4: Output
    transcript = format_transcript(lines)
    print("\n" + "=" * 60)
    print(transcript)
    print("=" * 60 + "\n")

    with open(output_path, "w") as f:
        f.write(transcript + "\n")

    print(f"💾 Saved to: {output_path}")


if __name__ == "__main__":
    main()
