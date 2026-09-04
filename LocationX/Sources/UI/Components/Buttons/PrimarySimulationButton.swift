import SwiftUI

/// Nut hanh dong chinh cua mo phong.
///
/// Nut nay **doc thang `SimulationState` cua `SimulationCoordinator`** — khong giu ban sao
/// trang thai rieng. Nho vay no khong bao gio hien "Bat dau" trong khi engine dang chay,
/// va khong bao gio hien tien do gia: `.preparing`/`.stopping` la trang thai THAT do
/// coordinator dat ra.
///
/// Anh xa hanh dong (dung `canStart`/`canPause`/`canResume` cua chinh state machine,
/// nen khong the bam ra mot chuyen doi khong hop le):
///
/// ```
/// idle       -> Bắt đầu     (onStart)
/// completed  -> Bắt đầu lại (onStart)
/// failed     -> Thử lại     (onStart)
/// preparing  -> (vo hieu, co spinner)
/// running    -> Tạm dừng    (onPause)
/// paused     -> Tiếp tục    (onResume)
/// stopping   -> (vo hieu, co spinner)
/// ```
struct PrimarySimulationButton: View {
    let state: SimulationState
    var startTitle: String = L10n.start
    /// Cho phep chan hanh dong bat dau khi chua du dieu kien (vi du chua chon diem den).
    var isStartEnabled: Bool = true
    let onStart: () -> Void
    let onPause: () -> Void
    let onResume: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: performAction) {
            HStack(spacing: AppSpacing.sm) {
                if isBusy {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                        .controlSize(.small)
                } else {
                    Image(systemName: symbol)
                        .font(.system(size: 16, weight: .semibold))
                        // Chuyen icon co chuyen dong khi doi trang thai — chi khi khong Reduce Motion.
                        .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
                }
                Text(title)
                    .font(AppFont.headlineEmphasized)
            }
            .frame(maxWidth: .infinity, minHeight: AppButtonSize.prominent.minHeight)
            .padding(.horizontal, AppSpacing.xl)
            .foregroundStyle(.white)
            .background(tint, in: RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
        }
        .buttonStyle(.pressableLarge)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.55)
        .appAnimation(AppAnimation.spring, value: state)
        .accessibilityLabel(title)
        .accessibilityHint(accessibilityHint)
        .accessibilityAddTraits(isEnabled ? [] : [.isSelected])
    }

    // MARK: - Anh xa trang thai

    private var isBusy: Bool { state == .preparing || state == .stopping }

    private var isEnabled: Bool {
        if isBusy { return false }
        if state.canPause || state.canResume { return true }
        return state.canStart && isStartEnabled
    }

    private var title: String {
        switch state {
        case .idle:      return startTitle
        case .preparing: return L("simulation.preparing") + "…"
        case .running:   return L10n.pause
        case .paused:    return L10n.resume
        case .stopping:  return L("simulation.stopping") + "…"
        case .completed: return L("action.restart")
        case .failed:    return L10n.retry
        }
    }

    private var symbol: String {
        switch state {
        case .idle, .completed: return "play.fill"
        case .running:          return "pause.fill"
        case .paused:           return "play.fill"
        case .failed:           return "arrow.clockwise"
        case .preparing, .stopping: return "circle.dotted"
        }
    }

    private var tint: Color {
        switch state {
        case .running:  return AppColor.warning   // hanh dong ke tiep la TAM DUNG
        case .paused:   return AppColor.success   // hanh dong ke tiep la TIEP TUC
        case .failed:   return AppColor.danger
        default:        return AppColor.primary
        }
    }

    private var accessibilityHint: String {
        switch state {
        case .running:   return L("a11y.sim.pause_hint")
        case .paused:    return L("a11y.sim.resume_hint")
        case .preparing: return L("a11y.sim.preparing_hint")
        case .stopping:  return L("a11y.sim.stopping_hint")
        case .failed:    return L("a11y.sim.retry_hint")
        default:         return isStartEnabled ? L("a11y.sim.start_hint") : L("a11y.sim.start_disabled_hint")
        }
    }

    private func performAction() {
        switch state {
        case .running:
            AppHaptics.toggle()
            onPause()
        case .paused:
            AppHaptics.toggle()
            onResume()
        case .idle, .completed, .failed:
            guard isStartEnabled else { AppHaptics.failure(); return }
            AppHaptics.start()
            onStart()
        case .preparing, .stopping:
            break  // state machine dang chuyen — khong nhan them lenh
        }
    }
}

// MARK: - StopSimulationButton

/// Nut dung phien. Tach rieng khoi nut chinh vi day la hanh dong pha huy:
/// gop chung mot nut se khien mot cu bam nhanh vo tinh ket thuc phien.
struct StopSimulationButton: View {
    let state: SimulationState
    var compact: Bool = false
    let onStop: () -> Void

    var body: some View {
        Button {
            AppHaptics.stop()
            onStop()
        } label: {
            if compact {
                Image(systemName: "stop.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: AppButtonSize.prominent.minHeight,
                           height: AppButtonSize.prominent.minHeight)
            } else {
                Label(L10n.stop, systemImage: "stop.fill")
                    .font(AppFont.calloutEmphasized)
                    .frame(maxWidth: .infinity, minHeight: AppButtonSize.prominent.minHeight)
            }
        }
        .foregroundStyle(AppColor.danger)
        .background(AppColor.danger.opacity(0.14),
                    in: RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
        .buttonStyle(.pressableLarge)
        .disabled(!state.canStop)
        .opacity(state.canStop ? 1 : 0.4)
        .accessibleButton(label: L10n.stop, hint: L("a11y.sim.stop_hint"))
    }
}

#Preview("Simulation button states") {
    VStack(spacing: AppSpacing.lg) {
        ForEach(["idle", "preparing", "running", "paused", "stopping", "failed"], id: \.self) { key in
            let state: SimulationState = {
                switch key {
                case "preparing": return .preparing
                case "running":   return .running
                case "paused":    return .paused
                case "stopping":  return .stopping
                case "failed":    return .failed("Không có tuyến")
                default:          return .idle
                }
            }()
            HStack(spacing: AppSpacing.sm) {
                PrimarySimulationButton(state: state, onStart: {}, onPause: {}, onResume: {})
                StopSimulationButton(state: state, compact: true, onStop: {})
            }
        }
    }
    .padding()
}
