import SwiftUI

/// Accessibility extensions — VoiceOver, Dynamic Type, Reduce Motion support.
extension View {
    /// Thêm accessibility label + hint cho icon-only buttons.
    func accessibleButton(label: String, hint: String = "") -> some View {
        self.accessibilityLabel(label)
            .accessibilityHint(hint)
            .accessibilityAddTraits(.isButton)
    }

    /// Animation có tôn trọng Reduce Motion.
    func safeAnimation<V: Equatable>(_ value: V, _ animation: Animation = .easeInOut) -> some View {
        self.animation(UIAccessibility.isReduceMotionEnabled ? nil : animation, value: value)
    }
}

/// Accessible metric — VoiceOver đọc được giá trị telemetry.
struct AccessibleMetric: View {
    let label: String
    let value: String
    let unit: String

    var body: some View {
        MetricView(label, value: value, unit: unit)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(label): \(value) \(unit)")
    }
}

/// Dynamic Type support — đảm bảo text scale đúng.
struct ScalableText: View {
    let text: String
    let style: Font.TextStyle

    init(_ text: String, style: Font.TextStyle = .body) {
        self.text = text
        self.style = style
    }

    var body: some View {
        Text(text)
            .font(.system(style))
            .dynamicTypeSize(.xSmall ... .accessibility3)
    }
}
