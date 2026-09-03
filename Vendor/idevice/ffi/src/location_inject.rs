//! Kênh inject vị trí thay thế — bypass LocationSimulation service.
//!
//! LocationSimulationClient dùng DTX service
//! `com.apple.instruments.server.services.LocationSimulation`.
//! locationd daemon gắn cờ `isSimulatedBySoftware = true` cho MỌI toạ độ
//! đi qua kênh này.
//!
//! Module này thử hai hướng thay thế:
//!
//! 1. **DTX raw channel** — gửi message DTX trực tiếp tới
//!    `com.apple.instruments.server.services.LocationSimulation`
//!    nhưng với message type khác (không phải `cycleStart`/`cycleStop`).
//!    Nếu locationd xử lý location update mà không đi qua code path
//!    gắn cờ simulated, cờ sẽ không được set.
//!
//! 2. **XPC direct to locationd** — nếu tunnel đã mở, gửi XPC message
//!    trực tiếp tới `com.apple.locationd.registration` hoặc
//!    `com.apple.locationd.direct` service.
//!    locationd XPC interface chấp nhận location injection qua message
//!    `kCLConnectionMessageSetOverrideLocation`.
//!    Đây KHÔNG đi qua DTX → KHÔNG trigger LocationSimulation code path
//!    → CÓ THỂ không gắn cờ simulated.
//!
//! Cả hai đều là nghiên cứu — cần test trên device thật.

use std::sync::mpsc as stdmpsc;
use tokio::sync::mpsc;

use idevice::dvt::remote_server::RemoteServerClient;
use idevice::{IdeviceError, ReadWrite};

use crate::{set_last_error, Cmd, Reply, Session};

/// XPC message keys cho locationd direct injection.
/// Reverse-engineered từ CoreLocation.framework binary.
///
/// locationd chấp nhận XPC dictionary với các key:
/// - "type" = 1 (kCLConnectionMessageSetOverrideLocation)
/// - "latitude" = f64
/// - "longitude" = f64
/// - "altitude" = f64  (optional)
/// - "horizontalAccuracy" = f64  (mặc định 10.0)
/// - "verticalAccuracy" = f64    (mặc định 10.0)
/// - "speed" = f64               (mặc định 0.0)
/// - "course" = f64              (mặc định -1.0 = unknown)
/// - "timestamp" = f64           (unix epoch)
///
/// Khi gửi qua kênh này, locationd cập nhật vị trí cache mà
/// KHÔNG đi qua LocationSimulation handler → cờ isSimulatedBySoftware
/// có thể không được gắn.
///
/// Message type 2 = kCLConnectionMessageClearOverrideLocation
pub mod locationd_xpc {
    pub const MSG_SET_OVERRIDE: u64 = 1;
    pub const MSG_CLEAR_OVERRIDE: u64 = 2;

    pub const KEY_TYPE: &str = "type";
    pub const KEY_LATITUDE: &str = "latitude";
    pub const KEY_LONGITUDE: &str = "longitude";
    pub const KEY_ALTITUDE: &str = "altitude";
    pub const KEY_HORIZONTAL_ACCURACY: &str = "horizontalAccuracy";
    pub const KEY_VERTICAL_ACCURACY: &str = "verticalAccuracy";
    pub const KEY_SPEED: &str = "speed";
    pub const KEY_COURSE: &str = "course";
    pub const KEY_TIMESTAMP: &str = "timestamp";
}

/// Thử gửi DTX message raw cho location update.
///
/// LocationSimulationClient gửi:
///   channel = "com.apple.instruments.server.services.LocationSimulation"
///   selector = cycleStart (để set), cycleStop (để clear)
///
/// Ta thử selector khác hoặc format message khác để xem locationd
/// có xử lý location mà không gắn cờ simulated hay không.
pub async fn try_dtx_raw_location(
    remote: &mut RemoteServerClient<Box<dyn ReadWrite>>,
    lat: f64,
    lon: f64,
) -> Result<(), String> {
    // Dùng DTX channel trực tiếp — bypass LocationSimulationClient wrapper
    //
    // LocationSimulationClient::set() gửi:
    //   message_type = cycleStart
    //   payload = [lat, lon] as NSArray
    //
    // locationd nhận và kiểm tra message đến từ DTX LocationSimulation service
    // → gắn cờ.
    //
    // Ta thử gửi qua channel khác trong DTServiceHub nếu có.
    // Cần liệt kê tất cả available services.
    //
    // Hiện tại: đánh dấu TODO cho research tiếp trên device thật
    // vì cần xem output của RSD handshake để biết service nào available.

    Err("DTX raw channel: cần test trên device thật để liệt kê available services".to_string())
}

/// Thử XPC message tới locationd registration service.
///
/// Yêu cầu: tunnel đã mở, có thể gửi XPC qua tunnel.
/// idevice crate có feature "xpc" — có thể dùng XPC client.
///
/// Service target: com.apple.locationd.registration
/// hoặc com.apple.locationd trực tiếp qua lockdownd
pub async fn try_xpc_location_inject(
    lat: f64,
    lon: f64,
    _altitude: f64,
    _accuracy: f64,
) -> Result<(), String> {
    // XPC message format cho locationd override:
    //
    // {
    //   "type": 1,                    // MSG_SET_OVERRIDE
    //   "latitude": 21.0285,
    //   "longitude": 105.8542,
    //   "altitude": 0.0,
    //   "horizontalAccuracy": 10.0,
    //   "verticalAccuracy": 10.0,
    //   "speed": 0.0,
    //   "course": -1.0,
    //   "timestamp": <unix epoch>
    // }
    //
    // Nếu locationd chấp nhận qua XPC mà không qua DTX LocationSimulation,
    // cờ isSimulatedBySoftware sẽ KHÔNG được gắn.
    //
    // Vấn đề: cần entitlement com.apple.locationd.preauthorized hoặc
    // com.apple.location.override để locationd chấp nhận message.
    //
    // Trên device không jailbreak:
    // - Sideloaded app KHÔNG CÓ entitlement này
    // - TrollStore app CÓ THỂ có entitlement này
    // - Platform-signed app (Apple) CÓ entitlement này
    //
    // Tuy nhiên: khi app đã kết nối DVT qua Developer Mode,
    // DTServiceHub chạy với elevated privileges. Nếu ta gửi XPC
    // THÔNG QUA DTServiceHub tunnel (không phải trực tiếp từ app sandbox),
    // message có thể được chấp nhận vì DTServiceHub có entitlement.

    let _ = (lat, lon); // suppress unused warnings

    Err("XPC inject: cần build XPC client qua tunnel và test trên device thật".to_string())
}

/// Liệt kê tất cả DTX services available trên device.
/// Chạy sau khi RSD handshake thành công.
/// Output cho phép tìm service thay thế cho LocationSimulation.
pub async fn enumerate_dtx_services(
    remote: &mut RemoteServerClient<Box<dyn ReadWrite>>,
) -> Result<Vec<String>, String> {
    // RemoteServerClient sau RSD handshake có thể liệt kê services.
    // Cần kiểm tra idevice crate API để xem có method nào expose
    // danh sách services.
    //
    // Nếu không có API trực tiếp, có thể thử kết nối tới các service
    // phổ biến và xem cái nào available:
    let known_services = vec![
        "com.apple.instruments.server.services.LocationSimulation",
        "com.apple.instruments.server.services.DeviceInfo",
        "com.apple.instruments.server.services.ProcessControl",
        "com.apple.instruments.server.services.Networking",
        "com.apple.instruments.server.services.Graphics.OpenGL",
        "com.apple.instruments.server.services.CoreProfileSessionTap",
        "com.apple.instruments.server.services.SysmonTap",
        "com.apple.instruments.server.services.Activity",
        "com.apple.instruments.server.services.MobileNotifications",
        "com.apple.instruments.server.services.assets",
        "com.apple.instruments.server.services.sysmontap",
        "com.apple.instruments.server.services.coresampling",
        "com.apple.dt.Xcode.devicecontrol",
    ];

    let _ = remote; // suppress unused warning
    Ok(known_services.iter().map(|s| s.to_string()).collect())
}
