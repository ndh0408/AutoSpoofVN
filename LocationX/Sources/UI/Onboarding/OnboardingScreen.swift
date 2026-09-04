import CoreLocation
import SwiftUI

/// Màn hình chào lần đầu.
///
/// Bản trước có bốn bước, trong đó hai bước dẫn người dùng đi một đường đã chết: "Bật
/// Developer Mode" và "Ghép nối thiết bị" đều thuộc về đường DVT/FFI. Sau khi bỏ FFI,
/// nút "Bắt đầu ghép nối" không bao giờ thành công — người mới cài app gặp thất bại
/// ngay ở lần mở đầu tiên.
///
/// Bản này đi đúng đường đang chạy: chọn ngôn ngữ → hiểu cơ chế → cấp quyền →
/// cài Shadowrocket → xong. Mỗi bước chỉ tiến được khi điều kiện của nó thật sự đạt,
/// hoặc người dùng chủ động bỏ qua.
struct OnboardingScreen: View {
    @AppStorage("locationx_onboarding_completed") private var completed = false
    @ObservedObject private var localization = LocalizationManager.shared
    @ObservedObject private var shadowrocket = ShadowrocketManager.shared
    @StateObject private var permissions = OnboardingPermissions()

    @State private var step: Step = .welcome

    private enum Step: Int, CaseIterable {
        case welcome, language, howItWorks, permission, proxy, ready

        var next: Step? { Step(rawValue: rawValue + 1) }
        var previous: Step? { Step(rawValue: rawValue - 1) }
    }

    var body: some View {
        VStack(spacing: 0) {
            progressBar

            ScrollView {
                content
                    .padding(.horizontal, AppSpacing.xxl)
                    .padding(.top, AppSpacing.xxl)
                    .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)

            footer
        }
        .background(AppColor.background)
        .animation(AppAnimation.smooth, value: step)
    }

    // MARK: - Thanh tiến trình

    private var progressBar: some View {
        HStack(spacing: AppSpacing.xs) {
            ForEach(Step.allCases, id: \.rawValue) { s in
                Capsule()
                    .fill(s.rawValue <= step.rawValue ? AppColor.primary : AppColor.divider)
                    .frame(height: 3)
            }
        }
        .padding(.horizontal, AppSpacing.xxl)
        .padding(.top, AppSpacing.xl)
        .accessibilityElement()
        .accessibilityLabel(L("onboarding.progress", step.rawValue + 1, Step.allCases.count))
    }

    // MARK: - Nội dung từng bước

    @ViewBuilder
    private var content: some View {
        switch step {
        case .welcome:
            OnboardingHero(icon: "location.north.circle.fill",
                           tint: AppColor.primary,
                           title: "LocationX",
                           subtitle: L("about.tagline"),
                           detail: L("onboarding.welcome.description"))

        case .language:
            VStack(spacing: AppSpacing.xl) {
                OnboardingHero(icon: "globe",
                               tint: AppColor.info,
                               title: L("language.title"),
                               subtitle: L("onboarding.language.subtitle"),
                               detail: nil)
                VStack(spacing: 0) {
                    ForEach(AppLanguage.allCases) { lang in
                        Button {
                            localization.setLanguage(lang)
                            AppHaptics.selection()
                        } label: {
                            HStack(spacing: AppSpacing.md) {
                                Image(systemName: lang.symbol)
                                    .foregroundStyle(AppColor.primary)
                                Text(lang.displayName)
                                    .font(AppFont.body)
                                    .foregroundStyle(AppColor.textPrimary)
                                Spacer()
                                if localization.language == lang {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(AppColor.primary)
                                }
                            }
                            .padding(AppSpacing.lg)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if lang != AppLanguage.allCases.last {
                            Divider().padding(.leading, AppSpacing.xxl)
                        }
                    }
                }
                .background(AppColor.surfaceSecondary,
                            in: RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
            }

        case .howItWorks:
            VStack(spacing: AppSpacing.xl) {
                OnboardingHero(icon: "arrow.triangle.branch",
                               tint: AppColor.accent,
                               title: L("onboarding.how.title"),
                               subtitle: L("onboarding.how.subtitle"),
                               detail: nil)
                VStack(alignment: .leading, spacing: AppSpacing.lg) {
                    OnboardingStepRow(number: 1, text: L("onboarding.how.step1"))
                    OnboardingStepRow(number: 2, text: L("onboarding.how.step2"))
                    OnboardingStepRow(number: 3, text: L("onboarding.how.step3"))
                }
                .padding(AppSpacing.xl)
                .background(AppColor.surfaceSecondary,
                            in: RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))

                Label(L("onboarding.how.note"), systemImage: "info.circle")
                    .font(AppFont.caption1)
                    .foregroundStyle(AppColor.textSecondary)
                    .multilineTextAlignment(.leading)
            }

        case .permission:
            VStack(spacing: AppSpacing.xl) {
                OnboardingHero(icon: "location.circle.fill",
                               tint: AppColor.success,
                               title: L("onboarding.permission.title"),
                               subtitle: L("onboarding.permission.subtitle"),
                               detail: L("onboarding.permission.description"))

                if permissions.status == .notDetermined {
                    Button(L("onboarding.permission.grant")) {
                        permissions.request()
                    }
                    .buttonStyle(OnboardingPrimaryButtonStyle())
                } else {
                    StatusBadge(permissions.summary,
                                color: permissions.isSufficient ? AppColor.success : AppColor.warning,
                                icon: permissions.isSufficient ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    if !permissions.isSufficient {
                        Button(L("onboarding.permission.open_settings")) {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                        .buttonStyle(OnboardingSecondaryButtonStyle())
                    }
                }
            }

        case .proxy:
            VStack(spacing: AppSpacing.xl) {
                OnboardingHero(icon: "bolt.horizontal.circle.fill",
                               tint: shadowrocket.isInstalled ? AppColor.success : AppColor.warning,
                               title: "Shadowrocket",
                               subtitle: L("onboarding.proxy.subtitle"),
                               detail: L("onboarding.proxy.description"))

                StatusBadge(shadowrocket.isInstalled ? L("common.installed") : L("common.not_installed"),
                            color: shadowrocket.isInstalled ? AppColor.success : AppColor.warning,
                            icon: shadowrocket.isInstalled ? "checkmark.circle.fill" : "arrow.down.circle")

                if !shadowrocket.isInstalled {
                    Button(L("onboarding.proxy.install")) {
                        shadowrocket.openAppStore()
                    }
                    .buttonStyle(OnboardingPrimaryButtonStyle())
                }

                Text(L("onboarding.proxy.later"))
                    .font(AppFont.caption1)
                    .foregroundStyle(AppColor.textSecondary)
                    .multilineTextAlignment(.center)
            }

        case .ready:
            VStack(spacing: AppSpacing.xl) {
                OnboardingHero(icon: "checkmark.circle.fill",
                               tint: AppColor.success,
                               title: L("onboarding.ready.title"),
                               subtitle: L("onboarding.ready.subtitle"),
                               detail: nil)
                VStack(alignment: .leading, spacing: AppSpacing.lg) {
                    OnboardingFeatureRow(icon: "hand.tap.fill", text: L("onboarding.ready.tap_map"))
                    OnboardingFeatureRow(icon: "point.topleft.down.to.point.bottomright.curvepath.fill",
                                         text: L("onboarding.ready.route_studio"))
                    OnboardingFeatureRow(icon: "list.bullet.clipboard.fill",
                                         text: L("onboarding.ready.scenario_studio"))
                    OnboardingFeatureRow(icon: "airplane", text: L("onboarding.ready.flight"))
                    OnboardingFeatureRow(icon: "clock.arrow.2.circlepath", text: L("onboarding.ready.routine"))
                }
                .padding(AppSpacing.xl)
                .background(AppColor.surfaceSecondary,
                            in: RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
            }
        }
    }

    // MARK: - Điều hướng

    private var footer: some View {
        VStack(spacing: AppSpacing.md) {
            Button(step == .ready ? L("action.start") : L("onboarding.continue")) {
                if let next = step.next {
                    step = next
                } else {
                    AppHaptics.success()
                    completed = true
                }
            }
            .buttonStyle(OnboardingPrimaryButtonStyle())

            if let previous = step.previous {
                HStack(spacing: AppSpacing.xl) {
                    Button(L("action.back")) { step = previous }
                    if step != .ready {
                        Button(L("onboarding.skip")) { completed = true }
                    }
                }
                .font(AppFont.footnote)
                .foregroundStyle(AppColor.textTertiary)
            }
        }
        .padding(.horizontal, AppSpacing.xxl)
        .padding(.top, AppSpacing.lg)
        .padding(.bottom, AppSpacing.xxl)
    }
}

// MARK: - Thành phần dùng lại

private struct OnboardingHero: View {
    let icon: String
    let tint: Color
    let title: String
    let subtitle: String
    /// Không được đặt tên là `body`: nó sẽ trùng với `body` của `View`.
    let detail: String?

    var body: some View {
        VStack(spacing: AppSpacing.md) {
            Image(systemName: icon)
                .font(.system(size: 56))
                .foregroundStyle(tint)
                .padding(.bottom, AppSpacing.xs)
            Text(title)
                .font(AppFont.title.weight(.bold))
                .multilineTextAlignment(.center)
            Text(subtitle)
                .font(AppFont.headline)
                .foregroundStyle(AppColor.textSecondary)
                .multilineTextAlignment(.center)
            if let detail {
                Text(detail)
                    .font(AppFont.callout)
                    .foregroundStyle(AppColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, AppSpacing.xs)
            }
        }
    }
}

private struct OnboardingStepRow: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.md) {
            Text("\(number)")
                .font(AppFont.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(AppColor.primary, in: Circle())
            Text(text)
                .font(AppFont.footnote)
                .foregroundStyle(AppColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct OnboardingFeatureRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: AppSpacing.md) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(AppColor.primary)
                .frame(width: 24)
            Text(text)
                .font(AppFont.footnote)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct OnboardingPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppFont.callout.weight(.semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppSpacing.lg)
            .background(AppColor.primary.opacity(configuration.isPressed ? 0.8 : 1),
                        in: RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
    }
}

private struct OnboardingSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppFont.callout.weight(.medium))
            .foregroundStyle(AppColor.primary)
            .padding(.horizontal, AppSpacing.xl)
            .padding(.vertical, AppSpacing.md)
            .background(AppColor.primary.opacity(configuration.isPressed ? 0.2 : 0.12),
                        in: Capsule())
    }
}

// MARK: - Quyền vị trí

/// Xin quyền vị trí ngay trong onboarding.
///
/// App cần quyền này cho hai việc thật: vẽ vị trí thật của bạn trên bản đồ, và giữ tiến
/// trình sống khi chạy nền (`BackgroundKeeper` bật `allowsBackgroundLocationUpdates`).
/// Trước đây app chỉ xin quyền lúc người dùng tình cờ chạm đúng nút, nên phần chạy nền
/// hay im lặng không hoạt động.
@MainActor
final class OnboardingPermissions: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var status: CLAuthorizationStatus

    private let manager = CLLocationManager()

    override init() {
        status = manager.authorizationStatus
        super.init()
        manager.delegate = self
    }

    func request() {
        manager.requestWhenInUseAuthorization()
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let new = manager.authorizationStatus
        Task { @MainActor in self.status = new }
    }

    var isSufficient: Bool {
        status == .authorizedAlways || status == .authorizedWhenInUse
    }

    var summary: String {
        switch status {
        case .authorizedAlways:    return L("permission.always")
        case .authorizedWhenInUse: return L("permission.when_in_use")
        case .denied:              return L("permission.denied")
        case .restricted:          return L("permission.restricted")
        default:                   return L("permission.not_determined")
        }
    }
}
