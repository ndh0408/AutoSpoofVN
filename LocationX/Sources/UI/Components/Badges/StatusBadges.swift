import SwiftUI

// MARK: - StatusBadge

/// Nhan trang thai nho gon.
///
/// API giu nguyen tu ban dau (8 file dang dung `StatusBadge("...", color:icon:)`).
/// Cai tien: gop thanh mot phan tu VoiceOver duy nhat va luon co hinh dang phan biet
/// duoc (cham tron hoac icon) chu khong chi dua vao mau.
struct StatusBadge: View {
    let text: String
    let color: Color
    let icon: String?
    /// Nhip dap nhe cho trang thai "dang chay". Tat khi Reduce Motion bat.
    var pulses: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulseOn = false

    init(_ text: String, color: Color = AppColor.success, icon: String? = nil, pulses: Bool = false) {
        self.text = text
        self.color = color
        self.icon = icon
        self.pulses = pulses
    }

    var body: some View {
        HStack(spacing: AppSpacing.xs) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .semibold))
            } else {
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)
                    .opacity(shouldPulse && pulseOn ? 0.35 : 1)
            }
            Text(text)
                .font(AppFont.caption)
                .lineLimit(1)
        }
        .foregroundStyle(color)
        .padding(.horizontal, AppSpacing.sm)
        .padding(.vertical, AppSpacing.xs)
        .background(color.opacity(0.12), in: Capsule(style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(text)
        .onAppear {
            guard shouldPulse else { return }
            withAnimation(AppAnimation.pulse) { pulseOn = true }
        }
    }

    private var shouldPulse: Bool { pulses && !reduceMotion }
}

// MARK: - ConnectionBadge

/// Trang thai ket noi thiet bi, doc thang tu `DeviceConnectionState`.
struct ConnectionBadge: View {
    let state: DeviceConnectionState
    /// Ban rut gon chi hien cham + tu ngan, dung tren thanh chat cho.
    var compact: Bool = false

    var body: some View {
        StatusBadge(compact ? shortLabel : state.displayName,
                    color: state.tint,
                    icon: compact ? nil : state.icon)
            .accessibilityLabel(L("a11y.device_state", state.displayName))
    }

    private var shortLabel: String {
        switch state {
        case .disconnected: return L("device.short.disconnected")
        case .connecting:   return L("device.short.connecting")
        case .connected:    return L("device.short.connected")
        case .error:        return L("device.short.error")
        }
    }
}

// MARK: - SourceBadge

/// Nguon dang giu quyen ghi GPS (Thu cong / Tuyen / Kich ban / Chu trinh / Bay / Phat lai).
///
/// Day la tin hieu UI duy nhat cho biet he thong con nao dang dieu khien vi tri —
/// khong duoc bo khi thiet ke lai.
struct SourceBadge: View {
    let source: SimulationSource

    var body: some View {
        StatusBadge(source.displayName, color: AppColor.accent, icon: source.icon)
            .accessibilityLabel(L("a11y.source", source.displayName))
    }
}

// MARK: - SimulationStatusView

/// Trang thai mo phong: icon + chu + mau, ba tin hieu song song.
///
/// Khong bao gio chi dung mau: nguoi dung mu mau van doc duoc icon va nhan chu.
struct SimulationStatusView: View {
    let state: SimulationState
    var showsLabel: Bool = true

    var body: some View {
        StatusBadge(showsLabel ? state.displayName : "",
                    color: state.tint,
                    icon: state.symbolName,
                    pulses: state == .running)
            .accessibilityLabel(L("a11y.status", state.displayName))
    }
}

// MARK: - HealthDot

/// Cham suc khoe he thong cho hang chan doan.
struct HealthDot: View {
    let status: SystemHealth.Status

    var body: some View {
        Image(systemName: status.icon)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(status.tint)
            .accessibilityLabel(status.rawValue)
    }
}

#Preview("Badges") {
    VStack(alignment: .leading, spacing: AppSpacing.md) {
        SimulationStatusView(state: .running)
        SimulationStatusView(state: .paused)
        SimulationStatusView(state: .failed("Không có tuyến"))
        ConnectionBadge(state: .connected(transport: "DVT"))
        ConnectionBadge(state: .disconnected)
        SourceBadge(source: .route)
        HStack { HealthDot(status: .healthy); HealthDot(status: .warning); HealthDot(status: .error) }
    }
    .padding()
}
