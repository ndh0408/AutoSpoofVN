import Combine
import CoreLocation
import Foundation
import SwiftUI

final class DiagnosticsStore: ObservableObject {
    static let shared = DiagnosticsStore()

    struct CoordinateSample: Identifiable {
        let id = UUID()
        let timestamp: Date
        let coordinate: CLLocationCoordinate2D
        let source: SpoofSource?
        let isLoopbackConnected: Bool
    }

    @Published private(set) var recentLocations: [CoordinateSample] = []

    private var observation: AnyCancellable?
    private var lastCoordinate: CLLocationCoordinate2D?
    private var lastSource: SpoofSource?
    private var lastRecordedAt: Date?

    private init() {
        let engine = SpoofEngine.shared
        observation = engine.$currentCoordinate
            .combineLatest(engine.$isSimulating)
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak engine] output in
                let (coordinate, isSimulating) = output
                guard let self, let engine, isSimulating else { return }
                self.record(
                    coordinate: coordinate,
                    source: engine.activeSource,
                    isLoopbackConnected: engine.isLoopbackConnected
                )
            }
    }

    func clear() {
        recentLocations.removeAll()
        lastCoordinate = nil
        lastSource = nil
        lastRecordedAt = nil
    }

    private func record(
        coordinate: CLLocationCoordinate2D,
        source: SpoofSource?,
        isLoopbackConnected: Bool
    ) {
        guard CLLocationCoordinate2DIsValid(coordinate) else { return }
        let now = Date()
        if let lastCoordinate, let lastRecordedAt {
            let distance = CLLocation(latitude: lastCoordinate.latitude, longitude: lastCoordinate.longitude)
                .distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
            if distance < 0.05, lastSource == source, now.timeIntervalSince(lastRecordedAt) < 1 {
                return
            }
        }

        recentLocations.insert(
            CoordinateSample(
                timestamp: now,
                coordinate: coordinate,
                source: source,
                isLoopbackConnected: isLoopbackConnected
            ),
            at: 0
        )
        if recentLocations.count > 50 {
            recentLocations.removeLast(recentLocations.count - 50)
        }
        lastCoordinate = coordinate
        lastSource = source
        lastRecordedAt = now
    }
}

struct DiagnosticsView: View {
    @EnvironmentObject private var engine: SpoofEngine
    @EnvironmentObject private var diagnosticsStore: DiagnosticsStore
    @StateObject private var backgroundKeeper = BackgroundKeeper.shared
    @State private var routeDiagnostics = RouteProvider.DiagnosticsSnapshot.empty

    var body: some View {
        List {
            Section("Engine") {
                DiagnosticsRow(
                    title: "Nguồn đang điều khiển",
                    value: engine.activeSource?.displayName ?? "Không có",
                    color: engine.activeSource == nil ? .secondary : .blue
                )
                DiagnosticsRow(
                    title: "Arbiter",
                    value: engine.isHalted ? "Đã khóa" : "Sẵn sàng",
                    color: engine.isHalted ? .red : .green
                )
                DiagnosticsRow(
                    title: "Kết nối DVT",
                    value: engine.isLoopbackConnected ? "Đã kết nối" : "Chưa kết nối",
                    color: engine.isLoopbackConnected ? .green : .orange
                )
                DiagnosticsRow(
                    title: "Mô phỏng vị trí",
                    value: engine.isSimulating ? "Đang chạy" : "Đã dừng",
                    color: engine.isSimulating ? .green : .secondary
                )

                if let lastSpoofedAt = engine.lastSpoofedAt {
                    DiagnosticsRow(
                        title: "Lần gửi gần nhất",
                        value: lastSpoofedAt.formatted(date: .omitted, time: .standard),
                        color: .secondary
                    )
                }

                if let error = engine.lastFFIError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }

            Section("Chạy ngầm") {
                DiagnosticsRow(
                    title: "Silent audio",
                    value: backgroundKeeper.isAudioRunning ? "Đang chạy" : "Đã dừng",
                    color: backgroundKeeper.isAudioRunning ? .green : .red
                )
                DiagnosticsRow(
                    title: "Cập nhật vị trí nền",
                    value: backgroundKeeper.isLocationUpdating ? "Đang chạy" : "Đã dừng",
                    color: backgroundKeeper.isLocationUpdating ? .green : .orange
                )
                DiagnosticsRow(
                    title: "Quyền vị trí",
                    value: locationAuthorizationLabel,
                    color: backgroundKeeper.authorizationStatus == .authorizedAlways ? .green : .orange
                )
                DiagnosticsRow(
                    title: "Số lần audio gián đoạn",
                    value: "\(backgroundKeeper.interruptionCount)",
                    color: backgroundKeeper.interruptionCount == 0 ? .secondary : .orange
                )
            }

            Section("Tuyến đường") {
                DiagnosticsRow(
                    title: "Nguồn tuyến cuối",
                    value: routeDiagnostics.lastSource?.displayName ?? "Chưa có tuyến",
                    color: routeDiagnostics.lastSource == .straightLineFallback ? .orange : .green
                )
                DiagnosticsRow(
                    title: "Tuyến MKDirections",
                    value: "\(routeDiagnostics.mapKitRouteCount)",
                    color: .secondary
                )
                DiagnosticsRow(
                    title: "Số lần fallback",
                    value: "\(routeDiagnostics.fallbackCount)",
                    color: routeDiagnostics.fallbackCount == 0 ? .secondary : .orange
                )
                DiagnosticsRow(
                    title: "Mục trong cache",
                    value: "\(routeDiagnostics.cacheEntryCount)",
                    color: .secondary
                )

                if let updatedAt = routeDiagnostics.lastUpdatedAt {
                    DiagnosticsRow(
                        title: "Cập nhật tuyến cuối",
                        value: updatedAt.formatted(date: .omitted, time: .standard),
                        color: .secondary
                    )
                }

                if let error = routeDiagnostics.lastErrorDescription {
                    Label(error, systemImage: "arrow.triangle.branch")
                        .font(.caption)
                        .foregroundColor(.orange)
                }

                Button("Đặt lại thống kê tuyến") {
                    Task {
                        await RouteProvider.shared.resetDiagnostics()
                        routeDiagnostics = await RouteProvider.shared.diagnosticsSnapshot()
                    }
                }
            }

            Section("50 tọa độ gần nhất") {
                if diagnosticsStore.recentLocations.isEmpty {
                    Text("Chưa ghi nhận tọa độ mô phỏng nào trong phiên này.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(diagnosticsStore.recentLocations) { sample in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(sample.timestamp.formatted(date: .omitted, time: .standard))
                                    .font(.caption.monospacedDigit())
                                Spacer()
                                Text(sample.source?.displayName ?? "Không rõ nguồn")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            Text(String(
                                format: "%.6f, %.6f",
                                sample.coordinate.latitude,
                                sample.coordinate.longitude
                            ))
                            .font(.system(.caption, design: .monospaced))
                            Label(
                                sample.isLoopbackConnected ? "DVT đã kết nối" : "DVT chưa kết nối",
                                systemImage: sample.isLoopbackConnected ? "link.circle.fill" : "link.badge.plus"
                            )
                            .font(.caption2)
                            .foregroundColor(sample.isLoopbackConnected ? .green : .orange)
                        }
                        .padding(.vertical, 2)
                    }

                    Button("Xóa lịch sử tọa độ", role: .destructive) {
                        diagnosticsStore.clear()
                    }
                }
            }
        }
        .navigationTitle("Chẩn đoán")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            while !Task.isCancelled {
                routeDiagnostics = await RouteProvider.shared.diagnosticsSnapshot()
                do {
                    try await Task.sleep(for: .seconds(1))
                } catch {
                    break
                }
            }
        }
    }

    private var locationAuthorizationLabel: String {
        switch backgroundKeeper.authorizationStatus {
        case .authorizedAlways:
            return "Luôn luôn"
        case .authorizedWhenInUse:
            return "Khi dùng app"
        case .denied:
            return "Đã từ chối"
        case .restricted:
            return "Bị hạn chế"
        case .notDetermined:
            return "Chưa quyết định"
        @unknown default:
            return "Không xác định"
        }
    }
}

private struct DiagnosticsRow: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .font(.caption)
                .foregroundColor(color)
                .multilineTextAlignment(.trailing)
        }
    }
}
