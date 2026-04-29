import SwiftUI

struct TailToolbar: ToolbarContent {
    @ObservedObject var controller: WindowController
    @AppStorage("TailGui.appearance") private var appearanceRaw: String = AppearanceMode.system.rawValue
    @State private var showOpacityPopover = false

    var body: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                cycleAppearance()
            } label: {
                Image(systemName: appearanceSymbol)
            }
            .help(appearanceTooltip)
            .keyboardShortcut("d", modifiers: [.command, .shift])
        }

        ToolbarItem(placement: .primaryAction) {
            Button {
                showOpacityPopover.toggle()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: opacitySymbol)
                    Text("\(Int((controller.alpha * 100).rounded()))%")
                        .font(.caption)
                        .monospacedDigit()
                }
            }
            .help("Window transparency")
            .popover(isPresented: $showOpacityPopover, arrowEdge: .bottom) {
                OpacityPopover(controller: controller)
                    .frame(width: 220)
                    .padding(14)
            }
        }

        ToolbarItem(placement: .primaryAction) {
            Toggle(isOn: $controller.isPinned) {
                Label(
                    controller.isPinned ? "Unpin" : "Pin on top",
                    systemImage: controller.isPinned ? "pin.fill" : "pin"
                )
            }
            .toggleStyle(.button)
            .keyboardShortcut("p", modifiers: [.command])
            .help(controller.isPinned ? "Stop floating above other apps (⌘P)" : "Float above other apps (⌘P)")
        }
    }

    private var opacitySymbol: String {
        let a = controller.alpha
        if a >= 0.95 { return "circle.fill" }
        if a >= 0.6 { return "circle.lefthalf.filled" }
        return "circle.dotted"
    }

    private var appearance: AppearanceMode {
        AppearanceMode(rawValue: appearanceRaw) ?? .system
    }

    private var appearanceSymbol: String {
        switch appearance {
        case .system: return "circle.dashed"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }

    private var appearanceTooltip: String {
        switch appearance {
        case .system: return "Appearance: System (⇧⌘D)"
        case .light: return "Appearance: Light (⇧⌘D)"
        case .dark: return "Appearance: Dark (⇧⌘D)"
        }
    }

    private func cycleAppearance() {
        let next: AppearanceMode
        switch appearance {
        case .system: next = .light
        case .light: next = .dark
        case .dark: next = .system
        }
        appearanceRaw = next.rawValue
    }
}

struct OpacityPopover: View {
    @ObservedObject var controller: WindowController

    private let presets: [Double] = [1.0, 0.85, 0.7, 0.5, 0.35]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Transparency", systemImage: "circle.lefthalf.filled")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(Int((controller.alpha * 100).rounded()))%")
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Slider(value: $controller.alpha, in: 0.3...1.0, step: 0.05)
                .controlSize(.small)

            HStack(spacing: 6) {
                ForEach(presets, id: \.self) { preset in
                    Button {
                        withAnimation(.easeOut(duration: 0.15)) {
                            controller.alpha = preset
                        }
                    } label: {
                        Text("\(Int(preset * 100))")
                            .font(.caption.weight(.medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.borderless)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(isActive(preset) ? Color.accentColor.opacity(0.25) : Color.secondary.opacity(0.12))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(isActive(preset) ? Color.accentColor.opacity(0.6) : Color.clear, lineWidth: 1)
                    )
                }
            }
        }
    }

    private func isActive(_ preset: Double) -> Bool {
        abs(controller.alpha - preset) < 0.02
    }
}
