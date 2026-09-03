import CoreLocation
import SwiftUI

/// Scenario Studio — tạo và chạy kịch bản tự động hoá.
struct ScenarioStudioView: View {
    @StateObject private var engine = ScenarioEngine.shared
    @State private var showEditor = false
    @State private var editingScenario: Scenario?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if engine.scenarios.isEmpty {
                    EmptyStateView(
                        icon: "list.bullet.clipboard",
                        title: L10n.noRoutes,
                        message: "Tạo kịch bản đầu tiên để tự động hoá mô phỏng GPS.",
                        actionTitle: "Tạo kịch bản"
                    ) {
                        editingScenario = Scenario(name: "Kịch bản mới")
                        showEditor = true
                    }
                } else {
                    List {
                        // Running scenario status
                        if engine.isRunning {
                            Section("Đang chạy") {
                                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                                    HStack {
                                        StatusBadge("Đang chạy", color: .green, icon: "play.fill")
                                        Spacer()
                                        Text("Bước \(engine.currentStepIndex + 1)")
                                            .font(AppFont.mono)
                                    }
                                    Text(engine.currentStepDescription)
                                        .font(AppFont.footnote)
                                        .foregroundStyle(AppColor.textSecondary)
                                    ProgressView(value: engine.progress)
                                    HStack {
                                        Button("Tạm dừng") { engine.pause() }
                                        Spacer()
                                        Button("Dừng", role: .destructive) { engine.stop() }
                                    }
                                    .font(AppFont.footnote.weight(.medium))
                                }
                            }
                        }

                        // Scenario list
                        Section("Kịch bản") {
                            ForEach(engine.scenarios) { scenario in
                                ScenarioRow(scenario: scenario) {
                                    engine.start(scenario: scenario)
                                } onEdit: {
                                    editingScenario = scenario
                                    showEditor = true
                                }
                            }
                            .onDelete { indices in
                                for i in indices {
                                    engine.deleteScenario(id: engine.scenarios[i].id)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Scenario Studio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Đóng") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        editingScenario = Scenario(name: "Kịch bản mới")
                        showEditor = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showEditor) {
                if let scenario = editingScenario {
                    ScenarioEditorView(scenario: scenario) { updated in
                        engine.saveScenario(updated)
                        showEditor = false
                    }
                }
            }
        }
    }
}

struct ScenarioRow: View {
    let scenario: Scenario
    let onRun: () -> Void
    let onEdit: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(scenario.name)
                    .font(AppFont.body)
                HStack(spacing: AppSpacing.sm) {
                    Text("\(scenario.steps.count) bước")
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textSecondary)
                    if scenario.isLoop {
                        StatusBadge("Lặp", color: .purple, icon: "repeat")
                    }
                }
            }
            Spacer()
            Button(action: onRun) {
                Image(systemName: "play.circle.fill")
                    .font(.title2)
                    .foregroundStyle(AppColor.primary)
            }
            Button(action: onEdit) {
                Image(systemName: "pencil.circle")
                    .font(.title2)
                    .foregroundStyle(AppColor.textSecondary)
            }
        }
        .padding(.vertical, AppSpacing.xs)
    }
}

// MARK: - Scenario Editor

struct ScenarioEditorView: View {
    @State var scenario: Scenario
    let onSave: (Scenario) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Thông tin") {
                    TextField("Tên kịch bản", text: $scenario.name)
                    Toggle("Lặp vô hạn", isOn: $scenario.isLoop)
                }

                Section("Các bước") {
                    ForEach(Array(scenario.steps.enumerated()), id: \.element.id) { index, step in
                        HStack {
                            Text("\(index + 1).")
                                .font(AppFont.mono)
                                .foregroundStyle(AppColor.textTertiary)
                            VStack(alignment: .leading) {
                                Text(step.action.displayName)
                                    .font(AppFont.body)
                                Text(stepDetail(step.action))
                                    .font(AppFont.caption)
                                    .foregroundStyle(AppColor.textSecondary)
                            }
                        }
                    }
                    .onDelete { indices in
                        scenario.steps.remove(atOffsets: indices)
                    }
                    .onMove { from, to in
                        scenario.steps.move(fromOffsets: from, toOffset: to)
                    }

                    Menu("Thêm bước") {
                        Button("Đặt vị trí", systemImage: "mappin") {
                            addStep(.setLocation(CoordinateCodable(latitude: 21.0285, longitude: 105.8542)))
                        }
                        Button("Di chuyển đến", systemImage: "arrow.right") {
                            addStep(.moveTo(CoordinateCodable(latitude: 21.03, longitude: 105.85), speedKmh: 30))
                        }
                        Button("Chờ", systemImage: "clock") {
                            addStep(.wait(seconds: 60))
                        }
                        Button("Dừng chân", systemImage: "pause") {
                            addStep(.dwell(seconds: 300))
                        }
                        Button("Di chuyển ngẫu nhiên", systemImage: "shuffle") {
                            addStep(.randomNearby(radiusMeters: 200, durationSeconds: 600))
                        }
                        Button("Đổi tốc độ", systemImage: "speedometer") {
                            addStep(.changeSpeed(kmh: 40))
                        }
                    }
                }
            }
            .navigationTitle("Chỉnh sửa kịch bản")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Huỷ") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Lưu") { onSave(scenario); dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private func addStep(_ action: ScenarioAction) {
        scenario.steps.append(ScenarioStep(action: action, order: scenario.steps.count))
    }

    private func stepDetail(_ action: ScenarioAction) -> String {
        switch action {
        case .setLocation(let c): return "\(String(format: "%.4f", c.latitude)), \(String(format: "%.4f", c.longitude))"
        case .moveTo(let c, let s): return "→ \(String(format: "%.4f", c.latitude)), \(String(format: "%.4f", c.longitude)) @ \(Int(s)) km/h"
        case .wait(let s): return "\(Int(s)) giây"
        case .dwell(let s): return "\(Int(s)) giây tại chỗ"
        case .changeSpeed(let s): return "\(Int(s)) km/h"
        case .changeTravelMode(let m): return m.displayName
        case .randomNearby(let r, let d): return "bán kính \(Int(r))m, \(Int(d))s"
        case .followRoute: return "Theo tuyến đường"
        case .pause: return "Tạm dừng kịch bản"
        case .resume: return "Tiếp tục"
        case .loop(let n): return "Lặp \(n) lần"
        }
    }
}
