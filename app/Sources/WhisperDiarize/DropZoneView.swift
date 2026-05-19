import SwiftUI
import UniformTypeIdentifiers

struct DropZoneView: View {
    @EnvironmentObject private var runner: TranscriptionRunner
    @AppStorage("hfToken") private var hfToken = ""
    @Environment(\.openSettings) private var openSettings
    @AppStorage("model") private var model = "mlx-community/whisper-large-v3-mlx"
    @AppStorage("language") private var language = ""
    @AppStorage("speakers") private var speakersRaw = 0
    @AppStorage("polish") private var polish = false
    @AppStorage("polishModel") private var polishModel = "mlx-community/Qwen2.5-7B-Instruct-4bit"

    @State private var isTargeted = false
    @State private var showFilePicker = false
    @State private var showMissingToken = false

    var body: some View {
        HStack(spacing: 0) {
            IntakeSidebar(
                hfToken: $hfToken,
                model: $model,
                language: $language,
                speakersRaw: $speakersRaw,
                polish: $polish,
                openSettings: { openSettings() }
            )
            .frame(width: AppDesign.Layout.sidebarWidth)

            VStack(alignment: .leading, spacing: AppDesign.Spacing.xl) {
                HeaderBar()

                DropTarget(
                    isTargeted: isTargeted,
                    showFilePicker: { showFilePicker = true }
                )
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
                .frame(maxHeight: AppDesign.Layout.dropMaxHeight)

                HStack(spacing: AppDesign.Spacing.md) {
                    MetricBadge(title: "Runs on", value: "MLX + Metal", systemImage: "cpu", tint: AppDesign.accent)
                    MetricBadge(title: "Accepts", value: "Audio & video", systemImage: "waveform", tint: AppDesign.amber)
                    MetricBadge(title: "Creates", value: polish ? "Polished transcript" : "Speaker transcript", systemImage: "doc.text", tint: AppDesign.rose)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, AppDesign.Spacing.page)
            .padding(.vertical, AppDesign.Spacing.xxl)
        }
        .alert("Token Required", isPresented: $showMissingToken) {
            Button("Open Settings") {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Add your HuggingFace token in Settings to identify speakers.")
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
                speakers: speakers,
                polish: polish,
                polishModel: polishModel
            )
        }
    }
}

private struct HeaderBar: View {
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: AppDesign.Spacing.xs) {
                Text("WhisperDiarize")
                    .font(AppDesign.TypeScale.screenTitle)
                Text("Transcribe audio and identify speakers locally.")
                    .font(AppDesign.TypeScale.headlineSupport)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Label("Apple Silicon", systemImage: "bolt.fill")
                .font(.caption.weight(.medium))
                .foregroundStyle(AppDesign.accent)
                .padding(.horizontal, AppDesign.Spacing.md)
                .padding(.vertical, AppDesign.Spacing.xs)
                .background(AppDesign.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: AppDesign.Radius.control, style: .continuous))
        }
    }
}

private struct DropTarget: View {
    let isTargeted: Bool
    let showFilePicker: () -> Void

    var body: some View {
        Panel(padding: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: AppDesign.Radius.panel, style: .continuous)
                    .fill(isTargeted ? AppDesign.accent.opacity(0.08) : Color.clear)

                RoundedRectangle(cornerRadius: AppDesign.Radius.panel, style: .continuous)
                    .strokeBorder(
                        isTargeted ? AppDesign.accent : Color.secondary.opacity(0.28),
                        style: StrokeStyle(lineWidth: 1.6, dash: [7, 5])
                    )
                    .padding(AppDesign.Spacing.lg)

                VStack(spacing: AppDesign.Spacing.xl) {
                    WaveformMark(active: isTargeted)

                    VStack(spacing: AppDesign.Spacing.xs) {
                        Text("Drop audio or video")
                            .font(AppDesign.TypeScale.dropTitle)
                        Text("wav, mp3, m4a, mp4, flac, ogg")
                            .font(AppDesign.TypeScale.dropCaption)
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        showFilePicker()
                    } label: {
                        Label("Choose File", systemImage: "folder")
                            .frame(minWidth: 128)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
                .padding(AppDesign.Spacing.page + AppDesign.Spacing.lg)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .frame(minHeight: AppDesign.Layout.dropMinHeight)
        }
        .animation(.easeInOut(duration: 0.16), value: isTargeted)
    }
}

private struct IntakeSidebar: View {
    @Binding var hfToken: String
    @Binding var model: String
    @Binding var language: String
    @Binding var speakersRaw: Int
    @Binding var polish: Bool
    let openSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppDesign.Spacing.xl) {
            VStack(alignment: .leading, spacing: AppDesign.Spacing.xs) {
                AppLogo(size: AppDesign.Layout.mainLogo, showShadow: true)
                Text("Session")
                    .font(AppDesign.TypeScale.sidebarTitle)
            }

            VStack(alignment: .leading, spacing: AppDesign.Spacing.md) {
                StatusRow(title: hfToken.isEmpty ? "Token missing" : "Token ready", systemImage: hfToken.isEmpty ? "key.slash" : "key.fill", tint: hfToken.isEmpty ? AppDesign.rose : AppDesign.accent)

                Divider()

                VStack(alignment: .leading, spacing: AppDesign.Spacing.xs) {
                    Text("Model")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Picker("", selection: $model) {
                        Text("large-v3").tag("mlx-community/whisper-large-v3-mlx")
                        Text("large-v3-turbo").tag("mlx-community/whisper-large-v3-turbo")
                        Text("medium").tag("mlx-community/whisper-medium-mlx")
                        Text("small").tag("mlx-community/whisper-small-mlx")
                        Text("Breeze zh-en").tag("Kenji8000/Breeze-ASR-25-mlx")
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                VStack(alignment: .leading, spacing: AppDesign.Spacing.xs) {
                    Text("Language")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    LanguagePicker(selection: $language)
                }

                VStack(alignment: .leading, spacing: AppDesign.Spacing.xs) {
                    Text("Speakers")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Picker("", selection: $speakersRaw) {
                        Text("Auto").tag(0)
                        ForEach(1...8, id: \.self) { Text("\($0)").tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Toggle(isOn: $polish) {
                    Label("Polish", systemImage: "sparkles")
                }
                .toggleStyle(.switch)
            }

            Spacer()

            Button {
                openSettings()
            } label: {
                Label("Settings", systemImage: "slider.horizontal.3")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
        .padding(.horizontal, AppDesign.Spacing.xl)
        .padding(.vertical, AppDesign.Spacing.xxl)
        .background {
            SidebarSurface { Color.clear }
        }
    }
}

private struct StatusRow: View {
    let title: String
    let systemImage: String
    let tint: Color

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(AppDesign.TypeScale.bodyLabel)
            .foregroundStyle(tint)
            .lineLimit(1)
    }
}
