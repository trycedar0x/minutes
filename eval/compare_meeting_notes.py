"""Local single-recording ablation; never uploads audio or transcript content.

Use --transcript-input with the app's notes JSON input and --whisper-cache with
its cached Whisper JSON. A/B isolates labels (turn boundaries remain); C uses
Whisper segments directly, also changing segmentation and text postprocessing.
This is NOT an ASR accuracy benchmark and provides no automatic quality score.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import sys
import time

os.environ.setdefault("HF_HUB_OFFLINE", "1")
os.environ.setdefault("HF_HUB_DISABLE_TELEMETRY", "1")
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import transcribe


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--transcript-input", type=Path, required=True)
    parser.add_argument("--whisper-cache", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--model", default="mlx-community/Qwen2.5-7B-Instruct-4bit")
    parser.add_argument("--pipeline", choices=["baseline", "experimental"], default="baseline")
    parser.add_argument("--conditions", nargs="+", choices=["A-diarized", "B-labels-masked", "C-whisper-only"],
                        default=["A-diarized", "B-labels-masked", "C-whisper-only"])
    args = parser.parse_args()
    args.output_dir.mkdir(parents=True, exist_ok=True)
    if any(args.output_dir.iterdir()):
        parser.error("--output-dir must be empty to avoid mixing stale and new results")
    labeled = json.loads(args.transcript_input.read_text())
    masked = [{**line, "speaker": "UNKNOWN"} for line in labeled]
    whisper = json.loads(args.whisper_cache.read_text())
    raw = [{"timestamp": f"{transcribe.format_time(s['start'])} → {transcribe.format_time(s['end'])}",
            "speaker": "UNKNOWN", "text": s["text"].strip()}
           for s in whisper["segments"] if s["text"].strip()]
    assert all(a["text"] == b["text"] and a["timestamp"] == b["timestamp"]
               for a, b in zip(labeled, masked))
    metrics = {"model": args.model, "pipeline": args.pipeline, "worker_sha256": hashlib.sha256(Path(transcribe.__file__).read_bytes()).hexdigest(),
               "design": "A/B masks labels only, preserving both turn boundaries AND model extraction chunk boundaries from A. C bypasses diarization using original Whisper segments and changes boundaries and postprocessing.",
               "runs": {}}
    organizer = transcribe._organize_meeting_notes
    original_chunks = transcribe._meeting_chunks
    for name, lines in [("A-diarized", labeled), ("B-labels-masked", masked), ("C-whisper-only", raw)]:
        if name not in args.conditions:
            continue
        folder = args.output_dir / name
        folder.mkdir(exist_ok=True)
        chunk_sources = []
        def controlled_chunks(input_lines, tokenizer, budget=2500):
            # Freeze model chunk membership, not just transcript turn boundaries.
            # UNKNOWN has fewer tokens than SPEAKER_00, otherwise B packs more lines.
            source_lines = labeled if name == "B-labels-masked" else input_lines
            for chunk in original_chunks(source_lines, tokenizer, budget):
                if name == "B-labels-masked":
                    chunk = [(ref, json.dumps({**json.loads(text), "speaker": "UNKNOWN"}, ensure_ascii=False))
                             for ref, text in chunk]
                chunk_sources.append([ref for ref, _ in chunk])
                yield chunk
        transcribe._meeting_chunks = controlled_chunks
        (folder / "input.json").write_text(json.dumps(lines, ensure_ascii=False, indent=2))
        def capture(extracted, *rest):
            (folder / "extracted.json").write_text(json.dumps(extracted, ensure_ascii=False, indent=2))
            return organizer(extracted, *rest)
        transcribe._organize_meeting_notes = capture
        start = time.monotonic()
        print(f"\n=== {name}: {len(lines)} lines ===", flush=True)
        try:
            notes = transcribe.generate_meeting_notes(lines, args.model, experimental=args.pipeline == "experimental")
            (folder / "notes.json").write_text(json.dumps(notes, ensure_ascii=False, indent=2))
            metrics["runs"][name] = {"status": "success", "items": {k: len(v) for k, v in notes.items()}}
        except Exception as error:
            metrics["runs"][name] = {"status": "failed", "error": str(error)}
            print(f"Failed: {error}", flush=True)
        metrics["runs"][name].update(seconds=round(time.monotonic() - start, 2), lines=len(lines),
                                    extraction_chunks=len(chunk_sources), chunk_source_ids=chunk_sources)
        (args.output_dir / "metrics.json").write_text(json.dumps(metrics, ensure_ascii=False, indent=2))
    transcribe._organize_meeting_notes = organizer
    transcribe._meeting_chunks = original_chunks
    print(json.dumps(metrics, ensure_ascii=False, indent=2))
    return 1 if any(run["status"] == "failed" for run in metrics["runs"].values()) else 0


if __name__ == "__main__":
    sys.exit(main())
