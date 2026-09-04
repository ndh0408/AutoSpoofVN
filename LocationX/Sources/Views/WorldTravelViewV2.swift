import SwiftUI
import CoreLocation

/// World Travel v2 — dùng AirportRepository, search, grouped by country.
struct WorldTravelViewV2: View {
    @EnvironmentObject var flight: FlightManager
    @StateObject private var coordinator = SimulationCoordinator.shared
    @State private var searchText = ""
    @State private var selectedOrigin: Airport?
    @State private var selectedDestination: Airport?
    @State private var showFlightPreview = false
    @Environment(\.dismiss) private var dismiss

    private let repo = AirportRepository.shared

    private var filteredAirports: [Airport] {
        repo.search(query: searchText)
    }

    // Tach rieng + chu thich kieu ro rang: de nguyen `repo.byCountry.filter { ... }` lam
    // inline trong ForEach lam trinh bien dich type-check qua lau ("unable to type-check
    // this expression in reasonable time").
    private var nonVietnameseCountries: [(String, [Airport])] {
        repo.byCountry.filter { $0.0 != "Việt Nam" }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Selection header
                selectionHeader
                    .padding(AppSpacing.lg)

                // Airport list
                List {
                    if searchText.isEmpty {
                        // Grouped by country
                        Section(L("flight.section.vietnam")) {
                            ForEach(repo.vietnamese) { airport in
                                airportRow(airport)
                            }
                        }
                        ForEach(nonVietnameseCountries, id: \.0) { country, airports in
                            Section(country) {
                                ForEach(airports) { airport in
                                    airportRow(airport)
                                }
                            }
                        }
                    } else {
                        ForEach(filteredAirports) { airport in
                            airportRow(airport)
                        }
                    }

                    // World Odyssey
                    if !flight.worldDestinations.isEmpty {
                        Section {
                            Button {
                                flight.toggleAutoWorldOdyssey()
                                coordinator.acquire(.flight)
                                dismiss()
                            } label: {
                                HStack {
                                    Image(systemName: "globe.americas.fill")
                                        .font(.title2)
                                        .foregroundStyle(.purple)
                                    VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                                        Text("World Odyssey")
                                            .font(AppFont.body.weight(.medium))
                                        Text(L("flight.world_odyssey.subtitle"))
                                            .font(AppFont.caption)
                                            .foregroundStyle(AppColor.textSecondary)
                                    }
                                    Spacer()
                                    Image(systemName: "play.circle.fill")
                                        .font(.title2)
                                        .foregroundStyle(.purple)
                                }
                            }
                        } header: {
                            Label(L("flight.section.auto"), systemImage: "globe")
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .searchable(text: $searchText, prompt: L("flight.search_airport"))
            }
            .navigationTitle(L("tab.flight"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button(L("action.close")) { dismiss() } }
            }
            .sheet(isPresented: $showFlightPreview) {
                if let origin = selectedOrigin, let dest = selectedDestination {
                    FlightPreviewSheet(origin: origin, destination: dest) {
                        flight.startFlight(origin: origin, destination: dest)
                        coordinator.acquire(.flight)
                        dismiss()
                    }
                }
            }
        }
    }

    private var selectionHeader: some View {
        HStack(spacing: AppSpacing.md) {
            // Origin
            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text(L("flight.from")).font(AppFont.caption).foregroundStyle(AppColor.textTertiary)
                Text(selectedOrigin?.code ?? "---")
                    .font(AppFont.title3.weight(.bold))
                    .foregroundStyle(selectedOrigin != nil ? AppColor.textPrimary : AppColor.textTertiary)
                if let o = selectedOrigin {
                    Text(o.city).font(AppFont.caption).foregroundStyle(AppColor.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "airplane")
                .font(.title2)
                .foregroundStyle(AppColor.primary)
                .rotationEffect(.degrees(90))

            // Destination
            VStack(alignment: .trailing, spacing: AppSpacing.xxs) {
                Text(L("flight.to")).font(AppFont.caption).foregroundStyle(AppColor.textTertiary)
                Text(selectedDestination?.code ?? "---")
                    .font(AppFont.title3.weight(.bold))
                    .foregroundStyle(selectedDestination != nil ? AppColor.textPrimary : AppColor.textTertiary)
                if let d = selectedDestination {
                    Text(d.city).font(AppFont.caption).foregroundStyle(AppColor.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(AppSpacing.lg)
        .background(AppColor.surfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg))
    }

    private func airportRow(_ airport: Airport) -> some View {
        Button {
            if selectedOrigin == nil {
                selectedOrigin = airport
            } else if selectedDestination == nil {
                selectedDestination = airport
                showFlightPreview = true
            } else {
                selectedOrigin = airport
                selectedDestination = nil
            }
        } label: {
            HStack {
                Text(airport.code)
                    .font(AppFont.monoBody.weight(.bold))
                    .foregroundStyle(AppColor.primary)
                    .frame(width: 40)
                VStack(alignment: .leading, spacing: 1) {
                    Text(airport.city)
                        .font(AppFont.body)
                    Text(airport.name)
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textSecondary)
                        .lineLimit(1)
                }
                Spacer()
                Text(airport.country)
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textTertiary)
            }
        }
    }
}

struct FlightPreviewSheet: View {
    let origin: Airport
    let destination: Airport
    let onStart: () -> Void
    @Environment(\.dismiss) private var dismiss

    private var distance: Double {
        MotionEngine.haversineDistanceSync(from: origin.coordinate.clCoordinate, to: destination.coordinate.clCoordinate)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: AppSpacing.xl) {
                // Route
                HStack {
                    VStack {
                        Text(origin.code).font(AppFont.title2.weight(.bold))
                        Text(origin.city).font(AppFont.caption).foregroundStyle(AppColor.textSecondary)
                    }
                    Spacer()
                    VStack(spacing: AppSpacing.xxs) {
                        Image(systemName: "airplane").font(.title2).foregroundStyle(AppColor.primary)
                        Text(String(format: "%.0f km", distance / 1000))
                            .font(AppFont.mono)
                            .foregroundStyle(AppColor.textSecondary)
                    }
                    Spacer()
                    VStack {
                        Text(destination.code).font(AppFont.title2.weight(.bold))
                        Text(destination.city).font(AppFont.caption).foregroundStyle(AppColor.textSecondary)
                    }
                }
                .padding(AppSpacing.xl)

                // Flight info
                AppCard {
                    VStack(spacing: AppSpacing.md) {
                        HStack {
                            MetricView(L("route.distance"), value: String(format: "%.0f", distance / 1000), unit: "km", icon: "ruler")
                            Spacer()
                            MetricView(L("flight.cruise"), value: "850", unit: "km/h", icon: "speedometer")
                            Spacer()
                            MetricView(L("flight.duration"), value: String(format: "%.1f", distance / 850_000), unit: L("common.unit.hour"), icon: "clock")
                        }
                    }
                }
                .padding(.horizontal)

                Spacer()

                Button(action: onStart) {
                    Label(L("flight.start"), systemImage: "airplane.departure")
                        .font(AppFont.callout.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppSpacing.lg)
                        .background(AppColor.primary)
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg))
                }
                .padding(.horizontal, AppSpacing.xxxl)
                .padding(.bottom, AppSpacing.xxxl)
            }
            .navigationTitle(L("flight.preview.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) { Button(L("action.close")) { dismiss() } }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Sync helper (MotionEngine is actor, need sync version for preview)
extension MotionEngine {
    /// Sync version cho UI preview — không cần actor isolation.
    static func haversineDistanceSync(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> Double {
        let R = 6_371_000.0
        let dLat = (b.latitude - a.latitude) * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let lat1 = a.latitude * .pi / 180
        let lat2 = b.latitude * .pi / 180
        let h = sin(dLat/2) * sin(dLat/2) + cos(lat1) * cos(lat2) * sin(dLon/2) * sin(dLon/2)
        return 2 * R * atan2(sqrt(h), sqrt(1-h))
    }
}
