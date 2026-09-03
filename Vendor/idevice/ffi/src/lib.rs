//! Cầu nối C cho AutoSpoofVN: mô phỏng vị trí qua DVT trên iOS 17+.
//!
//! Chuỗi kết nối thật (không phải một lời gọi duy nhất như header cũ giả định):
//!
//! ```text
//! TcpProvider(10.7.0.1:62078, pairing file)
//!   -> CoreDeviceProxy                (lockdownd StartService, CDTunnel handshake)
//!   -> create_software_tunnel()       (jktcp, mang gói IPv6)
//!   -> AdapterHandle                  (đóng vai RsdProvider)
//!   -> RsdHandshake                   (trên server_rsd_port lấy từ tunnel info)
//!   -> RemoteServerClient             (service com.apple.instruments.dtservicehub)
//!   -> LocationSimulationClient       (kênh DTX, set/clear toạ độ)
//! ```
//!
//! Toạ độ mô phỏng chỉ tồn tại chừng nào kênh DTX còn mở, nên toàn bộ chuỗi trên phải
//! được giữ sống suốt phiên. Vì `LocationSimulationClient` mượn `RemoteServerClient`,
//! không thể gói cả hai vào một struct trả cho C.
//!
//! Cách giải: mỗi phiên chạy trong một thread riêng với runtime tokio của nó, và toàn
//! bộ chuỗi nằm trên stack của `block_on`. Dùng `block_on` chứ không `spawn` là có lý do:
//! `Runtime::spawn` đòi future phải `'static` theo nghĩa higher-ranked, mà
//! `RsdService` chỉ được cài cho `RemoteServerClient<Box<dyn ReadWrite + 'static>>`
//! nên trình biên dịch từ chối với "implementation of RsdService is not general enough".
//!
//! Phía C điều khiển qua kênh lệnh; phản hồi đi bằng `std::sync::mpsc` để bên gọi
//! không cần runtime tokio nào.

use std::ffi::{CStr, CString};
use std::os::raw::{c_char, c_int};
use std::sync::Mutex;
use std::sync::mpsc as stdmpsc;

use idevice::IdeviceService;
use idevice::dvt::location_simulation::LocationSimulationClient;
use idevice::dvt::remote_server::RemoteServerClient;
use idevice::pairing_file::PairingFile;
use idevice::provider::{RsdProvider, TcpProvider};
use idevice::services::core_device_proxy::CoreDeviceProxy;
use idevice::services::rsd::RsdHandshake;
use idevice::{IdeviceError, ReadWrite};

use tokio::sync::mpsc;

// ---------------------------------------------------------------- lỗi gần nhất

static LAST_ERROR: Mutex<Option<CString>> = Mutex::new(None);

fn set_last_error(msg: impl Into<String>) {
    if let Ok(mut slot) = LAST_ERROR.lock() {
        *slot = CString::new(msg.into()).ok();
    }
}

fn clear_last_error() {
    if let Ok(mut slot) = LAST_ERROR.lock() {
        *slot = None;
    }
}

/// Trả về mô tả lỗi gần nhất, hoặc NULL nếu chưa có lỗi.
///
/// Con trỏ chỉ hợp lệ tới lần gọi FFI tiếp theo — phía Swift phải sao chép ngay.
#[unsafe(no_mangle)]
pub extern "C" fn idevice_last_error() -> *const c_char {
    match LAST_ERROR.lock() {
        Ok(slot) => slot.as_ref().map_or(std::ptr::null(), |s| s.as_ptr()),
        Err(_) => std::ptr::null(),
    }
}

// ---------------------------------------------------------------- phiên

type Reply = stdmpsc::Sender<Result<(), String>>;

enum Cmd {
    Set(f64, f64, Reply),
    Clear(Reply),
}

pub struct Session {
    tx: Option<mpsc::Sender<Cmd>>,
    thread: Option<std::thread::JoinHandle<()>>,
}

/// Dựng toàn bộ chuỗi kết nối rồi phục vụ lệnh cho tới khi kênh lệnh đóng.
async fn session_task(
    host: String,
    port: u16,
    pairing: Vec<u8>,
    ready: stdmpsc::Sender<Result<(), String>>,
    mut rx: mpsc::Receiver<Cmd>,
) {
    macro_rules! bail {
        ($msg:expr) => {{
            let _ = ready.send(Err($msg));
            return;
        }};
    }

    let addr: std::net::IpAddr = match host.parse() {
        Ok(a) => a,
        Err(e) => bail!(format!("địa chỉ '{host}' không hợp lệ: {e}")),
    };

    let pairing_file = match PairingFile::from_bytes(&pairing) {
        Ok(p) => p,
        Err(e) => bail!(format!(
            "pairing file không đọc được ({e}). Phải là lockdown pairing record \
             (.mobiledevicepairing / .plist), không phải RPPairing."
        )),
    };

    let provider = TcpProvider {
        addr,
        scope_id: None,
        pairing_file,
        label: "AutoSpoofVN".to_string(),
    };

    // Chặng 1-2: lockdownd -> CoreDeviceProxy -> CDTunnel
    let proxy = match CoreDeviceProxy::connect(&provider).await {
        Ok(p) => p,
        Err(e) => bail!(format!(
            "không mở được CoreDeviceProxy tại {host}:{port} ({e}). \
             Kiểm tra VPN loopback đang bật và pairing file còn hiệu lực."
        )),
    };
    let rsd_port = proxy.tunnel_info().server_rsd_port;

    // Chặng 3: ngăn xếp TCP phần mềm chạy trên tunnel
    let adapter = match proxy.create_software_tunnel() {
        Ok(a) => a,
        Err(e) => bail!(format!("không dựng được software tunnel: {e}")),
    };
    let mut handle = adapter.to_async_handle();

    // Chặng 4: bắt tay RemoteServiceDiscovery
    let rsd_stream = match handle.connect_to_service_port(rsd_port).await {
        Ok(s) => s,
        Err(e) => bail!(format!("không nối được tới cổng RSD {rsd_port}: {e}")),
    };
    let mut handshake = match RsdHandshake::new(rsd_stream).await {
        Ok(h) => h,
        Err(e) => bail!(format!("bắt tay RSD thất bại: {e}")),
    };

    // Chặng 5: dtservicehub. Chỉ được quảng bá khi Developer Disk Image đã mount.
    let mut remote: RemoteServerClient<Box<dyn ReadWrite>> =
        match handshake.connect(&mut handle).await {
            Ok(r) => r,
            Err(IdeviceError::ServiceNotFound) => bail!(
                "thiết bị không quảng bá com.apple.instruments.dtservicehub. Thường là do \
                 chưa mount Developer Disk Image, hoặc chưa bật Developer Mode trong \
                 Settings > Privacy & Security. DDI mất sau mỗi lần khởi động lại máy."
                    .to_string()
            ),
            Err(e) => bail!(format!("không mở được dtservicehub: {e}")),
        };

    // Chặng 6: kênh DTX cho mô phỏng vị trí
    let mut loc = match LocationSimulationClient::new(&mut remote).await {
        Ok(l) => l,
        Err(e) => bail!(format!("không mở được kênh LocationSimulation: {e}")),
    };

    let _ = ready.send(Ok(()));

    while let Some(cmd) = rx.recv().await {
        match cmd {
            Cmd::Set(lat, lon, reply) => {
                let r = loc
                    .set(lat, lon)
                    .await
                    .map_err(|e| format!("đặt toạ độ thất bại: {e}"));
                let _ = reply.send(r);
            }
            Cmd::Clear(reply) => {
                let r = loc
                    .clear()
                    .await
                    .map_err(|e| format!("xoá mô phỏng thất bại: {e}"));
                let _ = reply.send(r);
            }
        }
    }
    // Kênh lệnh đóng: rời hàm, mọi tầng được thả, thiết bị tự trả lại GPS thật.
}

// ---------------------------------------------------------------- API C

/// Mở phiên mô phỏng vị trí.
///
/// `pairing_data` là nội dung **nhị phân** của lockdown pairing record; đừng truyền
/// chuỗi C, pairing file thường là binary plist chứa byte 0.
/// Trả về NULL nếu thất bại — gọi [`idevice_last_error`] để lấy lý do.
///
/// # Safety
/// `host` phải là chuỗi C hợp lệ kết thúc bằng NUL. `pairing_data` phải trỏ tới ít nhất
/// `pairing_len` byte đọc được.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn idevice_connect_dvt(
    host: *const c_char,
    port: u16,
    pairing_data: *const u8,
    pairing_len: usize,
) -> *mut Session {
    clear_last_error();

    if host.is_null() || pairing_data.is_null() || pairing_len == 0 {
        set_last_error("tham số không hợp lệ: thiếu host hoặc pairing data");
        return std::ptr::null_mut();
    }

    let host = match unsafe { CStr::from_ptr(host) }.to_str() {
        Ok(h) => h.to_string(),
        Err(_) => {
            set_last_error("host không phải UTF-8 hợp lệ");
            return std::ptr::null_mut();
        }
    };
    let pairing = unsafe { std::slice::from_raw_parts(pairing_data, pairing_len) }.to_vec();

    let (tx, rx) = mpsc::channel::<Cmd>(8);
    let (ready_tx, ready_rx) = stdmpsc::channel::<Result<(), String>>();
    let build_err_tx = ready_tx.clone();

    let thread = match std::thread::Builder::new()
        .name("autospoof-dvt".to_string())
        .spawn(move || {
            let rt = match tokio::runtime::Builder::new_multi_thread()
                .worker_threads(2)
                .enable_all()
                .build()
            {
                Ok(rt) => rt,
                Err(e) => {
                    let _ = build_err_tx.send(Err(format!("không tạo được tokio runtime: {e}")));
                    return;
                }
            };
            rt.block_on(session_task(host, port, pairing, ready_tx, rx));
        }) {
        Ok(t) => t,
        Err(e) => {
            set_last_error(format!("không tạo được thread phiên: {e}"));
            return std::ptr::null_mut();
        }
    };

    match ready_rx.recv() {
        Ok(Ok(())) => Box::into_raw(Box::new(Session {
            tx: Some(tx),
            thread: Some(thread),
        })),
        Ok(Err(msg)) => {
            set_last_error(msg);
            let _ = thread.join();
            std::ptr::null_mut()
        }
        Err(_) => {
            set_last_error("phiên kết thúc trước khi kết nối xong");
            let _ = thread.join();
            std::ptr::null_mut()
        }
    }
}

fn send_and_wait(s: &Session, make: impl FnOnce(Reply) -> Cmd) -> bool {
    let Some(tx) = s.tx.as_ref() else {
        set_last_error("phiên đã đóng");
        return false;
    };
    let (reply_tx, reply_rx) = stdmpsc::channel();
    if tx.blocking_send(make(reply_tx)).is_err() {
        set_last_error("phiên đã đóng");
        return false;
    }
    match reply_rx.recv() {
        Ok(Ok(())) => true,
        Ok(Err(msg)) => {
            set_last_error(msg);
            false
        }
        Err(_) => {
            set_last_error("phiên kết thúc khi đang chờ phản hồi");
            false
        }
    }
}

/// Đặt toạ độ mô phỏng. Trả về false nếu thất bại.
///
/// # Safety
/// `handle` phải do [`idevice_connect_dvt`] trả về và chưa bị ngắt.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn idevice_set_location(
    handle: *mut Session,
    latitude: f64,
    longitude: f64,
) -> bool {
    clear_last_error();
    if handle.is_null() {
        set_last_error("handle rỗng");
        return false;
    }
    send_and_wait(unsafe { &*handle }, |tx| Cmd::Set(latitude, longitude, tx))
}

/// Xoá mô phỏng, trả thiết bị về GPS thật.
///
/// # Safety
/// `handle` phải do [`idevice_connect_dvt`] trả về và chưa bị ngắt.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn idevice_clear_location(handle: *mut Session) -> bool {
    clear_last_error();
    if handle.is_null() {
        set_last_error("handle rỗng");
        return false;
    }
    send_and_wait(unsafe { &*handle }, Cmd::Clear)
}

/// Đóng phiên và giải phóng handle. An toàn khi gọi với NULL.
///
/// # Safety
/// `handle` phải do [`idevice_connect_dvt`] trả về, và chỉ được gọi đúng một lần.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn idevice_disconnect(handle: *mut Session) {
    if handle.is_null() {
        return;
    }
    let mut session = unsafe { Box::from_raw(handle) };
    // Thả kênh lệnh để vòng lặp phiên thoát và gỡ toàn bộ chuỗi kết nối.
    session.tx = None;
    if let Some(t) = session.thread.take() {
        let _ = t.join();
    }
}

/// Phiên bản ABI. Tăng khi chữ ký các hàm trên thay đổi.
#[unsafe(no_mangle)]
pub extern "C" fn idevice_ffi_abi_version() -> c_int {
    2
}
