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
                Section("Trạng thái") {
                    MetricRow("Trạng thái", value: coordinator.state.displayName,
                              icon: coordinator.state.symbolName,
                              valueColor: coordinator.state.tint, monospaced: false)
                    MetricRow("Nguồn", value: coordinator.activeSource?.displayName ?? "—",
                              icon: coordinator.activeSource?.icon ?? "circle.dashed",
                              monospaced: false)
                    MetricRow("Thiết bị", value: coordinator.deviceState.displayName,
                              icon: coordinator.deviceState.icon,
                              valueColor: coordinator.deviceState.tint, monospaced: false)
                    if coordinator.isHalted {
                        MetricRow("GPS thật", value: "Đã khôi phục", icon: "location.slash",
                                  valueColor: AppColor.warning, monospaced: false)
                    }
                }

                Section("Vị trí") {
                    MetricRow("Vĩ độ", value: String(format: "%.8f", telemetry.coordinate.latitude), icon: "mappin")
                    MetricRow("Kinh độ", value: String(format: "%.8f", telemetry.coordinate.longitude), icon: "mappin")
                    MetricRow("Hướng", value: AppFormat.heading(telemetry.headingDegrees),
                              icon: "location.north.line")
                    MetricRow("Độ cao", value: AppFormat.altitude(telemetry.altitudeMeters),
                              icon: "arrow.up.to.line")
                }

                Section("Chuyển động") {
                    MetricRow("Tốc độ", value: "\(AppFormat.speed(telemetry.speedKmh)) km/h", icon: "speedometer")
                    MetricRow("Pha", value: telemetry.motionPhase.rawValue, icon: "waveform.path", monospaced: false)
                    MetricRow("Đã đi", value: AppFormat.distance(telemetry.distanceTravelledMeters), icon: "ruler")
                    MetricRow("Còn lại", value: AppFormat.distance(telemetry.distanceRemainingMeters), icon: "flag.checkered")
                    MetricRow("Tiến độ", value: AppFormat.percent(telemetry.routeProgress), icon: "chart.bar.fill")
                    MetricRow("Thời gian", value: AppFormat.duration(telemetry.elapsedTime), icon: "clock")
                    if let eta = telemetry.estimatedArrival {
                        MetricRow("Dự kiến đến", value: AppFormat.arrivalTime(eta), icon: "calendar.badge.clock")
                    }
                    if telemetry.updateRate > 0 {
                        MetricRow("Tần suất", value: String(format: "%.1f Hz", telemetry.updateRate), icon: "waveform")
                    }
                }

                Section("Cấu hình đang áp dụng") {
                    MetricRow("Nhiễu GPS",
                              value: coordinator.noiseConfig.enabled
                                  ? String(format: "%.1f m", coordinator.noiseConfig.radiusMeters)
                                  : "Tắt",
                              icon: "dot.radiowaves.left.and.right")
                    MetricRow("Quán tính nhiễu", value: String(format: "%.2f", coordinator.noiseConfig.inertia),
                              icon: "arrow.triangle.turn.up.right.circle")
                    MetricRow("Hệ số thời gian", value: String(format: "%.1f×", coordinator.timeMultiplier),
                              icon: "timer")
                }

                if let session = coordinator.session {
                    Section("Phiên") {
                        MetricRow("Mã phiên", value: session.id.uuidString.prefix(8).uppercased() + "…", icon: "number")
                        MetricRow("Phương tiện", value: session.travelMode.displayName,
                                  icon: session.travelMode.icon, monospaced: false)
                        MetricRow("Tốc độ tối đa", value: "\(AppFormat.speed(session.maxSpeedKmh)) km/h", icon: "gauge.high")
                        if let name = session.routeName {
                            MetricRow("Tuyến", value: name, icon: "map", monospaced: false)
                        }
                    }
                }
            }
            .navigationTitle("Telemetry")
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
