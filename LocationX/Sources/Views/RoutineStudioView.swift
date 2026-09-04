import CoreLocation
import MapKit
import SwiftUI

/// Routine Studio — lập lịch mô phỏng theo thói quen.
struct RoutineStudioView: View {
    @StateObject private var routine = RoutineManager.shared
    @State private var schedules: [RoutineSchedule] = PersistenceManager.shared.loadRoutineSchedules()
    @State private var showEditor = false
    @State private var editingSchedule: RoutineSchedule?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                // Quick toggle
                Section {
                    Toggle(isOn: Binding(
                        get: { routine.isAutoRoutineEnabled },
                        set: { _ in routine.toggleAutoRoutine() }
                    )) {
                        VStack(alignment: .leading, spacing: AppSpacing.xs) {
                            Text(L("routine.auto_cycle"))
                                .font(AppFont.body)
                            Text(routine.statusDescription)
                                .font(AppFont.caption)
                                .foregroundStyle(AppColor.textSecondary)
                        }
                    }

                    if routine.isAutoRoutineEnabled {
                        HStack {
                            StatusBadge(routine.currentState.rawValue, color: .green, icon: routine.currentState.icon)
                            Spacer()
                            if routine.currentSpeedKmh > 0 {
                                Text(String(format: "%.1f km/h", routine.currentSpeedKmh))
                                    .font(AppFont.mono)
                            }
                        }
                    }
                } header: {
                    Label(L("routine.section.cycle"), systemImage: "clock.arrow.2.circlepath")
                }

                // Locations
                Section {
                    LocationRow(label: L("routine.location.home"), icon: "house.fill", color: .green,
                               coordinate: routine.homeLocation) { coord in
                        routine.updateLocation(for: "home", coordinate: coord)
                    }
                    LocationRow(label: L("routine.location.work"), icon: "briefcase.fill", color: .blue,
                               coordinate: routine.workLocation) { coord in
                        routine.updateLocation(for: "work", coordinate: coord)
                    }
                    LocationRow(label: L("routine.location.cafe"), icon: "cup.and.saucer.fill", color: .brown,
                               coordinate: routine.cafeLocation) { coord in
                        routine.updateLocation(for: "cafe", coordinate: coord)
                    }
                } header: {
                    Label(L("routine.section.locations"), systemImage: "mappin.and.ellipse")
                }

                // Schedules
                Section {
                    if schedules.isEmpty {
                        VStack(spacing: AppSpacing.sm) {
                            Text(L("routine.schedule.empty"))
                                .font(AppFont.footnote)
                                .foregroundStyle(AppColor.textSecondary)
                            Text(L("routine.schedule.empty.message"))
                                .font(AppFont.caption)
                                .foregroundStyle(AppColor.textTertiary)
                        }
                    } else {
                        ForEach(schedules) { schedule in
                            ScheduleRow(schedule: schedule) {
                                editingSchedule = schedule
                                showEditor = true
                            }
                        }
                        .onDelete { indices in
                            schedules.remove(atOffsets: indices)
                            PersistenceManager.shared.saveRoutineSchedules(schedules)
                        }
                    }

                    Button {
                        editingSchedule = RoutineSchedule(
                            name: L("routine.schedule.new_name"),
                            time: "08:00",
                            days: [2,3,4,5,6], // Mon-Fri
                            start: routine.homeLocation,
                            end: routine.workLocation
                        )
                        showEditor = true
                    } label: {
                        Label(L("routine.schedule.add"), systemImage: "plus")
                    }
                } header: {
                    Label(L("routine.section.schedules"), systemImage: "calendar")
                }

                // Default schedule reference
                Section {
                    VStack(alignment: .leading, spacing: AppSpacing.sm) {
                        Text(L("routine.default_schedule"))
                            .font(AppFont.headline)
                        Group {
                            ScheduleInfoRow(time: "07:00–07:30", activity: L("routine.activity.home_to_work"), icon: "car.fill")
                            ScheduleInfoRow(time: "07:30–12:00", activity: L("routine.activity.working"), icon: "briefcase.fill")
                            ScheduleInfoRow(time: "12:00–13:00", activity: L("routine.activity.lunch_break"), icon: "cup.and.saucer.fill")
                            ScheduleInfoRow(time: "13:00–17:30", activity: L("routine.activity.working"), icon: "briefcase.fill")
                            ScheduleInfoRow(time: "17:30–18:00", activity: L("routine.activity.work_to_home"), icon: "car.fill")
                            ScheduleInfoRow(time: "18:00–19:30", activity: L("routine.activity.walk"), icon: "figure.walk")
                            ScheduleInfoRow(time: "22:00–07:00", activity: L("routine.activity.sleeping"), icon: "bed.double.fill")
                        }
                    }
                } header: {
                    Label(L("routine.section.reference"), systemImage: "info.circle")
                }
            }
            .navigationTitle("Routine Studio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(L("action.close")) { dismiss() }
                }
            }
            .sheet(isPresented: $showEditor) {
                if let schedule = editingSchedule {
                    ScheduleEditorView(schedule: schedule) { updated in
                        if let idx = schedules.firstIndex(where: { $0.id == updated.id }) {
                            schedules[idx] = updated
                        } else {
                            schedules.append(updated)
                        }
                        PersistenceManager.shared.saveRoutineSchedules(schedules)
                        showEditor = false
                    }
                }
            }
        }
    }
}

// MARK: - Supporting Views

struct LocationRow: View {
    let label: String
    let icon: String
    let color: Color
    let coordinate: CLLocationCoordinate2D
    let onUpdate: (CLLocationCoordinate2D) -> Void

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(AppFont.body)
                Text(String(format: "%.4f, %.4f", coordinate.latitude, coordinate.longitude))
                    .font(AppFont.mono)
                    .foregroundStyle(AppColor.textTertiary)
            }
        }
    }
}

struct ScheduleRow: View {
    let schedule: RoutineSchedule
    let onEdit: () -> Void

    var body: some View {
        Button(action: onEdit) {
            HStack {
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    HStack {
                        Text(schedule.timeString)
                            .font(AppFont.monoBody.weight(.medium))
                        Text(schedule.name)
                            .font(AppFont.body)
                    }
                    HStack(spacing: AppSpacing.xs) {
                        Image(systemName: schedule.travelMode.icon)
                            .font(.caption)
                        Text(daysText(schedule.days))
                            .font(AppFont.caption)
                    }
                    .foregroundStyle(AppColor.textSecondary)
                }
                Spacer()
                Image(systemName: schedule.isEnabled ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(schedule.isEnabled ? .green : AppColor.textTertiary)
            }
        }
    }

    private func daysText(_ days: Set<Int>) -> String {
        if days.count == 7 { return L("routine.days.daily") }
        if days == Set([2,3,4,5,6]) { return L("routine.days.weekdays") }
        return days.sorted().compactMap { RoutineDayNames.short(for: $0) }.joined(separator: ", ")
    }
}

// subscript(safe:) chuyen ve Engine/Route/RouteSimulator.swift (module-wide) de tranh
// "invalid redeclaration" khi hai file cung khai bao private extension Array trung chu ky.

/// Ten viet tat cac ngay trong tuan, dung chung cho danh sach lich va trinh soan lich.
/// Index theo quy uoc `Calendar` cua Apple: 1 = Chu nhat ... 7 = Thu bay.
enum RoutineDayNames {
    static let indices = Array(1...7)

    static func short(for index: Int) -> String? {
        guard let key = key(for: index) else { return nil }
        return L(key)
    }

    private static func key(for index: Int) -> String? {
        switch index {
        case 1: return "routine.day.sun"
        case 2: return "routine.day.mon"
        case 3: return "routine.day.tue"
        case 4: return "routine.day.wed"
        case 5: return "routine.day.thu"
        case 6: return "routine.day.fri"
        case 7: return "routine.day.sat"
        default: return nil
        }
    }
}

struct ScheduleInfoRow: View {
    let time: String
    let activity: String
    let icon: String

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            Text(time)
                .font(AppFont.mono)
                .foregroundStyle(AppColor.textSecondary)
                .frame(width: 100, alignment: .leading)
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(AppColor.textTertiary)
            Text(activity)
                .font(AppFont.footnote)
        }
    }
}

// MARK: - Schedule Editor

struct ScheduleEditorView: View {
    @State var schedule: RoutineSchedule
    let onSave: (RoutineSchedule) -> Void
    @Environment(\.dismiss) private var dismiss

    private let dayIndices = RoutineDayNames.indices

    var body: some View {
        NavigationStack {
            Form {
                Section(L("common.info")) {
                    TextField(L("common.name"), text: $schedule.name)
                    TextField(L("routine.schedule.time_field"), text: $schedule.timeString)
                        .keyboardType(.numbersAndPunctuation)
                    Toggle(L("common.enabled"), isOn: $schedule.isEnabled)
                }

                Section(L("routine.section.weekdays")) {
                    HStack {
                        ForEach(dayIndices, id: \.self) { day in
                            Button {
                                if schedule.days.contains(day) {
                                    schedule.days.remove(day)
                                } else {
                                    schedule.days.insert(day)
                                }
                            } label: {
                                Text(RoutineDayNames.short(for: day) ?? "")
                                    .font(AppFont.caption.weight(.medium))
                                    .frame(width: 32, height: 32)
                                    .background(schedule.days.contains(day) ? AppColor.primary : AppColor.surfaceTertiary)
                                    .foregroundStyle(schedule.days.contains(day) ? .white : AppColor.textPrimary)
                                    .clipShape(Circle())
                            }
                        }
                    }
                }

                Section(L("common.travel_mode")) {
                    Picker(L("common.travel_mode"), selection: $schedule.travelMode) {
                        ForEach(TravelMode.allCases) { mode in
                            Label(mode.displayName, systemImage: mode.icon).tag(mode)
                        }
                    }
                }
            }
            .navigationTitle(L("routine.schedule.edit_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(L("action.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(L("action.save")) { onSave(schedule); dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }
}
