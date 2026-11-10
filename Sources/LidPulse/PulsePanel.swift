import AppKit
import ServiceManagement
import SwiftUI

@MainActor
enum MenuGlyph {
    static let image: NSImage = {
        let logo = NSImage(systemSymbolName: "apple.logo", accessibilityDescription: "LidPulse")?
            .withSymbolConfiguration(.init(pointSize: 12, weight: .semibold))
        let glyph = NSImage(size: NSSize(width: 23, height: 19), flipped: false) { _ in
            let center = NSPoint(x: 11.5, y: 9.3)
            if let logo {
                logo.draw(in: NSRect(x: center.x - logo.size.width / 2, y: center.y - logo.size.height / 2,
                                     width: logo.size.width, height: logo.size.height))
            }
            NSColor.black.setStroke()
            let rays = NSBezierPath()
            rays.lineWidth = 0.9
            rays.lineCapStyle = .round
            for (degrees, start, end) in [(0.0, 7.1, 10.1), (40, 7.7, 10.1), (140, 7.7, 10.1),
                                          (180, 7.1, 10.1), (220, 7.7, 10.1), (320, 7.7, 10.1)] {
                let angle = degrees * .pi / 180
                rays.move(to: NSPoint(x: center.x + cos(angle) * start, y: center.y + sin(angle) * start))
                rays.line(to: NSPoint(x: center.x + cos(angle) * end, y: center.y + sin(angle) * end))
            }
            rays.stroke()
            return true
        }
        glyph.isTemplate = true
        return glyph
    }()
}

struct PulsePanel: View {
    @Bindable var model: LidModel
    let openSettings: () -> Void

    private var language: Language { model.language }
    private var active: Bool { model.mode != .system && model.mode != .dark }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            LidPreview(level: model.output, mode: model.mode)
            Divider()
            Text(language.text("模式", "Mode")).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            ModePicker(selected: model.mode, available: model.supported, language: language, select: model.select)
            tuning
            if let message = model.message {
                Label(message, systemImage: "info.circle")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            actions
        }
        .padding(15)
        .frame(width: 332)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .center)
        .environment(\.locale, language.locale)
        .onAppear { model.refresh() }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("LidPulse").font(.system(size: 16, weight: .semibold))
                Text(model.summary).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Toggle(language.text("啟用 LidPulse", "Enable LidPulse"), isOn: Binding(get: { active }, set: model.setEnabled))
                .toggleStyle(.switch)
                .labelsHidden()
                .disabled(!model.supported || model.changingLimit)
        }
    }

    private var tuning: some View {
        VStack(spacing: 7) {
            HStack(spacing: 8) {
                Image(systemName: "sun.min").accessibilityHidden(true)
                NativeSlider(value: $model.brightness, range: 0.01...1,
                             label: language.text("Logo 亮度", "Logo brightness"))
                Image(systemName: "sun.max").accessibilityHidden(true)
                Text(model.brightness, format: .percent.precision(.fractionLength(0)))
                    .monospacedDigit()
                    .frame(width: 31, alignment: .trailing)
            }
            .disabled(!model.supported || model.mode == .dark)
            if model.mode == .breathe {
                HStack(spacing: 8) {
                    let label = language.text("呼吸週期", "Breathing period")
                    Text(label)
                    Text(language.text("快", "Fast"))
                    NativeSlider(value: $model.breathePeriod, range: 2...9, label: label)
                    Text(language.text("慢", "Slow"))
                }
            }
            if model.mode == .music {
                HStack(spacing: 8) {
                    let label = language.text("節拍強度", "Beat intensity")
                    Text(label)
                    Text(language.text("弱", "Soft"))
                    NativeSlider(value: $model.musicSensitivity, range: 0...1, label: label)
                    Text(language.text("強", "Strong"))
                }
                Toggle(language.text("節拍之間熄燈", "Dark between beats"), isOn: $model.darkBetweenBeats)
                    .toggleStyle(.checkbox)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if model.mode == .agents {
                Text(language.text("喺設定連接 Claude Code 或 Codex。", "Connect Claude Code or Codex in Settings."))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 9) {
            actionSwitch(language.text("Logo 燈", "Logo Light"),
                         isOn: Binding(get: { model.mode != .dark },
                                       set: { model.select($0 ? .system : .dark) }))
            .disabled(!model.supported || model.changingLimit)
            if model.supportsClosedLid {
                actionSwitch(language.text("合蓋時保持 Logo 發光", "Keep Logo Lit With Lid Closed"),
                             isOn: Binding(get: { model.keepLogoWhenLidClosed }, set: model.setKeepLogoWhenLidClosed))
                .help(language.text("Mac 仲醒住時，合蓋後沿用目前模式同亮度。關閉開關後，合蓋會熄燈。",
                                    "Continues the selected mode and brightness with the lid closed while your Mac is awake. Turn this off to let the logo go dark on closing."))
            }
            Button(language.text("設定…", "Settings…"), action: openSettings)
                .keyboardShortcut(",", modifiers: .command)
            Button(language.text("退出 LidPulse", "Quit LidPulse")) { NSApp.terminate(nil) }
                .keyboardShortcut("q", modifiers: .command)
        }
        .buttonStyle(.borderless)
        .font(.system(size: 13))
    }

    private func actionSwitch(_ label: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(label).accessibilityHidden(true)
            Spacer(minLength: 8)
            Toggle(label, isOn: isOn)
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
        }
    }
}

private struct ModePicker: View {
    static let modes: [LidMode] = [.steady, .breathe, .music, .agents]
    let selected: LidMode
    let available: Bool
    let language: Language
    let select: (LidMode) -> Void

    var body: some View {
        if #available(macOS 26, *) {
            GlassEffectContainer(spacing: 4) { row }
        } else {
            row
        }
    }

    private var row: some View {
        HStack(spacing: 6) {
            ForEach(Self.modes) { mode in
                Button { select(mode) } label: {
                    tile(mode)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected == mode ? .isSelected : [])
                .disabled(!available)
            }
        }
    }

    private func tile(_ mode: LidMode) -> some View {
        let active = selected == mode
        return VStack(spacing: 6) {
            Image(systemName: mode.icon)
                .font(.system(size: 15, weight: .medium))
                .frame(width: 29, height: 29)
                .background(.primary.opacity(0.07), in: Circle())
                .accessibilityHidden(true)
            Text(mode.title(language)).font(.system(size: 11, weight: .semibold)).lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 65)
        .contentShape(RoundedRectangle(cornerRadius: 15))
        .modifier(ModeGlass(active: active))
    }
}

private struct ModeGlass: ViewModifier {
    let active: Bool

    @ViewBuilder func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content.glassEffect(.regular.tint(active ? .accentColor.opacity(0.37) : nil).interactive(),
                                in: .rect(cornerRadius: 15))
        } else {
            content.background(active ? Color.accentColor.opacity(0.20) : Color.primary.opacity(0.07),
                               in: RoundedRectangle(cornerRadius: 15))
        }
    }
}

private struct LidPreview: View {
    let level: Double
    let mode: LidMode

    var body: some View {
        let light = mode == .system ? 0.34 : sqrt(max(0, level))
        let shape = RoundedRectangle(cornerRadius: 15)
        ZStack {
            shape.fill(LinearGradient(colors: [Color(white: 0.105), Color(white: 0.039)],
                                      startPoint: .topLeading, endPoint: .bottomTrailing))
            RadialGradient(colors: [.white.opacity(light * 0.23), .white.opacity(light * 0.05), .clear],
                           center: .center, startRadius: 9, endRadius: 91)
            Image(systemName: "apple.logo")
                .font(.system(size: 41, weight: .medium))
                .foregroundStyle(.white.opacity(0.14 + light * 0.86))
                .shadow(color: .white.opacity(light * 0.66), radius: 12)
        }
        .frame(height: 128)
        .clipShape(shape)
        .overlay(shape.strokeBorder(.white.opacity(0.11), lineWidth: 1))
        .accessibilityHidden(true)
    }
}
