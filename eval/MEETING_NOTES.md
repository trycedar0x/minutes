# Local meeting notes evaluation

`compare_meeting_notes.py` compares three conditions using one cached Whisper result and the transcript JSON passed to `--notes-input`. All inference is local. Cached models are required by default (`HF_HUB_OFFLINE=1`). Keep private recordings, transcripts, and generated artifacts outside the repository.

```bash
python eval/compare_meeting_notes.py \
  --transcript-input /path/to/input.json \
  --whisper-cache /path/to/audio.whisper.json \
  --output-dir /path/to/results
```

The input JSON is an array of objects with `timestamp`, `speaker`, and `text` strings. The Whisper cache is the worker's original ASR output. Use the same recording for both files.

- **A-diarized:** labeled transcript from the normal worker.
- **B-labels-masked:** identical text and timestamps, labels changed to UNKNOWN. Model extraction chunk membership is frozen from A, because shorter labels otherwise change token-budget packing. Diarization-derived turn boundaries remain: this is a label ablation, not a diarization-free run.
- **C-whisper-only:** original Whisper segments, no speaker identification. Segmentation and transcript postprocessing differ as well as labels, so A/C is a workflow comparison, not a clean label ablation.

Optional arguments: `--model MODEL`, `--conditions A-diarized B-labels-masked C-whisper-only`, and `--pipeline experimental`. The experimental pipeline extracts evidence then organizes it globally; it is **not the app default**. Initial single-recording tests did not establish a quality improvement. It fails explicitly if extracted evidence exceeds the organization budget rather than silently truncating it.

Run with the project's Python dependencies installed and an empty output directory. Outputs include each condition's input and notes JSON, intermediate extracted evidence for the experimental pipeline, and metrics with worker SHA-256, model, timing, counts, extraction chunk membership, and failures. Any failed condition produces a nonzero exit status after metrics are saved. Counts and valid JSON are not quality scores. Timings exclude ASR/diarization, and generation retries affect them.

Review independently for concrete fact coverage, missing/spurious tasks, proposed versus agreed work, owner attribution, unsupported claims, unanswered versus already answered questions, and citation precision. Compare against a human-checked transcript/audio, not only another model's summary. Keep reference summaries out of generation prompts. Report failed runs and confounds, and do not generalize from one recording.

Worker contract tests: `python3 -m unittest discover -s tests`.
