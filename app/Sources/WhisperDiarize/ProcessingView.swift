import SwiftUI

struct ProcessingView: View {
    @EnvironmentObject private var runner: TranscriptionRunner
    @State private var scrollProxy: ScrollViewProxy? = nil

    private var phase: String {
        if case .running(let p) = runner.state { return p }
        return "Processing…"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Status header
            VStack(spacing: 12) {
                ProgressView()
                    .scaleEffect(1.4)
                    .padding(.bottom, 4)

                Text(phase)
                    .font(.title3.weight(.semibold))
                    .contentTransition(.numericText())
                    .animation(.easeInOut, value: phase)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)
            .background(.regularMaterial)

            Divider()

            // Live log
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(runner.logLines.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(logColor(for: line))
                                .textSelection(.enabled)
                                .id(line + "\(runner.logLines.count)")
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(12)
                }
                .onAppear { scrollProxy = proxy }
                .onChange(of: runner.logLines.count) { _, _ in
                    withAnimation { proxy.scrollTo("bottom") }
                }
            }
            .background(Color(nsColor: .textBackgroundColor))
        }
    }

    private func logColor(for line: String) -> Color {
        if line.hasPrefix("✅") { return .green }
        if line.hasPrefix("❌") { return .red }
        if line.hasPrefix("🎙️") || line.hasPrefix("👥") || line.hasPrefix("🔀") || line.hasPrefix("💾") || line.hasPrefix("💨") {
            return Color.accentColor
        }
        if line.contains("Error") || line.contains("error") { return .red }
        return .secondary
    }
}
