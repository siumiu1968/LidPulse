import AppKit
import SwiftUI

/// Lets macOS draw the track, thumb, focus ring, and drag effect.
struct NativeSlider: NSViewRepresentable {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let label: String

    func makeNSView(context: Context) -> NSSlider {
        let slider = NSSlider(value: value, minValue: range.lowerBound, maxValue: range.upperBound,
                              target: context.coordinator, action: #selector(Coordinator.changed(_:)))
        slider.controlSize = .small
        slider.isContinuous = true
        return slider
    }

    func updateNSView(_ slider: NSSlider, context: Context) {
        context.coordinator.value = $value
        slider.isEnabled = context.environment.isEnabled
        slider.setAccessibilityLabel(label)
        if slider.doubleValue != value { slider.doubleValue = value }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSSlider, context: Context) -> CGSize? {
        let size = nsView.intrinsicContentSize
        return CGSize(width: proposal.width ?? max(100, size.width), height: size.height)
    }

    func makeCoordinator() -> Coordinator { Coordinator(value: $value) }

    @MainActor final class Coordinator: NSObject {
        var value: Binding<Double>

        init(value: Binding<Double>) {
            self.value = value
        }

        @objc func changed(_ slider: NSSlider) {
            if value.wrappedValue != slider.doubleValue {
                value.wrappedValue = slider.doubleValue
            }
        }
    }
}
