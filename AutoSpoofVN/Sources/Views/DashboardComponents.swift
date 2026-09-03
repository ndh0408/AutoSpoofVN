import CoreLocation
import MapKit
import SwiftUI

// MARK: - Telemetry Panel (Bottom Sheet)

struct TelemetryPanel: View {
    @ObservedObject var coordinator: SimulationCoordinator
    let onPause: () -> Void
    let onStop: () -> Void
    let onResume: () -> Void

    var body: some View {
        VStack(spacing: AppSpacing.md) {
            // State badge
            HStack {
                StatusBadge(
                    coordinator.state.displayName,
                    color: stateColor,
                    icon: stateIcon
                )
                if let source = coordinator.activeSource {
                    StatusBadge(source.displayName, color: .indigo, icon: source.icon)
                }
                Spacer()
                if coordinator.telemetry.updateRate > 0 {
                    Text(String(format: "%.0f Hz", coordinator.telemetry.updateRate))
                        .font(AppFont.mono)
                        .foregroundStyle(AppColor.textTertiary)
                }
            }

            // Metrics grid
            HStack(spacing: AppSpacing.xl) {
                MetricView("Tốc độ", value: String(format: "%.1f", coordinator.telemetry.speedKmh), unit: "km/h", icon: "speedometer")
                MetricView("Hướng", value: coordinator.telemetry.formattedHeading, icon: "location.north.line")
                if coordinator.telemetry.distanceRemainingMeters > 0 {
                    MetricView("Còn lại", value: formatDistance(coordinator.telemetry.distanceRemainingMeters), icon: "ruler")
                }
                if let eta = coordinator.telemetry.estimatedArrival {
                    MetricView("ETA", value: DateFormatter.localizedString(from: eta, dateStyle: .none, timeStyle: .short), icon: "clock")
                }
            }

            // Coordinate display
            HStack {
                Image(systemName: "mappin")
                    .foregroundStyle(AppColor.primary)
                Text(String(format: "%.6f, %.6f", coordinator.currentCoordinate.latitude, coordinator.currentCoordinate.longitude))
                    .font(AppFont.mono)
                    .foregroundStyle(AppColor.textSecondary)
                Spacer()
                if coordinator.telemetry.elapsedTime > 0 {
                    Text(formatDuration(coordinator.telemetry.elapsedTime))
                        .font(AppFont.mono)
                        .foregroundStyle(AppColor.textTertiary)
                }
            }

            // Controls
            if coordinator.state.isActive {
                HStack(spacing: AppSpacing.lg) {
                    if coordinator.state.canPause {
                        Button(action: onPause) {
                            Label(L10n.pause, systemImage: "pause.fill")
                                .font(AppFont.callout.weight(.medium))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, AppSpacing.md)
                                .background(AppColor.warning.opacity(0.15))
                                .foregroundStyle(AppColor.warning)
                                .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))
                        }
                    }
                    if coordinator.state.canResume {
                        Button(action: onResume) {
                            Label(L10n.resume, systemImage: "play.fill")
                                .font(AppFont.callout.weight(.medium))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, AppSpacing.md)
                                .background(AppColor.primary.opacity(0.15))
                                .foregroundStyle(AppColor.primary)
                                .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))
                        }
                    }
                    Button(action: onStop) {
                        Label(L10n.stop, systemImage: "stop.fill")
                            .font(AppFont.callout.weight(.medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, AppSpacing.md)
                            .background(AppColor.danger.opacity(0.15))
                            .foregroundStyle(AppColor.danger)
                            .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))
                    }
                }
            }
        }
        .padding(AppSpacing.lg)
        .background(
            AppColor.surface
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.xl))
                .shadow(color: .black.opacity(0.08), radius: 12, y: -4)
        )
    }

    private var stateColor: Color {
        switch coordinator.state {
        case .running: return .green
        case .paused: return .orange
        case .failed: return .red
        default: return .secondary
        }
    }

    private var stateIcon: String {
        switch coordinator.state {
        case .running: return "play.fill"
        case .paused: return "pause.fill"
        case .failed: return "exclamationmark.triangle.fill"
        default: return "circle"
        }
    }

    private func formatDistance(_ meters: Double) -> String {
        meters > 1000 ? String(format: "%.1f km", meters / 1000) : String(format: "%.0f m", meters)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return m > 60 ? String(format: "%d:%02d:%02d", m/60, m%60, s) : String(format: "%d:%02d", m, s)
    }
}

// MARK: - Quick Actions

struct QuickActionsBar: View {
    let onSetLocation: () -> Void
    let onStartRoute: () -> Void
    let onCreateRoute: () -> Void
    let onScenario: () -> Void
    let onDevices: () -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppSpacing.md) {
                QuickActionButton(icon: "mappin", label: "Đặt vị trí", action: onSetLocation)
                QuickActionButton(icon: "map", label: "Route Studio", action: onCreateRoute)
                QuickActionButton(icon: "play.fill", label: "Chạy tuyến", action: onStartRoute)
                QuickActionButton(icon: "list.bullet.clipboard", label: "Kịch bản", action: onScenario)
                QuickActionButton(icon: "iphone", label: "Thiết bị", action: onDevices)
            }
            .padding(.horizontal, AppSpacing.lg)
        }
    }
}

struct QuickActionButton: View {
    let icon: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: AppSpacing.xs) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .frame(width: 44, height: 44)
                    .background(AppColor.primary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))
                Text(label)
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
            }
        }
        .foregroundStyle(AppColor.primary)
    }
}

// MARK: - Connection Header

struct ConnectionHeader: View {
    let deviceState: DeviceConnectionState
    let isSimulating: Bool

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            Text("AutoSpoof VN")
                .font(AppFont.headline)

            Spacer()

            // Device status
            HStack(spacing: AppSpacing.xs) {
                Circle()
                    .fill(deviceState.isConnected ? AppColor.connected : AppColor.disconnected)
                    .frame(width: 6, height: 6)
                Text(deviceState.isConnected ? "Kết nối" : "Ngắt")
                    .font(AppFont.caption)
                    .foregroundStyle(deviceState.isConnected ? AppColor.connected : AppColor.textTertiary)
            }

            if isSimulating {
                StatusBadge("GPS", color: .blue, icon: "location.fill")
            }
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.vertical, AppSpacing.sm)
        .background(.ultraThinMaterial)
    }
}

// MARK: - Map Trail Overlay

struct TrailOverlay {
    /// Lấy mẫu trail — không giữ vô hạn trong bộ nhớ.
    static func sampleTrail(_ trail: inout [CLLocationCoordinate2D], newPoint: CLLocationCoordinate2D, maxPoints: Int = 1000) {
        trail.append(newPoint)
        if trail.count > maxPoints {
            // Giữ lại mỗi điểm thứ 2
            trail = stride(from: 0, to: trail.count, by: 2).map { trail[$0] }
        }
    }
}

// MARK: - Expandable Telemetry Detail

struct TelemetryDetailView: View {
    let telemetry: SimulationTelemetry
    let coordinator: SimulationCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("Telemetry chi tiết")
                .font(AppFont.headline)
                .padding(.bottom, AppSpacing.xs)

            Group {
                TelemetryRow("Latitude", value: String(format: "%.8f", telemetry.coordinate.latitude))
                TelemetryRow("Longitude", value: String(format: "%.8f", telemetry.coordinate.longitude))
                TelemetryRow("Tốc độ", value: String(format: "%.2f km/h", telemetry.speedKmh))
                TelemetryRow("Hướng", value: String(format: "%.1f° %@", telemetry.headingDegrees, telemetry.cardinalDirection))
                TelemetryRow("Altitude", value: String(format: "%.1f m", telemetry.altitudeMeters))
                TelemetryRow("Đã đi", value: formatDistance(telemetry.distanceTravelledMeters))
                TelemetryRow("Còn lại", value: formatDistance(telemetry.distanceRemainingMeters))
                TelemetryRow("Thời gian", value: formatDuration(telemetry.elapsedTime))
                TelemetryRow("Phase", value: telemetry.motionPhase.rawValue)
                TelemetryRow("Noise", value: String(format: "%.1f m", coordinator.noiseConfig.radiusMeters))
                TelemetryRow("Multiplier", value: String(format: "%.1fx", coordinator.timeMultiplier))
            }
        }
        .font(AppFont.mono)
        .padding(AppSpacing.lg)
    }

    private func formatDistance(_ m: Double) -> String {
        m > 1000 ? String(format: "%.2f km", m/1000) : String(format: "%.0f m", m)
    }

    private func formatDuration(_ s: TimeInterval) -> String {
        let m = Int(s)/60; let sec = Int(s)%60
        return String(format: "%02d:%02d", m, sec)
    }
}

struct TelemetryRow: View {
    let label: String
    let value: String

    init(_ label: String, value: String) {
        self.label = label
        self.value = value
    }

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(AppColor.textTertiary)
                .frame(width: 100, alignment: .leading)
            Text(value)
                .foregroundStyle(AppColor.textPrimary)
            Spacer()
        }
    }
}
