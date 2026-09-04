import CoreLocation
import SwiftUI

/// Chu trình 24/7 — đường thời gian một ngày.
///
/// Thay cho `RoutineStudioView`, vốn có ba vấn đề:
/// 1. Không có đường vào nào trong app (`showRoutineStudio` không bao giờ được bật).
/// 2. Lịch soạn ra chỉ nằm trong `routines.json`, engine không đọc.
/// 3. Không sửa được Nhà/Công ty/Quán cà phê — closure `onUpdate` không có ai gọi.
struct RoutineScreen: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var routine = RoutineManager.shared

    @State private var editing: RoutineSchedule?
    @State private var isCreating = false
    @State private var placeBeingEdited: RoutinePlaceKind?

    /// Ba địa điểm cố định mà chu trình mặc định dựa vào.
    private enum RoutinePlaceKind: String, Identifiable {
        case home, work, cafe
        var id: String { rawValue }

        var titleKey: String {
            switch self {
            case .home: return "routine.place.home"
            case .work: return "routine.place.work"
            case .cafe: return "routine.place.cafe"
            }
        }

        var symbol: String {
            switch self {
            case .home: return "house.fill"
            case .work: return "building.2.fill"
            case .cafe: return "cup.and.saucer.fill"
            }
        }

        var tint: Color {
            switch self {
            case .home: return AppColor.success
            case .work: return AppColor.accent
            case .cafe: return AppColor.warning
            }
        }

        /// Khoá mà `RoutineManager.updateLocation(for:coordinate:)` mong đợi.
        var storageKey: String { rawValue }
    }

    /// Lịch đã sắp theo giờ trong ngày — đường thời gian phải đọc từ trên xuống.
    private var sortedSchedules: [RoutineSchedule] {
        routine.schedules.sorted { ($0.hour * 60 + $0.minute) < ($1.hour * 60 + $1.minute) }
    }

    var body: some View {
        NavigationStack {
            List {
                statusSection
                timelineSection
                placesSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle(L("routine.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("action.close")) { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isCreating = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibleButton(label: L("routine.add"))
                }
            }
            .sheet(isPresented: $isCreating) {
                RoutineEditor(schedule: nil, defaultStart: routine.homeLocation,
                              defaultEnd: routine.workLocation) { saved in
                    routine.schedules.append(saved)
                }
            }
            .sheet(item: $editing) { schedule in
                RoutineEditor(schedule: schedule, defaultStart: routine.homeLocation,
                              defaultEnd: routine.workLocation) { saved in
                    if let index = routine.schedules.firstIndex(where: { $0.id == saved.id }) {
                        routine.schedules[index] = saved
                    }
                }
            }
            .sheet(item: $placeBeingEdited) { kind in
                LocationPickerSheet(title: L(kind.titleKey),
                                    initialCoordinate: coordinate(for: kind)) { picked in
                    routine.updateLocation(for: kind.storageKey, coordinate: picked)
                }
            }
        }
    }

    // MARK: - Trạng thái

    private var statusSection: some View {
        Section {
            Toggle(isOn: Binding(get: { routine.isAutoRoutineEnabled },
                                 set: { _ in
                                     AppHaptics.toggle()
                                     routine.toggleAutoRoutine()
                                 })) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(L("routine.enable"))
                        .font(AppFont.body)
                    Text(routine.statusDescription)
                        .font(AppFont.caption1)
                        .foregroundStyle(AppColor.textSecondary)
                        .lineLimit(2)
                }
            }

            if routine.isAutoRoutineEnabled {
                MetricRow(L("routine.current_state"), value: routine.currentState.displayName,
                          icon: routine.currentState.icon, monospaced: false)
                MetricRow(L("routine.current_speed"),
                          value: "\(AppFormat.speed(routine.currentSpeedKmh)) km/h",
                          icon: "speedometer")
            }
        } footer: {
            Text(routine.schedules.isEmpty
                 ? L("routine.footer.default_rhythm")
                 : L("routine.footer.custom", routine.schedules.filter(\.isEnabled).count))
        }
    }

    // MARK: - Đường thời gian

    @ViewBuilder
    private var timelineSection: some View {
        Section {
            if sortedSchedules.isEmpty {
                EmptyStateView(icon: "clock.badge.questionmark",
                               title: L("routine.empty"),
                               message: L("routine.empty_message"),
                               actionTitle: L("routine.add")) { isCreating = true }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            } else {
                ForEach(sortedSchedules) { schedule in
                    Button {
                        editing = schedule
                    } label: {
                        RoutineTimelineRow(schedule: schedule)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            routine.schedules.removeAll { $0.id == schedule.id }
                        } label: {
                            Label(L("action.delete"), systemImage: "trash")
                        }
                        Button {
                            toggleEnabled(schedule)
                        } label: {
                            Label(schedule.isEnabled ? L("routine.disable") : L("routine.enable_one"),
                                  systemImage: schedule.isEnabled ? "pause" : "play")
                        }
                        .tint(AppColor.warning)
                    }
                }
            }
        } header: {
            Text(L("routine.timeline"))
        } footer: {
            if !sortedSchedules.isEmpty {
                Text(L("routine.timeline.footer"))
            }
        }
    }

    private func toggleEnabled(_ schedule: RoutineSchedule) {
        guard let index = routine.schedules.firstIndex(where: { $0.id == schedule.id }) else { return }
        routine.schedules[index].isEnabled.toggle()
        AppHaptics.toggle()
    }

    // MARK: - Địa điểm cố định

    private var placesSection: some View {
        Section {
            ForEach([RoutinePlaceKind.home, .work, .cafe]) { kind in
                Button {
                    placeBeingEdited = kind
                } label: {
                    HStack(spacing: AppSpacing.md) {
                        Image(systemName: kind.symbol)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white)
                            .frame(width: 29, height: 29)
                            .background(kind.tint, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(L(kind.titleKey))
                                .font(AppFont.body)
                                .foregroundStyle(AppColor.textPrimary)
                            Text(AppFormat.coordinate(coordinate(for: kind)))
                                .font(AppFont.monoFootnote)
                                .foregroundStyle(AppColor.textTertiary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AppColor.textQuaternary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityHint(L("routine.place.hint"))
            }
        } header: {
            Text(L("routine.places"))
        } footer: {
            Text(L("routine.places.footer"))
        }
    }

    private func coordinate(for kind: RoutinePlaceKind) -> CLLocationCoordinate2D {
        switch kind {
        case .home: return routine.homeLocation
        case .work: return routine.workLocation
        case .cafe: return routine.cafeLocation
        }
    }
}

// MARK: - Một mốc trên đường thời gian

struct RoutineTimelineRow: View {
    let schedule: RoutineSchedule

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.md) {
            // Cột giờ — căn phải để các mốc thẳng hàng, đọc dọc được như một thời gian biểu.
            Text(schedule.timeString)
                .font(AppFont.monoFootnote.weight(.semibold))
                .foregroundStyle(schedule.isEnabled ? AppColor.primary : AppColor.textTertiary)
                .frame(width: 46, alignment: .trailing)

            VStack(alignment: .leading, spacing: 3) {
                Text(schedule.name)
                    .font(AppFont.callout)
                    .foregroundStyle(schedule.isEnabled ? AppColor.textPrimary : AppColor.textTertiary)
                    .lineLimit(1)

                HStack(spacing: AppSpacing.xs) {
                    Label(schedule.travelMode.displayName, systemImage: schedule.travelMode.icon)
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.accent)
                    if !daysLabel.isEmpty {
                        Text("· \(daysLabel)")
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.textTertiary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer(minLength: AppSpacing.xs)

            if !schedule.isEnabled {
                Image(systemName: "pause.circle.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(AppColor.textQuaternary)
            }
        }
        .padding(.vertical, AppSpacing.xxs)
        .opacity(schedule.isEnabled ? 1 : 0.6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(schedule.timeString), \(schedule.name), \(schedule.travelMode.displayName)"
                            + (schedule.isEnabled ? "" : ", \(L("routine.disabled"))"))
    }

    /// "T2–T6" nếu liền mạch, ngược lại liệt kê. Rỗng = mọi ngày.
    private var daysLabel: String {
        guard !schedule.days.isEmpty, schedule.days.count < 7 else { return "" }
        let names = [1: "T2", 2: "T3", 3: "T4", 4: "T5", 5: "T6", 6: "T7", 7: "CN"]
        let sorted = schedule.days.sorted()
        let isContiguous = sorted.count > 2 && sorted.last! - sorted.first! == sorted.count - 1
        if isContiguous, let first = names[sorted.first!], let last = names[sorted.last!] {
            return "\(first)–\(last)"
        }
        return sorted.compactMap { names[$0] }.joined(separator: " ")
    }
}

#Preview {
    RoutineScreen()
}
