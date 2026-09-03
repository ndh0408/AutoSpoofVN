import SwiftUI

/// Thanh trang thai noi tren dinh ban do.
///
/// Ba tin hieu, doc tu trai sang phai: **dang lam gi** (trang thai mo phong),
/// **ai dieu khien** (nguon), **duong xuong thiet bi con khong** (ket noi).
/// Ca ba deu doc thang tu `SimulationCoordinator` — khong co ban sao trang thai nao o day.
///
/// Nguyen tac tiep can: moi trang thai deu co **icon + chu + mau**, khong bao gio chi mau.
struct SimulationStatusBar: View {
    @ObservedObject var coordinator: SimulationCoordinator
    /// Cham vao thanh -> mo chan doan.
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: AppSpacing.sm) {
                statusCluster

                if let source = coordinator.activeSource, coordinator.state.isActive {
                    HairlineVertical()
                    Label(source.displayName, systemImage: source.icon)
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.accent)
                        .lineLimit(1)
                        .layoutPriority(-1)
                }

                Spacer(minLength: AppSpacing.xs)

                HairlineVertical()
                connectionCluster
            }
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, AppSpacing.sm)
            .frame(minHeight: 38)
            .glassCapsule(material: AppMaterial.bar)
            .contentShape(Capsule())
        }
        .buttonStyle(.pressable)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
        .accessibilityHint("Mở chẩn đoán hệ thống")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Cum trang thai mo phong

    private var statusCluster: some View {
        HStack(spacing: AppSpacing.xs) {
            StatusIndicatorDot(color: statusTint, isPulsing: coordinator.state == .running)
            Text(statusText)
                .font(AppFont.caption.weight(.medium))
                .foregroundStyle(statusTint)
                .lineLimit(1)
        }
    }

    /// Nhan trang thai gop ca mo phong lan ket noi, dung dung tu ma brief yeu cau.
    private var statusText: String {
        if coordinator.isHalted { return "GPS thật" }
        switch coordinator.state {
        case .running:   return "Đang spoof"
        case .paused:    return "Tạm dừng"
        case .stopping:  return "Đang dừng"
        case .preparing: return "Đang chuẩn bị"
        case .failed:    return "Lỗi"
        case .completed: return "Hoàn thành"
        case .idle:      return "Sẵn sàng"
        }
    }

    private var statusTint: Color {
        coordinator.isHalted ? AppColor.warning : coordinator.state.tint
    }

    // MARK: - Cum ket noi

    private var connectionCluster: some View {
        HStack(spacing: AppSpacing.xs) {
            Image(systemName: coordinator.deviceState.icon)
                .font(.system(size: 11, weight: .medium))
            Text(connectionText)
                .font(AppFont.caption)
                .lineLimit(1)
        }
        .foregroundStyle(coordinator.deviceState.tint)
    }

    private var connectionText: String {
        switch coordinator.deviceState {
        case .connected:    return "Đã kết nối"
        case .connecting:   return "Đang kết nối"
        case .disconnected: return "Không kết nối"
        case .error:        return "Lỗi"
        }
    }

    private var accessibilitySummary: String {
        var parts = ["Trạng thái: \(statusText)"]
        if let source = coordinator.activeSource, coordinator.state.isActive {
            parts.append("Nguồn: \(source.displayName)")
        }
        parts.append("Thiết bị: \(coordinator.deviceState.displayName)")
        return parts.joined(separator: ". ")
    }
}

// MARK: - Chi tiet nho

/// Cham trang thai. Dap khi dang chay — mot tin hieu ngoai vi doc duoc ma khong can nhin thang.
struct StatusIndicatorDot: View {
    let color: Color
    var isPulsing: Bool = false
    var size: CGFloat = 7

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dimmed = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .opacity(shouldPulse && dimmed ? 0.3 : 1)
            .onAppear {
                guard shouldPulse else { return }
                withAnimation(AppAnimation.pulse) { dimmed = true }
            }
            .onChange(of: isPulsing) { _, newValue in
                if newValue, !reduceMotion {
                    withAnimation(AppAnimation.pulse) { dimmed = true }
                } else {
                    withAnimation(.linear(duration: 0.15)) { dimmed = false }
                }
            }
            .accessibilityHidden(true)
    }

    private var shouldPulse: Bool { isPulsing && !reduceMotion }
}

/// Vach ngan doc mong giua cac cum trong thanh trang thai.
private struct HairlineVertical: View {
    var body: some View {
        Rectangle()
            .fill(AppColor.separator)
            .frame(width: 1, height: 14)
            .accessibilityHidden(true)
    }
}

#Preview {
    ZStack {
        LinearGradient(colors: [.green.opacity(0.5), .blue.opacity(0.5)],
                       startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
        VStack {
            SimulationStatusBar(coordinator: .shared) {}
                .padding(.horizontal, AppSpacing.lg)
            Spacer()
        }
    }
}
