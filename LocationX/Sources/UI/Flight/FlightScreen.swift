import CoreLocation
import SwiftUI

/// Tab "Chuyến bay".
///
/// Hai trạng thái rõ rệt:
/// - **Đang bay**: telemetry thời gian thực, đường thời gian giai đoạn, điều khiển
///   (hệ số tua thời gian, huỷ bay).
/// - **Chưa bay**: chọn sân bay đi/đến, xem trước, bắt đầu; và chế độ du lịch thế giới.
///
/// Đây cũng là lần đầu người dùng **huỷ được chuyến bay** và **đổi được hệ số thời gian**
/// từ giao diện: hai điều khiển đó chỉ tồn tại trong `FlightHUDView`, mà view đó chưa từng
/// được khởi tạo ở bất kỳ đâu trong app.
struct FlightScreen: View {
    @Environment(\.navigator) private var navigator
    @EnvironmentObject private var flight: FlightManager
    @ObservedObject private var coordinator = SimulationCoordinator.shared

    @State private var origin: Airport?
    @State private var destination: Airport?
    @State private var showOriginPicker = false
    @State private var showDestinationPicker = false
    @State private var showCancelConfirm = false

    /// Hệ số tua thời gian có sẵn. Giữ đúng bộ giá trị của `FlightHUDView` cũ.
    private let timeWarpOptions: [Double] = [1, 5, 10, 30, 60, 120]

    var body: some View {
        List {
            if flight.isFlying, let sim = flight.activeFlight {
                activeFlightSections(sim)
            } else {
                plannerSections
            }
            worldTourSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle(L("tab.flight"))
        .sheet(isPresented: $showOriginPicker) {
            AirportPicker(title: L("flight.origin"), airports: flight.popularAirports) {
                origin = $0
            }
        }
        .sheet(isPresented: $showDestinationPicker) {
            AirportPicker(title: L("flight.destination"), airports: flight.popularAirports) {
                destination = $0
            }
        }
        .confirmationDialog(L("flight.cancel.title"),
                            isPresented: $showCancelConfirm, titleVisibility: .visible) {
            Button(L("flight.cancel.confirm"), role: .destructive) {
                AppHaptics.stop()
                flight.stopFlight()
            }
            Button(L("action.cancel"), role: .cancel) {}
        } message: {
            Text(L("flight.cancel.message"))
        }
    }

    // MARK: - Đang bay

    @ViewBuilder
    private func activeFlightSections(_ sim: FlightSimulation) -> some View {
        Section {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                HStack(spacing: AppSpacing.sm) {
                    Text(sim.flightNumber)
                        .font(AppFont.monoFootnote.weight(.bold))
                        .foregroundStyle(AppColor.primary)
                    Spacer()
                    StatusBadge(sim.phase.rawValue, color: AppColor.success,
                                icon: sim.phase.symbol, pulses: true)
                }

                HStack(alignment: .firstTextBaseline, spacing: AppSpacing.sm) {
                    airportEndpoint(sim.origin, alignment: .leading)
                    Image(systemName: "airplane")
                        .font(.system(size: 13))
                        .foregroundStyle(AppColor.textTertiary)
                    airportEndpoint(sim.destination, alignment: .trailing)
                }

                ProgressView(value: sim.progressFraction, total: 1)
                    .tint(AppColor.success)
                HStack {
                    Text(AppFormat.percent(sim.progressFraction))
                    Spacer()
                    Text(L("flight.remaining_km", Int(sim.remainingDistanceKm)))
                }
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)
                .monospacedDigit()
            }
            .padding(.vertical, AppSpacing.xs)
        } header: {
            Text(L("flight.in_progress"))
        }

        Section(L("flight.telemetry")) {
            TelemetryGrid(items: telemetryItems(sim))
                .listRowInsets(EdgeInsets(top: AppSpacing.sm, leading: AppSpacing.md,
                                          bottom: AppSpacing.sm, trailing: AppSpacing.md))
        }

        Section(L("flight.timeline")) {
            FlightTimeline(currentPhase: sim.phase)
                .padding(.vertical, AppSpacing.xs)
        }

        Section {
            Picker(L("flight.time_warp"), selection: $flight.flightTimeWarpMultiplier) {
                ForEach(timeWarpOptions, id: \.self) { multiplier in
                    Text("\(Int(multiplier))×").tag(multiplier)
                }
            }
            .pickerStyle(.segmented)

            Button(role: .destructive) {
                showCancelConfirm = true
            } label: {
                Label(L("flight.cancel.action"), systemImage: "xmark.circle")
            }
        } header: {
            Text(L("flight.controls"))
        } footer: {
            Text(L("flight.time_warp.footer"))
        }
    }

    private func airportEndpoint(_ airport: Airport, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 1) {
            Text(airport.code)
                .font(AppFont.headlineEmphasized)
                .foregroundStyle(AppColor.textPrimary)
            Text(airport.city)
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .trailing)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(airport.code), \(airport.city)")
    }

    private func telemetryItems(_ sim: FlightSimulation) -> [TelemetryGrid.TelemetryItem] {
        var items: [TelemetryGrid.TelemetryItem] = [
            .init(label: L("flight.altitude"), value: AppFormat.altitude(sim.altitudeMeters),
                  icon: "arrow.up.to.line"),
            .init(label: L("flight.ground_speed"), value: AppFormat.speed(sim.currentSpeedKmh),
                  unit: "km/h", icon: "speedometer"),
            .init(label: L("flight.vertical_speed"),
                  value: String(format: "%+.1f", flight.verticalSpeedMps), unit: "m/s",
                  icon: flight.verticalSpeedMps >= 0 ? "arrow.up.right" : "arrow.down.right",
                  tint: flight.verticalSpeedMps >= 0 ? AppColor.success : AppColor.warning),
            .init(label: L("flight.heading"),
                  value: AppFormat.heading(coordinator.telemetry.headingDegrees),
                  icon: "location.north.line"),
        ]
        if sim.estimatedMinutesRemaining > 0 {
            let arrival = Date().addingTimeInterval(sim.estimatedMinutesRemaining * 60)
            items.append(.init(label: L("route.eta"), value: AppFormat.arrivalTime(arrival),
                               icon: "clock"))
        }
        items.append(.init(label: L("flight.progress"),
                           value: AppFormat.percent(sim.progressFraction),
                           icon: "chart.bar.fill", tint: AppColor.success))
        return items
    }

    // MARK: - Lập chuyến bay

    @ViewBuilder
    private var plannerSections: some View {
        Section {
            AirportSelectionField(label: L("flight.origin"), airport: origin,
                                  symbol: "airplane.departure", tint: AppColor.success) {
                showOriginPicker = true
            }
            AirportSelectionField(label: L("flight.destination"), airport: destination,
                                  symbol: "airplane.arrival", tint: AppColor.danger) {
                showDestinationPicker = true
            }
            if origin != nil || destination != nil {
                Button {
                    AppHaptics.selection()
                    swap(&origin, &destination)
                } label: {
                    Label(L("flight.swap"), systemImage: "arrow.up.arrow.down")
                }
            }
        } header: {
            Text(L("flight.plan"))
        } footer: {
            if let preview = previewSummary {
                Text(preview)
            }
        }

        if let origin, let destination, origin.code != destination.code {
            Section {
                Button {
                    AppHaptics.start()
                    flight.startFlight(origin: origin, destination: destination)
                    navigator.select(.map)
                } label: {
                    Label(L("flight.start"), systemImage: "airplane.departure")
                }
                .fontWeight(.semibold)
            }
        }
    }

    /// Tóm tắt xem trước: khoảng cách và thời gian bay ước tính.
    private var previewSummary: String? {
        guard let origin, let destination, origin.code != destination.code else {
            return L("flight.plan.footer")
        }
        let km = GeodesicMath.distanceKm(from: origin.coordinate.clCoordinate,
                                         to: destination.coordinate.clCoordinate)
        let hours = km / 800.0
        return L("flight.preview.summary", Int(km), AppFormat.duration(hours * 3600))
    }

    // MARK: - Du lịch thế giới

    private var worldTourSection: some View {
        Section {
            HubRow(title: L("flight.world_tour"),
                   subtitle: L("flight.world_tour.subtitle"),
                   symbol: "globe.asia.australia.fill",
                   tint: AppColor.primary,
                   badge: flight.isAutoWorldOdysseyEnabled ? L("common.on") : nil) {
                navigator.present(.worldTravel)
            }
        } header: {
            Text(L("flight.destinations"))
        } footer: {
            if let destination = flight.activeDestination {
                Text(L("flight.world_tour.status",
                       destination.name, destination.country,
                       flight.currentDayInDestination, destination.stayDays)
                     + (flight.destinationLocalTime.isEmpty
                        ? "" : " · \(flight.destinationLocalTime)"))
            } else {
                Text(L("flight.world_tour.footer"))
            }
        }
    }
}

#Preview {
    NavigationStack { FlightScreen() }
        .environmentObject(FlightManager.shared)
}
