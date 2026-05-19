import SwiftUI

enum AppDesign {
    enum Spacing {
        static let xxs: CGFloat = 3
        static let xs: CGFloat = 6
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 24
        static let page: CGFloat = 28
    }

    enum Radius {
        static let control: CGFloat = 6
        static let panel: CGFloat = 8
    }

    enum Layout {
        static let sidebarWidth: CGFloat = 220
        static let settingsSidebarWidth: CGFloat = 210
        static let settingsWidth: CGFloat = 680
        static let settingsHeight: CGFloat = 620
        static let settingsContentWidth: CGFloat = 560
        static let dropMinHeight: CGFloat = 360
        static let dropMaxHeight: CGFloat = 500
        static let timestampWidth: CGFloat = 92
        static let searchWidth: CGFloat = 220
        static let settingsLabelWidth: CGFloat = 220
        static let settingsControlColumnWidth: CGFloat = 250
        static let settingsControlWidth: CGFloat = 220
        static let stepIcon: CGFloat = 34
        static let logHeight: CGFloat = 190
        static let speakerDot: CGFloat = 8
        static let logo: CGFloat = 42
        static let mainLogo: CGFloat = 44
    }

    enum Palette {
        static let surface = Color(nsColor: .windowBackgroundColor)
        static let panel = Color(nsColor: .controlBackgroundColor).opacity(0.68)
        static let selected = Color.primary.opacity(0.055)
        static let separator = Color(nsColor: .separatorColor).opacity(0.34)
        static let text = Color.primary
        static let secondaryText = Color.secondary
        static let accent = Color(red: 0.13, green: 0.43, blue: 0.38)
        static let amber = Color(red: 0.76, green: 0.48, blue: 0.16)
        static let rose = Color(red: 0.70, green: 0.25, blue: 0.34)
        static let speaker: [Color] = [accent, amber, rose, .blue, .teal, .indigo, .pink, .cyan]
    }

    enum TypeScale {
        static let screenTitle = Font.system(size: 24, weight: .semibold)
        static let settingsTitle = Font.system(size: 22, weight: .semibold)
        static let sidebarTitle = Font.system(size: 20, weight: .semibold)
        static let section = Font.headline
        static let bodyLabel = Font.callout.weight(.medium)
        static let caption = Font.caption
        static let controlCaption = Font.caption.weight(.semibold)
        static let title3 = Font.title3.weight(.semibold)
        static let sidebarIcon = Font.system(size: 13, weight: .semibold)
        static let smallIcon = Font.system(size: 13, weight: .bold)
        static let monoLog = Font.system(size: 10, design: .monospaced)
        static let headlineSupport = Font.system(size: 15)
        static let dropTitle = Font.system(size: 20, weight: .semibold)
        static let dropCaption = Font.system(size: 14)
    }

    static let surface = Palette.surface
    static let elevated = Palette.panel
    static let subtle = Palette.separator
    static let accent = Palette.accent
    static let amber = Palette.amber
    static let rose = Palette.rose
    static let controlRadius = Radius.control
    static let panelRadius = Radius.panel
    static let sidebarWidth = Layout.sidebarWidth
}

struct AppShell<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppDesign.surface)
    }
}

struct Panel<Content: View>: View {
    var padding: CGFloat = 16
    let content: Content

    init(padding: CGFloat = 16, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .background(AppDesign.Palette.panel, in: RoundedRectangle(cornerRadius: AppDesign.Radius.panel, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppDesign.Radius.panel, style: .continuous)
                    .strokeBorder(AppDesign.Palette.separator, lineWidth: 1)
            }
    }
}

struct SidebarSurface<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .background(.thinMaterial)
            .overlay(alignment: .trailing) {
                Rectangle()
                    .fill(AppDesign.Palette.separator)
                    .frame(width: 1)
            }
    }
}

struct AppLogo: View {
    var size: CGFloat = 42
    var showShadow = false

    var body: some View {
        Image("AppIcon", bundle: .module)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
            .shadow(color: .black.opacity(showShadow ? 0.14 : 0), radius: 8, y: 3)
            .accessibilityLabel("WhisperDiarize")
    }
}

struct MetricBadge: View {
    let title: String
    let value: String
    var systemImage: String
    var tint: Color = AppDesign.accent

    var body: some View {
        HStack(spacing: AppDesign.Spacing.sm) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.86)
            }
        }
        .padding(.horizontal, AppDesign.Spacing.md)
        .padding(.vertical, AppDesign.Spacing.sm + 1)
        .frame(minWidth: 136, alignment: .leading)
        .background(AppDesign.Palette.panel, in: RoundedRectangle(cornerRadius: AppDesign.Radius.control, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppDesign.Radius.control, style: .continuous)
                .strokeBorder(AppDesign.Palette.separator, lineWidth: 1)
        }
    }
}

struct WaveformMark: View {
    var active: Bool

    private let bars: [CGFloat] = [0.24, 0.52, 0.35, 0.82, 0.46, 0.68, 0.30, 0.92, 0.58, 0.40, 0.74, 0.28, 0.63, 0.48, 0.86, 0.34]

    var body: some View {
        HStack(alignment: .center, spacing: AppDesign.Spacing.xs - 2) {
            ForEach(Array(bars.enumerated()), id: \.offset) { index, height in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(active ? AppDesign.Palette.accent : Color.secondary.opacity(0.32))
                    .frame(width: 4, height: 56 * height)
                    .animation(.easeInOut(duration: 0.16).delay(Double(index) * 0.01), value: active)
            }
        }
        .frame(height: 60)
        .accessibilityHidden(true)
    }
}

struct SettingsSection<Content: View>: View {
    let title: String
    let subtitle: String?
    let content: Content

    init(_ title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppDesign.Spacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppDesign.TypeScale.section)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Panel(padding: 0) {
                VStack(spacing: 0) {
                    content
                }
            }
        }
    }
}

struct SettingsRow<Content: View>: View {
    let title: String
    let detail: String?
    let content: Content

    init(_ title: String, detail: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.detail = detail
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .center, spacing: AppDesign.Spacing.xl) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppDesign.TypeScale.bodyLabel)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(width: AppDesign.Layout.settingsLabelWidth, alignment: .leading)

            content
                .frame(width: AppDesign.Layout.settingsControlColumnWidth, alignment: .leading)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, AppDesign.Spacing.lg)
        .padding(.vertical, AppDesign.Spacing.md)
    }
}

struct RowDivider: View {
    var body: some View {
        Divider()
            .padding(.leading, AppDesign.Spacing.lg)
    }
}

struct LanguagePicker: View {
    @Binding var selection: String

    var body: some View {
        Picker("", selection: $selection) {
            Text("Auto").tag("")
            Divider()
            Text("English").tag("en")
            Text("Chinese").tag("zh")
            Text("Spanish").tag("es")
            Text("French").tag("fr")
            Text("German").tag("de")
            Text("Japanese").tag("ja")
            Text("Korean").tag("ko")
            Text("Portuguese").tag("pt")
            Text("Italian").tag("it")
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SettingsControlFrame<Content: View>: View {
    let alignment: Alignment
    let content: Content

    init(alignment: Alignment = .leading, @ViewBuilder content: () -> Content) {
        self.alignment = alignment
        self.content = content()
    }

    var body: some View {
        content
            .frame(width: AppDesign.Layout.settingsControlWidth, alignment: alignment)
    }
}

struct SmallIconButton: View {
    let title: String
    let systemImage: String
    var role: ButtonRole?
    let action: () -> Void

    var body: some View {
        Button(role: role, action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
        }
        .help(title)
    }
}
