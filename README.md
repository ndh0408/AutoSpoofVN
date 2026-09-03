# AutoSpoofVN

**GPS Simulation Studio cho iOS** — mô phỏng vị trí GPS trực tiếp trên iPhone, không cần jailbreak, không cần máy tính kết nối liên tục.

Mở bất kỳ app bản đồ nào — Grab, Google Maps, Zalo, Bumble, Tinder, Pokémon GO — và vị trí hiển thị đúng toạ độ bạn chọn. Đi bộ, chạy xe, bay quốc tế — tất cả đều mô phỏng được.

---

## Tính năng

### Mô phỏng GPS
- **Đặt vị trí thủ công** — chạm bản đồ hoặc nhập toạ độ
- **Mô phỏng tuyến đường** — di chuyển mượt giữa các điểm với tốc độ thực tế
- **Nhiều phương tiện** — đi bộ, xe đạp, xe máy, ô tô, tàu, máy bay
- **Tốc độ thực tế** — tăng tốc / giữ tốc / giảm tốc tự nhiên
- **Heading mượt** — hướng di chuyển không giật, không nhảy 0°/360°
- **GPS jitter tương quan** — nhiễu GPS giống thật, không phải random noise

### Chuyến bay quốc tế
- **14+ sân bay** — HAN, SGN, DAD, BKK, SIN, ICN, NRT, CDG, LHR, DXB, JFK, LAX, SYD...
- **World Odyssey** — tự động bay vòng quanh thế giới, tham quan từng thành phố
- **Giai đoạn bay đầy đủ** — check-in, boarding, taxi, takeoff, cruise, landing, arrival
- **Telemetry** — altitude, ground speed, vertical speed, heading, ETA, progress

### Chu trình 24/7
- **Routine tự động** — đi làm, nghỉ trưa, về nhà, đi dạo theo lịch
- **Bám đường thật** — sử dụng Apple Maps routing khi có mạng
- **Fallback thông minh** — tự chuyển sang nội suy thẳng khi mất mạng

### Kết nối thiết bị
- **Tự động ghép nối RPPairing** — không cần máy tính, không cần cable
- **DVT Transport thật** — kết nối qua Developer Tools protocol của Apple
- **LocalDevVPN loopback** — giao tiếp qua 10.7.0.1, không cần mạng ngoài
- **Heartbeat** — duy trì kết nối, tự reconnect khi đứt

### Chạy nền
- **Audio keep-alive** — phát audio im lặng giữ app sống
- **Location background** — CLLocationManager để iOS đánh thức app
- **Live Activity** — hiển thị trạng thái trên Dynamic Island và Lock Screen

### Kiến trúc v2.0
- **SimulationCoordinator** — một nguồn sự thật duy nhất cho toàn bộ mô phỏng
- **MotionEngine** — chuyển động mượt với speed profile cho từng phương tiện
- **HeadingEngine** — heading mượt, xử lý dateline
- **RouteSimulator** — mô phỏng tuyến đường 10Hz
- **PersistenceManager** — lưu trữ routes, scenarios, bookmarks, settings, GPX
- **Design System** — tokens + components chuẩn Apple-native

---

## Kiến trúc

```
                    ┌─────────────────────┐
                    │       SwiftUI       │
                    └──────────┬──────────┘
                               │
                    ┌──────────┴──────────┐
                    │ SimulationCoordinator│  ← MỘT nguồn sự thật
                    └──────────┬──────────┘
                               │
          ┌────────────────────┼────────────────────┐
          ▼                    ▼                    ▼
    RouteSimulator      RoutineManager       FlightManager
          │                    │                    │
          └────────────────────┼────────────────────┘
                               ▼
                       ┌───────────────┐
                       │  MotionEngine │
                       └───────┬───────┘
                               ▼
                       ┌───────────────┐
                       │ SpoofEngine   │  ← FFI bridge
                       └───────┬───────┘
                               ▼
                    ┌─────────────────────┐
                    │ DeviceTransport     │
                    ├─────────────────────┤
                    │ DVT / RPPairing FFI │
                    │ (Rust → staticlib)  │
                    └─────────────────────┘
```

### Luồng toạ độ

```
Nguồn (Manual / Route / Routine / Flight / Scenario / Replay)
    ↓
SimulationCoordinator.submit()     ← arbitrate source priority
    ↓
GPS Noise (correlated jitter)      ← nhiễu giống GPS thật
    ↓
SpoofEngine.setLocation()
    ↓
FFI Queue (serial)                 ← thread-safe, không block UI
    ↓
idevice_set_location()             ← Rust FFI → DVT → iPhone GPS
```

### Source Priority

```
Manual      = 100  (luôn thắng)
Scenario    = 80
Flight      = 60
Route       = 50
Routine     = 40
Replay      = 20
```

Chỉ MỘT source hoạt động tại một thời điểm. Source ưu tiên cao hơn tự động thay thế source thấp hơn.

---

## Yêu cầu

| Yêu cầu | Chi tiết |
|----------|----------|
| **iPhone** | iOS 17.4 trở lên |
| **Developer Mode** | Bật trong Settings → Privacy & Security → Developer Mode |
| **Build** | macOS, Xcode 16+, Rust toolchain |
| **Chạy** | Không cần máy tính sau khi cài app |

---

## Build

### 1. Cài đặt công cụ

```bash
# Xcode Command Line Tools
xcode-select --install

# Homebrew (nếu chưa có)
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# XcodeGen — sinh Xcode project từ project.yml
brew install xcodegen

# Rust
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source ~/.cargo/env
rustup target add aarch64-apple-ios
```

### 2. Clone repository

```bash
git clone https://github.com/ndh0408/AutoSpoofVN.git
cd AutoSpoofVN
```

### 3. Build thư viện Rust FFI

```bash
cd Vendor/idevice/ffi

# Build cho iPhone thật (arm64)
cargo build --release --target aarch64-apple-ios

# Copy thư viện vào đúng vị trí
cp target/aarch64-apple-ios/release/libidevice_ffi.a ../

# Verify
file ../libidevice_ffi.a
# → current ar archive random library
```

**Nếu gặp lỗi linker / SDK:**

```bash
export SDKROOT=$(xcrun --sdk iphoneos --show-sdk-path)
export CC=$(xcrun --find clang)
cargo build --release --target aarch64-apple-ios
```

### 4. Sinh Xcode project

```bash
cd ../../..  # về thư mục gốc AutoSpoofVN
xcodegen generate
```

### 5. Mở và build

```bash
open AutoSpoofVN.xcodeproj
```

Trong Xcode:
1. Chọn **Team** trong Signing & Capabilities (Apple ID miễn phí hoặc Developer account)
2. Chọn device iPhone thật (không chạy trên Simulator)
3. Build config: **Debug** hoặc **Debug-FFI** (cả hai đều bật FFI)
4. **Cmd+R** để build và chạy

### 6. Build IPA để chia sẻ

```bash
# Archive
xcodebuild archive \
  -project AutoSpoofVN.xcodeproj \
  -scheme AutoSpoofVN \
  -destination "generic/platform=iOS" \
  -archivePath build/AutoSpoofVN.xcarchive

# Export IPA
xcodebuild -exportArchive \
  -archivePath build/AutoSpoofVN.xcarchive \
  -exportPath build/ \
  -exportOptionsPlist ExportOptions.plist
```

Hoặc trong Xcode: **Product → Archive → Distribute App**.

---

## Cài đặt trên iPhone

### Cách 1: Xcode trực tiếp
Cắm iPhone → Cmd+R trong Xcode. Đơn giản nhất khi có Mac.

### Cách 2: Sideload IPA
Dùng một trong các tool sau:
- **AltStore** — miễn phí, ký lại mỗi 7 ngày
- **Sideloadly** — miễn phí, tương tự AltStore
- **TrollStore** — không giới hạn thời gian (cần iOS phù hợp)

### Cách 3: Enterprise / TestFlight
Nếu có Apple Developer account ($99/năm), dùng TestFlight hoặc Enterprise distribution.

---

## Sử dụng

### Lần đầu mở app

1. **Onboarding** — hướng dẫn cài đặt nhanh
2. **Bật Developer Mode** — Settings → Privacy & Security → Developer Mode → ON → Restart
3. **Ghép nối** — app tự phát hiện thiết bị qua Bonjour, hiện mã PIN, bạn nhập → xong
4. **Sẵn sàng** — bắt đầu mô phỏng

### Đặt vị trí thủ công

- Chạm bản đồ → vị trí được đặt ngay
- Hoặc nhập toạ độ trực tiếp

### Chạy tuyến đường

1. Chạm điểm bắt đầu trên bản đồ
2. Chạm điểm kết thúc
3. App tính tuyến đường qua Apple Maps
4. Chọn phương tiện (xe máy, ô tô, đi bộ...)
5. Bấm Start — mô phỏng chạy mượt dọc tuyến

### Chuyến bay quốc tế

1. Chọn sân bay xuất phát (VD: HAN - Nội Bài)
2. Chọn sân bay đích (VD: NRT - Narita, Tokyo)
3. Bấm Start — mô phỏng đầy đủ check-in → taxi → takeoff → cruise → landing

### Chu trình 24/7

Bật Routine → app tự di chuyển theo lịch:
- 07:30 Nhà → Công ty
- 12:00 Công ty → Quán cà phê
- 13:00 Quán cà phê → Công ty
- 18:00 Công ty → Nhà
- Đêm: ngủ tại nhà (GPS cố định + jitter nhẹ)

---

## RPPairing — Ghép nối tự động

AutoSpoofVN sử dụng RPPairing (Remote Pairing) để kết nối DVT trực tiếp trên thiết bị, **không cần máy tính kết nối liên tục**.

### Cách hoạt động

```
App khởi động
    ↓
Phát Bonjour service trên mạng cục bộ
    ↓
iPhone phát hiện → hiện popup "Pair with AutoSpoofVN"
    ↓
Người dùng nhấn Pair → nhập PIN
    ↓
RPPairing handshake (TLS-PSK)
    ↓
Mở tunnel DVT
    ↓
LocationSimulationClient sẵn sàng
    ↓
GPS mô phỏng hoạt động
```

### Yêu cầu RPPairing

- iPhone iOS 17.4+
- Developer Mode đã bật
- Quyền Local Network đã cấp cho app

### Troubleshooting pairing

| Vấn đề | Giải pháp |
|--------|-----------|
| Không thấy popup pair | Kiểm tra Developer Mode đã bật |
| Timeout | Kiểm tra quyền Local Network trong Settings → AutoSpoofVN |
| PIN không xuất hiện | Restart app, thử lại |
| Kết nối DVT thất bại | Kiểm tra LocalDevVPN (10.7.0.1) |

---

## DVT — Developer Tools Protocol

DVT là cách Apple cho phép Xcode giao tiếp với iPhone để debug, profile, và **mô phỏng vị trí**. AutoSpoofVN sử dụng chính protocol này.

### Chuỗi kết nối

```
TcpProvider (10.7.0.1:62078, pairing file)
    ↓
CoreDeviceProxy (lockdownd, CDTunnel handshake)
    ↓
Software Tunnel (TCP stack qua tunnel)
    ↓
RSD Handshake (Remote Service Discovery)
    ↓
RemoteServerClient (com.apple.instruments.dtservicehub)
    ↓
LocationSimulationClient (kênh DTX, set/clear toạ độ)
```

### FFI Bridge

App gọi Rust library (`libidevice_ffi.a`) qua C FFI:

```c
// Mở phiên
IdeviceHandle handle = idevice_connect_dvt(host, port, pairing_data, len);

// Đặt GPS
idevice_set_location(handle, 21.0285, 105.8542);  // Hoàn Kiếm

// Xoá mô phỏng → về GPS thật
idevice_clear_location(handle);

// Đóng phiên
idevice_disconnect(handle);
```

Mọi lời gọi FFI chạy trên serial queue riêng (`com.autospoof.vn.ffi`), không block main thread.

---

## Cấu trúc thư mục

```
AutoSpoofVN/
├── Resources/
│   ├── AutoSpoofVN.entitlements
│   └── Info.plist
├── Sources/
│   ├── AutoSpoofVNApp.swift              — App entry point
│   ├── Coordinator/
│   │   └── SimulationCoordinator.swift    — Bộ não trung tâm
│   ├── Design/
│   │   └── AppDesign.swift                — Design tokens + components
│   ├── Engine/
│   │   ├── BackgroundKeeper.swift         — Audio + Location keep-alive
│   │   ├── FlightManager.swift            — Chuyến bay + World Odyssey
│   │   ├── LiveActivityManager.swift      — Dynamic Island + Lock Screen
│   │   ├── Motion/
│   │   │   ├── MotionEngine.swift         — Chuyển động mượt
│   │   │   └── HeadingEngine.swift        — Heading mượt
│   │   ├── Route/
│   │   │   └── RouteSimulator.swift       — Mô phỏng tuyến đường
│   │   ├── RouteProvider.swift            — Apple Maps + fallback routing
│   │   ├── RoutineManager.swift           — Chu trình 24/7
│   │   ├── SelfPairingManager.swift       — RPPairing tự động
│   │   └── SpoofEngine.swift              — FFI bridge + GPS delivery
│   ├── Models/
│   │   ├── ActivityAttributes.swift       — Live Activity data
│   │   ├── SimulationSession.swift        — Session, Route, Scenario models
│   │   ├── SimulationTypes.swift          — State machine, enums, configs
│   │   └── Types.swift                    — Legacy types (Airport, Bookmark...)
│   ├── Persistence/
│   │   └── PersistenceManager.swift       — File storage + GPX
│   └── Views/
│       ├── DiagnosticsView.swift          — Chẩn đoán hệ thống
│       ├── FlightHUDView.swift            — HUD chuyến bay
│       ├── MainView.swift                 — Dashboard chính
│       ├── OnboardingView.swift           — Hướng dẫn lần đầu
│       └── WorldTravelView.swift          — Du lịch thế giới
├── AutoSpoofVNTests/
│   ├── EngineTests.swift
│   └── RouteProviderTests.swift
├── AutoSpoofWidgets/                      — Live Activity widget extension
├── Vendor/
│   └── idevice/
│       ├── ffi/
│       │   ├── src/
│       │   │   ├── lib.rs                 — Rust FFI: DVT session management
│       │   │   └── remote_pairing.rs      — Rust FFI: RPPairing protocol
│       │   ├── Cargo.toml
│       │   └── Cargo.lock
│       ├── idevice.h                      — C header cho Swift
│       ├── idevice_stub.c                 — Stub cho development (không gửi GPS)
│       └── module.modulemap
├── project.yml                            — XcodeGen project definition
├── BUILD.md                               — Build instructions chi tiết
└── ROADMAP.md                             — Kế hoạch phát triển
```

---

## Cài đặt app (Settings)

### Mô phỏng
| Setting | Mô tả | Mặc định |
|---------|--------|----------|
| GPS Noise | Nhiễu GPS tương quan | 3m |
| Update Rate | Tần suất gửi GPS xuống thiết bị | 1 Hz |
| Simulation Tick | Tần suất tính toán nội bộ | 10 Hz |
| Speed Smoothing | Làm mượt tốc độ | Bật |
| Heading Smoothing | Làm mượt hướng | Bật |

### Bản đồ
| Setting | Mô tả | Mặc định |
|---------|--------|----------|
| Map Style | Standard / Satellite / Hybrid | Standard |
| Follow Mode | Bản đồ theo vị trí hiện tại | Bật |
| 3D | Hiển thị 3D | Tắt |
| Trail | Vẽ vết di chuyển | Bật |

### Thiết bị
| Setting | Mô tả | Mặc định |
|---------|--------|----------|
| Auto Reconnect | Tự kết nối lại khi đứt | Bật |
| Heartbeat | Khoảng cách gửi heartbeat | 20s |

---

## Chẩn đoán (Diagnostics)

App có trang chẩn đoán chi tiết:

```
Thiết bị      — Connected / UDID / Model / iOS version
Transport     — DVT / RPPairing / latency / last error
Mô phỏng      — state / source / tick rate / update rate
Chạy nền      — audio keeper / location / background task
Live Activity — authorization / running / last update
Tuyến đường    — provider / cache / distance / segments
```

---

## Hạn chế đã biết

| Hạn chế | Chi tiết |
|---------|----------|
| **Background không vĩnh viễn** | iOS có thể thu hồi app sau thời gian dài ở nền. Audio keep-alive giúp kéo dài nhưng không bảo đảm 100% |
| **Developer Mode bắt buộc** | iPhone phải bật Developer Mode. Không có cách tránh |
| **Sideload 7 ngày** | IPA ký bằng Apple ID miễn phí hết hạn sau 7 ngày. Dùng TrollStore hoặc Enterprise cert để tránh |
| **Altitude giả** | DVT protocol hỗ trợ latitude/longitude. Altitude không truyền được qua LocationSimulation |
| **Không vượt qua anti-cheat** | App mô phỏng GPS ở cấp hệ thống nhưng một số game/app có thể phát hiện qua sensor fusion (accelerometer + gyroscope không khớp với GPS) |

---

## Câu hỏi thường gặp

### App có cần jailbreak không?
Không. Dùng DVT protocol chính thức của Apple, chỉ cần Developer Mode.

### Tôi có cần giữ máy tính kết nối không?
Không. Sau khi cài app lên iPhone, mọi thứ chạy trên thiết bị. RPPairing tự ghép nối không cần Mac.

### Build IPA rồi gửi cho bạn bè được không?
Được. IPA chứa sẵn thư viện Rust FFI. Người nhận chỉ cần cài IPA và bật Developer Mode. App tự pair lần đầu mở.

### Bump / Tinder / Grab có nhận vị trí giả không?
Có. GPS mô phỏng qua DVT hoạt động ở cấp hệ thống — mọi app đọc CLLocationManager đều nhận toạ độ giả.

### Pokémon GO có hoạt động không?
GPS sẽ đổi, nhưng Niantic kiểm tra thêm accelerometer/gyroscope. Di chuyển quá nhanh hoặc teleport sẽ bị phát hiện. Dùng speed profile Walking (4.5 km/h) và GPS jitter để giảm nghi ngờ.

### App có gửi dữ liệu ra ngoài không?
Không. Toàn bộ xử lý trên thiết bị. Không có server, không có analytics, không có tracking.

---

## Đóng góp

1. Fork repository
2. Tạo branch: `git checkout -b feat/ten-tinh-nang`
3. Commit: `git commit -m "feat: mo ta ngan"`
4. Push: `git push origin feat/ten-tinh-nang`
5. Mở Pull Request

---

## License

Private project. All rights reserved.

---

## Credit

- [idevice](https://github.com/jkcoxson/idevice) — Rust crate giao tiếp iOS devices (jkcoxson)
- Apple MapKit — Routing và bản đồ
- Apple ActivityKit — Live Activity và Dynamic Island
