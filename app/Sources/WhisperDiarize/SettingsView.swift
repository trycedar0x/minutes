import SwiftUI

struct SettingsView: View {
    @AppStorage("hfToken") private var hfToken = ""
    @AppStorage("model") private var model = "mlx-community/whisper-large-v3-mlx"
    @AppStorage("language") private var language = ""
    @AppStorage("speakers") private var speakersRaw = 0
    @AppStorage("polish") private var polish = false
    @AppStorage("polishModel") private var polishModel = "mlx-community/Qwen2.5-7B-Instruct-4bit"
    @FocusState private var focusedField: SettingsFocusedField?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppDesign.Spacing.xl) {
                SettingsHeader()

                SettingsSection("Access", subtitle: "Required for speaker identification.") {
                    SettingsRow("HuggingFace Token", detail: "Saved on this Mac.") {
                        SettingsControlFrame {
                            SecureField("hf_xxxxxxxxxxxxxxxx", text: $hfToken)
                                .textFieldStyle(.roundedBorder)
                                .focused($focusedField, equals: .hfToken)
                        }
                    }

                    RowDivider()

                    SettingsRow("Model Access") {
                        VStack(alignment: .leading, spacing: AppDesign.Spacing.xs) {
                            Link("Create a HuggingFace token", destination: URL(string: "https://huggingface.co/settings/tokens")!)
                            Link("Accept pyannote terms", destination: URL(string: "https://huggingface.co/pyannote/speaker-diarization-3.1")!)
                        }
                        .font(.caption.weight(.medium))
                    }
                }

                SettingsSection("Transcription", subtitle: "Defaults for each new file.") {
                    SettingsRow("Model", detail: selectedModelDetail) {
                        SettingsControlFrame {
                            Picker("", selection: $model) {
                                Text("large-v3").tag("mlx-community/whisper-large-v3-mlx")
                                Text("large-v3-turbo").tag("mlx-community/whisper-large-v3-turbo")
                                Text("medium").tag("mlx-community/whisper-medium-mlx")
                                Text("small").tag("mlx-community/whisper-small-mlx")
                                Text("Breeze zh-en").tag("Kenji8000/Breeze-ASR-25-mlx")
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                        }
                    }

                    RowDivider()

                    SettingsRow("Language", detail: "Use Auto unless you know the language.") {
                        SettingsControlFrame {
                            LanguagePicker(selection: $language)
                        }
                    }

                    RowDivider()

                    SettingsRow("Speakers", detail: "Set a count when you know it.") {
                        SettingsControlFrame {
                            Picker("", selection: $speakersRaw) {
                                Text("Auto").tag(0)
                                ForEach(1...8, id: \.self) { n in
                                    Text("\(n)").tag(n)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                        }
                    }
                }

                SettingsSection("Cleanup", subtitle: "Optional local LLM pass.") {
                    SettingsRow("Polish Transcript", detail: "Improve punctuation and readability.") {
                        SettingsControlFrame {
                            Toggle("", isOn: $polish)
                                .labelsHidden()
                                .toggleStyle(.switch)
                        }
                    }

                    if polish {
                        RowDivider()

                        SettingsRow("Polish Model", detail: "Downloaded the first time it runs.") {
                            SettingsControlFrame {
                                Picker("", selection: $polishModel) {
                                    Text("Qwen2.5 1.5B").tag("mlx-community/Qwen2.5-1.5B-Instruct-4bit")
                                    Text("Qwen2.5 3B").tag("mlx-community/Qwen2.5-3B-Instruct-4bit")
                                    Text("Qwen2.5 7B").tag("mlx-community/Qwen2.5-7B-Instruct-4bit")
                                }
                                .labelsHidden()
                                .pickerStyle(.menu)
                            }
                        }
                    }
                }

                SettingsSection("Runtime", subtitle: "Used by the bundled Python worker.") {
                    SettingsRow("uv", detail: findUV() == nil ? "Install uv to process files." : "Ready on this Mac.") {
                        Text(findUV() ?? "Not found")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(findUV() == nil ? AppDesign.rose : .secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
            .padding(AppDesign.Spacing.xxl)
            .frame(maxWidth: AppDesign.Layout.settingsContentWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(AppDesign.surface)
        .frame(width: AppDesign.Layout.settingsWidth, height: AppDesign.Layout.settingsHeight)
        .onAppear {
            Task { @MainActor in
                focusedField = nil
            }
        }
    }

    private var selectedModelDetail: String {
        switch model {
        case "mlx-community/whisper-large-v3-mlx":
            return "Best quality, larger download."
        case "mlx-community/whisper-large-v3-turbo":
            return "Fast large model."
        case "mlx-community/whisper-medium-mlx":
            return "Balanced speed and quality."
        case "mlx-community/whisper-small-mlx":
            return "Fast drafts."
        case "Kenji8000/Breeze-ASR-25-mlx":
            return "Chinese-English code switching."
        default:
            return "Custom MLX Whisper model."
        }
    }

    private func findUV() -> String? {
        let candidates = [
            "/opt/homebrew/bin/uv",
            "/usr/local/bin/uv",
            "\(NSHomeDirectory())/.local/bin/uv",
            "\(NSHomeDirectory())/.cargo/bin/uv",
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}

private enum SettingsFocusedField: Hashable {
    case hfToken
}

private struct SettingsHeader: View {
    var body: some View {
        Panel(padding: AppDesign.Spacing.lg) {
            HStack(alignment: .center, spacing: AppDesign.Spacing.md) {
                AppLogo(size: 32, showShadow: true)

                VStack(alignment: .leading, spacing: 2) {
                    Text("WhisperDiarize")
                        .font(.headline)
                    Text("Default transcription settings")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Label("Local", systemImage: "lock.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppDesign.accent)
                    .padding(.horizontal, AppDesign.Spacing.md)
                    .padding(.vertical, AppDesign.Spacing.xs)
                    .background(AppDesign.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: AppDesign.Radius.control, style: .continuous))
            }
        }
    }
}
