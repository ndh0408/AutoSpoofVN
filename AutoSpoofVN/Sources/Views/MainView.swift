import SwiftUI
import MapKit

struct MainView: View {
    @EnvironmentObject var engine: SpoofEngine
    @EnvironmentObject var routine: RoutineManager

    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var selectedCoord: CLLocationCoordinate2D?
    @State private var pairingPlistText: String = ""
    @State private var showingPairingSheet: Bool = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                // Bản đồ tương tác
                MapReader { proxy in
                    Map(position: $position) {
                        if engine.isSimulating {
                            Annotation("Vị trí ảo", coordinate: engine.currentCoordinate) {
                                ZStack {
                                    Circle().fill(Color.blue.opacity(0.3)).frame(width: 32, height: 32)
                                    Image(systemName: "location.north.circle.fill")
                                        .resizable()
                                        .frame(width: 24, height: 24)
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                    }
                    .mapStyle(.standard(elevation: .realistic))
                    .onTapGesture { screenCoord in
                        if let loc = proxy.convert(screenCoord, from: .local) {
                            selectedCoord = loc
                            engine.setLocation(latitude: loc.latitude, longitude: loc.longitude)
                        }
                    }
                }
                .ignoresSafeArea(edges: .top)

                // Thanh điều khiển bên dưới
                VStack(spacing: 12) {
                    // Trạng thái chu trình tự động
                    HStack {
                        Image(systemName: routine.currentState.icon)
                            .font(.title2)
                            .foregroundColor(.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(routine.currentState.rawValue)
                                .font(.headline)
                            Text(routine.statusDescription)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { routine.isAutoRoutineEnabled },
                            set: { _ in routine.toggleAutoRoutine() }
                        ))
                        .labelsHidden()
                    }
                    .padding()
                    .background(.ultraThinMaterial)
                    .cornerRadius(16)

                    // Nút điều khiển nhanh
                    HStack(spacing: 10) {
                        Button(action: {
                            showingPairingSheet = true
                        }) {
                            Label("Ghép nối", systemImage: "link")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                        }
                        .buttonStyle(.bordered)

                        if engine.isSimulating {
                            Button(role: .destructive, action: {
                                engine.clearSimulation()
                            }) {
                                Label("Về GPS thật", systemImage: "arrow.counterclockwise")
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("AutoSpoof VN")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showingPairingSheet) {
                PairingSetupView(pairingText: $pairingPlistText)
            }
        }
    }
}

struct PairingSetupView: View {
    @Binding var pairingText: String
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var engine: SpoofEngine

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Hướng dẫn thiết lập")) {
                    Text("1. Cài đặt app LocalDevVPN trên App Store và bật VPN (Loopback 10.7.0.1).")
                    Text("2. Xuất file RPPairing.plist bằng công cụ idevice_pair và dán nội dung vào bên dưới.")
                }

                Section(header: Text("Nội dung RPPairing Plist")) {
                    TextEditor(text: $pairingText)
                        .frame(height: 140)
                        .font(.system(.caption, design: .monospaced))
                }

                Section {
                    Button("Lưu và Kết nối DVT Loopback") {
                        engine.connectLoopback(pairingPlist: pairingText)
                        dismiss()
                    }
                    .disabled(pairingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .navigationTitle("Cấu hình Ghép nối")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đóng") { dismiss() }
                }
            }
        }
    }
}
