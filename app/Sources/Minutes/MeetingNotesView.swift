import SwiftUI
import MinutesCore
import UniformTypeIdentifiers

@MainActor
struct MeetingNotesView: View {
    @EnvironmentObject private var runner: TranscriptionRunner
    @AppStorage("notesModel") private var model = "mlx-community/Qwen2.5-7B-Instruct-4bit"
    @State private var exportError: String?
    let openSource: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Meeting notes").font(.title2.weight(.semibold))
                    Text("Generated on your Mac. Audio and text stay on-device.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if let notes = runner.meetingNotes {
                    Button("Copy notes", systemImage: "doc.on.doc") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(notes.markdown(transcript: runner.transcript), forType: .string)
                    }
                    Button("Export…", systemImage: "square.and.arrow.up") { export(notes) }
                }
                if runner.notesGenerating {
                    Button("Cancel") { runner.cancelMeetingNotes() }
                } else {
                    Button(runner.meetingNotes == nil ? "Generate notes" : "Regenerate") {
                        Task { await runner.generateMeetingNotes(model: model) }
                    }
                    .disabled(runner.transcript.isEmpty)
                }
            }
            .padding(24)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if runner.notesGenerating {
                        HStack {
                            ProgressView().controlSize(.small)
                            Text("Preparing meeting notes locally…")
                        }
                        Text("Long meetings take longer. The first run may download model weights.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if let error = runner.notesError {
                        Label("Generation failed", systemImage: "exclamationmark.triangle")
                        Text(error).font(.callout).textSelection(.enabled)
                    }
                    if let notes = runner.meetingNotes {
                        Text("AI-generated — verify important details using the references. Long meetings are summarized in sections; later discussion may revise earlier points.")
                            .font(.callout).foregroundStyle(.secondary)
                        section("Summary", items: notes.summary)
                        section("Decisions", items: notes.decisions)
                        section("Action items", items: notes.actions, actions: true)
                        section("Open questions", items: notes.questions)
                    } else if !runner.notesGenerating {
                        ContentUnavailableView {
                            Label("Turn conversation into notes", systemImage: "text.badge.checkmark")
                        } description: {
                            Text("Summaries, decisions, action items, and open questions — with references to your transcript. Uses the local language model selected in Settings.")
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
            }
        }
        .alert("Could not export notes", isPresented: Binding(
            get: { exportError != nil }, set: { if !$0 { exportError = nil } }
        )) {
            Button("OK") { exportError = nil }
        } message: { Text(exportError ?? "") }
    }

    private func section(_ title: String, items: [MeetingNoteItem], actions: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            if items.isEmpty {
                Text("None identified.").foregroundStyle(.secondary)
            }
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.text).textSelection(.enabled)
                    if actions {
                        Text("Owner: \(item.owner ?? "Not specified") · Due: \(item.due ?? "Not specified")")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    // Vertical references remain usable at large text sizes and with many citations.
                    ForEach(item.sources, id: \.self) { index in
                        if runner.transcript.indices.contains(index - 1) {
                            let source = runner.transcript[index - 1]
                            Button { openSource(index) } label: {
                                Label("[\(index)] \(source.timestamp) · \(source.speaker)", systemImage: "text.quote")
                                    .font(.caption)
                            }
                            .buttonStyle(.link)
                            .help(source.text)
                            .accessibilityLabel("Show transcript reference \(index): \(source.text)")
                        }
                    }
                }
            }
            Divider()
        }
    }

    private func export(_ notes: MeetingNotes) {
        let text = notes.markdown(transcript: runner.transcript)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.nameFieldStringValue = "meeting-notes.md"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do { try text.write(to: url, atomically: true, encoding: .utf8) }
            catch { exportError = error.localizedDescription }
        }
    }
}
