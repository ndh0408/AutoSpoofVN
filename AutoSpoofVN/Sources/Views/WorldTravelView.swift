import SwiftUI
import MapKit

/// Man hinh Du lich Toan cau, Chuyen bay Dai cung & Chu du The gioi 24/7
struct WorldTravelView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var flight: FlightManager
    @EnvironmentObject var engine: SpoofEngine
    @EnvironmentObject var routine: RoutineManager

    @State private var selectedTab: Int = 0
    @State private var customOriginCode: String = "HAN"
    @State private var customDestCode: String = "NRT"
    @State private var flightSpeed: Double = 800.0

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $selectedTab) {
                    Text("Thành phố du lịch").tag(0)
                    Text("Chuyến bay tuỳ chọn").tag(1)
                    Text("Chu du Thế giới").tag(2)
                }
                .pickerStyle(.segmented)
                .padding()

                if selectedTab == 0 {
                    // Danh sach Thanh pho Du lich The gioi
                    List(flight.worldDestinations) { dest in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(dest.name), \(dest.country)")
                                        .font(.headline)
                                    Text("Khách sạn: \(dest.hotelName)")
                                        .font(.caption)
                                        .foregroundColor(.purple)
                                }
                                Spacer()
                                Text("UTC\(dest.timeZoneOffsetHours >= 0 ? "+" : "")\(Int(dest.timeZoneOffsetHours))")
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.secondary.opacity(0.15))
                                    .cornerRadius(6)
                            }

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 6) {
                                    ForEach(dest.spots) { spot in
                                        Text(spot.name)
                                            .font(.caption2)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(Color.blue.opacity(0.1))
                                            .cornerRadius(8)
                                    }
                                }
                            }

                            HStack(spacing: 10) {
                                Button(action: {
                                    flight.startFlightToDestination(dest)
                                    dismiss()
                                }) {
                                    Label("Bay tới đây (800 km/h)", systemImage: "airplane.departure")
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 8)
                                }
                                .buttonStyle(.borderedProminent)

                                Button(action: {
                                    flight.setupDestinationRoutine(destination: dest)
                                    dismiss()
                                }) {
                                    Label("Ở KS & Đi tour ngay", systemImage: "bed.double.fill")
                                        .font(.caption)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 8)
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                } else if selectedTab == 1 {
                    // Tuy bien Chuyen bay San bay -> San bay
                    Form {
                        Section(header: Text("Sân bay Xuất phát")) {
                            Picker("Điểm đi", selection: $customOriginCode) {
                                ForEach(flight.popularAirports) { apt in
                                    Text("\(apt.code) - \(apt.city) (\(apt.name))").tag(apt.code)
                                }
                            }
                        }

                        Section(header: Text("Sân bay Đích đến")) {
                            Picker("Điểm đến", selection: $customDestCode) {
                                ForEach(flight.popularAirports) { apt in
                                    Text("\(apt.code) - \(apt.city) (\(apt.name))").tag(apt.code)
                                }
                            }
                        }

                        Section(header: Text("Tốc độ bay hành trình")) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Tốc độ: \(Int(flightSpeed)) km/h")
                                    .font(.subheadline)
                                Slider(value: $flightSpeed, in: 400.0...950.0, step: 25.0)
                            }
                        }

                        Section {
                            Button(action: {
                                if let orig = flight.popularAirports.first(where: { $0.code == customOriginCode }),
                                   let dest = flight.popularAirports.first(where: { $0.code == customDestCode }) {
                                    flight.startFlight(origin: orig, destination: dest, speedKmh: flightSpeed)
                                    dismiss()
                                }
                            }) {
                                Label("Bắt đầu Chuyến bay Đại cung", systemImage: "airplane.departure")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity)
                            }
                            .disabled(customOriginCode == customDestCode)
                        }
                    }
                } else {
                    // Che do Chu du Vong quanh The gioi (World Odyssey)
                    Form {
                        Section(header: Text("Chế độ Chu du Thế giới 24/7")) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Tự động du lịch xuyên quốc gia liên tục:")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                Text("• Tự bay quốc tế 500-900 km/h theo đường vòng cung.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("• Nhận phòng khách sạn, ngủ theo đúng múi giờ địa phương.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("• Ban ngày đi tour tham quan các danh lam thắng cảnh.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("• Trải nghiệm nhà hàng, phố đi bộ trước khi bay sang nước tiếp theo.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 4)

                            Button(action: {
                                flight.toggleAutoWorldOdyssey()
                                dismiss()
                            }) {
                                Label(flight.isAutoWorldOdysseyEnabled ? "Dừng Chu du Thế giới" : "Bật Tự động Chu du Thế giới 24/7",
                                      systemImage: flight.isAutoWorldOdysseyEnabled ? "stop.circle.fill" : "globe.americas.fill")
                                    .font(.headline)
                                    .foregroundColor(flight.isAutoWorldOdysseyEnabled ? .red : .blue)
                                    .frame(maxWidth: .infinity)
                            }
                        }

                        Section(header: Text("Hành trình các nước trong tour")) {
                            ForEach(Array(flight.worldDestinations.enumerated()), id: \.element.id) { idx, dest in
                                HStack {
                                    Text("\(idx + 1). \(dest.name) (\(dest.country))")
                                        .font(.subheadline)
                                    Spacer()
                                    Text("\(dest.stayDays) ngày")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Du lịch Thế giới & Đường bay")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đóng") { dismiss() }
                }
            }
        }
    }
}
