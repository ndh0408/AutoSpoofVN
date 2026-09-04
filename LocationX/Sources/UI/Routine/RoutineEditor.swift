import CoreLocation
import SwiftUI

/// Soạn một mốc trong chu trình 24/7.
///
/// Trước đây trình soạn lịch tồn tại nhưng dữ liệu nó tạo ra không engine nào đọc. Nay
/// `RoutineManager.schedules` là nguồn thật, nên mọi thứ chỉnh ở đây đều có hiệu lực.
struct RoutineEditor: View {
    /// `nil` = tạo mới.
    let schedule: RoutineSchedule?
    let defaultStart: CLLocationCoordinate2D
    let defaultEnd: CLLocationCoordinate2D
    let onSave: (RoutineSchedule) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var time: Date
    @State private var days: Set<Int>
    @State private var travelMode: TravelMode
    @State private var start: CLLocationCoordinate2D
    @State private var end: CLLocationCoordinate2D
    @State private var picking: Endpoint?

    private enum Endpoint: String, Identifiable {
        case start, end
        var id: String { rawValue }
    }

    private static let weekdayNames = [1: "T2", 2: "T3", 3: "T4", 4: "T5", 5: "T6", 6: "T7", 7: "CN"]

    init(schedule: RoutineSchedule?,
         defaultStart: CLLocationCoordinate2D,
         defaultEnd: CLLocationCoordinate2D,
         onSave: @escaping (RoutineSchedule) -> Void) {
        self.schedule = schedule
        self.defaultStart = defaultStart
        self.defaultEnd = defaultEnd
        self.onSave = onSave

        _name = State(initialValue: schedule?.name ?? "")
        _days = State(initialValue: schedule?.days ?? Set(1...5))
        _travelMode = State(initialValue: schedule?.travelMode ?? .driving)
        _start = State(initialValue: schedule?.startLocation.clCoordinate ?? defaultStart)
        _end = State(initialValue: schedule?.endLocation.clCoordinate ?? defaultEnd)

        var components = DateComponents()
        components.hour = schedule?.hour ?? 8
        components.minute = schedule?.minute ?? 0
        _time = State(initialValue: Calendar.current.date(from: components) ?? Date())
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(L("routine.editor.basics")) {
                    TextField(L("routine.editor.name"), text: $name)
                        .textInputAutocapitalization(.sentences)
                    DatePicker(L("routine.editor.time"), selection: $time,
                               displayedComponents: .hourAndMinute)
                }

                Section {
                    weekdayPicker
                } header: {
                    Text(L("routine.editor.days"))
                } footer: {
                    Text(days.isEmpty ? L("routine.editor.days.every")
                                      : L("routine.editor.days.footer"))
                }

                Section(L("routine.editor.route")) {
                    endpointRow(.start, label: L("routine.editor.from"),
                                coordinate: start, symbol: "location.circle.fill",
                                tint: AppColor.success)
                    endpointRow(.end, label: L("routine.editor.to"),
                                coordinate: end, symbol: "flag.checkered.circle.fill",
                                tint: AppColor.danger)

                    Picker(L("routine.editor.travel_mode"), selection: $travelMode) {
                        ForEach(TravelMode.allCases) { mode in
                            Label(mode.displayName, systemImage: mode.icon).tag(mode)
                        }
                    }
                }

                Section {
                    MetricRow(L("routine.editor.distance"),
                              value: AppFormat.distance(distanceMeters), icon: "ruler")
                    MetricRow(L("routine.editor.estimated"),
                              value: AppFormat.duration(estimatedSeconds), icon: "clock")
                } header: {
                    Text(L("routine.editor.preview"))
                }
            }
            .navigationTitle(schedule == nil ? L("routine.editor.new") : L("routine.editor.edit"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("action.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("action.save")) { save() }
                        .fontWeight(.semibold)
                        .disabled(!isValid)
                }
            }
            .sheet(item: $picking) { endpoint in
                LocationPickerSheet(
                    title: endpoint == .start ? L("routine.editor.from") : L("routine.editor.to"),
                    initialCoordinate: endpoint == .start ? start : end
                ) { picked in
                    if endpoint == .start { start = picked } else { end = picked }
                }
            }
        }
    }

    // MARK: - Thành phần

    private var weekdayPicker: some View {
        HStack(spacing: AppSpacing.xs) {
            ForEach(1...7, id: \.self) { day in
                let isOn = days.contains(day)
                Button {
                    AppHaptics.selection()
                    if isOn { days.remove(day) } else { days.insert(day) }
                } label: {
                    Text(Self.weekdayNames[day] ?? "")
                        .font(AppFont.caption.weight(.semibold))
                        .foregroundStyle(isOn ? .white : AppColor.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                        .background(isOn ? AppColor.primary : AppColor.surfaceTertiary,
                                    in: RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Self.weekdayNames[day] ?? "")
                .accessibilityAddTraits(isOn ? [.isSelected, .isButton] : .isButton)
            }
        }
        .padding(.vertical, AppSpacing.xxs)
    }

    private func endpointRow(_ endpoint: Endpoint, label: String,
                             coordinate: CLLocationCoordinate2D,
                             symbol: String, tint: Color) -> some View {
        Button {
            picking = endpoint
        } label: {
            HStack(spacing: AppSpacing.md) {
                Image(systemName: symbol)
                    .font(.system(size: 17))
                    .foregroundStyle(tint)
                VStack(alignment: .leading, spacing: 1) {
                    Text(label)
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textTertiary)
                    Text(AppFormat.coordinate(coordinate))
                        .font(AppFont.monoFootnote)
                        .foregroundStyle(AppColor.textPrimary)
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

    // MARK: - Tính toán

    private var distanceMeters: Double {
        MotionEngine.haversineDistance(from: start, to: end)
    }

    private var estimatedSeconds: TimeInterval {
        let speed = travelMode.defaultSpeed.cruise
        guard speed > 0 else { return 0 }
        return distanceMeters / (speed / 3.6)
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func save() {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: time)
        let minute = calendar.component(.minute, from: time)
        let timeString = String(format: "%02d:%02d", hour, minute)

        var result = RoutineSchedule(
            name: name.trimmingCharacters(in: .whitespaces),
            time: timeString,
            days: days,
            start: start,
            end: end
        )
        result.travelMode = travelMode
        // Giữ nguyên id khi sửa, để bản ghi cũ được thay chứ không nhân đôi.
        if let schedule {
            result = RoutineSchedule(existing: schedule, name: result.name, timeString: timeString,
                                     days: days, start: start, end: end, travelMode: travelMode)
        }
        AppHaptics.start()
        onSave(result)
        dismiss()
    }
}

extension RoutineSchedule {
    /// Tạo bản sửa đổi nhưng GIỮ NGUYÊN `id`.
    ///
    /// `init` gốc luôn sinh `id` mới, nên dùng nó để lưu bản sửa sẽ tạo ra một lịch thứ hai
    /// thay vì cập nhật lịch đang có.
    init(existing: RoutineSchedule,
         name: String,
         timeString: String,
         days: Set<Int>,
         start: CLLocationCoordinate2D,
         end: CLLocationCoordinate2D,
         travelMode: TravelMode) {
        self = existing
        self.name = name
        self.timeString = timeString
        self.days = days
        self.startLocation = CoordinateCodable(start)
        self.endLocation = CoordinateCodable(end)
        self.travelMode = travelMode
    }
}
