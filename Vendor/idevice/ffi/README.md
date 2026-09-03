# idevice_ffi — cầu nối C cho AutoSpoofVN

Crate này là **phần cài đặt thật** của `../idevice.h`. Nó bọc crate Rust
[`idevice`](https://crates.io/crates/idevice) của jkcoxson và xuất ra sáu hàm C.

## Vì sao cần crate này

Header ở thư mục cha ban đầu khai bốn hàm `idevice_connect_dvt`,
`idevice_set_location`, `idevice_clear_location`, `idevice_disconnect` — nhưng
**không hàm nào tồn tại** trong crate thật. Đã đối chiếu trực tiếp với mã nguồn
`idevice` 0.1.65: API thật là `LocationSimulationClient::new(&mut RemoteServerClient)`
cùng `.set(lat, lon)` và `.clear()`, và để tới được nó phải đi năm chặng:

```
TcpProvider(10.7.0.1:62078, pairing file)
  → CoreDeviceProxy            lockdownd StartService + CDTunnel handshake
  → create_software_tunnel()   ngăn xếp TCP phần mềm (jktcp) trên tunnel IPv6
  → AdapterHandle              đóng vai RsdProvider
  → RsdHandshake               trên server_rsd_port lấy từ tunnel info
  → RemoteServerClient         com.apple.instruments.dtservicehub
  → LocationSimulationClient   kênh DTX, set/clear toạ độ
```

Chặng `dtservicehub` chỉ được thiết bị quảng bá khi **Developer Disk Image đã
mount**. Nếu chưa, crate trả về `IdeviceError::ServiceNotFound` và cầu nối dịch
thành một thông điệp nói rõ nguyên nhân thay vì một lỗi chung chung.

## Hai quyết định thiết kế cần biết trước khi sửa

**Mỗi phiên chạy trong một thread riêng với `block_on`, không phải `Runtime::spawn`.**
`RsdService` chỉ được cài cho `RemoteServerClient<Box<dyn ReadWrite + 'static>>`,
trong khi `spawn` đòi future phải hợp lệ với *mọi* lifetime. Dùng `spawn` sẽ gặp:

```
error: implementation of `idevice::RsdService` is not general enough
```

**`LocationSimulationClient` mượn `RemoteServerClient`**, nên không gói được cả hai
vào một struct để trả cho C. Vì vậy toàn bộ chuỗi nằm trên stack của tác vụ phiên,
và C điều khiển qua kênh lệnh. Phản hồi đi bằng `std::sync::mpsc` để bên gọi không
cần runtime tokio nào.

## Build

Phải build trên macOS — `aws-lc-rs` cần trình biên dịch C cùng `xcrun` để lấy iOS SDK,
nên không cross-compile được từ Windows. Chi tiết đầy đủ, gồm cả cách vendor phụ
thuộc từ Windows và cách cài Rust ngoại tuyến, nằm ở mục 6 của `BUILD.md` ở gốc repo.

```sh
rustup target add aarch64-apple-ios     # hoặc cài rust-std rời
export IPHONEOS_DEPLOYMENT_TARGET=17.4
cargo build --release --target aarch64-apple-ios
cp target/aarch64-apple-ios/release/libidevice_ffi.a ../
```

Kết quả đã kiểm chứng: 12,2 MB, `lipo -info` cho `arm64`, `nm -g` cho đủ sáu symbol,
và app link được ở cấu hình `Debug-FFI`.

`libidevice_ffi.a` bị `.gitignore` loại trừ — không commit binary, build lại tại chỗ.

## Chưa làm

- Chưa chạy thử với thiết bị thật, nên chưa có bằng chứng nào cho thấy toạ độ đổi
  được. Mọi thứ tới lúc này chỉ chứng minh thư viện **biên dịch và link** được.
- Chưa có heartbeat client (`com.apple.mobile.heartbeat`). Không có nó, lockdownd
  sẽ đóng phiên và cả tunnel lẫn kênh DVT chết theo — đây là việc bắt buộc cho mục
  tiêu 24/7.
- Chưa có bước mount DDI. Crate có sẵn `mobile_image_mounter` và `tss`; cần thêm
  một pha `ensureDDIMounted()` chạy lại sau **mỗi** lần khởi động máy.
