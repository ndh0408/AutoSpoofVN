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
                            Text("Chu trình tự động 24/7")
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
                    Label("Chu trình", systemImage: "clock.arrow.2.circlepath")
                }

                // Locations
                Section {
                    LocationRow(label: "Nhà", icon: "house.fill", color: .green,
                               coordinate: routine.homeLocation) { coord in
                        routine.updateLocation(for: "home", coordinate: coord)
                    }
                    LocationRow(label: "Công ty", icon: "briefcase.fill", color: .blue,
                               coordinate: routine.workLocation) { coord in
                        routine.updateLocation(for: "work", coordinate: coord)
                    }
                    LocationRow(label: "Quán cà phê", icon: "cup.and.saucer.fill", color: .brown,
                               coordinate: routine.cafeLocation) { coord in
                        routine.updateLocation(for: "cafe", coordinate: coord)
                    }
                } header: {
                    Label("Địa điểm", systemImage: "mappin.and.ellipse")
                }

                // Schedules
                Section {
                    if schedules.isEmpty {
                        VStack(spacing: AppSpacing.sm) {
                            Text("Chưa có lịch trình tuỳ chỉnh")
                                .font(AppFont.footnote)
                                .foregroundStyle(AppColor.textSecondary)
                            Text("Đang dùng lịch trình mặc định theo khung giờ Việt Nam.")
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
                            name: "Lịch mới",
                            time: "08:00",
                            days: [2,3,4,5,6], // Mon-Fri
                            start: routine.homeLocation,
                            end: routine.workLocation
                        )
                        showEditor = true
                    } label: {
                        Label("Thêm lịch trình", systemImage: "plus")
                    }
                } header: {
                    Label("Lịch trình", systemImage: "calendar")
                }

                // Default schedule reference
                Section {
                    VStack(alignment: .leading, spacing: AppSpacing.sm) {
                        Text("Lịch mặc định")
                            .font(AppFont.headline)
                        Group {
                            ScheduleInfoRow(time: "07:00–07:30", activity: "Nhà → Công ty", icon: "car.fill")
                            ScheduleInfoRow(time: "07:30–12:00", activity: "Làm việc", icon: "briefcase.fill")
                            ScheduleInfoRow(time: "12:00–13:00", activity: "Nghỉ trưa / Cà phê", icon: "cup.and.saucer.fill")
                            ScheduleInfoRow(time: "13:00–17:30", activity: "Làm việc", icon: "briefcase.fill")
                            ScheduleInfoRow(time: "17:30–18:00", activity: "Công ty → Nhà", icon: "car.fill")
                            ScheduleInfoRow(time: "18:00–19:30", activity: "Đi dạo", icon: "figure.walk")
                            ScheduleInfoRow(time: "22:00–07:00", activity: "Ngủ", icon: "bed.double.fill")
                        }
                    }
                } header: {
                    Label("Tham khảo", systemImage: "info.circle")
                }
            }
            .navigationTitle("Routine Studio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Đóng") { dismiss() }
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
        if days.count == 7 { return "Hàng ngày" }
        if days == Set([2,3,4,5,6]) { return "T2-T6" }
        let names = ["", "CN", "T2", "T3", "T4", "T5", "T6", "T7"]
        return days.sorted().compactMap { names[safe: $0] }.joined(separator: ", ")
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
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

    private let dayNames = [(1,"CN"),(2,"T2"),(3,"T3"),(4,"T4"),(5,"T5"),(6,"T6"),(7,"T7")]

    var body: some View {
        NavigationStack {
            Form {
                Section("Thông tin") {
                    TextField("Tên", text: $schedule.name)
                    TextField("Giờ (HH:mm)", text: $schedule.timeString)
                        .keyboardType(.numbersAndPunctuation)
                    Toggle("Bật", isOn: $schedule.isEnabled)
                }

                Section("Ngày trong tuần") {
                    HStack {
                        ForEach(dayNames, id: \.0) { day in
                            Button {
                                if schedule.days.contains(day.0) {
                                    schedule.days.remove(day.0)
                                } else {
                                    schedule.days.insert(day.0)
                                }
                            } label: {
                                Text(day.1)
                                    .font(AppFont.caption.weight(.medium))
                                    .frame(width: 32, height: 32)
                                    .background(schedule.days.contains(day.0) ? AppColor.primary : AppColor.surfaceTertiary)
                                    .foregroundStyle(schedule.days.contains(day.0) ? .white : AppColor.textPrimary)
                                    .clipShape(Circle())
                            }
                        }
                    }
                }

                Section("Phương tiện") {
                    Picker("Phương tiện", selection: $schedule.travelMode) {
                        ForEach(TravelMode.allCases) { mode in
                            Label(mode.displayName, systemImage: mode.icon).tag(mode)
                        }
                    }
                }
            }
            .navigationTitle("Chỉnh sửa lịch trình")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Huỷ") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Lưu") { onSave(schedule); dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }
}
