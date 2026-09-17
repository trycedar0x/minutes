import Foundation
import SwiftUI
import MinutesCore

// Models are now in MinutesCore (TranscriptLine, RunnerState)

// MARK: - Runner

@MainActor
final class TranscriptionRunner: ObservableObject {
    @Published var state: RunnerState = .idle
    @Published var logLines: [String] = []
    @Published var transcript: [TranscriptLine] = []
    @Published var currentStep: Int = 0          // 0=transcribe 1=diarize 2=merge 3=save
    @Published var stepDetails: [Int: String] = [:] // extra info per step (e.g. language)
    @Published var stepProgress: [Int: Double] = [:] // 0.0–1.0 per step
    @Published var startTime: Date? = nil

    private var process: Process?
    private(set) var lastAudioURL: URL?
    private(set) var lastArgs: (hfToken: String, model: String, language: String,
                                speakers: Int?, polish: Bool, polishModel: String)?

    // MARK: - Public API

    func transcribe(audioURL: URL, hfToken: String, model: String, language: String, speakers: Int?,
                    polish: Bool = false, polishModel: String = "mlx-community/Qwen2.5-7B-Instruct-4bit",
                    force: Bool = false) async {
        state = .running(phase: "Preparing…")
        logLines = []
        transcript = []
        currentStep = 0
        stepDetails = [:]
        stepProgress = [:]
        startTime = Date()
        lastAudioURL = audioURL
        lastArgs = (hfToken, model, language, speakers, polish, polishModel)

        guard let workDir = prepareWorkDir() else {
            state = .failed("Could not set up working directory in Application Support.")
            return
        }

        let scriptPath = workDir.appendingPathComponent("transcribe.py").path
        let outputURL = workDir
            .appendingPathComponent(audioURL.deletingPathExtension().lastPathComponent + "_transcript.txt")

        guard let runtime = findPythonRuntime() else {
            state = .failed("Python runtime not found.\nUse a packaged app with bundled Python, or install uv for development builds.")
            return
        }

        var scriptArgs: [String] = [
            scriptPath,
            audioURL.path,
            "--output", outputURL.path,
            "--model", model,
        ]
        if !hfToken.isEmpty   { scriptArgs += ["--hf-token", hfToken] }
        if !language.isEmpty  { scriptArgs += ["--language", language] }
        if let n = speakers   { scriptArgs += ["--speakers", String(n)] }
        if polish             { scriptArgs += ["--polish", "--polish-model", polishModel] }
        if force              { scriptArgs += ["--force"] }

        let p = Process()
        switch runtime {
        case .bundled(let pythonURL, _):
            p.executableURL = pythonURL
            p.arguments = scriptArgs
        case .uv(let uvPath):
            p.executableURL = URL(fileURLWithPath: uvPath)
            p.arguments = ["run", "--project", workDir.path] + scriptArgs
        }
        p.currentDirectoryURL = workDir
        p.environment = enrichedEnv(for: runtime)

        let outPipe = Pipe()
        let errPipe = Pipe()
        p.standardOutput = outPipe
        p.standardError = errPipe

        for pipe in [outPipe, errPipe] {
            pipe.fileHandleForReading.readabilityHandler = { [weak self] fh in
                let data = fh.availableData
                guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
                let lines = text
                    .components(separatedBy: CharacterSet(charactersIn: "\n\r"))
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                Task { @MainActor [weak self] in self?.ingest(lines) }
            }
        }

        self.process = p

        await withCheckedContinuation { cont in
            p.terminationHandler = { [weak self] proc in
                Task { @MainActor [weak self] in
                    outPipe.fileHandleForReading.readabilityHandler = nil
                    errPipe.fileHandleForReading.readabilityHandler = nil
                    if proc.terminationStatus == 0 {
                        self?.loadTranscript(from: outputURL)
                        self?.state = .done
                    } else {
                        self?.state = .failed("Process exited with code \(proc.terminationStatus).\nCheck the log above for details.")
                    }
                    cont.resume()
                }
            }
            do {
                try p.run()
            } catch {
                Task { @MainActor [weak self] in
                    self?.state = .failed(error.localizedDescription)
                    cont.resume()
                }
            }
        }
    }

    func cancel() {
        process?.terminate()
        process = nil
        state = .idle
        currentStep = 0
        stepDetails = [:]
        stepProgress = [:]
        startTime = nil
    }

    func reprocess() async {
        guard let url = lastAudioURL, let a = lastArgs else { return }
        await transcribe(audioURL: url, hfToken: a.hfToken, model: a.model,
                         language: a.language, speakers: a.speakers,
                         polish: a.polish, polishModel: a.polishModel, force: true)
    }

    func reset() {
        process = nil
        state = .idle
        logLines = []
        transcript = []
        currentStep = 0
        stepDetails = [:]
        stepProgress = [:]
        startTime = nil
    }

    // MARK: - Log ingestion

    private func ingest(_ lines: [String]) {
        for line in lines {
            logLines.append(line)

            // Structured progress from Python: "APP_PROGRESS step=0 pct=45"
            if line.hasPrefix("APP_PROGRESS") {
                let parts = line.split(separator: " ")
                if let stepPart = parts.first(where: { $0.hasPrefix("step=") }),
                   let pctPart  = parts.first(where: { $0.hasPrefix("pct=")  }),
                   let step = Int(stepPart.dropFirst(5)),
                   let pct  = Double(pctPart.dropFirst(4)) {
                    stepProgress[step] = pct / 100.0
                    if pct >= 100 && step < 3 { currentStep = step + 1 }
                }
                continue
            }

            if line.contains("Transcribing") {
                currentStep = 0
                state = .running(phase: "Transcribing audio…")
            } else if line.contains("cached transcription") {
                stepProgress[0] = 1.0
                stepDetails[0] = "Loaded from cache"
                currentStep = 1
                state = .running(phase: "Identifying speakers…")
            } else if line.contains("Detected language") {
                if let lang = line.components(separatedBy: ":").last?.trimmingCharacters(in: .whitespaces) {
                    stepDetails[0] = "Language: \(lang)"
                }
            } else if line.contains("cached diarization") {
                stepProgress[1] = 1.0
                stepDetails[1] = "Loaded from cache"
                currentStep = 2
                state = .running(phase: "Merging results…")
            } else if line.contains("diarization") || line.contains("Diarization") {
                currentStep = 1
                state = .running(phase: "Identifying speakers…")
            } else if line.contains("Merging") {
                currentStep = 2
                state = .running(phase: "Merging results…")
            } else if line.contains("Polishing transcript") || line.contains("LLM loaded") {
                currentStep = 4
                state = .running(phase: "Polishing with LLM…")
            } else if line.contains("Polishing done") {
                stepProgress[4] = 1.0
            } else if line.contains("Saved to") {
                state = .running(phase: "Saving…")
            }
        }
    }

    // MARK: - Transcript parsing

    private func loadTranscript(from url: URL) {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return }
        transcript = parseTranscript(content)
    }

    // MARK: - Setup helpers

    private func prepareWorkDir() -> URL? {
        guard let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let dir = appSupport.appendingPathComponent("Minutes")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        // Copy bundled resources on first launch (or if missing)
        for (name, ext) in [("transcribe", "py"), ("pyproject", "toml"), ("uv", "lock")] {
            let dst = dir.appendingPathComponent("\(name).\(ext)")
            guard !FileManager.default.fileExists(atPath: dst.path) else { continue }
            if let src = AppResources.url(forResource: name, withExtension: ext) {
                try? FileManager.default.copyItem(at: src, to: dst)
            }
        }
        return dir
    }

    private enum PythonRuntime {
        case bundled(pythonURL: URL, envURL: URL)
        case uv(path: String)
    }

    private func findPythonRuntime() -> PythonRuntime? {
        if let bundled = findBundledPython() {
            return bundled
        }
        if let uvPath = findUV() {
            return .uv(path: uvPath)
        }
        return nil
    }

    private func findBundledPython() -> PythonRuntime? {
        guard let resourcesURL = Bundle.main.resourceURL else { return nil }
        let envURL = resourcesURL.appendingPathComponent("Python", isDirectory: true)
        for name in ["python3", "python"] {
            let pythonURL = envURL.appendingPathComponent("bin/\(name)")
            if FileManager.default.isExecutableFile(atPath: pythonURL.path) {
                return .bundled(pythonURL: pythonURL, envURL: envURL)
            }
        }
        return nil
    }

    private func findUV() -> String? {
        [
            "/opt/homebrew/bin/uv",
            "/usr/local/bin/uv",
            "\(NSHomeDirectory())/.local/bin/uv",
            "\(NSHomeDirectory())/.cargo/bin/uv",
        ].first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private func enrichedEnv(for runtime: PythonRuntime) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        var extra = "/opt/homebrew/bin:/usr/local/bin:\(NSHomeDirectory())/.local/bin:\(NSHomeDirectory())/.cargo/bin"
        if case .bundled(_, let envURL) = runtime {
            extra = envURL.appendingPathComponent("bin").path + ":" + extra
            env["VIRTUAL_ENV"] = envURL.path
        }
        env["PATH"] = extra + ":" + (env["PATH"] ?? "/usr/bin:/bin")
        env["PYTHONUNBUFFERED"] = "1"   // force unbuffered output so lines stream immediately
        // Never write bytecode into the app bundle: that invalidates the code
        // signature seal on first run, and fails outright from a read-only DMG.
        env["PYTHONDONTWRITEBYTECODE"] = "1"
        return env
    }
}
