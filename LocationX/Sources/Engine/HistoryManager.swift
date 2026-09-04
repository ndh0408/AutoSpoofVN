import CoreLocation
import Foundation

/// Ghi lịch sử mô phỏng và hỗ trợ phát lại.
@MainActor
final class HistoryManager: ObservableObject {
    static let shared = HistoryManager()

    @Published var records: [SimulationRecord] = []
    @Published private(set) var isRecording = false

    private var activeRecordId: UUID?
    private var recordingBuffer: [TimestampedCoordinate] = []
    private var recordingStart: Date?
    /// Nguồn và phương tiện được ghi lại lúc BẮT ĐẦU.
    ///
    /// `stopRecording()` từng đọc `coordinator.activeSource` tại thời điểm dừng — nhưng
    /// lúc đó `stopSession()` đã nhả nguồn và xoá session, nên mọi dòng lịch sử đều bị
    /// gán "Thủ công", `travelMode` luôn là "Ô tô" và `routeName` luôn rỗng.
    private var recordingSource: SimulationSource = .manual
    private var recordingTravelMode: TravelMode = .driving
    private var recordingRouteName: String?
    private var recordingSessionId: UUID?
    private var sampleTimer: Timer?
    private let maxBufferSize = 5000
    private let sampleInterval: TimeInterval = 2.0 // sample mỗi 2s

    private init() {
        records = PersistenceManager.shared.loadHistory()
    }

    // MARK: - Recording

    func startRecording(source: SimulationSource, travelMode: TravelMode) {
        stopRecording() // dừng recording cũ nếu có
        activeRecordId = UUID()
        recordingBuffer = []
        recordingStart = Date()
        isRecording = true
        // Chụp lại bối cảnh NGAY BÂY GIỜ, khi nguồn còn đang giữ quyền.
        recordingSource = source
        recordingTravelMode = travelMode
        let coordinator = SimulationCoordinator.shared
        recordingRouteName = coordinator.session?.routeName
        recordingSessionId = coordinator.session?.id

        sampleTimer = Timer.scheduledTimer(withTimeInterval: sampleInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.sampleCurrentPosition()
            }
        }
    }

    @discardableResult
    func stopRecording() -> SimulationRecord? {
        sampleTimer?.invalidate()
        sampleTimer = nil
        isRecording = false

        guard let id = activeRecordId,
              let start = recordingStart,
              !recordingBuffer.isEmpty
        else {
            activeRecordId = nil
            return nil
        }

        let first = recordingBuffer.first!
        let last = recordingBuffer.last!

        // Tính tổng khoảng cách
        var totalDistance: Double = 0
        for i in 1..<recordingBuffer.count {
            totalDistance += MotionEngine.haversineDistance(
                from: recordingBuffer[i-1].coordinate.clCoordinate,
                to: recordingBuffer[i].coordinate.clCoordinate
            )
        }

        let record = SimulationRecord(
            id: id,
            sessionId: recordingSessionId ?? UUID(),
            source: recordingSource,
            startedAt: start,
            endedAt: Date(),
            startCoordinate: first.coordinate,
            endCoordinate: last.coordinate,
            distanceMeters: totalDistance,
            durationSeconds: Date().timeIntervalSince(start),
            travelMode: recordingTravelMode,
            routeName: recordingRouteName,
            replayData: recordingBuffer
        )

        // Lưu
        records.insert(record, at: 0)
        if records.count > 500 { records = Array(records.prefix(500)) }
        PersistenceManager.shared.saveHistory(records)

        activeRecordId = nil
        recordingBuffer = []
        return record
    }

    func deleteRecord(id: UUID) {
        records.removeAll { $0.id == id }
        PersistenceManager.shared.saveHistory(records)
    }

    func clearAll() {
        records.removeAll()
        PersistenceManager.shared.saveHistory(records)
    }

    private func sampleCurrentPosition() {
        guard isRecording, let start = recordingStart else { return }
        let coordinator = SimulationCoordinator.shared
        let coord = coordinator.currentCoordinate
        let telemetry = coordinator.telemetry

        guard recordingBuffer.count < maxBufferSize else { return }

        recordingBuffer.append(TimestampedCoordinate(
            timestamp: Date().timeIntervalSince(start),
            coordinate: CoordinateCodable(coord),
            speedKmh: telemetry.speedKmh,
            headingDegrees: telemetry.headingDegrees
        ))
    }
}

/// Phát lại một simulation record.
@MainActor
final class ReplayEngine: ObservableObject {
    static let shared = ReplayEngine()

    @Published private(set) var isPlaying = false
    @Published private(set) var progress: Double = 0
    @Published var playbackSpeed: Double = 1.0

    private var replayTask: Task<Void, Never>?
    private let coordinator = SimulationCoordinator.shared

    private init() {}

    func play(record: SimulationRecord) {
        guard let data = record.replayData, !data.isEmpty else { return }
        stop()

        guard coordinator.acquire(.replay) else { return }
        isPlaying = true

        replayTask = Task { [weak self] in
            guard let self else { return }
            let totalDuration = data.last!.timestamp

            for i in 0..<data.count {
                guard !Task.isCancelled, self.isPlaying else { break }
                let point = data[i]

                self.coordinator.submit(
                    coordinate: point.coordinate.clCoordinate,
                    from: .replay,
                    speedKmh: point.speedKmh,
                    headingDegrees: point.headingDegrees
                )
                self.progress = totalDuration > 0 ? point.timestamp / totalDuration : 0

                // Tính thời gian chờ đến point kế
                if i + 1 < data.count {
                    let gap = (data[i+1].timestamp - point.timestamp) / self.playbackSpeed
                    if gap > 0 {
                        try? await Task.sleep(nanoseconds: UInt64(gap * 1_000_000_000))
                    }
                }
            }

            if !Task.isCancelled {
                self.isPlaying = false
                self.progress = 1.0
                self.coordinator.release(.replay)
            }
        }
    }

    func pause() {
        isPlaying = false
        coordinator.pauseSession()
    }

    func resume() {
        isPlaying = true
        coordinator.resumeSession()
    }

    func stop() {
        replayTask?.cancel()
        replayTask = nil
        isPlaying = false
        progress = 0
        coordinator.release(.replay)
    }

    func seek(to fraction: Double) {
        progress = max(0, min(1, fraction))
    }
}
