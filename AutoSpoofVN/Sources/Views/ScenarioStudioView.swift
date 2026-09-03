//
//  ScenarioStudioView.swift
//  AutoSpoofVN
//
//  Scenario Studio: Visual automation builder for QA and multi-step location testing.
//

import SwiftUI

struct ScenarioStudioView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var scenarioEngine = ScenarioEngine.shared
    @State private var scenarios: [Scenario] = []
    @State private var selectedScenario: Scenario? = nil
    @State private var showingCreateSheet = false

    var body: some View {
        NavigationStack {
            List {
                if scenarioEngine.isRunning, let active = scenarioEngine.activeScenario {
                    Section("Kịch bản đang thực thi") {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "play.circle.fill")
                                    .foregroundColor(.green)
                                Text(active.name)
                                    .font(.headline)
                                Spacer()
                                Button("Dừng", role: .destructive) {
                                    scenarioEngine.stopScenario()
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                            Text(scenarioEngine.statusText)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            ProgressView(value: Double(scenarioEngine.currentStepIndex + 1), total: Double(max(1, active.steps.count)))
                                .tint(.green)
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section("Kịch bản có sẵn") {
                    if scenarios.isEmpty {
                        Text("Chưa có kịch bản nào. Bấm nút '+' để tạo kịch bản mới.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(scenarios) { scenario in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(scenario.name)
                                        .font(.headline)
                                    Spacer()
                                    if scenario.isLooping {
                                        Label("Lặp vô hạn", systemImage: "repeat")
                                            .font(.caption2)
                                            .foregroundColor(.blue)
                                    }
                                }
                                if !scenario.summary.isEmpty {
                                    Text(scenario.summary)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Text("\(scenario.steps.count) bước thực hiện")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)

                                HStack {
                                    Button {
                                        scenarioEngine.startScenario(scenario)
                                        dismiss()
                                    } label: {
                                        Label("Chạy kịch bản", systemImage: "play.fill")
                                            .font(.caption.weight(.bold))
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.small)
                                }
                                .padding(.top, 4)
                            }
                            .padding(.vertical, 4)
                        }
                        .onDelete(perform: deleteScenario)
                    }
                }
            }
            .navigationTitle("Scenario Studio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đóng") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        createDefaultScenario()
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .onAppear {
                scenarios = PersistenceManager.shared.loadScenarios()
            }
        }
    }

    private func deleteScenario(at offsets: IndexSet) {
        scenarios.remove(atOffsets: offsets)
        PersistenceManager.shared.saveScenarios(scenarios)
    }

    private func createDefaultScenario() {
        let newScenario = Scenario(
            name: "Kịch bản \(scenarios.count + 1)",
            summary: "Kịch bản tự động kiểm thử tuần tự nhiều địa điểm.",
            steps: [
                ScenarioStep(title: "Điểm xuất phát", actionType: .setLocation, targetCoordinate: CoordinateCodable(latitude: 21.0285, longitude: 105.8542)),
                ScenarioStep(title: "Chờ 5 giây", actionType: .waitSeconds, waitDurationSeconds: 5),
                ScenarioStep(title: "Đi dạo khu vực", actionType: .dwellArea, dwellRadiusMeters: 30)
            ]
        )
        scenarios.append(newScenario)
        PersistenceManager.shared.saveScenarios(scenarios)
    }
}
