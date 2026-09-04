<div align="center">

# LocationX

**Mô phỏng vị trí GPS ngay trên iPhone — không jailbreak, không cần máy tính kết nối liên tục.**

[![Giấy phép](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](LICENSE)
[![Nền tảng](https://img.shields.io/badge/platform-iOS%2017.4%2B-lightgrey.svg)](#yêu-cầu)
[![Swift](https://img.shields.io/badge/Swift-5.9-orange.svg)](https://swift.org)
[![CI](https://github.com/ndh0408/LocationX/actions/workflows/ci.yml/badge.svg)](https://github.com/ndh0408/LocationX/actions/workflows/ci.yml)

Tiếng Việt · [English](README.en.md)

</div>

---

## LocationX là gì

LocationX là ứng dụng iOS gốc (SwiftUI) mô phỏng việc di chuyển bằng GPS: đặt vị trí thủ công,
chạy theo tuyến đường thật bám mặt đường, dựng kịch bản nhiều bước, mô phỏng chu trình sinh hoạt
24/7, và bay giữa các sân bay quốc tế.

Điểm khác biệt so với các công cụ đổi vị trí thông thường: LocationX mô phỏng **chuyển động
đáng tin** — có gia tốc, giảm tốc, bám hướng đường, nhiễu GPS tương quan theo thời gian — thay vì
nhảy cóc giữa các toạ độ.

> [!WARNING]
> Công cụ này dành cho **kiểm thử, phát triển và nghiên cứu** trên thiết bị của chính bạn.
> Dùng để gian lận trong trò chơi, qua mặt kiểm soát của nhà tuyển dụng, hay bất kỳ mục đích nào
> vi phạm điều khoản dịch vụ của bên thứ ba là **trách nhiệm của bạn**. Xem [Miễn trừ](#miễn-trừ-trách-nhiệm).

---

## Cách hoạt động

iOS không cho phép ứng dụng thường ghi đè vị trí toàn hệ thống. LocationX đi đường vòng: can thiệp
vào **dịch vụ định vị bằng WiFi** của Apple.

```
LocationX di chuyển (tuyến / kịch bản / chu trình / chuyến bay)
        │
        ▼
SimulationCoordinator  ← nguồn sự thật duy nhất cho vị trí
        │
        ▼
CoordinateServer  (HTTP nội bộ, 127.0.0.1:8765)
        │
        │   Shadowrocket lấy script + toạ độ realtime từ đây
        ▼
Shadowrocket (MITM)  chặn  gs-loc.apple.com/clls/wloc
        │
        ▼
location-spoofer.js  giải mã protobuf, thay latitude/longitude, mã hoá lại
        │
        ▼
iOS tin rằng WiFi quanh nó nằm ở toạ độ giả
        │
        ▼
CoreLocation trả về vị trí giả — và isSimulatedBySoftware = false
```

Chi tiết giao thức nằm ở [`Proxy/README.md`](Proxy/README.md).

### Vì sao lại là protobuf

Response của `gs-loc.apple.com` là protobuf. Message `Location` có:

| Trường | Tên | Kiểu | Đơn vị |
|---:|---|---|---|
| 1 | `latitude` | int64 varint | 1e-8 độ |
| 2 | `longitude` | int64 varint | 1e-8 độ |
| 3 | `horizontal_accuracy` | int64 varint | — |

Varint có **độ dài thay đổi**, nên không thể ghi đè tại chỗ: đổi giá trị là đổi số byte, làm lệch
mọi trường phía sau và sai luôn `length` của các message bao ngoài. `location-spoofer.js` vì vậy
giải mã cả cây message, sửa trường, rồi **mã hoá lại từ trong ra ngoài**.

Cấu trúc protobuf được xác định nhờ nghiên cứu của
[acheong08/apple-corelocation-experiments](https://github.com/acheong08/apple-corelocation-experiments).

---

## Tính năng

| Nhóm | Nội dung |
|---|---|
| **Bản đồ** | Bản đồ toàn khung, chạm để đặt vị trí, vết đường đã đi, bám theo vị trí, nghiêng 3D, ba kiểu bản đồ |
| **Tuyến đường** | Vẽ tuyến qua nhiều điểm dừng, bám đường thật qua MapKit, chọn phương tiện và tốc độ, xem trước, lưu, chạy lại, nhập/xuất GPX |
| **Kịch bản** | Chuỗi hành động: di chuyển, chờ, dừng chân, đổi tốc độ, đi lang thang, lặp lại |
| **Chu trình 24/7** | Lịch sinh hoạt tự động giữa nhà, công ty, quán cà phê theo giờ trong ngày |
| **Chuyến bay** | Bay giữa sân bay quốc tế theo đường vòng cung lớn, có giai đoạn cất/hạ cánh; chế độ du lịch thế giới tự động |
| **Telemetry** | Tốc độ, hướng, độ cao, quãng đường, tiến độ, giờ đến dự kiến — thời gian thực |
| **Chuyển động thật** | Gia tốc/giảm tốc theo phương tiện, làm mượt hướng qua mốc 0°/360°, nhiễu GPS tương quan theo thời gian |
| **Khác** | Lịch sử và phát lại phiên, địa điểm đã lưu, Live Activity / Dynamic Island, chạy nền, song ngữ Việt–Anh |

---

## Yêu cầu

- **iPhone chạy iOS 17.4 trở lên**
- **macOS + Xcode 16** để build
- [**XcodeGen**](https://github.com/yonaskolb/XcodeGen) — `brew install xcodegen`
- [**Shadowrocket**](https://apps.apple.com/app/shadowrocket/id932747118) (có phí) để chặn và sửa
  response định vị. Surge / Loon / Stash cũng dùng được cùng module.
- Tài khoản Apple Developer để ký ứng dụng lên máy thật

---

## Cài đặt

### 1. Build

```bash
git clone https://github.com/ndh0408/LocationX.git
cd LocationX
xcodegen generate
open LocationX.xcodeproj
```

Chọn scheme **LocationX**, chọn thiết bị, bấm ▶.

Chạy trên **máy thật** cần chọn Team ký cho cả ba target (`LocationX`, `LocationXTests`,
`LocationXWidgets`) trong *Signing & Capabilities*.

### 2. Thiết lập Shadowrocket

Mở LocationX → **Cài đặt → Thiết lập Shadowrocket** và làm theo hướng dẫn trong app, hoặc làm tay:

1. **Nhập module**

   ```
   https://raw.githubusercontent.com/ndh0408/LocationX/main/Proxy/locationx.sgmodule
   ```

   Shadowrocket → *Config* → *Modules* → *Add Module* → dán URL trên.

   Muốn toạ độ cập nhật **realtime** theo LocationX thì dùng bản nội bộ thay thế —
   yêu cầu LocationX đang chạy:

   ```
   http://127.0.0.1:8765/locationx.sgmodule
   ```

2. **Bật giải mã HTTPS**

   Shadowrocket → *Settings* → *HTTPS Decryption* → bật → *Generate Certificate* → *Install*.

3. **Tin cậy chứng chỉ** — bước này hay bị bỏ sót và là nguyên nhân phổ biến nhất khiến không chạy:

   *Cài đặt* → *Cài đặt chung* → *Giới thiệu* → *Cài đặt tin cậy chứng chỉ* → bật CA của Shadowrocket.

4. **Bật VPN** trong Shadowrocket.

Khi cả chuỗi đã thông, LocationX báo **“Đang hoạt động”** — trạng thái này chỉ hiện khi Shadowrocket
**thực sự** đã lấy script từ CoordinateServer, không phải đoán mò.

### 3. Kiểm tra

Mở Bản đồ của Apple. Vị trí hiển thị phải là toạ độ bạn đặt trong LocationX.

> [!NOTE]
> Vị trí giả chỉ có tác dụng khi thiết bị định vị **bằng WiFi**. Ở ngoài trời, tín hiệu GPS vệ tinh
> lấn át và vị trí thật sẽ thắng. Bật Chế độ máy bay rồi bật lại WiFi là cách buộc thiết bị định vị
> bằng WiFi.

---

## Cấu trúc dự án

```
LocationX/
├── Sources/
│   ├── Coordinator/     SimulationCoordinator — nguồn sự thật duy nhất
│   ├── Engine/          Chuyển động, tuyến, kịch bản, chu trình, chuyến bay, thiết bị
│   │   ├── Route/       RouteSimulator, RouteBuilder, SavedRouteStore
│   │   ├── Motion/      MotionEngine, HeadingEngine
│   │   └── Scenario/    ScenarioEngine
│   ├── Models/          Kiểu dữ liệu miền, máy trạng thái
│   ├── Persistence/     Lưu JSON, di trú dữ liệu
│   ├── UI/
│   │   ├── DesignSystem/  Token màu, chữ, khoảng cách, chuyển động, song ngữ
│   │   ├── Components/    Thành phần dùng chung
│   │   ├── Navigation/    RootTabView, AppRoute
│   │   ├── Map/           Màn hình bản đồ
│   │   ├── Routes/        Tuyến đường
│   │   ├── Flight/        Chuyến bay
│   │   ├── Routine/       Chu trình 24/7
│   │   ├── Onboarding/    Màn chào lần đầu
│   │   └── Settings/      Cài đặt, Chẩn đoán, Shadowrocket
│   └── Views/           Màn hình chưa thiết kế lại
├── Resources/           Info.plist, Assets, vi.lproj, en.lproj
LocationXWidgets/        Live Activity, Dynamic Island
LocationXTests/          Kiểm thử đơn vị
Proxy/                   Module MITM và script protobuf
docs/UI_AUDIT.md         Kiểm kê tính năng — ảnh chụp TRƯỚC khi thiết kế lại
```

### Nguyên tắc kiến trúc

`SimulationCoordinator` là **nguồn sự thật duy nhất** cho trạng thái mô phỏng. Mọi nguồn phát toạ độ
đều đi qua nó, và nó phân xử theo thứ tự ưu tiên:

```
Thủ công 100 > Kịch bản 80 > Chuyến bay 60 > Tuyến 50 > Chu trình 40 > Phát lại 20
```

Tầng giao diện **quan sát** trạng thái này, không giữ bản sao. Nhiễu GPS chỉ được áp đúng một lần,
ở thời điểm gửi ra thiết bị — vị trí nội bộ luôn là vị trí thật, nếu không nhiễu sẽ tích luỹ thành
trôi vị trí.

Chỉ có **một** đường đưa toạ độ ra khỏi app: `CoordinateServer` phục vụ toạ độ tại
`127.0.0.1:8765`, Shadowrocket đọc từ đó. Không còn đường DVT/FFI — toàn bộ lớp ghép nối
thiết bị đã được gỡ bỏ cùng thư viện FFI.

Nhãn "đã kết nối" trên thanh trạng thái đòi đủ bốn điều kiện: máy chủ đang chạy,
Shadowrocket đã cài, module đã nhập, VPN đang bật. Báo xanh trong khi toạ độ không tới
được ứng dụng nào là kiểu sai tệ nhất mà app này có thể mắc.

---

## Phát triển

```bash
xcodegen generate                      # sinh lại project sau khi đổi project.yml
xcodebuild -project LocationX.xcodeproj -scheme LocationX \
  -destination 'platform=iOS Simulator,name=iPhone 17' test
```

Thêm chuỗi giao diện: dùng `L("khoa.cua.ban")` rồi bổ sung vào **cả hai**
`Resources/vi.lproj/Localizable.strings` và `en.lproj/Localizable.strings`.
`LocalizationTests` sẽ báo lỗi nếu thiếu một bên hoặc lệch định dạng `%d`/`%@`.

Xem [CONTRIBUTING.md](CONTRIBUTING.md) để biết quy ước đóng góp.

---

## Miễn trừ trách nhiệm

Phần mềm này được cung cấp cho mục đích giáo dục và nghiên cứu. Tác giả **không** chịu trách nhiệm
cho việc bạn sử dụng nó như thế nào.

- Chỉ dùng trên thiết bị **bạn sở hữu**.
- Giả mạo vị trí có thể vi phạm điều khoản dịch vụ của nhiều ứng dụng và có thể dẫn tới khoá tài khoản.
- Ở một số nơi, việc khai báo sai vị trí cho một số dịch vụ nhất định có thể là hành vi trái pháp luật.
- Không dùng để lừa dối người khác, gian lận, hay né tránh nghĩa vụ pháp lý.

---

## Ghi nhận

- [acheong08/apple-corelocation-experiments](https://github.com/acheong08/apple-corelocation-experiments) — nghiên cứu giao thức định vị WiFi của Apple
- [acheong08/ios-location-spoofer](https://github.com/acheong08/ios-location-spoofer) — kiến trúc tham chiếu cho hướng MITM

---

## Giấy phép

[Apache License 2.0](LICENSE) — © 2026 Nguyễn Đức Huy
