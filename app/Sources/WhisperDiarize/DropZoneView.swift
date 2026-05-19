import SwiftUI
import UniformTypeIdentifiers

struct DropZoneView: View {
    @EnvironmentObject private var runner: TranscriptionRunner
    @AppStorage("hfToken")   private var hfToken = ""
    @AppStorage("model")     private var model = "mlx-community/whisper-large-v3-mlx"
    @AppStorage("language")  private var language = ""
    @AppStorage("speakers")  private var speakersRaw = 0   // 0 = auto

    @State private var isTargeted = false
    @State private var showFilePicker = false
    @State private var showMissingToken = false

    private let supportedTypes: [UTType] = [.audio, .movie, .wav, .mp3,
                                             UTType("public.aiff-audio")!,
                                             UTType("public.mpeg-4-audio")!]

    var body: some View {
        VStack(spacing: 0) {
            // Drop zone
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(
                        isTargeted ? Color.accentColor : Color.secondary.opacity(0.3),
                        style: StrokeStyle(lineWidth: 2, dash: [8, 5])
                    )
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(isTargeted ? Color.accentColor.opacity(0.07) : Color.clear)
                    )
                    .animation(.easeInOut(duration: 0.15), value: isTargeted)

                VStack(spacing: 16) {
                    Image(systemName: "waveform.circle.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(isTargeted ? Color.accentColor : .secondary)
                        .animation(.easeInOut(duration: 0.15), value: isTargeted)

                    Text("Drop audio here")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text("wav · mp3 · m4a · mp4 · flac · and more")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button("Choose File…") { showFilePicker = true }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .padding(.top, 4)
                }
                .padding(40)
            }
            .padding(32)
            .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
                guard let provider = providers.first else { return false }
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    DispatchQueue.main.async { handleDrop(url: url) }
                }
                return true
            }
            .fileImporter(isPresented: $showFilePicker, allowedContentTypes: [.audio, .movie]) { result in
                if case .success(let url) = result { handleDrop(url: url) }
            }

            Divider()

            // Quick settings bar
            HStack(spacing: 20) {
                Label(hfToken.isEmpty ? "No HF Token" : "Token set ✓",
                      systemImage: hfToken.isEmpty ? "key.slash" : "key.fill")
                    .font(.caption)
                    .foregroundStyle(hfToken.isEmpty ? .red : .green)

                Divider().frame(height: 16)

                Picker("", selection: $model) {
                    Text("large-v3").tag("mlx-community/whisper-large-v3-mlx")
                    Text("large-v3-turbo").tag("mlx-community/whisper-large-v3-turbo")
                    Text("medium").tag("mlx-community/whisper-medium-mlx")
                    Text("small").tag("mlx-community/whisper-small-mlx")
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 130)

                Divider().frame(height: 16)

                HStack(spacing: 4) {
                    Text("Speakers:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("", selection: $speakersRaw) {
                        Text("Auto").tag(0)
                        ForEach(1...8, id: \.self) { Text("\($0)").tag($0) }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(width: 60)
                }

                Spacer()

                Button("Open Settings") {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 12)
        }
        .alert("HuggingFace Token Required", isPresented: $showMissingToken) {
            Button("Open Settings") {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Set your HF_TOKEN in Settings to enable speaker diarization.")
        }
    }

    private func handleDrop(url: URL) {
        guard url.startAccessingSecurityScopedResource() else { return }
        if hfToken.isEmpty {
            showMissingToken = true
            return
        }
        let speakers = speakersRaw > 0 ? speakersRaw : nil
        Task {
            await runner.transcribe(
                audioURL: url,
                hfToken: hfToken,
                model: model,
                language: language,
                speakers: speakers
            )
        }
    }
}
