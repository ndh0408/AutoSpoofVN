import SwiftUI

// MARK: - EmptyStateView

/// Trang thai rong. API giu nguyen tu ban dau (4 file dang dung).
struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    let actionTitle: String?
    let action: (() -> Void)?

    init(icon: String, title: String, message: String,
         actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.icon = icon
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        VStack(spacing: AppSpacing.lg) {
            Image(systemName: icon)
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(AppColor.textTertiary)
                .accessibilityHidden(true)

            VStack(spacing: AppSpacing.sm) {
                Text(title)
                    .font(AppFont.headlineEmphasized)
                    .foregroundStyle(AppColor.textPrimary)
                Text(message)
                    .font(AppFont.footnote)
                    .foregroundStyle(AppColor.textSecondary)
                    .multilineTextAlignment(.center)
            }

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(PrimaryButtonStyle(size: .compact))
            }
        }
        .padding(AppSpacing.xxxl)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }
}

// MARK: - ErrorState

/// Trang thai loi toan man hinh, kem hanh dong khac phuc.
struct ErrorState: View {
    let title: String
    let message: String
    var suggestion: String?
    var retryTitle: String = L10n.retry
    var onRetry: (() -> Void)?
    var onDiagnostics: (() -> Void)?

    var body: some View {
        VStack(spacing: AppSpacing.lg) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36))
                .foregroundStyle(AppColor.warning)
                .accessibilityHidden(true)

            VStack(spacing: AppSpacing.sm) {
                Text(title)
                    .font(AppFont.headlineEmphasized)
                    .foregroundStyle(AppColor.textPrimary)
                Text(message)
                    .font(AppFont.footnote)
                    .foregroundStyle(AppColor.textSecondary)
                    .multilineTextAlignment(.center)
                if let suggestion {
                    Text(suggestion)
                        .font(AppFont.caption1)
                        .foregroundStyle(AppColor.textTertiary)
                        .multilineTextAlignment(.center)
                }
            }

            HStack(spacing: AppSpacing.md) {
                if let onRetry {
                    Button(retryTitle, action: onRetry)
                        .buttonStyle(PrimaryButtonStyle(size: .compact))
                }
                if let onDiagnostics {
                    Button(L10n.diagnostics, action: onDiagnostics)
                        .buttonStyle(SecondaryButtonStyle(size: .compact))
                }
            }
        }
        .padding(AppSpacing.xxxl)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - LoadingState

/// Dang tai. Luon co nhan chu: mot vong xoay khong noi cho nguoi dung dieu gi dang cho.
struct LoadingState: View {
    var message: String = "Đang tải…"

    var body: some View {
        VStack(spacing: AppSpacing.md) {
            ProgressView()
                .controlSize(.large)
            Text(message)
                .font(AppFont.footnote)
                .foregroundStyle(AppColor.textSecondary)
        }
        .padding(AppSpacing.xxxl)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message)
    }
}

// MARK: - ErrorBanner

/// Bang loi inline. API giu nguyen tu ban dau.
struct ErrorBanner: View {
    let message: String
    let suggestion: String?
    let retryAction: (() -> Void)?
    let diagnosticsAction: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack(alignment: .top, spacing: AppSpacing.sm) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(AppColor.warning)
                Text(message)
                    .font(AppFont.footnote)
                    .foregroundStyle(AppColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let suggestion {
                Text(suggestion)
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if retryAction != nil || diagnosticsAction != nil {
                HStack(spacing: AppSpacing.lg) {
                    if let retryAction {
                        Button(L10n.retry, action: retryAction)
                            .font(AppFont.footnoteEmphasized)
                    }
                    if let diagnosticsAction {
                        Button(L10n.diagnostics, action: diagnosticsAction)
                            .font(AppFont.footnote)
                            .foregroundStyle(AppColor.textSecondary)
                    }
                }
            }
        }
        .padding(AppSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColor.warning.opacity(0.1),
                    in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
        .accessibilityElement(children: .contain)
    }
}

// MARK: - ScalableText

/// Text co gioi han bac Dynamic Type. API giu nguyen tu ban dau.
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

#Preview("States") {
    ScrollView {
        VStack(spacing: AppSpacing.xxl) {
            EmptyStateView(icon: "map", title: L10n.noRoutes,
                           message: L10n.noRoutesMessage, actionTitle: L10n.createRoute) {}
            ErrorState(title: "Không kết nối được thiết bị",
                       message: "Không mở được kênh DVT qua loopback.",
                       suggestion: "Kiểm tra Developer Mode và VPN loopback.",
                       onRetry: {}, onDiagnostics: {})
            LoadingState(message: "Đang tính tuyến…")
            ErrorBanner(message: "Thiếu thư viện FFI",
                        suggestion: "Bản build này chưa có libidevice_ffi.a.",
                        retryAction: {}, diagnosticsAction: {})
        }
        .padding()
    }
}
