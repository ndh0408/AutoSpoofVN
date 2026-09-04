import SwiftUI

extension FlightPhase {
    /// Icon cho từng giai đoạn.
    var symbol: String {
        switch self {
        case .taxiToAirport:  return "car.fill"
        case .airportCheckin: return "person.badge.clock"
        case .scheduled:      return "clock"
        case .taxi:           return "airplane.circle"
        case .takeoff:        return "airplane.departure"
        case .cruising:       return "airplane"
        case .descent:        return "airplane.arrival"
        case .landed:         return "flag.checkered"
        case .taxiToHotel:    return "building.2.fill"
        }
    }

    /// Vị trí trong chuỗi giai đoạn, dùng để biết giai đoạn nào đã qua.
    var order: Int {
        FlightPhase.allCases.firstIndex(of: self) ?? 0
    }
}

/// Đường thời gian của chuyến bay.
///
/// Dùng chính `FlightPhase` của engine chứ không dựng một danh sách giai đoạn riêng —
/// một danh sách song song sẽ lệch khỏi engine ngay lần đầu ai đó thêm giai đoạn mới.
struct FlightTimeline: View {
    let currentPhase: FlightPhase

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(FlightPhase.allCases.enumerated()), id: \.element) { index, phase in
                row(phase: phase, isLast: index == FlightPhase.allCases.count - 1)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L("flight.timeline.a11y", currentPhase.displayName))
    }

    private func row(phase: FlightPhase, isLast: Bool) -> some View {
        let state = state(for: phase)
        return HStack(alignment: .top, spacing: AppSpacing.md) {
            // Cột chỉ báo: chấm + đường nối
            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(state.fill)
                        .frame(width: 22, height: 22)
                    Image(systemName: state == .done ? "checkmark" : phase.symbol)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(state.iconColor)
                }
                if !isLast {
                    Rectangle()
                        .fill(state == .upcoming ? AppColor.separator : AppColor.success)
                        .frame(width: 2)
                        .frame(minHeight: 18)
                }
            }

            Text(phase.displayName)
                .font(state == .current ? AppFont.calloutEmphasized : AppFont.callout)
                .foregroundStyle(state.textColor)
                .padding(.bottom, isLast ? 0 : AppSpacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)

            if state == .current {
                StatusIndicatorDot(color: AppColor.success, isPulsing: true, size: 7)
                    .padding(.top, 7)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(phase.displayName). \(state.a11ySuffix)")
    }

    private enum PhaseState {
        case done, current, upcoming

        var fill: Color {
            switch self {
            case .done:     return AppColor.success
            case .current:  return AppColor.primary
            case .upcoming: return AppColor.surfaceTertiary
            }
        }

        var iconColor: Color {
            self == .upcoming ? AppColor.textTertiary : .white
        }

        var textColor: Color {
            switch self {
            case .done:     return AppColor.textSecondary
            case .current:  return AppColor.textPrimary
            case .upcoming: return AppColor.textTertiary
            }
        }

        var a11ySuffix: String {
            switch self {
            case .done:     return L("flight.timeline.done")
            case .current:  return L("flight.timeline.current")
            case .upcoming: return L("flight.timeline.upcoming")
            }
        }
    }

    private func state(for phase: FlightPhase) -> PhaseState {
        if phase == currentPhase { return .current }
        return phase.order < currentPhase.order ? .done : .upcoming
    }
}

#Preview {
    ScrollView {
        FlightTimeline(currentPhase: .cruising)
            .padding()
    }
}
