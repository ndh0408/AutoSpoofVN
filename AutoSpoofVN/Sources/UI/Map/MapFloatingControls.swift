import SwiftUI

/// Cum dieu khien noi ben phai ban do.
///
/// Ban cu xep 10 nut rieng le thanh mot cot doc — vua che ban do, vua khong phan cap.
/// Ban nay chia hai muc:
///
/// - **Nhom truc tiep** (luon hien): bam theo vi tri, kieu ban do, nghieng 3D.
///   Ba thu nay dieu khien CHINH ban do dang nhin, nen dang o ngay tren ban do.
/// - **Menu tran** (nut `…`): cac diem den phu. Khong bi mat di dau — moi muc deu con
///   duong vao thu hai qua tab tuong ung (xem `RootTabView`).
struct MapFloatingControls: View {
    @Binding var followMode: Bool
    @Binding var styleKind: MapStyleKind
    @Binding var isPitched: Bool
    /// Chi hien nut nghieng 3D khi dang bam theo — nghieng ma khong bam theo thi vo nghia.
    var showsPitchControl: Bool = true
    let onRecenter: () -> Void
    let onOpenSheet: (AppSheet) -> Void

    var body: some View {
        VStack(spacing: AppSpacing.sm) {
            primaryCluster
            overflowMenu
        }
    }

    // MARK: - Nhom dieu khien ban do

    private var primaryCluster: some View {
        VStack(spacing: 0) {
            IconButton(systemImage: followMode ? "location.fill" : "location",
                       label: followMode ? "Đang bám theo vị trí" : "Bám theo vị trí",
                       hint: "Đưa bản đồ về vị trí đang mô phỏng và bám theo",
                       isActive: followMode) {
                AppHaptics.selection()
                onRecenter()
            }

            HairlineDivider()

            Menu {
                Picker("Kiểu bản đồ", selection: $styleKind) {
                    ForEach(MapStyleKind.allCases) { kind in
                        Label(kind.title, systemImage: kind.symbol).tag(kind)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                Image(systemName: styleKind.symbol)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(AppColor.textPrimary)
                    .frame(width: AppSpacing.floatingControlSize,
                           height: AppSpacing.floatingControlSize)
                    .contentShape(Rectangle())
            }
            .accessibleButton(label: "Kiểu bản đồ: \(styleKind.title)",
                              hint: "Chọn giữa bản đồ, kết hợp và vệ tinh")

            if showsPitchControl {
                HairlineDivider()

                IconButton(systemImage: isPitched ? "view.3d" : "view.2d",
                           label: isPitched ? "Tắt góc nghiêng 3D" : "Bật góc nghiêng 3D",
                           hint: "Đổi giữa nhìn từ trên xuống và nhìn nghiêng",
                           isActive: isPitched) {
                    AppHaptics.selection()
                    withAppAnimation(AppAnimation.smooth) { isPitched.toggle() }
                }
            }
        }
        // Chot be ngang bang mot o. Thieu dong nay, `HairlineDivider` (mot Rectangle
        // khong gioi han chieu ngang) keo ca cot gian het be ngang man hinh.
        .frame(width: AppSpacing.floatingControlSize)
        .glassSurface(radius: AppRadius.lg)
    }

    // MARK: - Menu tran

    private var overflowMenu: some View {
        Menu {
            Section("Vị trí") {
                Button {
                    onOpenSheet(.manualCoordinate)
                } label: {
                    Label("Nhập toạ độ…", systemImage: "character.cursor.ibeam")
                }
                Button {
                    onOpenSheet(.bookmarks)
                } label: {
                    Label("Địa điểm đã lưu", systemImage: "bookmark")
                }
                Button {
                    onOpenSheet(.history)
                } label: {
                    Label("Lịch sử & phát lại", systemImage: "clock.arrow.circlepath")
                }
            }

            Section("Thiết bị") {
                Button {
                    onOpenSheet(.deviceManager)
                } label: {
                    Label("Quản lý thiết bị", systemImage: "iphone")
                }
                Button {
                    onOpenSheet(.diagnostics)
                } label: {
                    Label("Chẩn đoán hệ thống", systemImage: "stethoscope")
                }
            }

            Section("Vượt kiểm tra") {
                Button {
                    onOpenSheet(.shadowrocketSetup)
                } label: {
                    Label("Thiết lập Shadowrocket", systemImage: "bolt.horizontal")
                }
                Button {
                    onOpenSheet(.bypassTroubleshoot)
                } label: {
                    Label("Khắc phục sự cố", systemImage: "questionmark.circle")
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppColor.textPrimary)
                .frame(width: AppSpacing.floatingControlSize,
                       height: AppSpacing.floatingControlSize)
                .contentShape(Rectangle())
                .glassSurface(radius: AppRadius.lg)
        }
        .frame(width: AppSpacing.floatingControlSize)
        .accessibleButton(label: "Thêm", hint: "Địa điểm, thiết bị và công cụ vượt kiểm tra")
    }
}

#Preview {
    ZStack {
        LinearGradient(colors: [.teal, .green], startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
        HStack {
            Spacer()
            MapFloatingControls(followMode: .constant(true),
                                styleKind: .constant(.standard),
                                isPitched: .constant(false),
                                onRecenter: {}, onOpenSheet: { _ in })
                .padding(.trailing, AppSpacing.lg)
        }
    }
}
