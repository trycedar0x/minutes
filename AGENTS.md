# AGENTS.md

## Native Apple UI Guidelines

Use Apple Human Interface Guidelines as the baseline for this app's SwiftUI design.

- Prefer system materials and subtle separators over large custom gray blocks. Sidebars and control regions should feel like functional layers above content, not unrelated colored panels.
- Use visual hierarchy through spacing, alignment, typography, and material. Avoid using background color as the main organizing device unless it matches a system surface.
- Keep controls grouped by task and aligned for scanning. Labels should be short, direct, and consistent across the main window and Settings.
- Use the app icon as the brand mark where a screen needs identity. Avoid swapping in unrelated SF Symbols for the app identity.
- Keep content areas visually dominant. Navigation, settings, and status surfaces should support the workflow without competing with the drop zone or transcript.
- Use semantic system colors and materials so light/dark mode and accessibility settings remain coherent.
- Prefer concise copy: name the action or setting, then add a short detail only when it prevents confusion.

References:
- Apple HIG Layout: https://developer.apple.com/design/human-interface-guidelines/layout
- Apple HIG Materials: https://developer.apple.com/design/human-interface-guidelines/materials
- Apple HIG Sidebars: https://developer.apple.com/design/Human-Interface-Guidelines/sidebars
