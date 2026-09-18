# minutes

**Who said what** — local, private speaker transcription for Apple Silicon.

- 🔒 **Fully local** — transcription, diarization, and LLM polish all run on-device. No audio ever sent to a server.
- 🖥️ **Native macOS app** — drag, drop, transcribe, search, copy, and save
- 🎙️ **Transcription** via [`mlx-whisper`](https://github.com/ml-explore/mlx-examples/tree/main/whisper), with an experimental local Qwen3-ASR + ForcedAligner backend for mixed-language meetings
- 👥 **Speaker diarization** via [`pyannote.audio`](https://github.com/pyannote/pyannote-audio) — who said what, automatically, runs on Metal (MPS)
- ✨ **LLM polish** via [Qwen 2.5](https://huggingface.co/mlx-community/Qwen2.5-7B-Instruct-4bit) — local cleanup of punctuation and readability, no cloud API needed
- ⚡ **Fast** — all models run natively on Apple Silicon, no GPU server needed
- 💾 **Cached** — transcription is cached so retries are instant
- 🌍 **Multilingual** — auto-detects language via Whisper
- 🆓 **Free and open source** — MIT license

- 🖥️ **Native macOS app** — drag, drop, transcribe, search, copy, and save
- 🎙️ **Transcription** via [`mlx-whisper`](https://github.com/ml-explore/mlx-examples/tree/main/whisper) — runs on Apple Silicon GPU via MLX
- 👥 **Diarization** via [`pyannote.audio`](https://github.com/pyannote/pyannote-audio) — runs on Metal (MPS)
- ⚡ **Fast** — both models run natively on Apple Silicon, no GPU server needed
- 💾 **Cached** — transcription is cached to `.whisper.json` so retries are instant
- 🌍 **Multilingual** — auto-detects language via Whisper

**Output:**
```
[00:01.20 → 00:05.44]  SPEAKER_00: Hello, welcome to the meeting.
[00:05.45 → 00:12.10]  SPEAKER_01: Thanks for having me, let's get started.
```

---

## Privacy

Everything runs on your Mac:

| Step | Model | Runs on |
|------|-------|---------|
| Transcription | mlx-whisper (large-v3), or experimental Qwen3-ASR 1.7B + ForcedAligner 0.6B | Apple Silicon GPU (MLX) |
| Speaker detection | pyannote 3.1 | Metal (MPS) |
| LLM cleanup | Qwen 2.5 7B | Apple Silicon GPU (MLX) |

No audio, transcripts, or metadata are sent to any server. Ever. This makes Minutes suitable for interviews, legal recordings, medical notes, and any other sensitive audio.

## Requirements

- macOS with Apple Silicon (M1/M2/M3/M4)
- Python 3.11+
- [`uv`](https://docs.astral.sh/uv/) — for dependency management
- A free [HuggingFace](https://huggingface.co/settings/tokens) account and token
- Xcode 16+ if building the native app

---

## Native macOS App

The SwiftUI app lives in [`app/`](app/). It provides:

- drag and drop audio/video input
- model, language, speaker count, token, and polish settings
- live processing state and logs
- searchable speaker-labeled transcript
- copy and save actions

After transcription, open **Meeting notes → Generate notes** to create a local summary, decisions, action items, and open questions. Choose the notes model independently in Settings: Qwen2.5 7B is faster, while Qwen3 14B targets higher extraction recall on Macs with 24 GB or more unified memory. The first run may download model weights; transcript content is never uploaded. Click a reference to jump to its transcript line, or use **Copy notes** / **Export…** to save Markdown with referenced passages.

Long meetings are processed in bounded sections covering the entire transcript, not just the opening. Results are combined in transcript order, so later discussion may revise earlier points; this first version does not reconcile those revisions across sections. AI-generated claims still need review: reference IDs are validated, but citations do not prove factual correctness. Unspecified owners and deadlines are shown as “Not specified.” Generation can be canceled or retried without losing the transcript. Notes are held in memory until you start a new transcription or close the app; export anything you want to keep.

Run the normal unit-test gate with `make test`; it runs Python worker tests first, then Swift parsing/export tests. The Swift step requires the full Xcode toolchain and reports `no such module 'XCTest'` when only Command Line Tools are selected.

Run from Xcode:

```bash
open app/Package.swift
```

Then use **Product -> Run**.

Or build from the command line:

```bash
cd app
swift build
```

The app bundles `transcribe.py`, `pyproject.toml`, `uv.lock`, and app icon resources. On first use it copies the Python worker files into:

```text
~/Library/Application Support/Minutes/
```

Development builds still fall back to `uv` if no bundled Python runtime is present. Packaged builds include a bundled Python runtime and the locked Python dependencies.

---

## Packaging

Build a distributable `.app` and ZIP artifact:

```bash
make package
```

This creates:

```text
dist/Minutes.app
dist/Minutes-macos-arm64.zip
```

The package script:

- Builds the Swift app in release mode
- Creates a macOS `.app` bundle
- Copies the app binary, `Info.plist`, app icon, and SwiftPM resources
- Installs a standalone CPython into `Contents/Resources/PythonRuntime` and creates `Contents/Resources/Python` against it (`bin/python` is a *relative* link, so the app works from `/Applications`, `~/Downloads`, or the mounted DMG)
- Installs the locked Python dependencies into the app bundle
- Ad-hoc signs the app by default
- Creates `dist/Minutes-macos-arm64.dmg` (HFS+ volume — the APFS default produced a ~45% larger image) and `dist/Minutes-macos-arm64.zip`

Long term, a dedicated Xcode macOS app target would make archive, signing, icons, and notarization cleaner than manually wrapping a SwiftPM executable.

Important: packaged builds bundle Python and Python dependencies, but Whisper, pyannote, and LLM model weights are still downloaded on first use.

### GitHub Builds

GitHub Actions builds the packaged macOS app on pushes to `main`, manual workflow runs, and published GitHub releases:

- workflow: `.github/workflows/macos-app.yml`
- artifact: `Minutes-macos-arm64.zip`
- release asset: attached automatically when a GitHub Release is published

Release builds get their version from the release tag (`v0.2.0` → `CFBundleShortVersionString 0.2.0`, `CFBundleVersion` from the workflow run number) and are **ad-hoc signed** — not notarized, so Gatekeeper blocks the first launch. On macOS 15+ the old Control-click → Open shortcut no longer works: use **System Settings → Privacy & Security → “Open Anyway”**, or clear the flag from Terminal with `xattr -dr com.apple.quarantine /Applications/Minutes.app`. For distribution without that detour, sign with a Developer ID certificate and notarize.

---

## CLI Setup

**1. Clone and install dependencies**

```bash
git clone https://github.com/trycedar0x/minutes.git
cd minutes
uv sync
```

**2. Create your `.env` file**

```bash
cp .env.example .env
```

Then open `.env` and paste your HuggingFace token:

```
HF_TOKEN=hf_xxxxxxxxxxxxxxxx
```

Get a free token at: https://huggingface.co/settings/tokens

**3. Accept model terms on HuggingFace** *(one-time, takes 30 seconds)*

- https://huggingface.co/pyannote/speaker-diarization-3.1
- https://huggingface.co/pyannote/segmentation-3.0
- https://huggingface.co/pyannote/speaker-diarization-community-1

---

## Usage

```bash
# Basic — auto-detects language and number of speakers
uv run transcribe.py path/to/audio.wav

# Faster — specify number of speakers if you know it
uv run transcribe.py path/to/audio.wav --speakers 2

# Experimental mixed-language backend (falls back to Whisper if inference,
# cached evidence, alignment validation, or aggregation fails)
uv run transcribe.py path/to/audio.wav --backend qwen3-asr

# Specify language (skips auto-detection)
uv run transcribe.py path/to/audio.wav --language en

# Custom output path
uv run transcribe.py path/to/audio.wav --output my_transcript.txt

# Pass HF token directly instead of .env
uv run transcribe.py path/to/audio.wav --hf-token hf_xxxx
```

Supported audio formats: `wav`, `mp3`, `m4a`, `mp4`, `flac`, `ogg`, and more. Successful Qwen3-ASR runs also save `<output>.qwen3-asr-evidence.json`, containing the exact raw ASR text and original forced-aligned units for auditability; speaker smoothing changes attribution only, never that evidence.

---

## Options

| Flag | Default | Description |
|------|---------|-------------|
| `--backend` | `whisper` | `whisper` or experimental `qwen3-asr` (Qwen3-ASR 1.7B + ForcedAligner 0.6B) |
| `--model` | `mlx-community/whisper-large-v3-mlx` | MLX Whisper model and fallback to use |
| `--language` | auto-detect | Language code (`en`, `zh`, `es`, …) |
| `--speakers` | auto-detect | Number of speakers in the audio |
| `--output` | `<audio>_transcript.txt` | Output file path |
| `--hf-token` | reads `HF_TOKEN` from `.env` | HuggingFace token |

**Available models** (faster → more accurate):

| Model | HuggingFace repo |
|-------|-----------------|
| tiny | `mlx-community/whisper-tiny-mlx` |
| base | `mlx-community/whisper-base-mlx` |
| small | `mlx-community/whisper-small-mlx` |
| medium | `mlx-community/whisper-medium-mlx` |
| large-v3 *(default)* | `mlx-community/whisper-large-v3-mlx` |
| large-v3-turbo | `mlx-community/whisper-large-v3-turbo` |

---

## How it works

```
Audio file
    │
    ▼
mlx-whisper ──► word-level timestamps + text   (Apple Silicon GPU / MLX)
    │
    ├──► cached to <audio>.whisper.json
    │
pyannote ────► speaker segments (who spoke when)   (Metal / MPS)
    │
    ▼
merge: assign each word to a speaker
    │
    ▼
transcript with timestamps + speaker labels
```

---

## License

MIT
