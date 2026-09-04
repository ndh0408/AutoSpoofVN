import SwiftUI

/// Flight HUD v2 — đọc từ SimulationCoordinator, dùng design system,
/// hiển thị đầy đủ telemetry chuyến bay.
struct FlightHUDView: View {
    @EnvironmentObject var flight: FlightManager
    @StateObject private var coordinator = SimulationCoordinator.shared

    var body: some View {
        if flight.isFlying, let sim = flight.activeFlight {
            VStack(spacing: AppSpacing.sm) {
                // Header: flight number + route + phase
                HStack {
                    HStack(spacing: AppSpacing.xs) {
                        Image(systemName: "airplane.departure")
                            .font(.caption)
                        Text(sim.flightNumber)
                            .font(AppFont.footnote.weight(.bold))
                    }
                    .foregroundStyle(AppColor.primary)

                    Spacer()

                    Text("\(sim.origin.code) → \(sim.destination.code)")
                        .font(AppFont.footnote.weight(.bold))

                    Spacer()

                    StatusBadge(sim.phase.rawValue, color: phaseColor(sim.phase))
                }

                // Progress bar
                ProgressView(value: sim.progressFraction)
                    .tint(AppColor.primary)

                // Telemetry grid
                HStack(spacing: AppSpacing.lg) {
                    FlightMetric(label: L("flight.metric.altitude"), value: String(format: "%.0f", sim.altitudeMeters), unit: "m")
                    FlightMetric(label: L("flight.metric.speed"), value: String(format: "%.0f", sim.currentSpeedKmh), unit: "km/h")
                    FlightMetric(label: L("flight.metric.remaining"), value: String(format: "%.0f", sim.remainingDistanceKm), unit: "km")
                    FlightMetric(label: L("flight.metric.heading"), value: String(format: "%.0f°", coordinator.telemetry.headingDegrees), unit: coordinator.telemetry.cardinalDirection)
                }

                // Controls
                HStack {
                    if sim.progressFraction > 0 {
                        Text(String(format: "%.0f%%", sim.progressFraction * 100))
                            .font(AppFont.mono)
                            .foregroundStyle(AppColor.textSecondary)
                    }

                    Spacer()

                    // Time warp
                    Menu {
                        Button("1x") { flight.flightTimeWarpMultiplier = 1.0 }
                        Button("5x") { flight.flightTimeWarpMultiplier = 5.0 }
                        Button("10x") { flight.flightTimeWarpMultiplier = 10.0 }
                        Button("30x") { flight.flightTimeWarpMultiplier = 30.0 }
                        Button("60x") { flight.flightTimeWarpMultiplier = 60.0 }
                        Button("120x") { flight.flightTimeWarpMultiplier = 120.0 }
                    } label: {
                        HStack(spacing: AppSpacing.xxs) {
                            Image(systemName: "forward.fill")
                            Text("\(Int(flight.flightTimeWarpMultiplier))x")
                        }
                        .font(AppFont.caption.weight(.bold))
                        .padding(.horizontal, AppSpacing.sm)
                        .padding(.vertical, AppSpacing.xs)
                        .background(AppColor.primary.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm))
                    }

                    Button(role: .destructive) {
                        flight.stopFlight()
                        coordinator.release(.flight)
                    } label: {
                        Text(L("flight.cancel"))
                            .font(AppFont.caption.weight(.medium))
                            .foregroundStyle(AppColor.danger)
                    }
                }
            }
            .padding(AppSpacing.md)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg))
            .padding(.horizontal, AppSpacing.lg)
        }
    }

    // Ten case that trong FlightPhase (Models/Types.swift) khac ten FlightHUDView goc dinh
    // dung (checkin/boarding/climb/cruise/landing/arrival kieu section 40 cua spec) - anh xa
    // sang ten case that dang co, khong doi FlightPhase vi FlightManager.swift dang dung ten cu.
    private func phaseColor(_ phase: FlightPhase) -> Color {
        switch phase {
        case .taxiToAirport, .airportCheckin, .scheduled: return .orange
        case .taxi: return .yellow
        case .takeoff: return .blue
        case .cruising: return .green
        case .descent: return .purple
        case .landed, .taxiToHotel: return .green
        }
    }
}

struct FlightMetric: View {
    let label: String
    let value: String
    let unit: String

    var body: some View {
        VStack(spacing: 1) {
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(AppColor.textTertiary)
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(value)
                    .font(AppFont.mono.weight(.medium))
                Text(unit)
                    .font(.system(size: 8))
                    .foregroundStyle(AppColor.textSecondary)
            }
        }
    }
}
