import SwiftUI

/// Telemetry day du — moi truong cua `SimulationTelemetry` cong cau hinh dang ap dung.
///
/// Doc truc tiep tu `SimulationCoordinator` (khong nhan snapshot truyen vao) nen so lieu
/// cap nhat theo thoi gian thuc khi sheet dang mo. Ban cu nhan mot `SimulationTelemetry`
/// tinh nen so dong bang ngay khi sheet mo ra.
struct TelemetryDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var coordinator = SimulationCoordinator.shared

    var body: some View {
        NavigationStack {
            List {
                Section(L("telemetry.status")) {
                    MetricRow(L("telemetry.status"), value: coordinator.state.displayName,
                              icon: coordinator.state.symbolName,
                              valueColor: coordinator.state.tint, monospaced: false)
                    MetricRow(L("telemetry.source"), value: coordinator.activeSource?.displayName ?? "—",
                              icon: coordinator.activeSource?.icon ?? "circle.dashed",
                              monospaced: false)
                    MetricRow(L("settings.device"), value: coordinator.deviceState.displayName,
                              icon: coordinator.deviceState.icon,
                              valueColor: coordinator.deviceState.tint, monospaced: false)
                    if coordinator.isHalted {
                        MetricRow(L("telemetry.real_gps"), value: L("telemetry.restored"), icon: "location.slash",
                                  valueColor: AppColor.warning, monospaced: false)
                    }
                }

                Section(L("telemetry.section.location")) {
                    MetricRow(L("common.latitude"), value: String(format: "%.8f", telemetry.coordinate.latitude), icon: "mappin")
                    MetricRow(L("common.longitude"), value: String(format: "%.8f", telemetry.coordinate.longitude), icon: "mappin")
                    MetricRow(L("telemetry.heading"), value: AppFormat.heading(telemetry.headingDegrees),
                              icon: "location.north.line")
                    MetricRow(L("telemetry.altitude"), value: AppFormat.altitude(telemetry.altitudeMeters),
                              icon: "arrow.up.to.line")
                }

                Section(L("telemetry.section.motion")) {
                    MetricRow(L("telemetry.speed"), value: "\(AppFormat.speed(telemetry.speedKmh)) km/h", icon: "speedometer")
                    MetricRow(L("telemetry.phase"), value: telemetry.motionPhase.displayName, icon: "waveform.path", monospaced: false)
                    MetricRow(L("telemetry.distance_travelled"), value: AppFormat.distance(telemetry.distanceTravelledMeters), icon: "ruler")
                    MetricRow(L("telemetry.distance_remaining"), value: AppFormat.distance(telemetry.distanceRemainingMeters), icon: "flag.checkered")
                    MetricRow(L("telemetry.progress"), value: AppFormat.percent(telemetry.routeProgress), icon: "chart.bar.fill")
                    MetricRow(L("telemetry.elapsed"), value: AppFormat.duration(telemetry.elapsedTime), icon: "clock")
                    if let eta = telemetry.estimatedArrival {
                        MetricRow(L("route.eta"), value: AppFormat.arrivalTime(eta), icon: "calendar.badge.clock")
                    }
                    if telemetry.updateRate > 0 {
                        MetricRow(L("telemetry.update_rate"), value: String(format: "%.1f Hz", telemetry.updateRate), icon: "waveform")
                    }
                }

                Section(L("telemetry.section.config")) {
                    MetricRow(L("telemetry.noise"),
                              value: coordinator.noiseConfig.enabled
                                  ? String(format: "%.1f m", coordinator.noiseConfig.radiusMeters)
                                  : L("common.off"),
                              icon: "dot.radiowaves.left.and.right")
                    MetricRow(L("telemetry.noise_inertia"), value: String(format: "%.2f", coordinator.noiseConfig.inertia),
                              icon: "arrow.triangle.turn.up.right.circle")
                    MetricRow(L("telemetry.time_multiplier"), value: String(format: "%.1f×", coordinator.timeMultiplier),
                              icon: "timer")
                }

                if let session = coordinator.session {
                    Section(L("telemetry.section.session")) {
                        MetricRow(L("telemetry.session_id"), value: session.id.uuidString.prefix(8).uppercased() + "…", icon: "number")
                        MetricRow(L("telemetry.travel_mode"), value: session.travelMode.displayName,
                                  icon: session.travelMode.icon, monospaced: false)
                        MetricRow(L("telemetry.max_speed"), value: "\(AppFormat.speed(session.maxSpeedKmh)) km/h", icon: "gauge.high")
                        if let name = session.routeName {
                            MetricRow(L("telemetry.route"), value: name, icon: "map", monospaced: false)
                        }
                    }
                }
            }
            .navigationTitle(L("telemetry.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.close) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var telemetry: SimulationTelemetry { coordinator.telemetry }
}

#Preview {
    TelemetryDetailSheet()
}
