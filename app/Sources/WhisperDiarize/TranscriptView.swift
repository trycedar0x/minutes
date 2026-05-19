import SwiftUI
import WhisperDiarizeCore

private let speakerPalette: [Color] = [
    AppDesign.Palette.accent, AppDesign.Palette.amber, AppDesign.Palette.rose, .blue, .teal, .indigo, .pink, .cyan
]

struct TranscriptView: View {
    @EnvironmentObject private var runner: TranscriptionRunner
    @State private var searchText = ""
    @State private var selectedSpeaker: String? = nil

    private var speakers: [String] {
        Array(Set(runner.transcript.map(\.speaker))).sorted()
    }

    private var filtered: [TranscriptLine] {
        runner.transcript.filter { line in
            let matchesSpeaker = selectedSpeaker == nil || line.speaker == selectedSpeaker
            let matchesSearch = searchText.isEmpty ||
                line.text.localizedCaseInsensitiveContains(searchText) ||
                line.speaker.localizedCaseInsensitiveContains(searchText)
            return matchesSpeaker && matchesSearch
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            TranscriptSidebar(
                lineCount: runner.transcript.count,
                visibleCount: filtered.count,
                speakers: speakers,
                selectedSpeaker: $selectedSpeaker
            )
            .frame(width: AppDesign.Layout.sidebarWidth)

            VStack(spacing: 0) {
                TranscriptToolbar(searchText: $searchText)
                    .padding(.horizontal, AppDesign.Spacing.xl)
                    .padding(.vertical, AppDesign.Spacing.lg)

                Divider()

                ScrollView(.vertical) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(filtered) { line in
                            TranscriptLineRow(line: line)
                            Divider().padding(.leading, AppDesign.Layout.timestampWidth - AppDesign.Spacing.lg)
                        }
                    }
                    .padding(.vertical, AppDesign.Spacing.sm)
                }
                .background(Color(nsColor: .textBackgroundColor).opacity(0.45))
            }
        }
    }
}

private struct TranscriptSidebar: View {
    let lineCount: Int
    let visibleCount: Int
    let speakers: [String]
    @Binding var selectedSpeaker: String?

    var body: some View {
        VStack(alignment: .leading, spacing: AppDesign.Spacing.xl) {
            VStack(alignment: .leading, spacing: AppDesign.Spacing.sm) {
                AppLogo(size: AppDesign.Layout.logo, showShadow: true)
                Text("Transcript")
                    .font(.headline)
                Text("\(visibleCount) of \(lineCount) lines")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: AppDesign.Spacing.sm) {
                Text("Speakers")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                SpeakerFilterButton(
                    label: "All speakers",
                    color: .secondary,
                    selected: selectedSpeaker == nil
                ) {
                    selectedSpeaker = nil
                }

                ForEach(Array(speakers.enumerated()), id: \.element) { index, speaker in
                    SpeakerFilterButton(
                        label: speaker,
                        color: speakerPalette[index % speakerPalette.count],
                        selected: selectedSpeaker == speaker
                    ) {
                        selectedSpeaker = selectedSpeaker == speaker ? nil : speaker
                    }
                }
            }

            Spacer()
        }
        .padding(AppDesign.Spacing.xl)
        .background {
            SidebarSurface { Color.clear }
        }
    }
}

private struct TranscriptToolbar: View {
    @Binding var searchText: String

    var body: some View {
        HStack(spacing: AppDesign.Spacing.md) {
            VStack(alignment: .leading, spacing: AppDesign.Spacing.xxs) {
                Text("Review")
                    .font(AppDesign.TypeScale.title3)
                Text("Search speaker-labeled transcript.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: AppDesign.Spacing.sm) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search transcript", text: $searchText)
                    .textFieldStyle(.plain)
                    .frame(width: AppDesign.Layout.searchWidth)
            }
            .padding(.horizontal, AppDesign.Spacing.md)
            .padding(.vertical, AppDesign.Spacing.sm)
            .background(AppDesign.Palette.selected, in: RoundedRectangle(cornerRadius: AppDesign.Radius.control, style: .continuous))
        }
    }
}

private struct TranscriptLineRow: View {
    let line: TranscriptLine

    private var color: Color {
        speakerPalette[line.speakerIndex % speakerPalette.count]
    }

    var body: some View {
        HStack(alignment: .top, spacing: AppDesign.Spacing.lg) {
            Text(line.timestamp)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: AppDesign.Layout.timestampWidth, alignment: .leading)
                .textSelection(.enabled)

            VStack(alignment: .leading, spacing: AppDesign.Spacing.xs) {
                HStack(spacing: AppDesign.Spacing.sm) {
                    Circle()
                        .fill(color)
                        .frame(width: AppDesign.Layout.speakerDot, height: AppDesign.Layout.speakerDot)
                    Text(line.speaker)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(color)
                }

                Text(line.text)
                    .font(.body)
                    .lineSpacing(2)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: AppDesign.Spacing.lg)
        }
        .padding(.horizontal, AppDesign.Spacing.xl)
        .padding(.vertical, AppDesign.Spacing.md)
        .contentShape(Rectangle())
    }
}

private struct SpeakerFilterButton: View {
    let label: String
    let color: Color
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppDesign.Spacing.sm) {
                Circle()
                    .fill(color)
                    .frame(width: AppDesign.Layout.speakerDot, height: AppDesign.Layout.speakerDot)
                Text(label)
                    .font(.callout.weight(selected ? .semibold : .regular))
                    .lineLimit(1)
                Spacer()
                if selected {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                }
            }
            .padding(.horizontal, AppDesign.Spacing.md)
            .padding(.vertical, AppDesign.Spacing.sm)
            .background(selected ? color.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: AppDesign.Radius.control, style: .continuous))
            .foregroundStyle(selected ? color : .secondary)
        }
        .buttonStyle(.plain)
    }
}
