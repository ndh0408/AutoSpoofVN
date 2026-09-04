import SwiftUI

/// Onboarding v2 — ngắn gọn, chuyên nghiệp, 4 bước.
struct OnboardingViewV2: View {
    @AppStorage("locationx_onboarding_completed") private var completed = false
    @StateObject private var pairing = SelfPairingManager.shared
    @State private var step = 0

    var body: some View {
        VStack(spacing: 0) {
            // Progress
            HStack(spacing: AppSpacing.xs) {
                ForEach(0..<4) { i in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(i <= step ? AppColor.primary : AppColor.divider)
                        .frame(height: 3)
                }
            }
            .padding(.horizontal, AppSpacing.xxxl)
            .padding(.top, AppSpacing.xl)

            TabView(selection: $step) {
                welcomeStep.tag(0)
                developerModeStep.tag(1)
                pairingStep.tag(2)
                readyStep.tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .safeAnimation(step)

            // Bottom button
            Button {
                if step < 3 {
                    withAnimation { step += 1 }
                } else {
                    completed = true
                }
            } label: {
                Text(step < 3 ? L("onboarding.continue") : L("action.start"))
                    .font(AppFont.callout.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppSpacing.lg)
                    .background(AppColor.primary)
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg))
            }
            .padding(.horizontal, AppSpacing.xxxl)
            .padding(.bottom, AppSpacing.xxxl)

            if step > 0 && step < 3 {
                Button(L("onboarding.skip")) { completed = true }
                    .font(AppFont.footnote)
                    .foregroundStyle(AppColor.textTertiary)
                    .padding(.bottom, AppSpacing.lg)
            }
        }
        .background(AppColor.surface)
    }

    // MARK: - Steps

    private var welcomeStep: some View {
        OnboardingPage(
            icon: "location.fill",
            iconColor: .blue,
            title: "LocationX",
            subtitle: "GPS Simulation Studio",
            description: L("onboarding.welcome.description")
        )
    }

    private var developerModeStep: some View {
        OnboardingPage(
            icon: "wrench.and.screwdriver",
            iconColor: .orange,
            title: L("onboarding.devmode.title"),
            subtitle: L("onboarding.devmode.subtitle"),
            description: L("onboarding.devmode.description")
        )
    }

    private var pairingStep: some View {
        VStack(spacing: AppSpacing.xl) {
            Spacer()
            Image(systemName: "link.badge.plus")
                .font(.system(size: 56))
                .foregroundStyle(.green)

            Text(L("onboarding.pairing.title"))
                .font(AppFont.title2.weight(.bold))

            // Pairing status
            VStack(spacing: AppSpacing.md) {
                HStack {
                    Circle()
                        .fill(pairingStatusColor)
                        .frame(width: 8, height: 8)
                    Text(pairing.phase.description)
                        .font(AppFont.footnote)
                        .foregroundStyle(AppColor.textSecondary)
                }

                if let pin = pairing.latestPin {
                    VStack(spacing: AppSpacing.xs) {
                        Text(L("onboarding.pairing.pin"))
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.textTertiary)
                        Text(pin)
                            .font(.system(size: 32, weight: .bold, design: .monospaced))
                            .foregroundStyle(AppColor.primary)
                    }
                    .padding(AppSpacing.lg)
                    .background(AppColor.surfaceSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg))
                }

                if !pairing.isRunning {
                    Button {
                        pairing.startAutoPairing()
                    } label: {
                        Label(L("onboarding.pairing.start"), systemImage: "antenna.radiowaves.left.and.right")
                            .font(AppFont.callout.weight(.medium))
                            .padding(.horizontal, AppSpacing.xl)
                            .padding(.vertical, AppSpacing.md)
                            .background(AppColor.primary.opacity(0.1))
                            .clipShape(Capsule())
                    }
                } else {
                    ProgressView()
                        .padding()
                }

                if case .success = pairing.phase {
                    StatusBadge(L("onboarding.pairing.success"), color: .green, icon: "checkmark.circle.fill")
                }
            }

            Spacer()
        }
        .padding(.horizontal, AppSpacing.xxxl)
    }

    private var readyStep: some View {
        VStack(spacing: AppSpacing.xl) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)

            Text(L("onboarding.ready.title"))
                .font(AppFont.title2.weight(.bold))

            VStack(alignment: .leading, spacing: AppSpacing.md) {
                readyItem(icon: "hand.tap", text: L("onboarding.ready.tap_map"))
                readyItem(icon: "map", text: L("onboarding.ready.route_studio"))
                readyItem(icon: "list.bullet.clipboard", text: L("onboarding.ready.scenario_studio"))
                readyItem(icon: "airplane", text: L("onboarding.ready.flight"))
                readyItem(icon: "clock.arrow.2.circlepath", text: L("onboarding.ready.routine"))
            }
            .padding(AppSpacing.xl)
            .background(AppColor.surfaceSecondary)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg))

            Spacer()
        }
        .padding(.horizontal, AppSpacing.xxxl)
    }

    private func readyItem(icon: String, text: String) -> some View {
        HStack(spacing: AppSpacing.md) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(AppColor.primary)
                .frame(width: 24)
            Text(text)
                .font(AppFont.footnote)
        }
    }

    private var pairingStatusColor: Color {
        switch pairing.phase {
        case .success: return .green
        case .failed: return .red
        case .idle: return .secondary
        default: return .orange
        }
    }
}

struct OnboardingPage: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    let description: String

    var body: some View {
        VStack(spacing: AppSpacing.xl) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 56))
                .foregroundStyle(iconColor)
            Text(title)
                .font(AppFont.title.weight(.bold))
            Text(subtitle)
                .font(AppFont.headline)
                .foregroundStyle(AppColor.textSecondary)
            Text(description)
                .font(AppFont.body)
                .foregroundStyle(AppColor.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, AppSpacing.xl)
            Spacer()
        }
        .padding(.horizontal, AppSpacing.xxxl)
    }
}
