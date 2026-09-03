# AutoSpoofVN — Kết quả kiểm tra & Lộ trình phát triển

Ngày 03/09/2026. Soạn bởi Claude, phối hợp với Codex trong cùng worktree `main-dev`.

Tài liệu này phân biệt rõ hai loại kết luận:

- **[ĐÃ CHẠY THẬT]** — chạy trên macOS 26.6 / Xcode 26.5 (máy ảo `tahoe`), có output thật.
- **[CHƯA KIỂM CHỨNG]** — suy luận hoặc tra cứu tài liệu, chưa chạm được thiết bị thật.

---

## 1. Kết luận sống còn

**Mục tiêu "GPS ảo 24/7, không cần máy tính" — chưa đạt được ở dạng đang thiết kế, và
khoảng cách còn xa hơn nhiều so với vẻ ngoài của mã nguồn.**

Ba lý do độc lập, mỗi lý do đủ để chặn:

**(a) Tầng kết nối chưa từng tồn tại. [ĐÃ CHẠY THẬT]**
`Vendor/idevice/idevice.h` khai báo 4 hàm `idevice_connect_dvt` / `idevice_set_location` /
`idevice_clear_location` / `idevice_disconnect`, nhưng trong repo không có thư viện nào cài
đặt chúng. Linker xác nhận:

```
Undefined symbols for architecture arm64:
  "_idevice_connect_dvt", "_idevice_set_location",
  "_idevice_clear_location", "_idevice_disconnect"
ld: library 'idevice_ffi' not found
```

**[CHƯA KIỂM CHỨNG]** Theo tra cứu, crate Rust `idevice` là có thật nhưng API C của nó
khác hẳn: họ `lockdown_location_simulation_*` (chỉ cho iOS ≤ 16, cần DDI) và họ
`location_simulation_new/set/clear/free` đi qua `RemoteServerHandle` cho iOS 17+.
Nghĩa là 4 hàm trong header là do người viết tự đặt ra, không phải API thật.

**(b) Một lời gọi tới cổng 62078 là không đủ trên iOS 17+. [CHƯA KIỂM CHỨNG]**
Từ iOS 17, dịch vụ Instruments không còn trả lời `StartService` trực tiếp của lockdownd.
Chuỗi thật gồm 5 chặng:

```
TCP 10.7.0.1:62078 (lockdownd, TLS bằng pairing record)
  └─> StartService com.apple.internal.devicecompute.CoreDeviceProxy
        └─> tunnel mang gói IPv6
              └─> bắt tay RemoteServiceDiscovery (RSD)
                    └─> RemoteXPC lấy cổng dtservicehub
                          └─> kênh DTX -> LocationSimulation
```

Code hiện tại gộp cả 5 chặng vào một hàm. Ngoài ra iOS 17+ bắt buộc mount **personalized
DDI** (ký qua Apple TSS theo ECID của máy) thì `dtservicehub` mới xuất hiện, và DDI **mất
sau mỗi lần reboot** nên phải mount lại. Cũng cần chạy service heartbeat thật
(`com.apple.mobile.heartbeat`) — cái tên `heartBeatTimer` trong code chỉ gửi lại toạ độ,
không phải heartbeat giao thức.

**(c) Chạy ngầm 24/7 bằng silent audio là chỗ dựa không chắc. [ĐÃ CHẠY THẬT + CHƯA KIỂM CHỨNG]**
Tôi chạy lại đúng hàm `createSilentAudioData()` cũ trên macOS:

```
ChunkSize=0  ByteRate=0  BlockAlign=0  Subchunk2Size=0
AVAudioPlayer INIT FAILED: NSOSStatusErrorDomain Code=1685348671
```

Header WAV thiếu 4 trường bắt buộc nên `AVAudioPlayer` **không khởi tạo được**. Lỗi bị nuốt
trong `catch` chỉ `print`, nên app tưởng đang chạy ngầm còn thực tế bị treo sau ~30 giây.
**Tính năng 24/7 chưa từng hoạt động một lần nào.** Đã sửa và kiểm chứng:
`AVAudioPlayer INIT OK duration=1.0 prepare=true`.

Nhưng kể cả khi audio chạy, **[CHƯA KIỂM CHỨNG]** Apple không cam kết background mode
`audio` giữ app sống, và không có cách nào trên iOS không jailbreak để tự khởi động lại sau
reboot / crash / user vuốt tắt.

### Còn hai điều phá vỡ khẩu hiệu "không cần máy tính" [CHƯA KIỂM CHỨNG]

- **Pairing file phải sinh từ máy tính một lần.** App không tự tạo được vì pairing là bắt
  tay tin cậy có prompt "Trust This Computer" ở tầng lockdownd. Khẩu hiệu chỉ đúng ở trạng
  thái *vận hành*, không đúng ở *cài đặt*.
- **Loopback VPN cần entitlement `com.apple.developer.networking.networkextension`**, mà
  tài khoản Apple Developer **miễn phí không được cấp**. Đó là lý do dự án đang phụ thuộc
  app ngoài (LocalDevVPN/StosVPN). Rủi ro: hệ sinh thái này từng bị Apple gỡ khỏi App Store.

---

## 2. Tình trạng hiện tại

**[ĐÃ CHẠY THẬT] Repo hiện build xanh, 0 error 0 warning, ở cả hai cấu hình.**

| Hạng mục | Trạng thái |
| --- | --- |
| Swift type-check toàn bộ nguồn | Sạch |
| `xcodebuild -configuration Debug` (chế độ mô phỏng) | `** BUILD SUCCEEDED **` |
| `xcodebuild -configuration Debug-FFI` (kèm thư viện stub) | `** BUILD SUCCEEDED **` |
| Chạy trên thiết bị thật | Chưa thử — chưa có chữ ký |
| Đổi được GPS thật | **Không**. Chưa có thư viện FFI thật |

Chạy được ngay hôm nay: bản đồ, chạm để đặt toạ độ, chu trình sinh hoạt 24/7, mô phỏng
chuyến bay và tour du lịch thế giới — tất cả ở **chế độ mô phỏng trong app**, GPS thật của
máy không hề thay đổi.

### Những lỗi đã sửa trong đợt này

| # | Lỗi | Bằng chứng | Trạng thái |
| --- | --- | --- | --- |
| 1 | `#if canImport(idevice)` **luôn TRUE** (modulemap chỉ cần header), nên nhánh mô phỏng `#else` là code chết và mọi bản build đều chết ở link | Undefined symbols ở trên | Đổi sang `#if USE_IDEVICE_FFI` + tách config `Debug` / `Debug-FFI` |
| 2 | WAV im lặng hỏng → keep-alive nền chưa từng chạy | OSStatus 1685348671 | Viết lại `makeSilentWavData()`, đã xác nhận init OK |
| 3 | 3 module cùng ghi toạ độ, không loại trừ lẫn nhau — bật đồng thời chu trình và chuyến bay thì vị trí nhảy loạn | Đọc mã | Thêm arbiter `acquire`/`release`/`submit` với ưu tiên Manual > Flight > Routine |
| 4 | Lịch đánh giá mỗi 60 giây gọi lại `startCommute()` → lộ trình reset về điểm đầu, **không bao giờ tới nơi** | Đọc mã | Thêm `activeCommuteKey` chặn khởi động lại |
| 5 | Nhận phòng khách sạn **xoá vĩnh viễn** nhà/cơ quan/quán cà phê và toàn bộ bookmark thật của người dùng | Đọc mã | Thêm `beginTravelOverride()` / `endTravelOverride()` sao lưu – khôi phục |
| 6 | Nút "khôi phục GPS thật" vô hiệu — chu trình ghi đè lại ở tick kế tiếp | Đọc mã | Thêm cờ `isHalted`, chặn mọi nguồn tới khi khởi động lại rõ ràng |
| 7 | Toàn bộ lời gọi FFI chặn main thread (mỗi 1–2,5 giây khi bay) → nguy cơ watchdog giết app | Đọc mã | Đưa hết sang `ffiQueue` nối tiếp |
| 8 | 15 chuỗi trong `FlightManager` mất dấu `\` → HUD hiện `(flight.flightNumber)` thay vì số hiệu | Đọc mã, compiler không bắt được | Đã sửa 15 chỗ |
| 9 | 35 chỗ trong 3 file View **thừa** `\\` → 6 lỗi cú pháp | `error: expected expression path in Swift key path` | Đã sửa |
| 10 | `loadSavedLocations` dùng `!= 0.0` để dò "chưa lưu" → sai ở xích đạo và kinh tuyến gốc | Đọc mã | Đổi sang kiểm tra tồn tại khoá + `CLLocationCoordinate2DIsValid` |
| 11 | Đổi 1 toạ độ ghi UserDefaults 6 lần; `init()` tự ghi đè 18 lần lúc khởi động | Đọc mã | Thêm cờ `isLoading` |
| 12 | `case 23...24` — `Calendar` không bao giờ trả giờ 24 | Đọc mã | Đổi thành `case 23` |
| 13 | Jitter chia cho `cos(lat)` → vô cực ở gần cực | Đọc mã | Chặn mẫu số tối thiểu + kẹp toạ độ hợp lệ |
| 14 | `TARGETED_DEVICE_FAMILY: "1,2"` gây warning orientation | warning từ xcodebuild | Đổi thành `"1"` ở cấp target |
| 15 | Rác: `setup_travel_engine.js` 0 byte, không có `.gitignore` | — | Đã xoá / đã thêm |

### Còn nợ, chưa sửa

- `UIBackgroundModes` khai `location` và `processing` nhưng **không có** `CLLocationManager`
  nào và **không có** `BGTaskSchedulerPermittedIdentifiers`. Vừa vô tác dụng vừa là rủi ro
  bị từ chối. Đáng nói hơn: `location` kèm `CLLocationManager` thật là **cơ chế relaunch
  duy nhất iOS cho phép** — đang bị bỏ phí.
- Không có observer `AVAudioSession.interruptionNotification`: sau một cuộc gọi hay Siri,
  audio không tự chạy lại và app chết vĩnh viễn.
- Chạm bản đồ bật `isSimulating = true` kể cả khi chưa kết nối → app **giả vờ hoạt động**.
- Pairing record lưu dạng `String` trong `UserDefaults`; file pairing thật là binary plist,
  dán tay không được, và đây là khoá riêng không nên để trần.
- Không có onboarding. Người dùng phải tự làm khoảng 10 bước, app chỉ ghi 4 bước.
- Không có test, không có CI, không có AppIcon, `DEVELOPMENT_TEAM` rỗng.
- `RoutePlan` là code chết, chưa dùng ở đâu.

---

## 3. Lộ trình

Nguyên tắc: **không viết thêm tính năng nào cho tới khi M1 trả lời xong câu hỏi khả thi.**
Hiện đã có 479 dòng mô phỏng chuyến bay quốc tế nằm trên một lõi chưa đổi được GPS.

### M0 — Chốt nền (gần xong)

- [x] Build xanh cả hai cấu hình
- [x] Sửa 15 lỗi ở bảng trên
- [x] `BUILD.md` ghi quy trình đã kiểm chứng
- [ ] Người dùng chạy 1 lệnh mở mạng cho VM macOS (mục 5)
- [ ] Commit mốc "build xanh" làm điểm lùi an toàn

**Xong khi:** `git log` có một commit mà từ đó `xcodebuild -configuration Debug` xanh.

### M1 — Trả lời câu hỏi sống còn *trước khi viết thêm code* ⭐

Đây là mốc quan trọng nhất. Mục tiêu: biết chắc DVT có khả thi không, **bằng máy tính
trước**, chưa động tới on-device.

1. Cắm iPhone vào máy tính, chạy `pymobiledevice3` để mount DDI và thử
   `simulate-location set`. Nếu **toạ độ trên máy đổi thật** → cơ chế đúng, chỉ còn là bài
   toán port sang on-device. Nếu **không** → dừng đường DVT ngay, chuyển M1-B.
2. Nếu (1) chạy: build crate `idevice` cho `aarch64-apple-ios`, đọc API C **thật** bằng
   `cbindgen`, rồi **viết lại `Vendor/idevice/idevice.h` theo API thật** (header hiện tại
   phải bị xoá — nó là hàng tự chế).
3. Xác định dứt điểm: tài khoản Apple Developer đang dùng là **miễn phí hay trả phí**. Câu
   trả lời quyết định có tự nhúng NEPacketTunnelProvider được không, hay buộc phụ thuộc
   LocalDevVPN/StosVPN bên ngoài.

**Xong khi:** có ảnh chụp màn hình iPhone hiển thị toạ độ giả do máy tính đặt, **hoặc** một
kết luận viết ra rằng đường DVT không khả thi.

**M1-B (dự phòng, nếu M1 thất bại):** đánh giá kiến trúc MITM Wi-Fi positioning
(`acheong08/ios-location-spoofer`). Ưu: không cần pairing, không cần DDI, không cần máy
tính, không có phiên nào để chết → 24/7 thật. Nhược: vẫn cần tài khoản trả phí, người dùng
phải cài VPN profile + tin CA thủ công, và **[CHƯA KIỂM CHỨNG]** khi máy bắt được GNSS thật
ngoài trời thì CoreLocation có thể vẫn ưu tiên vệ tinh.

### M2 — Làm app trung thực về trạng thái

Trước khi thêm tính năng, phải hết "giả vờ chạy được". Đây là việc rẻ, làm được ngay, và
là thứ người dùng cảm nhận đầu tiên.

- Chạm bản đồ khi chưa kết nối: hiện cảnh báo, **không** bật `isSimulating`.
- Nhãn rõ ràng "CHẾ ĐỘ MÔ PHỎNG — GPS thật không đổi" khi build ở config `Debug`.
- Hiện `activeSource` (ai đang điều khiển toạ độ) và cảnh báo khi `keepAliveError != nil`.
- Sheet ghép nối không tự đóng trước khi có kết quả; hiển thị lỗi cụ thể.
- Đổi ô dán text sang `.fileImporter` cho pairing file (file thật là binary plist).

**Xong khi:** không còn màn hình nào báo thành công khi thực tế chưa làm được gì.

### M3 — Chạy ngầm cho ra chạy ngầm

- Thêm `CLLocationManager` thật với `allowsBackgroundLocationUpdates` — vừa hợp thức hoá
  background mode `location`, vừa lấy được cơ chế relaunch duy nhất iOS cho.
- Thêm observer `AVAudioSession.interruptionNotification` để chạy lại audio sau cuộc gọi.
- Bỏ background mode `processing` (không có gì backing) hoặc thêm `BGTaskScheduler` thật.
- Đo pin thật trong 24 giờ. Ba timer không tolerance cộng audio liên tục là chi phí đáng kể.

**Xong khi:** app sống qua 12 giờ khoá máy, có log chứng minh, và pin tụt ở mức chấp nhận được.

### M4 — Nối FFI thật

Chỉ bắt đầu khi M1 cho kết quả dương tính.

- Dùng xcframework/SPM chính chủ thay cho `-lidevice_ffi` thủ công.
- Viết lại `SpoofEngine` theo đúng chuỗi CoreDeviceProxy → RSD → RemoteServer → LocationSimulation.
- Thêm pha `ensureDDIMounted()` chạy lại sau **mỗi lần** khởi động máy.
- Chạy heartbeat client thật; dùng nó làm nguồn sự thật cho `isLoopbackConnected`; timer 20
  giây đổi vai thành watchdog tái kết nối, thay vì spam `set`.

**Xong khi:** đặt toạ độ trong app và Apple Maps trên chính máy đó hiển thị đúng vị trí giả.

### M5 — Chất lượng mô phỏng & mở rộng

- Bám đường thật bằng `MKDirections` thay cho nội suy đường thẳng.
- Mô hình gia tốc, dừng đèn đỏ, độ chính xác GPS thay đổi theo môi trường. Hiện tại chuyển
  động thẳng đều với jitter nhiễu trắng là dấu hiệu dễ nhận ra.
- Tách protocol cho nguồn toạ độ + tiêm phụ thuộc `Date`/`Timer` để unit-test được logic
  lịch trình mà không cần thiết bị.
- Bản địa hoá bằng `Localizable.strings`.

---

## 4. Phân chia sở hữu file

Đã thống nhất với Codex và đang chạy tốt.

| File | Chủ | Ghi chú |
| --- | --- | --- |
| `Engine/SpoofEngine.swift` | Claude | Arbiter, keep-alive, FFI |
| `Engine/RoutineManager.swift` | Claude | Lịch sinh hoạt, lưu trữ |
| `Vendor/idevice/*`, `project.yml`, `Info.plist`, `*.entitlements` | Claude | Cấu hình build |
| `Engine/FlightManager.swift` | Codex | Chuyến bay, World Odyssey |
| `Views/WorldTravelView.swift`, `Views/FlightHUDView.swift` | Codex | UI du lịch |
| `Models/Types.swift`, `Views/MainView.swift`, `AutoSpoofVNApp.swift` | **Chung** | Báo nhau trước khi sửa |

**Quy tắc bắt buộc:** chỉ làm việc trong `C:/Users/Admin/orca/workspaces/AutoSpoofVN/main-dev`.
Worktree `D:/ToolGN/AutoSpoofVN` đã lệch và không còn là nguồn sự thật.

Hai sự cố đã xảy ra vì ghi file qua nhiều lớp shell/python, cần tránh lặp lại:

- File `.git` của worktree bị ghi đè bằng nội dung reflog (đã khôi phục).
- `MainView.swift` ở `D:/ToolGN` bị cắt còn 0 byte (đã khôi phục từ `main-dev`).
- Dấu `\` trong chuỗi Swift lúc thì mất, lúc thì nhân đôi — gây 6 lỗi cú pháp và 15 chuỗi
  hiển thị sai. **Hãy ghi file trực tiếp, đừng đi qua heredoc/base64.**

---

## 5. Việc cần người dùng làm

| # | Việc | Vì sao chặn |
| --- | --- | --- |
| 1 | Chạy trên VM macOS: `sudo networksetup -ordernetworkservices "Bridged LAN" "Ethernet" "Tailscale"` | VM có 2 default route; `en0` qua NAT VMware `192.168.25.2` đã chết, `en1` bridge ra LAN thì **có** internet (ping 8.8.8.8 = 29 ms). macOS đang ưu tiên nhầm `en0`. Lệnh cần mật khẩu quản trị nên tôi không chạy được. Không có internet thì không cài được `rustup`/`cargo` → không build được thư viện FFI. |
| 2 | Cho biết tài khoản Apple Developer là **miễn phí hay trả phí** | Quyết định có tự nhúng được VPN extension hay buộc phụ thuộc app ngoài. Ảnh hưởng trực tiếp tới kiến trúc. |
| 3 | Cắm một iPhone thật vào máy tính để chạy thí nghiệm M1 | Đây là thí nghiệm rẻ nhất bác bỏ được giả định lớn nhất của dự án. |
| 4 | Xác nhận iPhone đích chạy iOS bao nhiêu | Deployment target 17.4 đã loại TrollStore (Apple vá từ 17.0.1). Nếu máy ở iOS ≤ 16 thì có đường đơn giản hơn nhiều. |

---

## 6. Lưu ý về phân phối

App dạng này không lên App Store được (dùng background audio im lặng để duy trì tiến trình,
và can thiệp dịch vụ vị trí của hệ thống). Kênh khả dĩ là sideload qua AltStore/SideStore
với chứng chỉ dev, phải gia hạn 7 ngày một lần với tài khoản miễn phí.

Dùng để thay đổi vị trí báo cho dịch vụ bên thứ ba có thể vi phạm điều khoản của dịch vụ đó.
Đây là việc của người dùng cân nhắc, nêu ra ở đây để không bị bất ngờ.
