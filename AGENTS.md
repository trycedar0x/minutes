# AGENTS.md

## Native Apple UI Guidelines

Use Apple Human Interface Guidelines as the baseline for this app's SwiftUI design.

- Prefer system materials and subtle separators over large custom gray blocks. Sidebars and control regions should feel like functional layers above content, not unrelated colored panels.
- Use visual hierarchy through spacing, alignment, typography, and material. Avoid using background color as the main organizing device unless it matches a system surface.
- Keep controls grouped by task and aligned for scanning. Labels should be short, direct, and consistent across the main window and Settings.
- Use the app icon as the brand mark where a screen needs identity. Avoid swapping in unrelated SF Symbols for the app identity.
- Keep content areas visually dominant. Navigation, settings, and status surfaces should support the workflow without competing with the drop zone or transcript.
- Use semantic system colors and materials so light/dark mode and accessibility settings remain coherent.
- Prefer concise copy: name the action or setting, then add a short detail only when it prevents confusion.

References:
- Apple HIG Layout: https://developer.apple.com/design/human-interface-guidelines/layout
- Apple HIG Materials: https://developer.apple.com/design/human-interface-guidelines/materials
- Apple HIG Sidebars: https://developer.apple.com/design/human-interface-guidelines/sidebars

## Project

Minutes — local, private speaker transcription for Apple Silicon. A SwiftUI macOS app (macOS 14+, Swift 6) wraps a Python worker that does the actual speech pipeline.

- `transcribe.py` — Python worker: mlx-whisper transcription, pyannote diarization, mlx-lm polish. Also usable standalone: `uv run transcribe.py <audio>`.
- `app/Sources/MinutesCore` — pure logic, no UI, fully testable (`Models.swift`, `TranscriptParser.swift`).
- `app/Sources/Minutes` — SwiftUI UI layer; depends on `MinutesCore`, bundles the Python worker files as resources.
- `app/Tests/MinutesTests` — unit tests, run by `make test`.
- `app/UITests` — XCUITest, intentionally excluded from `Package.swift`; needs Xcode and a running app.
- `scripts/package-macos.sh` — packaging entry point, invoked by `make package`.

## Build and Test

- `make run` — build, assemble and ad-hoc sign `app/.build/Minutes.app`, then launch it.
- `make test` — unit tests via `swift test --filter MinutesTests`. No Xcode scheme needed, but the full Xcode toolchain must be selected: with only Command Line Tools (`xcode-select -p` → `/Library/Developer/CommandLineTools`), it fails with `no such module 'XCTest'`. That is an environment problem, not a repo bug.
- `make test-ui` — prints instructions; run UI tests from Xcode (`open app/Package.swift`, then ⌘U).
- `make package` — builds `dist/Minutes.app` plus `Minutes-macos-arm64.dmg` and `.zip`, embedding a relocatable Python runtime.
- `make sync-app-resources` — **required after editing `transcribe.py`, `pyproject.toml`, or `uv.lock`.** The app builds against copies in `app/Sources/Minutes/Resources/`, so edits at the repo root do not reach the app until this runs.
- CI: `.github/workflows/macos-app.yml` runs `make test` then `make package` on pushes to `main` and on releases.

## Constraints

- **Everything stays on-device.** Audio, transcripts, and metadata are never uploaded. Do not add analytics, telemetry, or cloud API calls to the transcription or polish path.
- The only permitted network use is downloading model weights and the HuggingFace token check on first run. Any new network dependency needs an explicit reason in the PR description.
- `transcribe.py` is the single source of truth for the pipeline. Prefer changing it over reimplementing logic in Swift; Swift should shell out to the worker, not duplicate it.
- Swift 6 strict concurrency is on. UI code and test lifecycle methods touching UI are `@MainActor`; keep new UI types isolated the same way.
- Settings persist via `@AppStorage` (the HuggingFace token lives in the `hfToken` key). Do not introduce a second settings store.
- Keep `MinutesCore` free of SwiftUI imports — it is the testable seam.
