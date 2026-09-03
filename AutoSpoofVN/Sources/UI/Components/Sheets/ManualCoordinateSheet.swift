import CoreLocation
import SwiftUI

/// Nhap toa do thu cong.
///
/// Thay cho `.alert` hai o TextField truoc day: alert khong hien duoc loi xac thuc,
/// khong dan duoc chuoi "21.0285, 105.8542", va khong cho biet toa do dang o dau.
/// Vien xac thuc (`-90...90`, `-180...180`) duoc giu nguyen — `SimulationCoordinator`
/// KHONG tu kiem tra, nen bo o day la gui toa do rac xuong thiet bi.
struct ManualCoordinateSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var latitudeText: String
    @State private var longitudeText: String
    @FocusState private var focus: Field?

    private let coordinator = SimulationCoordinator.shared

    private enum Field: Hashable { case latitude, longitude }

    init() {
        let current = SimulationCoordinator.shared.currentCoordinate
        _latitudeText = State(initialValue: String(format: "%.6f", current.latitude))
        _longitudeText = State(initialValue: String(format: "%.6f", current.longitude))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Vĩ độ") {
                        TextField("21.028500", text: $latitudeText)
                            .keyboardType(.numbersAndPunctuation)
                            .multilineTextAlignment(.trailing)
                            .font(AppFont.monoBody)
                            .focused($focus, equals: .latitude)
                            .submitLabel(.next)
                            .onSubmit { focus = .longitude }
                    }
                    LabeledContent("Kinh độ") {
                        TextField("105.854200", text: $longitudeText)
                            .keyboardType(.numbersAndPunctuation)
                            .multilineTextAlignment(.trailing)
                            .font(AppFont.monoBody)
                            .focused($focus, equals: .longitude)
                            .submitLabel(.done)
                            .onSubmit { apply() }
                    }
                } header: {
                    Text("Toạ độ")
                } footer: {
                    if let error = validationError {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(AppFont.caption1)
                            .foregroundStyle(AppColor.danger)
                    } else {
                        Text("Vĩ độ từ −90 đến 90, kinh độ từ −180 đến 180. Có thể dán chuỗi “21.0285, 105.8542”.")
                    }
                }

                Section {
                    Button {
                        pasteFromClipboard()
                    } label: {
                        Label("Dán từ bộ nhớ tạm", systemImage: "doc.on.clipboard")
                    }
                    Button {
                        let current = coordinator.currentCoordinate
                        latitudeText = String(format: "%.6f", current.latitude)
                        longitudeText = String(format: "%.6f", current.longitude)
                        AppHaptics.selection()
                    } label: {
                        Label("Dùng vị trí đang mô phỏng", systemImage: "location.circle")
                    }
                }

                if coordinator.state.isActive, coordinator.activeSource != .manual {
                    Section {
                        Label {
                            Text("\(coordinator.activeSource?.displayName ?? "Một nguồn khác") đang chạy. Đặt vị trí thủ công sẽ giành quyền điều khiển và dừng nguồn đó.")
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(AppColor.warning)
                        }
                        .font(AppFont.footnote)
                    }
                }
            }
            .navigationTitle("Đặt vị trí")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Đặt") { apply() }
                        .fontWeight(.semibold)
                        .disabled(parsed == nil)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Xac thuc

    /// Toa do hop le, hoac `nil` neu chua nhap dung.
    private var parsed: CLLocationCoordinate2D? {
        guard let lat = Double(latitudeText.trimmingCharacters(in: .whitespaces)),
              let lon = Double(longitudeText.trimmingCharacters(in: .whitespaces)),
              lat.isFinite, lon.isFinite,
              (-90...90).contains(lat), (-180...180).contains(lon) else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    private var validationError: String? {
        let latTrimmed = latitudeText.trimmingCharacters(in: .whitespaces)
        let lonTrimmed = longitudeText.trimmingCharacters(in: .whitespaces)
        guard !latTrimmed.isEmpty, !lonTrimmed.isEmpty else { return nil }
        guard let lat = Double(latTrimmed) else { return "Vĩ độ không phải là số." }
        guard let lon = Double(lonTrimmed) else { return "Kinh độ không phải là số." }
        if !(-90...90).contains(lat) { return "Vĩ độ phải nằm trong khoảng −90 đến 90." }
        if !(-180...180).contains(lon) { return "Kinh độ phải nằm trong khoảng −180 đến 180." }
        return nil
    }

    private func apply() {
        guard let coord = parsed else {
            AppHaptics.failure()
            return
        }
        AppHaptics.start()
        coordinator.setManualLocation(coord)
        dismiss()
    }

    /// Chap nhan "21.0285, 105.8542" va "21.0285 105.8542".
    private func pasteFromClipboard() {
        guard let text = UIPasteboard.general.string else {
            AppHaptics.failure()
            return
        }
        let parts = text
            .split(whereSeparator: { $0 == "," || $0 == " " || $0 == "\n" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard parts.count >= 2, Double(parts[0]) != nil, Double(parts[1]) != nil else {
            AppHaptics.failure()
            return
        }
        latitudeText = parts[0]
        longitudeText = parts[1]
        AppHaptics.selection()
    }
}

#Preview {
    ManualCoordinateSheet()
}
