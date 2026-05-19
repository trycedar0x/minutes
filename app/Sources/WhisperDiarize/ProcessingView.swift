import SwiftUI

private struct Step {
    let icon: String
    let title: String
    let subtitle: String
}

private let steps: [Step] = [
    Step(icon: "waveform", title: "Transcribing", subtitle: "Whisper speech recognition"),
    Step(icon: "person.2.wave.2.fill", title: "Speakers", subtitle: "Finding speaker turns"),
    Step(icon: "arrow.triangle.merge", title: "Aligning", subtitle: "Matching words to speakers"),
    Step(icon: "doc.text.fill", title: "Saving", subtitle: "Writing transcript"),
    Step(icon: "sparkles", title: "Polishing", subtitle: "Optional cleanup"),
]

struct ProcessingView: View {
    @EnvironmentObject private var runner: TranscriptionRunner
    @State private var elapsed: TimeInterval = 0
    @State private var showLog = false
    @State private var timer: Timer?

    var body: some View {
        HStack(spacing: 0) {
            ProgressRail(elapsedString: elapsedString)
                .frame(width: AppDesign.Layout.sidebarWidth)

            VStack(alignment: .leading, spacing: AppDesign.Spacing.xl) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: AppDesign.Spacing.xs) {
                        Text(headerTitle)
                            .font(AppDesign.TypeScale.screenTitle)
                            .contentTransition(.numericText())
                        Text("Large models may take a moment to load.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(role: .destructive) {
                        runner.cancel()
                    } label: {
                        Label("Cancel", systemImage: "stop.circle")
                    }
                }

                Panel(padding: AppDesign.Spacing.xl) {
                    VStack(spacing: AppDesign.Spacing.md) {
                        ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                            StepRow(
                                step: step,
                                index: index,
                                currentStep: runner.currentStep,
                                detail: runner.stepDetails[index],
                                progress: runner.stepProgress[index]
                            )
                        }
                    }
                }

                LogPanel(showLog: $showLog)
            }
            .padding(AppDesign.Spacing.xxl)
        }
        .onAppear(perform: startTimer)
        .onDisappear(perform: stopTimer)
    }

    private var headerTitle: String {
        if case .running(let phase) = runner.state, !phase.isEmpty { return phase }
        return "Processing"
    }

    private var elapsedString: String {
        guard elapsed > 0 else { return "Starting" }
        let minutes = Int(elapsed) / 60
        let seconds = Int(elapsed) % 60
        return minutes > 0 ? "\(minutes)m \(seconds)s" : "\(seconds)s"
    }

    private func startTimer() {
        elapsed = runner.startTime.map { Date().timeIntervalSince($0) } ?? 0
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            Task { @MainActor in
                elapsed = runner.startTime.map { Date().timeIntervalSince($0) } ?? elapsed + 1
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}

private struct ProgressRail: View {
    let elapsedString: String

    var body: some View {
        VStack(alignment: .leading, spacing: AppDesign.Spacing.xl) {
            VStack(alignment: .leading, spacing: AppDesign.Spacing.sm) {
                AppLogo(size: AppDesign.Layout.logo, showShadow: true)
                Text("Processing")
                    .font(.headline)
                Text(elapsedString)
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .monospacedDigit()
            }

            Divider()

            VStack(alignment: .leading, spacing: AppDesign.Spacing.md) {
                MetricBadge(title: "Speech", value: "MLX Whisper", systemImage: "waveform", tint: AppDesign.accent)
                MetricBadge(title: "Speakers", value: "pyannote", systemImage: "person.2", tint: AppDesign.amber)
                MetricBadge(title: "Runtime", value: "Local", systemImage: "lock", tint: AppDesign.rose)
            }

            Spacer()
        }
        .padding(AppDesign.Spacing.xl)
        .background {
            SidebarSurface { Color.clear }
        }
    }
}

private struct StepRow: View {
    let step: Step
    let index: Int
    let currentStep: Int
    let detail: String?
    let progress: Double?

    private var status: StepStatus {
        if index < currentStep { return .done }
        if index == currentStep { return .active }
        return .pending
    }

    var body: some View {
        HStack(spacing: AppDesign.Spacing.lg) {
            ZStack {
                Circle()
                    .fill(status.tint.opacity(status == .pending ? 0.12 : 1))
                    .frame(width: AppDesign.Layout.stepIcon, height: AppDesign.Layout.stepIcon)

                if status == .active && progress == nil {
                    ProgressView()
                        .scaleEffect(0.58)
                        .tint(.white)
                } else {
                    Image(systemName: status == .done ? "checkmark" : step.icon)
                        .font(AppDesign.TypeScale.smallIcon)
                        .foregroundStyle(status == .pending ? Color.secondary : Color.white)
                }
            }

            VStack(alignment: .leading, spacing: AppDesign.Spacing.xs) {
                HStack {
                    Text(step.title)
                        .font(.body.weight(status == .active ? .semibold : .regular))
                    Spacer()
                    Text(statusLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(status.tint)
                        .monospacedDigit()
                }

                Text(detail ?? step.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ProgressView(value: displayedProgress)
                    .progressViewStyle(.linear)
                    .tint(status.tint)
                    .opacity(status == .pending ? 0.25 : 1)
            }
        }
        .padding(AppDesign.Spacing.md)
        .background(status == .active ? AppDesign.accent.opacity(0.06) : Color.clear, in: RoundedRectangle(cornerRadius: AppDesign.Radius.control, style: .continuous))
    }

    private var displayedProgress: Double {
        if let progress { return progress }
        if status == .done { return 1 }
        return 0
    }

    private var statusLabel: String {
        if status == .done { return "Done" }
        if status == .active {
            if let progress { return "\(Int(progress * 100))%" }
            return "Active"
        }
        return "Waiting"
    }
}

private struct LogPanel: View {
    @EnvironmentObject private var runner: TranscriptionRunner
    @Binding var showLog: Bool

    var body: some View {
        Panel(padding: 0) {
            VStack(spacing: 0) {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { showLog.toggle() }
                } label: {
                    HStack {
                        Label(showLog ? "Hide log" : "Show log", systemImage: showLog ? "chevron.down" : "chevron.right")
                            .font(.caption.weight(.medium))
                        Spacer()
                        Text("\(runner.logLines.count) lines")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, AppDesign.Spacing.lg)
                    .padding(.vertical, AppDesign.Spacing.md)
                }
                .buttonStyle(.plain)

                if showLog {
                    Divider()
                    LogView()
                        .frame(height: AppDesign.Layout.logHeight)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }
}

private struct LogView: View {
    @EnvironmentObject private var runner: TranscriptionRunner

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(runner.logLines.enumerated()), id: \.offset) { index, line in
                        Text(line)
                            .font(AppDesign.TypeScale.monoLog)
                            .foregroundStyle(logColor(for: line))
                            .textSelection(.enabled)
                            .id(index)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(AppDesign.Spacing.md)
            }
            .background(Color(nsColor: .textBackgroundColor))
            .onChange(of: runner.logLines.count) { _, _ in
                proxy.scrollTo("bottom")
            }
        }
    }

    private func logColor(for line: String) -> Color {
        if line.lowercased().contains("error") { return AppDesign.rose }
        if line.hasPrefix("APP_PROGRESS") { return AppDesign.accent }
        return .secondary
    }
}

private enum StepStatus {
    case pending, active, done

    var tint: Color {
        switch self {
        case .pending: return .secondary
        case .active: return AppDesign.accent
        case .done: return .green
        }
    }
}
