//
//  AppTheme.swift
//  AutoSpoofVN
//
//  Apple-native developer studio design system: cards, badges, materials, typography, and accessibility.
//

import SwiftUI

public enum AppTheme {
    public static let accentColor = Color.blue
    public static let successColor = Color.green
    public static let warningColor = Color.orange
    public static let errorColor = Color.red

    public static let cornerRadiusSmall: CGFloat = 8.0
    public static let cornerRadiusMedium: CGFloat = 14.0
    public static let cornerRadiusLarge: CGFloat = 20.0
}

public struct StudioCard<Content: View>: View {
    private let content: Content
    private let padding: CGFloat

    public init(padding: CGFloat = 14, @ViewBuilder content: () -> Content) {
        self.content = content()
        self.padding = padding
    }

    public var body: some View {
        content
            .padding(padding)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium, style: .continuous))
            .shadow(color: Color.black.opacity(0.06), radius: 6, x: 0, y: 3)
    }
}

public struct StatusBadge: View {
    let title: String
    let icon: String?
    let color: Color

    public init(title: String, icon: String? = nil, color: Color = .green) {
        self.title = title
        self.icon = icon
        self.color = color
    }

    public var body: some View {
        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon)
                    .font(.caption2.weight(.bold))
            } else {
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)
            }
            Text(title)
                .font(.caption2.weight(.semibold))
        }
        .foregroundColor(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(color.opacity(0.12)))
    }
}

public struct TelemetryMetricView: View {
    let title: String
    let value: String
    let unit: String?
    let icon: String
    let color: Color

    public init(title: String, value: String, unit: String? = nil, icon: String, color: Color = .blue) {
        self.title = title
        self.value = value
        self.unit = unit
        self.icon = icon
        self.color = color
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption2)
                    .foregroundColor(color)
                Text(title)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .foregroundColor(.primary)
                if let unit {
                    Text(unit)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}
