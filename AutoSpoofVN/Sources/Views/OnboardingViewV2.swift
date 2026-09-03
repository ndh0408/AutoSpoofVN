import SwiftUI

/// Onboarding v2 — ngắn gọn, chuyên nghiệp, 4 bước.
struct OnboardingViewV2: View {
    @AppStorage("autospoof_onboarding_completed") private var completed = false
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
                Text(step < 3 ? "Tiếp tục" : "Bắt đầu")
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
                Button("Bỏ qua") { completed = true }
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
            title: "AutoSpoof VN",
            subtitle: "GPS Simulation Studio",
            description: "Mô phỏng vị trí GPS trực tiếp trên iPhone. Không jailbreak, không cần máy tính kết nối liên tục."
        )
    }

    private var developerModeStep: some View {
        OnboardingPage(
            icon: "wrench.and.screwdriver",
            iconColor: .orange,
            title: "Bật Developer Mode",
            subtitle: "Bước bắt buộc",
            description: "Vào Settings → Privacy & Security → Developer Mode → Bật → Khởi động lại.\n\nĐây là yêu cầu của Apple để cho phép công cụ phát triển truy cập thiết bị."
        )
    }

    private var pairingStep: some View {
        VStack(spacing: AppSpacing.xl) {
            Spacer()
            Image(systemName: "link.badge.plus")
                .font(.system(size: 56))
                .foregroundStyle(.green)

            Text("Ghép nối thiết bị")
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
                        Text("Mã PIN")
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
                        Label("Bắt đầu ghép nối", systemImage: "antenna.radiowaves.left.and.right")
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
                    StatusBadge("Ghép nối thành công", color: .green, icon: "checkmark.circle.fill")
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

            Text("Sẵn sàng")
                .font(AppFont.title2.weight(.bold))

            VStack(alignment: .leading, spacing: AppSpacing.md) {
                readyItem(icon: "hand.tap", text: "Chạm bản đồ để đặt vị trí")
                readyItem(icon: "map", text: "Route Studio để tạo tuyến đường")
                readyItem(icon: "list.bullet.clipboard", text: "Scenario Studio để tự động hoá")
                readyItem(icon: "airplane", text: "Chuyến bay quốc tế với World Odyssey")
                readyItem(icon: "clock.arrow.2.circlepath", text: "Chu trình 24/7 tự động")
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
