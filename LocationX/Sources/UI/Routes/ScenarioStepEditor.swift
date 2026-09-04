import CoreLocation
import SwiftUI

/// Loại hành động trong kịch bản.
///
/// Tách khỏi `ScenarioAction` (vốn mang theo tham số) để dùng làm lựa chọn trong Picker.
enum ScenarioActionKind: String, CaseIterable, Identifiable {
    case setLocation
    case moveTo
    case followRoute
    case wait
    case dwell
    case randomNearby
    case changeSpeed
    case changeTravelMode
    case loop
    case pause
    case resume

    var id: String { rawValue }

    var titleKey: String { "scenario.kind." + rawValue }

    var symbol: String {
        switch self {
        case .setLocation:      return "mappin"
        case .moveTo:           return "arrow.right"
        case .followRoute:      return "point.topleft.down.to.point.bottomright.curvepath"
        case .wait:             return "clock"
        case .dwell:            return "pause.circle"
        case .randomNearby:     return "shuffle"
        case .changeSpeed:      return "speedometer"
        case .changeTravelMode: return "car.fill"
        case .loop:             return "repeat"
        case .pause:            return "pause.fill"
        case .resume:           return "play.fill"
        }
    }

    init(action: ScenarioAction) {
        switch action {
        case .setLocation:      self = .setLocation
        case .moveTo:           self = .moveTo
        case .followRoute:      self = .followRoute
        case .wait:             self = .wait
        case .dwell:            self = .dwell
        case .randomNearby:     self = .randomNearby
        case .changeSpeed:      self = .changeSpeed
        case .changeTravelMode: self = .changeTravelMode
        case .loop:             self = .loop
        case .pause:            self = .pause
        case .resume:           self = .resume
        }
    }
}

/// Soạn một bước của kịch bản.
///
/// Trước đây mọi bước được tạo bằng hằng số viết cứng — đặt vị trí thì luôn là Hà Nội
/// 21.0285/105.8542, di chuyển thì luôn 30 km/h, chờ luôn 60 giây — và **không có bất kỳ
/// giao diện nào để sửa tham số sau khi thêm**. Năm trong mười một loại hành động
/// (`followRoute`, `changeTravelMode`, `loop`, `pause`, `resume`) thậm chí không tạo được.
struct ScenarioStepEditor: View {
    let initial: ScenarioAction?
    let onSave: (ScenarioAction) -> Void

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var routeStore = SavedRouteStore.shared

    @State private var kind: ScenarioActionKind
    @State private var coordinate: CLLocationCoordinate2D
    @State private var speedKmh: Double
    @State private var seconds: Double
    @State private var radiusMeters: Double
    @State private var durationSeconds: Double
    @State private var loopTimes: Int
    @State private var travelMode: TravelMode
    @State private var routeID: UUID?
    @State private var isPickingLocation = false

    init(initial: ScenarioAction?, onSave: @escaping (ScenarioAction) -> Void) {
        self.initial = initial
        self.onSave = onSave

        let current = SimulationCoordinator.shared.currentCoordinate
        var kind = ScenarioActionKind.setLocation
        var coordinate = current
        var speed = 30.0
        var seconds = 60.0
        var radius = 200.0
        var duration = 600.0
        var loops = 2
        var mode = TravelMode.driving
        var route: UUID?

        if let initial {
            kind = ScenarioActionKind(action: initial)
            switch initial {
            case .setLocation(let c):
                coordinate = c.clCoordinate
            case .moveTo(let c, let s):
                coordinate = c.clCoordinate
                speed = s
            case .followRoute(let id):
                route = id
            case .wait(let s):
                seconds = s
            case .dwell(let s):
                seconds = s
            case .randomNearby(let r, let d):
                radius = r
                duration = d
            case .changeSpeed(let s):
                speed = s
            case .changeTravelMode(let m):
                mode = m
            case .loop(let n):
                loops = n
            case .pause, .resume:
                break
            }
        }

        _kind = State(initialValue: kind)
        _coordinate = State(initialValue: coordinate)
        _speedKmh = State(initialValue: speed)
        _seconds = State(initialValue: seconds)
        _radiusMeters = State(initialValue: radius)
        _durationSeconds = State(initialValue: duration)
        _loopTimes = State(initialValue: loops)
        _travelMode = State(initialValue: mode)
        _routeID = State(initialValue: route)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(L("scenario.step.type")) {
                    Picker(L("scenario.step.type"), selection: $kind) {
                        ForEach(ScenarioActionKind.allCases) { option in
                            Label(L(option.titleKey), systemImage: option.symbol).tag(option)
                        }
                    }
                    .pickerStyle(.menu)
                }

                parameterSection
            }
            .navigationTitle(initial == nil ? L("scenario.step.new") : L("scenario.step.edit"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("action.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("action.save")) {
                        AppHaptics.start()
                        onSave(buildAction())
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(!isValid)
                }
            }
            .sheet(isPresented: $isPickingLocation) {
                LocationPickerSheet(title: L(kind.titleKey), initialCoordinate: coordinate) {
                    coordinate = $0
                }
            }
        }
    }

    // MARK: - Tham số theo từng loại

    @ViewBuilder
    private var parameterSection: some View {
        switch kind {
        case .setLocation:
            Section(L("scenario.step.parameters")) { locationRow }

        case .moveTo:
            Section(L("scenario.step.parameters")) {
                locationRow
                speedRow
            }

        case .followRoute:
            Section {
                if routeStore.routes.isEmpty {
                    Text(L("scenario.step.no_routes"))
                        .font(AppFont.footnote)
                        .foregroundStyle(AppColor.textTertiary)
                } else {
                    Picker(L("scenario.step.route"), selection: $routeID) {
                        Text(L("scenario.step.route.none")).tag(UUID?.none)
                        ForEach(routeStore.routes) { route in
                            Text(route.name).tag(UUID?.some(route.id))
                        }
                    }
                }
            } header: {
                Text(L("scenario.step.parameters"))
            } footer: {
                Text(L("scenario.step.route.footer"))
            }

        case .wait, .dwell:
            Section(L("scenario.step.parameters")) {
                durationRow(value: $seconds, label: L("scenario.step.duration"), range: 1...3600)
            }

        case .randomNearby:
            Section(L("scenario.step.parameters")) {
                stepperRow(value: $radiusMeters, label: L("scenario.step.radius"),
                           unit: "m", range: 10...5000, step: 10)
                durationRow(value: $durationSeconds, label: L("scenario.step.duration"), range: 10...7200)
            }

        case .changeSpeed:
            Section(L("scenario.step.parameters")) { speedRow }

        case .changeTravelMode:
            Section(L("scenario.step.parameters")) {
                Picker(L("scenario.step.travel_mode"), selection: $travelMode) {
                    ForEach(TravelMode.allCases) { mode in
                        Label(mode.displayName, systemImage: mode.icon).tag(mode)
                    }
                }
            }

        case .loop:
            Section(L("scenario.step.parameters")) {
                Stepper(value: $loopTimes, in: 1...100) {
                    LabeledContent(L("scenario.step.loop_times"), value: "\(loopTimes)")
                }
            }

        case .pause, .resume:
            Section {
                Text(L("scenario.step.no_parameters"))
                    .font(AppFont.footnote)
                    .foregroundStyle(AppColor.textTertiary)
            }
        }
    }

    private var locationRow: some View {
        Button {
            isPickingLocation = true
        } label: {
            HStack {
                Label(L("scenario.step.location"), systemImage: "mappin.circle.fill")
                    .foregroundStyle(AppColor.textPrimary)
                Spacer()
                Text(AppFormat.coordinate(coordinate))
                    .font(AppFont.monoFootnote)
                    .foregroundStyle(AppColor.textSecondary)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppColor.textQuaternary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var speedRow: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            LabeledContent(L("scenario.step.speed"), value: "\(Int(speedKmh)) km/h")
            Slider(value: $speedKmh, in: 1...200, step: 1)
                .tint(AppColor.primary)
                .accessibilityValue("\(Int(speedKmh)) km/h")
        }
    }

    private func durationRow(value: Binding<Double>, label: String,
                             range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            LabeledContent(label, value: AppFormat.duration(value.wrappedValue))
            Slider(value: value, in: range, step: 1)
                .tint(AppColor.primary)
                .accessibilityValue(AppFormat.duration(value.wrappedValue))
        }
    }

    private func stepperRow(value: Binding<Double>, label: String, unit: String,
                            range: ClosedRange<Double>, step: Double) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            LabeledContent(label, value: "\(Int(value.wrappedValue)) \(unit)")
            Slider(value: value, in: range, step: step)
                .tint(AppColor.primary)
                .accessibilityValue("\(Int(value.wrappedValue)) \(unit)")
        }
    }

    // MARK: - Kết quả

    /// `followRoute` không có tuyến thì lưu ra một bước vô nghĩa — chặn ngay ở đây.
    private var isValid: Bool {
        if kind == .followRoute { return routeID != nil }
        return true
    }

    private func buildAction() -> ScenarioAction {
        switch kind {
        case .setLocation:      return .setLocation(CoordinateCodable(coordinate))
        case .moveTo:           return .moveTo(CoordinateCodable(coordinate), speedKmh: speedKmh)
        case .followRoute:      return .followRoute(routeId: routeID ?? UUID())
        case .wait:             return .wait(seconds: seconds)
        case .dwell:            return .dwell(seconds: seconds)
        case .randomNearby:     return .randomNearby(radiusMeters: radiusMeters,
                                                     durationSeconds: durationSeconds)
        case .changeSpeed:      return .changeSpeed(kmh: speedKmh)
        case .changeTravelMode: return .changeTravelMode(travelMode)
        case .loop:             return .loop(times: loopTimes)
        case .pause:            return .pause
        case .resume:           return .resume
        }
    }
}
