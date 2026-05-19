import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var runner: TranscriptionRunner
    @AppStorage("hfToken") private var hfToken = ""

    var body: some View {
        AppShell {
            switch runner.state {
            case .idle:
                DropZoneView()
            case .running:
                ProcessingView()
            case .done:
                TranscriptView()
            case .failed(let message):
                ErrorView(message: message)
            }
        }
        .frame(minWidth: 860, minHeight: 560)
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                if case .done = runner.state {
                    Button {
                        copyTranscript()
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    Button {
                        saveTranscript()
                    } label: {
                        Label("Save…", systemImage: "arrow.down.circle")
                    }
                    Divider()
                }
                if case .running = runner.state {
                    Button(role: .destructive) {
                        runner.cancel()
                    } label: {
                        Label("Cancel", systemImage: "stop.circle")
                    }
                }
                if case .done = runner.state {
                    Button { Task { await runner.reprocess() } } label: {
                        Label("Reprocess", systemImage: "arrow.clockwise")
                    }
                    Button {
                        runner.reset()
                    } label: {
                        Label("New", systemImage: "plus.circle")
                    }
                }
                if case .failed = runner.state {
                    Button { Task { await runner.reprocess() } } label: {
                        Label("Reprocess", systemImage: "arrow.clockwise")
                    }
                    Button {
                        runner.reset()
                    } label: {
                        Label("Try Again", systemImage: "arrow.counterclockwise")
                    }
                }
            }
        }
    }

    private func copyTranscript() {
        let text = runner.transcript.map { "[\($0.timestamp)]  \($0.speaker): \($0.text)" }.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func saveTranscript() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "transcript.txt"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            let text = runner.transcript.map { "[\($0.timestamp)]  \($0.speaker): \($0.text)" }.joined(separator: "\n")
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
