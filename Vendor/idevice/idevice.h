#ifndef IDEVICE_H
#define IDEVICE_H

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/*
 * Cầu nối C tới crate Rust `idevice` (jkcoxson), cho mô phỏng vị trí qua DVT.
 *
 * Bản đầu của file này khai bốn hàm không tồn tại trong crate thật. Đã kiểm chứng
 * bằng cách đọc mã nguồn idevice 0.1.65: API thật là
 * `LocationSimulationClient::new(&mut RemoteServerClient)` cùng `.set()` / `.clear()`,
 * và phải đi qua năm chặng chứ không phải một lời gọi:
 *
 *     lockdownd 62078  ->  CoreDeviceProxy (CDTunnel)
 *                      ->  software tunnel (jktcp)
 *                      ->  RemoteServiceDiscovery
 *                      ->  com.apple.instruments.dtservicehub
 *                      ->  kênh DTX LocationSimulation
 *
 * Bốn hàm dưới đây gói trọn chuỗi đó. Phần cài đặt ở `idevice_ffi` (Rust, staticlib);
 * `idevice_stub.c` là bản giả để biên dịch và link được khi chưa có thư viện thật.
 *
 * Toạ độ mô phỏng chỉ tồn tại chừng nào phiên còn mở. Gọi idevice_disconnect() là
 * thiết bị tự trả lại GPS thật.
 *
 * ABI version 3.
 */

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

/**
 * Chạy listener RPPairing trên chính iPhone. Swift quảng bá thông tin được trả
 * qua ready_callback bằng NetService; người dùng chọn "Pair with AutoSpoofVN"
 * trong Developer Mode và nhập PIN từ pin_callback.
 */
int32_t idevice_pairing_host_run(const char* bind_address,
                                 const char* host_name,
                                 const char* model,
                                 const char* output_path,
                                 uint32_t timeout_seconds,
                                 IdevicePairingReadyCallback ready_callback,
                                 IdevicePairingPinCallback pin_callback,
                                 void* context,
                                 IdevicePairingResult* output);

/** Giải phóng các chuỗi trong IdevicePairingResult. */
void idevice_pairing_result_free(IdevicePairingResult* result);

/**
 * Mở phiên mô phỏng vị trí.
 *
 * @param host          Địa chỉ thiết bị qua VPN loopback, thường là "10.7.0.1".
 * @param port          Cổng lockdownd, thường là 62078.
 * @param pairing_data  Nội dung NHỊ PHÂN của lockdown pairing record.
 *                      Đừng truyền chuỗi C: pairing file là binary plist và sẽ bị
 *                      cắt cụt ở byte 0 đầu tiên.
 * @param pairing_len   Số byte của pairing_data.
 *
 * @return Handle phiên, hoặc NULL nếu thất bại. Khi NULL, gọi idevice_last_error()
 *         để lấy lý do cụ thể.
 */
IdeviceHandle idevice_connect_dvt(const char* host,
                                  uint16_t port,
                                  const uint8_t* pairing_data,
                                  size_t pairing_len);

/**
 * Mở phiên DVT qua RPPairing iOS 27, không cần lockdown pairing record từ máy tính.
 * Cổng mặc định của LocalDevVPN là 49152; PIN chỉ dùng nếu thiết bị yêu cầu pair lại.
 */
IdeviceHandle idevice_connect_dvt_remote(const char* host,
                                         uint16_t pairing_port,
                                         const uint8_t* pairing_data,
                                         size_t pairing_len,
                                         const char* pin);

/** Đặt toạ độ mô phỏng. Trả về false nếu thất bại; xem idevice_last_error(). */
bool idevice_set_location(IdeviceHandle handle, double latitude, double longitude);

/** Xoá mô phỏng, trả thiết bị về GPS thật. */
bool idevice_clear_location(IdeviceHandle handle);

/** Đóng phiên và giải phóng handle. An toàn khi gọi với NULL. Chỉ gọi một lần. */
void idevice_disconnect(IdeviceHandle handle);

/**
 * Mô tả lỗi gần nhất, hoặc NULL nếu chưa có lỗi.
 *
 * Con trỏ chỉ hợp lệ tới lần gọi FFI kế tiếp — phía gọi phải sao chép ngay.
 */
const char* idevice_last_error(void);

/** Phiên bản ABI của thư viện đang link. Hiện là 3. */
int idevice_ffi_abi_version(void);

#ifdef __cplusplus
}
#endif

#endif // IDEVICE_H
