//
//  RouteStudioView.swift
//  AutoSpoofVN
//
//  Visual Route Editor: Map search, waypoints insertion, reordering, reverse, and preview.
//

import CoreLocation
import MapKit
import SwiftUI

struct RouteStudioView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var searchService = RouteSearchService.shared
    @ObservedObject private var coordinator = SimulationCoordinator.shared

    @State private var routeName: String = "Lộ trình mới"
    @State private var waypoints: [CLLocationCoordinate2D] = []
    @State private var waypointNames: [String] = []
    @State private var selectedTravelMode: TravelMode = .driving
    @State private var customSpeedKmh: Double = 45.0
    @State private var searchQuery: String = ""
    @State private var isCalculating: Bool = false
    @State private var calculatedDistanceKm: Double = 0
    @State private var calculatedDurationMinutes: Double = 0
    @State private var errorMessage: String? = nil

    var body: some View {
        NavigationStack {
            Form {
                Section("Thông tin lộ trình") {
                    TextField("Tên lộ trình", text: $routeName)
                    Picker("Phương tiện di chuyển", selection: $selectedTravelMode) {
                        ForEach(TravelMode.allCases) { mode in
                            Label(mode.displayName, systemImage: mode.icon).tag(mode)
                        }
                    }
                    HStack {
                        Text("Vận tốc mô phỏng:")
                        Spacer()
                        Text("\(Int(customSpeedKmh)) km/h")
                            .fontWeight(.bold)
                    }
                    Slider(value: $customSpeedKmh, in: 5...120, step: 5)
                }

                Section("Tìm kiếm & Thêm điểm dừng") {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                        TextField("Tìm kiếm địa danh, đường phố...", text: $searchQuery)
                            .onSubmit {
                                Task { await searchService.search(query: searchQuery, near: coordinator.currentCoordinate) }
                            }
                        if !searchQuery.isEmpty {
                            Button {
                                searchQuery = ""
                                searchService.searchResults = []
                            } label: {
                                Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                            }
                        }
                    }

                    if searchService.isSearching {
                        ProgressView("Đang tìm kiếm...")
                    } else if !searchService.searchResults.isEmpty {
                        ForEach(searchService.searchResults) { item in
                            Button {
                                addWaypoint(item.coordinate, name: item.title)
                                searchQuery = ""
                                searchService.searchResults = []
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.title)
                                            .font(.subheadline)
                                            .foregroundColor(.primary)
                                        Text(item.subtitle)
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                    }

                    Button {
                        addWaypoint(coordinator.currentCoordinate, name: "Vị trí hiện tại")
                    } label: {
                        Label("Thêm vị trí hiện tại vào điểm dừng", systemImage: "location.fill")
                    }
                }

                Section("Danh sách điểm dừng (\(waypoints.count))") {
                    if waypoints.isEmpty {
                        Text("Chưa có điểm dừng nào. Hãy tìm kiếm hoặc bấm thêm vị trí hiện tại.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(Array(waypoints.enumerated()), id: \.offset) { index, coord in
                            HStack {
                                Circle()
                                    .fill(index == 0 ? Color.green : (index == waypoints.count - 1 ? Color.red : Color.blue))
                                    .frame(width: 8, height: 8)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(index < waypointNames.count ? waypointNames[index] : "Điểm \(index + 1)")
                                        .font(.subheadline.weight(.semibold))
                                    Text(String(format: "%.4f, %.4f", coord.latitude, coord.longitude))
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                            }
                        }
                        .onDelete(perform: deleteWaypoint)
                        .onMove(perform: moveWaypoint)

                        HStack {
                            Button("Đảo chiều lộ trình") {
                                waypoints.reverse()
                                waypointNames.reverse()
                            }
                            .disabled(waypoints.count < 2)

                            Spacer()

                            Button("Xóa tất cả", role: .destructive) {
                                waypoints.removeAll()
                                waypointNames.removeAll()
                            }
                        }
                        .font(.caption)
                    }
                }

                if let error = errorMessage {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }

                Section {
                    Button {
                        startSimulation()
                    } label: {
                        HStack {
                            Spacer()
                            Label("Bắt đầu mô phỏng tuyến đường", systemImage: "play.fill")
                                .font(.headline)
                                .foregroundColor(.white)
                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowBackground(waypoints.count >= 2 ? Color.blue : Color.gray.opacity(0.3))
                    .disabled(waypoints.count < 2 || isCalculating)
                }
            }
            .navigationTitle("Route Studio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đóng") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    EditButton()
                }
            }
        }
    }

    private func addWaypoint(_ coordinate: CLLocationCoordinate2D, name: String) {
        waypoints.append(coordinate)
        waypointNames.append(name)
    }

    private func deleteWaypoint(at offsets: IndexSet) {
        waypoints.remove(atOffsets: offsets)
        waypointNames.remove(atOffsets: offsets)
    }

    private func moveWaypoint(from source: IndexSet, to destination: Int) {
        waypoints.move(fromOffsets: source, toOffset: destination)
        waypointNames.move(fromOffsets: source, toOffset: destination)
    }

    private func startSimulation() {
        guard waypoints.count >= 2 else { return }
        isCalculating = true
        errorMessage = nil

        Task {
            var allSegments: [CLLocationCoordinate2D] = []
            for i in 0..<(waypoints.count - 1) {
                let origin = waypoints[i]
                let dest = waypoints[i + 1]
                let seg = RouteProvider.straightLineCoordinates(from: origin, to: dest, spacingMeters: 20.0)
                allSegments.append(contentsOf: seg)
            }

            await MainActor.run {
                coordinator.startRouteSimulation(
                    name: routeName,
                    waypoints: allSegments,
                    travelMode: selectedTravelMode,
                    speedKmh: customSpeedKmh
                )
                isCalculating = false
                dismiss()
            }
        }
    }
}
