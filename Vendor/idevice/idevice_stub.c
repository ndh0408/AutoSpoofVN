// Thư viện FFI GIẢ dùng cho phát triển.
//
// Mục đích duy nhất: cho phép biên dịch và link config `Debug-FFI` khi CHƯA có
// libidevice_ffi.a thật. Nếu không có nó, toàn bộ code nằm sau `#if USE_IDEVICE_FFI`
// không bao giờ được compiler kiểm tra, và lỗi cú pháp trong nhánh đó sẽ ẩn mình
// cho tới tận ngày có thư viện thật.
//
// Nó KHÔNG thay đổi GPS. Mọi hàm chỉ trả về thành công.
//
// Build (trên macOS):
//   xcrun --sdk iphoneos clang -target arm64-apple-ios17.4 -c idevice_stub.c -o idevice_stub.o
//   xcrun ar rcs libidevice_ffi.a idevice_stub.o
//
// libidevice_ffi.a bị .gitignore loại trừ — sinh lại tại chỗ khi cần.

#include <stdint.h>
#include <stdbool.h>

typedef void* IdeviceHandle;

static int autospoof_stub_session;

IdeviceHandle idevice_connect_dvt(const char* host, uint16_t port, const char* pairing_plist) {
    (void)host;
    (void)port;
    (void)pairing_plist;
    return (IdeviceHandle)&autospoof_stub_session;
}

bool idevice_set_location(IdeviceHandle handle, double latitude, double longitude) {
    (void)handle;
    (void)latitude;
    (void)longitude;
    return true;
}

bool idevice_clear_location(IdeviceHandle handle) {
    (void)handle;
    return true;
}

void idevice_disconnect(IdeviceHandle handle) {
    (void)handle;
}
