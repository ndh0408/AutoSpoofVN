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
// libidevice_ffi.a bị .gitignore loại trừ — sinh lại tại chỗ khi cần, và nhớ xoá
// bản giả trước khi đặt thư viện thật vào.

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

typedef void* IdeviceHandle;

typedef void (*IdevicePairingReadyCallback)(void* context,
                                            const char* service_id,
                                            uint16_t port,
                                            const char* const* txt_keys,
                                            const char* const* txt_values,
                                            size_t txt_count);
typedef void (*IdevicePairingPinCallback)(const char* pin, void* context);

typedef struct {
    char* error;
    char* device_name;
    char* device_model;
    char* device_udid;
    char* pairing_file_path;
} IdevicePairingResult;

static int autospoof_stub_session;
static const char* autospoof_stub_error = NULL;

int32_t idevice_pairing_host_run(const char* bind_address,
                                 const char* host_name,
                                 const char* model,
                                 const char* output_path,
                                 uint32_t timeout_seconds,
                                 IdevicePairingReadyCallback ready_callback,
                                 IdevicePairingPinCallback pin_callback,
                                 void* context,
                                 IdevicePairingResult* output) {
    (void)bind_address;
    (void)host_name;
    (void)model;
    (void)output_path;
    (void)timeout_seconds;
    (void)ready_callback;
    (void)pin_callback;
    (void)context;
    if (output != NULL) {
        output->error = NULL;
        output->device_name = NULL;
        output->device_model = NULL;
        output->device_udid = NULL;
        output->pairing_file_path = NULL;
    }
    autospoof_stub_error = "stub: self-pairing khong chay that";
    return 1;
}

void idevice_pairing_result_free(IdevicePairingResult* result) {
    if (result == NULL) {
        return;
    }
    result->error = NULL;
    result->device_name = NULL;
    result->device_model = NULL;
    result->device_udid = NULL;
    result->pairing_file_path = NULL;
}

IdeviceHandle idevice_connect_dvt(const char* host,
                                  uint16_t port,
                                  const uint8_t* pairing_data,
                                  size_t pairing_len) {
    (void)host;
    (void)port;
    if (pairing_data == NULL || pairing_len == 0) {
        autospoof_stub_error = "stub: thieu pairing data";
        return NULL;
    }
    autospoof_stub_error = NULL;
    return (IdeviceHandle)&autospoof_stub_session;
}

IdeviceHandle idevice_connect_dvt_remote(const char* host,
                                         uint16_t pairing_port,
                                         const uint8_t* pairing_data,
                                         size_t pairing_len,
                                         const char* pin) {
    (void)host;
    (void)pairing_port;
    (void)pin;
    if (pairing_data == NULL || pairing_len == 0) {
        autospoof_stub_error = "stub: thieu RPPairing data";
        return NULL;
    }
    autospoof_stub_error = NULL;
    return (IdeviceHandle)&autospoof_stub_session;
}

bool idevice_set_location(IdeviceHandle handle, double latitude, double longitude) {
    (void)latitude;
    (void)longitude;
    if (handle == NULL) {
        autospoof_stub_error = "stub: handle rong";
        return false;
    }
    return true;
}

bool idevice_clear_location(IdeviceHandle handle) {
    if (handle == NULL) {
        autospoof_stub_error = "stub: handle rong";
        return false;
    }
    return true;
}

void idevice_disconnect(IdeviceHandle handle) {
    (void)handle;
}

const char* idevice_last_error(void) {
    return autospoof_stub_error;
}

int idevice_ffi_abi_version(void) {
    return 3;
}
