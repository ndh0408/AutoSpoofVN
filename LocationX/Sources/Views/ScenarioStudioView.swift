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
                        message: L("empty.scenarios.message"),
                        actionTitle: L("scenario.create")
                    ) {
                        editingScenario = Scenario(name: L("scenario.new_name"))
                        showEditor = true
                    }
                } else {
                    List {
                        // Running scenario status
                        if engine.isRunning {
                            Section(L("scenario.running")) {
                                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                                    HStack {
                                        StatusBadge(L("scenario.running"), color: .green, icon: "play.fill")
                                        Spacer()
                                        Text(L("scenario.step_number", engine.currentStepIndex + 1))
                                            .font(AppFont.mono)
                                    }
                                    Text(engine.currentStepDescription)
                                        .font(AppFont.footnote)
                                        .foregroundStyle(AppColor.textSecondary)
                                    ProgressView(value: engine.progress)
                                    HStack {
                                        Button(L("action.pause")) { engine.pause() }
                                        Spacer()
                                        Button(L("action.stop"), role: .destructive) { engine.stop() }
                                    }
                                    .font(AppFont.footnote.weight(.medium))
                                }
                            }
                        }

                        // Scenario list
                        Section(L("scenario.section.list")) {
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
                    Button(L("action.close")) { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        editingScenario = Scenario(name: L("scenario.new_name"))
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
                    Text(L("scenario.step_count", scenario.steps.count))
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textSecondary)
                    if scenario.isLoop {
                        StatusBadge(L("scenario.loop"), color: .purple, icon: "repeat")
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

    /// Chi so buoc dang sua. `nil` = khong sua buoc nao.
    @State private var editingStepIndex: Int?
    @State private var isAddingStep = false

    var body: some View {
        NavigationStack {
            Form {
                Section(L("common.info")) {
                    TextField(L("scenario.name_field"), text: $scenario.name)
                    Toggle(L("scenario.loop_forever"), isOn: $scenario.isLoop)
                }

                Section(L("scenario.section.steps")) {
                    ForEach(Array(scenario.steps.enumerated()), id: \.element.id) { index, step in
                        // Cham de SUA. Truoc day danh sach nay chi doc: buoc duoc tao voi
                        // hang so viet cung va khong co duong nao chinh lai tham so.
                        Button {
                            editingStepIndex = index
                        } label: {
                            HStack {
                                Text("\(index + 1).")
                                    .font(AppFont.mono)
                                    .foregroundStyle(AppColor.textTertiary)
                                VStack(alignment: .leading) {
                                    Text(step.action.displayName)
                                        .font(AppFont.body)
                                        .foregroundStyle(AppColor.textPrimary)
                                    Text(stepDetail(step.action))
                                        .font(AppFont.caption)
                                        .foregroundStyle(AppColor.textSecondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(AppColor.textQuaternary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete { indices in
                        scenario.steps.remove(atOffsets: indices)
                    }
                    .onMove { from, to in
                        scenario.steps.move(fromOffsets: from, toOffset: to)
                    }

                    Button {
                        isAddingStep = true
                    } label: {
                        Label(L("scenario.add_step"), systemImage: "plus.circle")
                    }
                }
            }
            .navigationTitle(L("scenario.edit_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(L("action.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(L("action.save")) { onSave(scenario); dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $isAddingStep) {
                ScenarioStepEditor(initial: nil) { action in
                    addStep(action)
                }
            }
            .sheet(item: Binding(
                get: { editingStepIndex.map { StepIndex(value: $0) } },
                set: { editingStepIndex = $0?.value }
            )) { wrapper in
                ScenarioStepEditor(initial: scenario.steps[safe: wrapper.value]?.action) { action in
                    guard scenario.steps.indices.contains(wrapper.value) else { return }
                    scenario.steps[wrapper.value].action = action
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
        case .wait(let s): return L("scenario.detail.wait_seconds", Int(s))
        case .dwell(let s): return L("scenario.detail.dwell_seconds", Int(s))
        case .changeSpeed(let s): return "\(Int(s)) km/h"
        case .changeTravelMode(let m): return m.displayName
        case .randomNearby(let r, let d): return L("scenario.detail.random_nearby", Int(r), Int(d))
        case .followRoute: return L("scenario.detail.follow_route")
        case .pause: return L("scenario.detail.pause")
        case .resume: return L("action.resume")
        case .loop(let n): return L("scenario.detail.loop_count", n)
        }
    }
}


/// Boc chi so buoc de dung voi `.sheet(item:)`.
///
/// `Int` khong conform `Identifiable`, ma dung `.sheet(isPresented:)` kem mot bien chi so
/// rieng se mo sheet voi gia tri cu trong mot vong cap nhat.
private struct StepIndex: Identifiable {
    let value: Int
    var id: Int { value }
}
