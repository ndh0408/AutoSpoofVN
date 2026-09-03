import SwiftUI

/// Tab "Chuyến bay".
///
/// **Giai doan 1**: duong vao cho man hinh du lich the gioi hien co, chua phai ban thiet
/// ke lai giao dien chuyen bay (Giai doan 6).
///
/// Mot dieu quan trong duoc sua ngay o day: `FlightHUDView` **chua tung duoc dung o dau**
/// trong app — no khong co mot call site nao. Vi no la noi DUY NHAT co nut "Huỷ bay" va
/// bo chon he so thoi gian, hau qua la truoc day khong co cach nao huy mot chuyen bay
/// dang chay hay doi toc do tua tu giao dien. Gan no vao day tra lai hai kha nang do.
struct FlightHubScreen: View {
    @Environment(\.navigator) private var navigator
    @EnvironmentObject private var flight: FlightManager
    @ObservedObject private var coordinator = SimulationCoordinator.shared

    var body: some View {
        List {
            if flight.isFlying {
                Section("Chuyến bay đang thực hiện") {
                    FlightHUDView()
                        .listRowInsets(EdgeInsets(top: AppSpacing.md, leading: AppSpacing.md,
                                                  bottom: AppSpacing.md, trailing: AppSpacing.md))
                }
            }

            Section {
                HubRow(title: "Du lịch thế giới",
                       subtitle: "Chọn điểm đến, bay tới sân bay và tự tham quan",
                       symbol: "globe.asia.australia.fill",
                       tint: AppColor.primary,
                       badge: flight.isAutoWorldOdysseyEnabled ? "Tự động" : nil) {
                    navigator.present(.worldTravel)
                }
            } header: {
                Text("Điểm đến")
            } footer: {
                if let destination = flight.activeDestination {
                    Text("Đang ở \(destination.name), \(destination.country) · ngày \(flight.currentDayInDestination)/\(destination.stayDays)"
                         + (flight.destinationLocalTime.isEmpty ? "" : " · giờ địa phương \(flight.destinationLocalTime)"))
                } else {
                    Text("Mô phỏng chuyến bay giữa các sân bay quốc tế, kèm lịch tham quan tại điểm đến.")
                }
            }

            if !flight.isFlying {
                Section("Sân bay phổ biến") {
                    ForEach(flight.popularAirports.prefix(6)) { airport in
                        HStack(spacing: AppSpacing.md) {
                            Text(airport.code)
                                .font(AppFont.monoFootnote.weight(.bold))
                                .foregroundStyle(AppColor.primary)
                                .frame(width: 44, alignment: .leading)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(airport.city)
                                    .font(AppFont.callout)
                                    .foregroundStyle(AppColor.textPrimary)
                                Text(airport.name)
                                    .font(AppFont.caption1)
                                    .foregroundStyle(AppColor.textSecondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Text(airport.country)
                                .font(AppFont.caption)
                                .foregroundStyle(AppColor.textTertiary)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(airport.code), \(airport.city), \(airport.country)")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(L10n.tabFlight)
    }
}

#Preview {
    NavigationStack { FlightHubScreen() }
        .environmentObject(FlightManager.shared)
}
