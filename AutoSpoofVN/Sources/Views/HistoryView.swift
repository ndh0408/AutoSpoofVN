//
//  HistoryView.swift
//  AutoSpoofVN
//
//  Simulation History, Replay Studio, and GPX Export.
//

import SwiftUI

struct HistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var replayEngine = ReplayEngine.shared
    @ObservedObject private var coordinator = SimulationCoordinator.shared
    @State private var history: [SimulationSession] = []
    @State private var exportedGPX: String? = nil
    @State private var showingExportSheet = false

    var body: some View {
        NavigationStack {
            List {
                if replayEngine.isReplaying, let session = replayEngine.activeSession {
                    Section("Đang phát lại lộ trình (Replay)") {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Image(systemName: "play.circle.fill")
                                    .foregroundColor(.blue)
                                Text(session.name)
                                    .font(.headline)
                                Spacer()
                                Button("Dừng phát", role: .destructive) {
                                    replayEngine.stopReplay()
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }

                            HStack {
                                Text("Điểm: \(replayEngine.currentTrackIndex)/\(replayEngine.totalPoints)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Picker("Tốc độ", selection: $replayEngine.replayMultiplier) {
                                    Text("1x").tag(1.0)
                                    Text("5x").tag(5.0)
                                    Text("10x").tag(10.0)
                                    Text("30x").tag(30.0)
                                }
                                .pickerStyle(.segmented)
                                .frame(width: 160)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section("Lịch sử các phiên mô phỏng") {
                    if history.isEmpty {
                        Text("Chưa có phiên mô phỏng nào được ghi nhận.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(history) { session in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(session.name)
                                        .font(.headline)
                                    Spacer()
                                    Text(session.source.displayName)
                                        .font(.caption2)
                                        .foregroundColor(.blue)
                                }

                                HStack(spacing: 12) {
                                    Label("\(String(format: "%.1f", session.distanceTravelledMeters / 1000.0)) km", systemImage: "arrow.left.and.right")
                                    Label("\(Int(session.maxSpeedKmh)) km/h max", systemImage: "speedometer")
                                    Label("\(session.recordedTrack.count) điểm", systemImage: "point.filled.topleft.down.curvedto.point.bottomright.up")
                                }
                                .font(.caption2)
                                .foregroundColor(.secondary)

                                HStack {
                                    Button {
                                        replayEngine.startReplay(session: session)
                                    } label: {
                                        Label("Phát lại", systemImage: "play.fill")
                                            .font(.caption.weight(.bold))
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.small)
                                    .disabled(session.recordedTrack.isEmpty)

                                    Button {
                                        let gpx = PersistenceManager.shared.exportToGPX(track: session.recordedTrack, name: session.name)
                                        self.exportedGPX = gpx
                                        self.showingExportSheet = true
                                    } label: {
                                        Label("Xuất GPX", systemImage: "square.and.arrow.up")
                                            .font(.caption)
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                    .disabled(session.recordedTrack.isEmpty)
                                }
                                .padding(.top, 2)
                            }
                            .padding(.vertical, 4)
                        }
                        .onDelete(perform: deleteHistory)
                    }
                }
            }
            .navigationTitle("Lịch sử & Replay")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đóng") { dismiss() }
                }
            }
            .onAppear {
                history = PersistenceManager.shared.loadHistory()
                if history.isEmpty, !coordinator.recentTracks.isEmpty {
                    let sample = SimulationSession(
                        name: "Phiên gần nhất",
                        source: coordinator.activeSource,
                        startCoordinate: CoordinateCodable(coordinator.recentTracks.first!),
                        currentCoordinate: CoordinateCodable(coordinator.recentTracks.last!),
                        totalDistanceMeters: Double(coordinator.recentTracks.count * 20),
                        distanceTravelledMeters: Double(coordinator.recentTracks.count * 20),
                        maxSpeedKmh: 45,
                        recordedTrack: coordinator.recentTracks.map { CoordinateCodable($0) }
                    )
                    history.append(sample)
                    PersistenceManager.shared.saveHistory(history)
                }
            }
            .sheet(isPresented: $showingExportSheet) {
                if let gpx = exportedGPX {
                    NavigationStack {
                        ScrollView {
                            Text(gpx)
                                .font(.system(.caption, design: .monospaced))
                                .padding()
                        }
                        .navigationTitle("Nội dung GPX")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Xong") { showingExportSheet = false }
                            }
                        }
                    }
                }
            }
        }
    }

    private func deleteHistory(at offsets: IndexSet) {
        history.remove(atOffsets: offsets)
        PersistenceManager.shared.saveHistory(history)
    }
}
