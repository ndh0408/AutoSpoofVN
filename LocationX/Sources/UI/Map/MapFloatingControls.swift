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
                       label: followMode ? L("map.follow.active") : L("map.follow"),
                       hint: L("map.follow.hint"),
                       isActive: followMode) {
                AppHaptics.selection()
                onRecenter()
            }

            HairlineDivider()

            Menu {
                Picker(L("map.style"), selection: $styleKind) {
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
            .accessibleButton(label: L("map.style.a11y", styleKind.title),
                              hint: L("map.style.hint"))

            if showsPitchControl {
                HairlineDivider()

                IconButton(systemImage: isPitched ? "view.3d" : "view.2d",
                           label: isPitched ? L("map.pitch.off") : L("map.pitch.on"),
                           hint: L("map.pitch.hint"),
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
            Section(L("map.menu.location")) {
                Button {
                    onOpenSheet(.manualCoordinate)
                } label: {
                    Label(L("map.menu.manual_coordinate"), systemImage: "character.cursor.ibeam")
                }
                Button {
                    onOpenSheet(.bookmarks)
                } label: {
                    Label(L("map.menu.bookmarks"), systemImage: "bookmark")
                }
                Button {
                    onOpenSheet(.history)
                } label: {
                    Label(L("map.menu.history"), systemImage: "clock.arrow.circlepath")
                }
            }

            Section(L("settings.device")) {
                Button {
                    onOpenSheet(.deviceManager)
                } label: {
                    Label(L("device.manage"), systemImage: "iphone")
                }
                Button {
                    onOpenSheet(.diagnostics)
                } label: {
                    Label(L("diagnostics.title"), systemImage: "stethoscope")
                }
            }

            Section(L("map.menu.bypass")) {
                Button {
                    onOpenSheet(.shadowrocketSetup)
                } label: {
                    Label(L("shadowrocket.setup"), systemImage: "bolt.horizontal")
                }
                Button {
                    onOpenSheet(.bypassTroubleshoot)
                } label: {
                    Label(L("shadowrocket.troubleshoot"), systemImage: "questionmark.circle")
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
        .accessibleButton(label: L("common.more"), hint: L("map.menu.more_hint"))
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
