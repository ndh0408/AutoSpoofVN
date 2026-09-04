import CoreLocation
import SwiftUI

// MARK: - CurrentPositionMarker

/// Dau vi tri dang mo phong.
///
/// Hai hinh dang: may bay (co xoay theo huong) khi dang bay, cham xanh kieu Apple Maps
/// khi di chuyen tren mat dat. Vong toa sang chi dap khi phien dang CHAY — dung yen thi
/// dung yen, de trang thai doc duoc ma khong can nhin chu.
struct CurrentPositionMarker: View {
    let isFlying: Bool
    let headingDegrees: Double
    let isRunning: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var haloExpanded = false

    var body: some View {
        ZStack {
            if shouldAnimate {
                Circle()
                    .fill(AppColor.primary.opacity(0.22))
                    .frame(width: haloSize, height: haloSize)
                    .scaleEffect(haloExpanded ? 1.35 : 0.9)
                    .opacity(haloExpanded ? 0 : 0.9)
            } else {
                Circle()
                    .fill(AppColor.primary.opacity(0.22))
                    .frame(width: haloSize, height: haloSize)
            }

            if isFlying {
                Image(systemName: "airplane")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(AppColor.primary, in: Circle())
                    // SF Symbol "airplane" huong sang phai (90°), nen tru 90 de 0° = huong Bac.
                    .rotationEffect(.degrees(headingDegrees - 90))
            } else {
                Circle()
                    .fill(AppColor.primary)
                    .frame(width: 16, height: 16)
                    .overlay(Circle().strokeBorder(.white, lineWidth: 2.5))
            }
        }
        .shadow(color: .black.opacity(0.25), radius: 4, y: 1)
        .accessibilityElement()
        .accessibilityLabel(isFlying ? L("a11y.marker.aircraft") : L("a11y.marker.position"))
        .onAppear {
            guard shouldAnimate else { return }
            withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) {
                haloExpanded = true
            }
        }
    }

    private var shouldAnimate: Bool { isRunning && !reduceMotion }
    private var haloSize: CGFloat { isFlying ? 52 : 42 }
}

// MARK: - SavedPlaceMarker

/// Dia diem co dinh cua chu trinh 24/7 (Nha / Cong ty / Ca phe).
///
/// Nho va tram hon ban cu (icon `.title2` khong nen): day la thong tin nen, khong duoc
/// canh tranh thi giac voi dau vi tri hien tai.
struct SavedPlaceMarker: View {
    let symbol: String
    let tint: Color

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 24, height: 24)
            .background(tint, in: Circle())
            .overlay(Circle().strokeBorder(.white.opacity(0.9), lineWidth: 1.5))
            .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
    }
}

// MARK: - TargetPinMarker

/// Ghim diem nguoi dung vua chon tren ban do, truoc khi xac nhan dat vi tri.
struct TargetPinMarker: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dropped = false

    var body: some View {
        Image(systemName: "mappin.circle.fill")
            .font(.system(size: 28))
            .foregroundStyle(AppColor.danger, .white)
            .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
            .scaleEffect(dropped || reduceMotion ? 1 : 0.4)
            .opacity(dropped || reduceMotion ? 1 : 0)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(AppAnimation.spring) { dropped = true }
            }
            .accessibilityLabel(L("a11y.marker.selected_point"))
    }
}

// MARK: - Dia diem co dinh cua chu trinh

/// Mo ta mot dia diem cua `RoutineManager` de ve len ban do.
struct RoutinePlace: Identifiable {
    let id: String
    let title: String
    let symbol: String
    let tint: Color
    let coordinate: CLLocationCoordinate2D

    /// Ba dia diem `RoutineManager` dang giu. Giu nguyen bo ba cua ban cu.
    @MainActor
    static func all(from routine: RoutineManager) -> [RoutinePlace] {
        [
            RoutinePlace(id: "home", title: L("routine.place.home"), symbol: "house.fill",
                         tint: AppColor.success, coordinate: routine.homeLocation),
            RoutinePlace(id: "work", title: L("routine.place.work"), symbol: "building.2.fill",
                         tint: AppColor.accent, coordinate: routine.workLocation),
            RoutinePlace(id: "cafe", title: L("routine.place.cafe"), symbol: "cup.and.saucer.fill",
                         tint: AppColor.warning, coordinate: routine.cafeLocation),
        ]
    }
}

#Preview("Markers") {
    VStack(spacing: AppSpacing.xxl) {
        CurrentPositionMarker(isFlying: false, headingDegrees: 0, isRunning: true)
        CurrentPositionMarker(isFlying: true, headingDegrees: 45, isRunning: true)
        HStack(spacing: AppSpacing.lg) {
            SavedPlaceMarker(symbol: "house.fill", tint: AppColor.success)
            SavedPlaceMarker(symbol: "building.2.fill", tint: AppColor.accent)
            SavedPlaceMarker(symbol: "cup.and.saucer.fill", tint: AppColor.warning)
        }
        TargetPinMarker()
    }
    .padding(AppSpacing.xxxl)
}
