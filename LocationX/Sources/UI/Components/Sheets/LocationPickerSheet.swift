import CoreLocation
import MapKit
import SwiftUI

/// Chọn một toạ độ trên bản đồ.
///
/// Dùng chung cho việc sửa Nhà / Công ty / Quán cà phê và cho điểm đầu–cuối của một lịch
/// chu trình. Trước đây không có bộ chọn nào: `RoutineStudioView` truyền closure
/// `onUpdate` cho `LocationRow` nhưng thân hàng đó chỉ là `HStack` hiển thị, không có
/// `Button` hay `onTapGesture` nào gọi tới — nên `RoutineManager.updateLocation` không có
/// đường nào chạy được và địa điểm cố định là thứ không sửa được từ giao diện.
struct LocationPickerSheet: View {
    let title: String
    let initialCoordinate: CLLocationCoordinate2D
    let onPick: (CLLocationCoordinate2D) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var camera: MapCameraPosition
    @State private var picked: CLLocationCoordinate2D
    @State private var showSearch = false

    init(title: String,
         initialCoordinate: CLLocationCoordinate2D,
         onPick: @escaping (CLLocationCoordinate2D) -> Void) {
        self.title = title
        self.initialCoordinate = initialCoordinate
        self.onPick = onPick
        _picked = State(initialValue: initialCoordinate)
        _camera = State(initialValue: .camera(
            MapCamera(centerCoordinate: initialCoordinate, distance: 4_000)
        ))
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                MapReader { proxy in
                    Map(position: $camera, interactionModes: .all) {
                        Annotation("", coordinate: picked, anchor: .bottom) {
                            TargetPinMarker()
                        }
                        .annotationTitles(.hidden)
                    }
                    .onTapGesture { point in
                        guard let coordinate = proxy.convert(point, from: .local) else { return }
                        AppHaptics.selection()
                        withAppAnimation(AppAnimation.snappy) { picked = coordinate }
                    }
                }
                .ignoresSafeArea(edges: .top)

                footer
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("action.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showSearch = true
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .accessibleButton(label: L("location_picker.search"))
                }
            }
            .sheet(isPresented: $showSearch) {
                LocationSearchView { result in
                    picked = result.coordinate
                    camera = .camera(MapCamera(centerCoordinate: result.coordinate, distance: 2_000))
                }
            }
        }
    }

    private var footer: some View {
        VStack(spacing: AppSpacing.md) {
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: "mappin.circle.fill")
                    .foregroundStyle(AppColor.danger)
                Text(AppFormat.coordinate(picked))
                    .font(AppFont.monoFootnote)
                    .foregroundStyle(AppColor.textSecondary)
                Spacer()
            }

            Button {
                AppHaptics.start()
                onPick(picked)
                dismiss()
            } label: {
                Text(L("location_picker.use_this"))
            }
            .buttonStyle(.appPrimary(.prominent, fillsWidth: true))
        }
        .padding(AppSpacing.lg)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: AppRadius.xl,
                                   bottomLeadingRadius: 0,
                                   bottomTrailingRadius: 0,
                                   topTrailingRadius: AppRadius.xl,
                                   style: .continuous)
                .fill(AppMaterial.sheet)
                .appShadow(AppShadow.sheet)
        )
        .overlay(alignment: .top) {
            Text(L("location_picker.hint"))
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)
                .padding(.horizontal, AppSpacing.md)
                .padding(.vertical, AppSpacing.sm)
                .glassCapsule(material: AppMaterial.bar)
                .offset(y: -44)
        }
    }
}
