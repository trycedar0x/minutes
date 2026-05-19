import SwiftUI

struct ErrorView: View {
    @EnvironmentObject private var runner: TranscriptionRunner
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
                                runner.state = .running(phase: "")
                            } label: {
                                Label("Show Log", systemImage: "terminal")
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
                    }
                }
                Spacer()
            }
            .padding(AppDesign.Spacing.xxl)
        }
    }
}
