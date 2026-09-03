# AutoSpoofVN

**GPS Simulation Studio cho iOS** — mô phỏng vị trí GPS trực tiếp trên iPhone với khả năng bypass phát hiện GPS giả.

Mở bất kỳ app nào — **Bump**, Grab, Google Maps, Zalo, Tinder, Pokémon GO — vị trí hiển thị đúng toạ độ bạn chọn. Đi bộ, chạy xe, bay quốc tế — tất cả mô phỏng được. Với Shadowrocket integration, `isSimulatedBySoftware = false` — các app kiểm tra GPS giả như Bump đều nhận.

---

## Bypass GPS Detection (Mới v2.0)

### Vấn đề
iOS 15+ cung cấp `CLLocationSourceInformation.isSimulatedBySoftware` cho app kiểm tra GPS giả. DVT LocationSimulation (cách truyền thống) luôn set cờ này = `true`. Các app như **Bump** kiểm tra cờ này và từ chối vị trí giả.

### Giải pháp: Shadowrocket MITM
```
iPhone scan WiFi access points
    ↓
Gửi danh sách BSSID tới gs-loc.apple.com (HTTPS)
    ↓
Shadowrocket chặn response (MITM)
    ↓
Rewrite toạ độ → toạ độ giả
    ↓
iPhone nghĩ mình ở toạ độ giả qua "WiFi positioning"
    ↓
isSimulatedBySoftware = false ✓
    ↓
Bump nhận ✓
```

### Tích hợp tự động
AutoSpoofVN tích hợp Shadowrocket gần như hoàn toàn tự động:

1. **Auto-detect** — app tự nhận biết Shadowrocket có cài không
2. **Banner thông minh** — hiện hướng dẫn setup nếu chưa sẵn sàng
3. **One-tap import** — bấm một nút để import MITM module vào Shadowrocket
4. **CoordinateServer** — HTTP server port 8765 sync toạ độ realtime
5. **Auto-trigger VPN** — khi bắt đầu mô phỏng, app tự mở Shadowrocket bật VPN

### Yêu cầu bypass
- **Shadowrocket** ($2.99 trên App Store) — proxy app hỗ trợ MITM
- HTTPS Decryption bật + Trust CA certificate
- Airplane mode trick lần đầu (buộc iOS dùng WiFi positioning)

### Hạn chế bypass
| Tình huống | Hoạt động? | Lý do |
|------------|-----------|-------|
| Trong nhà / GPS yếu | ✅ Có | iOS dùng WiFi positioning → bị MITM |
| Ngoài trời, GPS mạnh | ⚠️ Có thể không | GPS hardware chiếm quyền |
| Sau airplane trick | ✅ Có | GPS cache xoá, WiFi chiếm quyền |
| Không WiFi | ❌ Không | MITM cần WiFi positioning |

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
- **38 sân bay** — HAN, SGN, DAD, BKK, SIN, ICN, NRT, CDG, LHR, DXB, JFK, LAX, SYD...
- **World Odyssey** — tự động bay vòng quanh thế giới, tham quan từng thành phố
- **Giai đoạn bay đầy đủ** — check-in, boarding, taxi, takeoff, cruise, landing, arrival
- **Telemetry** — altitude, ground speed, heading, ETA, progress

### Chu trình 24/7
- **Routine tự động** — đi làm, nghỉ trưa, về nhà, đi dạo theo lịch
- **Bám đường thật** — sử dụng Apple Maps routing khi có mạng
- **Fallback thông minh** — tự chuyển sang nội suy thẳng khi mất mạng

### Kết nối thiết bị
- **Tự động ghép nối RPPairing** — không cần máy tính, không cần cable
- **DVT Transport** — kết nối qua Developer Tools protocol của Apple
- **Heartbeat** — duy trì kết nối, tự reconnect khi đứt

### Chạy nền
- **Audio keep-alive** — phát audio im lặng giữ app sống
- **Live Activity** — hiển thị trạng thái trên Dynamic Island và Lock Screen

---

## Kiến trúc v2.0

```
┌─────────────────────────────────────────────────────────────┐
│                        SwiftUI Views                         │
│  MainViewV2 │ RouteStudio │ WorldTravel │ RoutineStudio     │
│  FlightHUD  │ ScenarioStudio │ Settings │ ShadowrocketSetup │
└──────────────────────────┬──────────────────────────────────┘
                           │
┌──────────────────────────┴──────────────────────────────────┐
│                   SimulationCoordinator                      │
│            MỘT nguồn sự thật cho toàn bộ mô phỏng          │
│   Source Priority: Manual(100) > Scenario(80) > Flight(60)  │
│                  > Route(50) > Routine(40) > Replay(20)     │
└─────┬──────────┬──────────┬──────────┬──────────┬───────────┘
      │          │          │          │          │
      ▼          ▼          ▼          ▼          ▼
 RouteSimulator  FlightMgr  RoutineMgr  ScenarioEng  HistoryMgr
      │          │          │          │          │
      └──────────┴──────────┴──────────┴──────────┘
                           │
              ┌────────────┼────────────┐
              ▼            ▼            ▼
        SpoofEngine   CoordinateServer  LiveActivity
        (FFI bridge)   (port 8765)      (Dynamic Island)
              │            │
              ▼            ▼
        DeviceTransport  Shadowrocket MITM
        DVT/RPPairing    → isSimulated = false
              │            │
              ▼            ▼
           iPhone GPS    Bump / Apps ✓
```

### Luồng toạ độ
```
Nguồn (Route/Flight/Routine/Manual)
    ↓
SimulationCoordinator.submit()
    ↓
MotionEngine (speed profile: accel → cruise → decel)
    ↓
HeadingEngine (smooth heading, dateline-safe)
    ↓
GPS Noise (jitter tương quan, bán kính configurable)
    ↓
SpoofEngine.setLocation() → DVT → iPhone GPS
    ↓
CoordinateServer.updateCoordinate() → Shadowrocket MITM
    ↓
Bump nhận vị trí giả, isSimulatedBySoftware = false ✓
```

---

## Yêu cầu

| Thành phần | Chi tiết |
|------------|---------|
| macOS | Monterey 12+ (để build) |
| Xcode | 16.0+ |
| iPhone | iOS 17.4+ với Developer Mode bật |
| Rust | stable (cho FFI library) |
| XcodeGen | `brew install xcodegen` |
| Shadowrocket | $2.99 App Store (cho bypass detection) |

---

## Build

### 1. Clone và build FFI

```bash
git clone https://github.com/ndh0408/AutoSpoofVN.git
cd AutoSpoofVN

# Build Rust FFI cho iPhone
cd Vendor/idevice/ffi
rustup target add aarch64-apple-ios
export SDKROOT=$(xcrun --sdk iphoneos --show-sdk-path)
cargo build --release --target aarch64-apple-ios

# Copy thư viện
cp target/aarch64-apple-ios/release/libidevice_ffi.a ../
cd ../../..
```

### 2. Sinh project và build

```bash
xcodegen generate
open AutoSpoofVN.xcodeproj
```

Trong Xcode:
- Chọn Team (Signing & Capabilities)
- Chọn scheme `AutoSpoofVN-RealFFI` (có FFI thật) hoặc `AutoSpoofVN-Mock` (dev/UI)
- Build & Run trên iPhone thật

---

## Cài đặt Shadowrocket (Bypass GPS Detection)

### Lần đầu (one-time setup)

1. **Mua Shadowrocket** ($2.99) trên App Store
2. **Mở AutoSpoofVN** → banner sẽ hiện "Import module"
3. **Bấm Import** → Shadowrocket mở → module tự import
4. **Trong Shadowrocket:**
   - Settings → HTTPS Decryption → ON → Generate Certificate → Install
   - Trên iPhone: Settings → General → About → Certificate Trust Settings → bật CA
5. **Bật VPN** trong Shadowrocket

### Airplane Mode Trick (buộc WiFi positioning)

```
1. Bật Airplane Mode
2. Tắt Location Services (Settings → Privacy → Location Services → OFF)
3. Restart iPhone
4. Tắt Airplane Mode
5. Bật WiFi
6. Bật Shadowrocket VPN
7. Bật Location Services
8. Mở AutoSpoofVN → bắt đầu mô phỏng
```

### Lần sau

Chỉ cần bật Shadowrocket VPN → mở AutoSpoofVN → fake GPS. App tự sync toạ độ.

---

## Sử dụng

### Đặt vị trí thủ công
- Chạm bản đồ → toạ độ được đặt ngay
- Nhập toạ độ qua search bar

### Chạy tuyến đường
- Route Studio → đặt waypoints → tính tuyến → Start
- Chọn phương tiện (đi bộ / xe máy / ô tô)
- Import/export GPX

### Chuyến bay quốc tế
- World Travel → chọn sân bay → Start Flight
- Hoặc bật World Odyssey để bay tự động vòng quanh thế giới

### Chu trình 24/7
- Routine Studio → đặt home/work/cafe
- Bật Auto Routine → di chuyển theo lịch cả ngày

---

## Cấu trúc thư mục

```
AutoSpoofVN/
├── Sources/
│   ├── AutoSpoofVNApp.swift           ← @main entry point
│   ├── Coordinator/
│   │   └── SimulationCoordinator.swift ← nguồn sự thật duy nhất
│   ├── Design/
│   │   ├── AppDesign.swift             ← design tokens + components
│   │   └── Accessibility.swift         ← VoiceOver, Dynamic Type
│   ├── Engine/
│   │   ├── SpoofEngine.swift           ← FFI bridge tới device
│   │   ├── CoordinateServer.swift      ← HTTP server port 8765
│   │   ├── ShadowrocketManager.swift   ← auto-detect, setup, VPN monitor
│   │   ├── FlightManager.swift         ← mô phỏng bay quốc tế
│   │   ├── RoutineManager.swift        ← chu trình 24/7
│   │   ├── RouteProvider.swift         ← Apple Maps routing + fallback
│   │   ├── Route/RouteSimulator.swift  ← mô phỏng route 10Hz
│   │   ├── Scenario/ScenarioEngine.swift ← automation builder
│   │   ├── Motion/MotionEngine.swift   ← speed profiles
│   │   ├── Motion/HeadingEngine.swift  ← smooth heading
│   │   ├── HistoryManager.swift        ← recording + replay
│   │   ├── AirportRepository.swift     ← 38 airports worldwide
│   │   ├── LiveActivityManager.swift   ← Dynamic Island
│   │   ├── BackgroundKeeper.swift      ← audio keep-alive
│   │   ├── SelfPairingManager.swift    ← auto RPPairing
│   │   ├── DeviceTransport.swift       ← DVT/RPPairing transport
│   │   ├── Device/DeviceManager.swift  ← device info, heartbeat
│   │   └── Device/ConnectionRecovery.swift ← auto-reconnect
│   ├── Models/
│   │   ├── Types.swift                 ← core types (Airport, FlightPhase, etc)
│   │   ├── SimulationTypes.swift       ← state machine, speed profiles
│   │   ├── SimulationSession.swift     ← session, route, scenario models
│   │   └── FlightTypes.swift           ← DestinationInfo
│   ├── Persistence/
│   │   ├── PersistenceManager.swift    ← Codable storage + GPX
│   │   └── MigrationManager.swift      ← data migration
│   └── Views/
│       ├── MainViewV2.swift            ← dashboard (264 lines)
│       ├── ShadowrocketSetupView.swift ← bypass setup (tabs, hero)
│       ├── ShadowrocketBanner.swift    ← auto-detect banner
│       ├── LocationCloakGuideView.swift ← troubleshoot bypass
│       ├── RouteStudioView.swift       ← route editor
│       ├── WorldTravelViewV2.swift     ← flights + airports
│       ├── FlightHUDView.swift         ← flight telemetry
│       ├── RoutineStudioView.swift     ← routine editor
│       ├── ScenarioStudioView.swift    ← automation builder
│       ├── BookmarksView.swift         ← saved locations
│       ├── HistoryView.swift           ← replay
│       ├── DeviceManagerView.swift     ← pairing + diagnostics
│       ├── SettingsView.swift          ← settings + bypass section
│       ├── DiagnosticsV2View.swift     ← self-diagnostic
│       ├── OnboardingViewV2.swift      ← first-run flow
│       └── DashboardComponents.swift   ← telemetry panel
├── Resources/
│   ├── Info.plist
│   ├── en.lproj/Localizable.strings
│   └── vi.lproj/Localizable.strings
├── Proxy/
│   ├── autospoof-location.sgmodule    ← Shadowrocket module
│   ├── autospoof-location.surge.sgmodule ← Surge module
│   ├── location-spoofer.js           ← MITM script
│   └── README.md                     ← proxy setup guide
├── Tweak/LocationCloak/              ← jailbreak option (backup)
├── Vendor/idevice/                   ← Rust FFI library
└── project.yml                       ← XcodeGen project definition
```

---

## FAQ

### App có cần jailbreak không?
Không. Chạy với free Apple account (Developer Mode). Bypass detection cần Shadowrocket ($3).

### Bump có nhận vị trí giả không?
Có — khi dùng Shadowrocket MITM. `isSimulatedBySoftware = false` vì iOS coi đây là WiFi positioning thật.

### Cần giữ máy tính kết nối không?
Không. Sau khi build và cài lên iPhone, app chạy độc lập.

### Có cần paid Apple Developer account không?
Không bắt buộc. Free account build được app. Paid ($99/năm) chỉ cần nếu muốn VPN tunnel trong app (thay Shadowrocket).

### Tại sao cần Shadowrocket?
DVT LocationSimulation (cách thông thường) set `isSimulatedBySoftware = true`. Shadowrocket MITM thay đổi WiFi positioning response — iOS không set cờ simulated cho WiFi positioning.

### App có gửi dữ liệu ra ngoài không?
Không. Mọi xử lý trên device. CoordinateServer chỉ listen trên 127.0.0.1 (localhost).

---

## License

MIT

## Credit

- [acheong08/ios-location-spoofer](https://github.com/acheong08/ios-location-spoofer) — VPN MITM approach reference
- [mekos2772/ios-location-spoofer](https://github.com/mekos2772/ios-location-spoofer) — Shadowrocket/Surge module reference
- [Apple CoreLocation Experiments](https://github.com/acheong08/apple-corelocation-experiments) — WiFi positioning protocol research
