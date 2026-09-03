import SwiftUI

// MARK: - Design System (inspired by Impeccable)

/// Token màu sắc — hệ thống phẳng, developer-tool, Apple-native.
enum AppColor {
    static let primary = Color.blue
    static let accent = Color.indigo
    static let success = Color.green
    static let warning = Color.orange
    static let danger = Color.red

    static let surface = Color(.systemBackground)
    static let surfaceSecondary = Color(.secondarySystemBackground)
    static let surfaceTertiary = Color(.tertiarySystemBackground)

    static let textPrimary = Color(.label)
    static let textSecondary = Color(.secondaryLabel)
    static let textTertiary = Color(.tertiaryLabel)

    static let divider = Color(.separator)
    static let overlay = Color.black.opacity(0.3)

    // Status colors
    static let connected = Color.green
    static let disconnected = Color(.secondaryLabel)
    static let simulating = Color.blue
    static let paused = Color.orange
    static let error = Color.red
}

/// Token spacing.
enum AppSpacing {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 24
    static let xxxl: CGFloat = 32
}

/// Token typography.
enum AppFont {
    static let caption = Font.caption2
    static let footnote = Font.footnote
    static let body = Font.body
    static let callout = Font.callout
    static let headline = Font.headline
    static let title3 = Font.title3
    static let title2 = Font.title2
    static let title = Font.title

    static let mono = Font.system(.caption, design: .monospaced)
    static let monoBody = Font.system(.body, design: .monospaced)
}

/// Token border radius.
enum AppRadius {
    static let sm: CGFloat = 6
    static let md: CGFloat = 10
    static let lg: CGFloat = 14
    static let xl: CGFloat = 20
    static let full: CGFloat = 100
}

// MARK: - Reusable Components

/// Status badge — hiện trạng thái nhỏ gọn.
struct StatusBadge: View {
    let text: String
    let color: Color
    let icon: String?

    init(_ text: String, color: Color = .green, icon: String? = nil) {
        self.text = text
        self.color = color
        self.icon = icon
    }

    var body: some View {
        HStack(spacing: AppSpacing.xs) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 8))
            } else {
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)
            }
            Text(text)
                .font(AppFont.caption)
                .foregroundStyle(color)
        }
        .padding(.horizontal, AppSpacing.sm)
        .padding(.vertical, AppSpacing.xs)
        .background(color.opacity(0.12), in: Capsule())
    }
}

/// Card component.
struct AppCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(AppSpacing.lg)
            .background(AppColor.surfaceSecondary)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg))
    }
}

/// Metric display — số liệu telemetry.
struct MetricView: View {
    let label: String
    let value: String
    let unit: String?
    let icon: String?

    init(_ label: String, value: String, unit: String? = nil, icon: String? = nil) {
        self.label = label
        self.value = value
        self.unit = unit
        self.icon = icon
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xxs) {
            HStack(spacing: AppSpacing.xs) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 10))
                        .foregroundStyle(AppColor.textTertiary)
                }
                Text(label)
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textTertiary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(AppFont.headline)
                    .foregroundStyle(AppColor.textPrimary)
                if let unit {
                    Text(unit)
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textSecondary)
                }
            }
        }
    }
}

/// Empty state view.
struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    let actionTitle: String?
    let action: (() -> Void)?

    init(icon: String, title: String, message: String, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.icon = icon
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        VStack(spacing: AppSpacing.lg) {
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundStyle(AppColor.textTertiary)

            VStack(spacing: AppSpacing.sm) {
                Text(title)
                    .font(AppFont.headline)
                    .foregroundStyle(AppColor.textPrimary)
                Text(message)
                    .font(AppFont.footnote)
                    .foregroundStyle(AppColor.textSecondary)
                    .multilineTextAlignment(.center)
            }

            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(AppFont.callout.weight(.medium))
                        .padding(.horizontal, AppSpacing.xl)
                        .padding(.vertical, AppSpacing.md)
                        .background(AppColor.primary)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                }
            }
        }
        .padding(AppSpacing.xxxl)
    }
}

/// Error banner.
struct ErrorBanner: View {
    let message: String
    let suggestion: String?
    let retryAction: (() -> Void)?
    let diagnosticsAction: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(AppColor.warning)
                Text(message)
                    .font(AppFont.footnote)
                    .foregroundStyle(AppColor.textPrimary)
            }

            if let suggestion {
                Text(suggestion)
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
            }

            HStack(spacing: AppSpacing.md) {
                if let retryAction {
                    Button("Thử lại", action: retryAction)
                        .font(AppFont.footnote.weight(.medium))
                }
                if let diagnosticsAction {
                    Button("Chẩn đoán", action: diagnosticsAction)
                        .font(AppFont.footnote)
                        .foregroundStyle(AppColor.textSecondary)
                }
            }
        }
        .padding(AppSpacing.md)
        .background(AppColor.warning.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))
    }
}

// MARK: - Localization Keys (Architecture)

/// String keys cho localization — chưa đa ngôn ngữ nhưng đặt nền.
enum L10n {
    // Simulation
    static let simulationRunning = "Đang mô phỏng"
    static let simulationPaused = "Tạm dừng"
    static let simulationIdle = "Sẵn sàng"

    // Device
    static let deviceConnected = "Đã kết nối"
    static let deviceDisconnected = "Chưa kết nối"

    // Route
    static let routeDistance = "Khoảng cách"
    static let routeETA = "Dự kiến đến"
    static let routeSource = "Nguồn tuyến"

    // Actions
    static let start = "Bắt đầu"
    static let stop = "Dừng"
    static let pause = "Tạm dừng"
    static let resume = "Tiếp tục"
    static let retry = "Thử lại"
    static let diagnostics = "Chẩn đoán"

    // Empty states
    static let noRoutes = "Chưa có tuyến đường"
    static let noRoutesMessage = "Tạo tuyến đường đầu tiên để bắt đầu mô phỏng."
    static let createRoute = "Tạo tuyến"
    static let noDevice = "Chưa kết nối thiết bị"
    static let noDeviceMessage = "Ghép nối iPhone để bắt đầu mô phỏng GPS."
}
