# AutoSpoofVN — Hướng dẫn build

Tài liệu này ghi lại quy trình build **đã được chạy thật** trên macOS 26.6 + Xcode 26.5
(máy ảo `tahoe`), không phải quy trình lý thuyết.

## 1. Hai chế độ build

Dự án có hai chế độ, chọn bằng `-configuration`:

| Config | Link `libidevice_ffi` | Cờ Swift | Kết quả |
| --- | --- | --- | --- |
| `Debug` / `Release` | Không | (không) | Build xanh ở bất kỳ máy nào. GPS thật **không** đổi. |
| `Debug-FFI` | Có | `USE_IDEVICE_FFI` | Cần `Vendor/idevice/libidevice_ffi.a`. Từ 2026-09-03 đây là thư viện Rust **thật** (build tại mục 6), không còn là stub — đã build lại và `** BUILD SUCCEEDED **` trên tahoe. |

Chế độ mặc định là **mô phỏng**. Toàn bộ giao diện, lịch trình 24/7 và mô phỏng chuyến bay
chạy được, chỉ có bước gửi toạ độ xuống thiết bị là không có thật.

### Vì sao phải tách hai config

Bản đầu dùng `#if canImport(idevice)`. Điều kiện này **luôn đúng**, vì `module.modulemap`
chỉ cần một file header là đã tạo được module. Hậu quả: nhánh mô phỏng `#else` không bao giờ
được biên dịch, lời gọi FFI luôn lọt vào binary, và build chết ở khâu link:

```
Undefined symbols for architecture arm64:
  "_idevice_clear_location", "_idevice_connect_dvt",
  "_idevice_disconnect", "_idevice_set_location"
ld: library 'idevice_ffi' not found
```

Nay điều kiện là `#if USE_IDEVICE_FFI`, do build setting bật, nên tách được hai chế độ thật sự.

## 2. Chuẩn bị máy build

Cần macOS + Xcode (đã kiểm chứng trên Xcode 26.5) và XcodeGen.

XcodeGen không có sẵn và máy ảo hiện **không ra được internet**. Cách đã dùng: tải
`xcodegen.zip` từ GitHub Releases trên máy Windows rồi đẩy sang qua `ssh`, giải nén vào `~/bin`.

## 3. Build

```sh
xcodegen generate

# Chế độ mô phỏng — build xanh
xcodebuild -project AutoSpoofVN.xcodeproj -scheme AutoSpoofVN \
  -sdk iphoneos -configuration Debug \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build

# Chế độ FFI thật — chỉ chạy khi đã có Vendor/idevice/libidevice_ffi.a
xcodebuild -project AutoSpoofVN.xcodeproj -scheme AutoSpoofVN \
  -sdk iphoneos -configuration Debug-FFI \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Kiểm tra nhanh cú pháp Swift mà không cần dựng project:

```sh
xcrun --sdk iphoneos swiftc -target arm64-apple-ios17.4 -typecheck \
  $(find AutoSpoofVN/Sources -name '*.swift')
```

## 4. Kiểm tra nhánh FFI khi chưa có thư viện thật

Code nằm sau `#if USE_IDEVICE_FFI` không được biên dịch ở config `Debug`, nên lỗi cú pháp
trong nhánh đó có thể ẩn rất lâu. `Vendor/idevice/idevice_stub.c` là thư viện giả để bịt lỗ
hổng này — nó không đổi GPS, mọi hàm chỉ trả về thành công.

```sh
cd Vendor/idevice
xcrun --sdk iphoneos clang -target arm64-apple-ios17.4 -c idevice_stub.c -o idevice_stub.o
xcrun ar rcs libidevice_ffi.a idevice_stub.o
cd ../..

xcodebuild -project AutoSpoofVN.xcodeproj -scheme AutoSpoofVN \
  -sdk iphoneos -configuration Debug-FFI \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Đã chạy thật và cho `** BUILD SUCCEEDED **`. Nhớ xoá `libidevice_ffi.a` giả trước khi đặt
thư viện thật vào, đừng để lẫn.

## 5. Cảnh báo link vô hại

Ba dòng cảnh báo sau xuất hiện ở mọi bản build và không làm hỏng sản phẩm:

```
ld: warning: Could not find or use auto-linked framework 'CoreAudioTypes'
ld: warning: Could not find or use auto-linked framework 'UIUtilities'
ld: warning: ... cannot link directly with 'SwiftUICore'
```

## 6. Build thư viện FFI thật

`Vendor/idevice/idevice.h` khai báo ABI v2. Phần cài đặt là một crate Rust
(`crate-type = ["staticlib"]`) bọc crate [`idevice`](https://crates.io/crates/idevice)
của jkcoxson.

### Vì sao phải build trên macOS

Không cross-compile được từ Windows: `aws-lc-rs` (nhà cung cấp mật mã của `rustls`)
cần một trình biên dịch C cùng `xcrun` để lấy iOS SDK. Trên Windows nó dừng ngay ở

```
error occurred in cc-rs: failed to find tool "xcrun": program not found
```

Nhưng phần *tải phụ thuộc* thì làm trên Windows được, rồi mang sang:

```sh
# Trên Windows, trong thư mục crate FFI
cargo vendor vendor          # ~276 MB
tar -czf idevffi-src.tar.gz Cargo.toml Cargo.lock src vendor
```

Trên macOS, thêm `.cargo/config.toml` trỏ về thư mục vendor rồi build `--offline`:

```sh
export PATH=$HOME/rust/bin:$PATH
export IPHONEOS_DEPLOYMENT_TARGET=17.4
cargo build --release --offline --target aarch64-apple-ios
cp target/aarch64-apple-ios/release/libidevice_ffi.a <repo>/Vendor/idevice/
```

### Máy ảo macOS không có internet — cách đi vòng, không cần quyền quản trị

Máy có hai default route: `en0` qua NAT của VMware (`192.168.25.2`) đã chết, còn `en1`
nối thẳng ra LAN thì có internet. macOS ưu tiên `en0` nên mọi kết nối đều hỏng, kể cả DNS.

Sửa triệt để cần quyền quản trị:

```sh
sudo networksetup -ordernetworkservices "Bridged LAN" "Ethernet" "Tailscale"
```

Không có mật khẩu vẫn tải được, bằng cách ép đúng interface và bỏ qua DNS — phân giải
tên máy ở nơi khác rồi truyền thẳng IP vào:

```sh
curl -L --interface en1 --resolve static.rust-lang.org:443:151.101.66.137   -o rust.tar.xz https://static.rust-lang.org/dist/rust-1.98.0-x86_64-apple-darwin.tar.xz
```

### Cài Rust ngoại tuyến lên máy ảo

Không có `rustup` thì dùng bộ cài rời:

```sh
tar -xf rust-1.98.0-x86_64-apple-darwin.tar.xz
tar -xf rust-std-1.98.0-aarch64-apple-ios.tar.xz
./rust-1.98.0-x86_64-apple-darwin/install.sh --prefix=$HOME/rust --without=rust-docs
./rust-std-1.98.0-aarch64-apple-ios/install.sh --prefix=$HOME/rust
```

## 7. Việc chưa làm được

- Cập nhật 2026-09-03: `libidevice_ffi.a` **thật** đã build xong trên tahoe (lệnh ở mục 6,
  offline bằng `vendor/` đã tải sẵn, ~1 phút 14s, chỉ 2 warning vô hại) và link thành công
  vào `Debug-FFI` (`** BUILD SUCCEEDED **`). File nhị phân không commit vào git (`.gitignore`
  loại `Vendor/idevice/*.a`) — máy build nào cũng phải tự dựng lại theo mục 6.
- Test tự động: đã có (`AutoSpoofVNTests/SimulationStudioTests.swift`), 25/25 test pass trên
  simulator `iPhone 17` (Xcode 26.5).
- Chưa chạy thử trên thiết bị thật. Kể cả khi có `libidevice_ffi.a` thật, để đổi được GPS
  còn cần, tự tay trên máy có Xcode + thiết bị cắm dây:
  1. Sinh **pairing record** một lần từ máy tính (không làm được qua SSH — cần thiết bị vật lý
     cắm vào máy đó và xác nhận "Trust" trên màn hình iPhone).
  2. Bật **Developer Mode** trong Settings > Privacy & Security trên iPhone (yêu cầu khởi động
     lại máy sau khi bật).
  3. Mount **Developer Disk Image (DDI)** — Xcode tự mount khi thấy thiết bị Developer Mode đã
     bật và đã trust; DDI mất sau mỗi lần khởi động lại iPhone, phải mount lại.
  4. Bật **VPN loopback** (LocalDevVPN) để app gọi được `10.7.0.1:62078`/`:49152`.
  5. **Chữ ký (code signing)**: cần Apple ID/Team ID thật của bạn khai vào `DEVELOPMENT_TEAM`
     trong `project.yml`, hoặc set qua Xcode UI — hiện đang để trống (`CODE_SIGN_STYLE: Automatic`
     nhưng `DEVELOPMENT_TEAM: ""`).
  6. Chưa có AppIcon.
  Các bước 1–4 cần thao tác tay trên máy Mac + iPhone thật, agent không làm thay được qua SSH.
