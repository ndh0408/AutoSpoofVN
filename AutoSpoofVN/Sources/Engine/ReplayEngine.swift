//
//  ReplayEngine.swift
//  AutoSpoofVN
//
//  Replays recorded simulation tracks at customizable time warps without external route dependencies.
//

import Combine
import CoreLocation
import Foundation

@MainActor
public final class ReplayEngine: ObservableObject {
    public static let shared = ReplayEngine()

    @Published public private(set) var isReplaying: Bool = false
    @Published public private(set) var currentTrackIndex: Int = 0
    @Published public private(set) var totalPoints: Int = 0
    @Published public var replayMultiplier: Double = 1.0 // 1x, 5x, 10x, 30x
    @Published public private(set) var activeSession: SimulationSession? = nil

    private var replayTimer: Timer?
    private var coordinates: [CLLocationCoordinate2D] = []

    public init() {}

    public func startReplay(session: SimulationSession) {
        stopReplay()
        guard !session.recordedTrack.isEmpty else { return }

        self.activeSession = session
        self.coordinates = session.recordedTrack.map(\.clCoordinate)
        self.totalPoints = coordinates.count
        self.currentTrackIndex = 0
        self.isReplaying = true

        startTimer()
    }

    public func pauseReplay() {
        replayTimer?.invalidate()
        replayTimer = nil
        isReplaying = false
    }

    public func resumeReplay() {
        guard currentTrackIndex < coordinates.count else { return }
        isReplaying = true
        startTimer()
    }

    public func stopReplay() {
        replayTimer?.invalidate()
        replayTimer = nil
        isReplaying = false
        activeSession = nil
        coordinates = []
        currentTrackIndex = 0
    }

    public func seek(to fraction: Double) {
        guard !coordinates.isEmpty else { return }
        let index = Int(Double(coordinates.count - 1) * max(0, min(1.0, fraction)))
        self.currentTrackIndex = index
        let coord = coordinates[index]
        SimulationCoordinator.shared.setManualLocation(coord)
    }

    private func startTimer() {
        replayTimer?.invalidate()
        let interval = 0.5 / replayMultiplier
        replayTimer = Timer.scheduledTimer(withTimeInterval: max(0.05, interval), repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tickReplay()
            }
        }
    }

    private func tickReplay() {
        guard currentTrackIndex < coordinates.count else {
            stopReplay()
            return
        }
        let coord = coordinates[currentTrackIndex]
        SimulationCoordinator.shared.setManualLocation(coord)
        currentTrackIndex += 1
    }
}
