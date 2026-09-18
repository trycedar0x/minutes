import SwiftUI

struct ErrorView: View {
    @EnvironmentObject private var runner: TranscriptionRunner
    @State private var showLog = false
    let message: String

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: AppDesign.Spacing.xl) {
                AppLogo(size: AppDesign.Layout.logo, showShadow: true)
                Text("Run failed")
                    .font(.headline)
                Text("Transcript not completed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(minWidth: AppDesign.Layout.sidebarWidth, idealWidth: AppDesign.Layout.sidebarWidth, maxWidth: AppDesign.Layout.sidebarWidth, maxHeight: .infinity, alignment: .topLeading)
            .padding(AppDesign.Spacing.xl)
            .background {
                SidebarSurface { Color.clear }
            }

            VStack(alignment: .leading, spacing: AppDesign.Spacing.xl) {
                Panel {
                    VStack(alignment: .leading, spacing: AppDesign.Spacing.md) {
                        Text("Couldn’t finish transcription")
                            .font(AppDesign.TypeScale.screenTitle)

                        Text(message)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)

                        HStack(spacing: AppDesign.Spacing.md) {
                            Button {
                                showLog.toggle()
                            } label: {
                                Label(showLog ? "Hide Log" : "Show Log", systemImage: "terminal")
                            }
                            .buttonStyle(.bordered)

                            Button {
                                runner.reset()
                            } label: {
                                Label("Try Again", systemImage: "arrow.counterclockwise")
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .padding(.top, AppDesign.Spacing.xs)

                        if showLog {
                            Divider()
                            ScrollView {
                                LazyVStack(alignment: .leading, spacing: 2) {
                                    ForEach(Array(runner.logLines.enumerated()), id: \.offset) { _, line in
                                        Text(line)
                                            .font(AppDesign.TypeScale.monoLog)
                                            .foregroundStyle(line.lowercased().contains("error") ? AppDesign.rose : .secondary)
                                            .textSelection(.enabled)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                                .padding(AppDesign.Spacing.md)
                            }
                            .frame(minHeight: 120, maxHeight: 280)
                            .background(Color(nsColor: .textBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: AppDesign.Radius.control, style: .continuous))
                        }
                    }
                }
                Spacer()
            }
            .padding(AppDesign.Spacing.xxl)
        }
    }
}
