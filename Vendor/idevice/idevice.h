#ifndef IDEVICE_H
#define IDEVICE_H

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef void* IdeviceHandle;

/// Khởi tạo kết nối DVT Location Simulation qua loopback (LocalDevVPN 10.7.0.1)
IdeviceHandle idevice_connect_dvt(const char* host, uint16_t port, const char* pairing_plist);

/// Thiết lập toạ độ GPS giả lập
bool idevice_set_location(IdeviceHandle handle, double latitude, double longitude);

/// Dừng giả lập và khôi phục GPS thật
bool idevice_clear_location(IdeviceHandle handle);

/// Đóng kết nối
void idevice_disconnect(IdeviceHandle handle);

#ifdef __cplusplus
}
#endif

#endif // IDEVICE_H
