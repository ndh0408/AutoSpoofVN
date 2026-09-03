# AutoSpoofVN — Hướng dẫn build

Tài liệu này ghi lại quy trình build **đã được chạy thật** trên macOS 26.6 + Xcode 26.5
(máy ảo `tahoe`), không phải quy trình lý thuyết.

## 1. Hai chế độ build

Dự án có hai chế độ, chọn bằng `-configuration`:

| Config | Link `libidevice_ffi` | Cờ Swift | Kết quả |
| --- | --- | --- | --- |
| `Debug` / `Release` | Không | (không) | Build xanh ở bất kỳ máy nào. GPS thật **không** đổi. |
| `Debug-FFI` | Có | `USE_IDEVICE_FFI` | Cần `Vendor/idevice/libidevice_ffi.a`. Chưa có file này. |

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

## 6. Việc chưa làm được

- Chưa có `libidevice_ffi.a` cho `aarch64-apple-ios`. Đây là chốt chặn của tính năng cốt lõi.
- Máy ảo macOS không có `rustup`, `cargo`, `brew`, và không ra được internet.
  Nguyên nhân mạng: máy có hai default route, `en0` đi qua NAT của VMware (`192.168.25.2`)
  đang chết, còn `en1` bridge ra LAN thì **có** internet. macOS đang ưu tiên `en0`.
  Lệnh sửa, cần mật khẩu quản trị nên phải do người dùng chạy:

  ```sh
  sudo networksetup -ordernetworkservices "Bridged LAN" "Ethernet" "Tailscale"
  ```

- Chưa có chữ ký để cài lên máy thật, chưa có AppIcon, chưa có test tự động.
