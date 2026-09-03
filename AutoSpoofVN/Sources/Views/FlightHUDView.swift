import SwiftUI
import MapKit

/// Banner hiển thị chi tiết khi đang trên chuyến bay hoặc tour du lịch
struct FlightHUDView: View {
    @EnvironmentObject var flight: FlightManager
    @EnvironmentObject var engine: SpoofEngine

    var body: some View {
        if flight.isFlying, let sim = flight.activeFlight {
            VStack(spacing: 6) {
                HStack {
                    Label(sim.flightNumber, systemImage: "airplane.departure")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.blue)
                    Spacer()
                    Text("\(sim.origin.code) ➔ \(sim.destination.code)")
                        .font(.caption)
                        .fontWeight(.bold)
                    Spacer()
                    Text(sim.phase.rawValue)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                ProgressView(value: sim.progressFraction)
                    .tint(.blue)

                HStack {
                    Text("Còn \(Int(sim.remainingDistanceKm)) km")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Spacer()
                    Menu {
                        Button("1x (Thời gian thật)") { flight.flightTimeWarpMultiplier = 1.0 }
                        Button("5x (Gấp 5 lần)") { flight.flightTimeWarpMultiplier = 5.0 }
                        Button("10x (Gấp 10 lần)") { flight.flightTimeWarpMultiplier = 10.0 }
                        Button("30x (Gấp 30 lần)") { flight.flightTimeWarpMultiplier = 30.0 }
                        Button("60x (Gấp 60 lần)") { flight.flightTimeWarpMultiplier = 60.0 }
                        Button("120x (Siêu tốc)") { flight.flightTimeWarpMultiplier = 120.0 }
                    } label: {
                        HStack(spacing: 2) {
                            Image(systemName: "forward.fill")
                            Text("\(Int(flight.flightTimeWarpMultiplier))x")
                        }
                        .font(.caption2)
                        .fontWeight(.bold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.blue.opacity(0.15))
                        .cornerRadius(6)
                    }

                    Button(role: .destructive, action: { flight.stopFlight() }) {
                        Text("Huỷ bay")
                            .font(.caption2)
                            .foregroundColor(.red)
                    }
                }
            }
            .padding(10)
            .background(.ultraThinMaterial)
            .cornerRadius(12)
            .padding(.horizontal, 16)
        }
    }
}
