use std::ffi::{c_char, c_void, CStr, CString};
use std::net::{IpAddr, SocketAddr};
use std::os::raw::c_int;
use std::path::{Path, PathBuf};
use std::ptr;
use std::sync::mpsc as stdmpsc;
use std::time::Duration;

use idevice::provider::RsdProvider;
use idevice::remote_pairing::{
    connect_tls_psk_tunnel_native, PairableHost, PairableHostInfo, RemotePairingClient,
    RpPairingFile, RpPairingSocket,
};
use tokio::net::{TcpListener, TcpStream};
use tokio::sync::mpsc;
use tokio::time::timeout;

use super::{clear_last_error, serve_location_session, set_last_error, Cmd, Session};

pub type PairingReadyCallback = Option<
    extern "C" fn(
        context: *mut c_void,
        service_id: *const c_char,
        port: u16,
        txt_keys: *const *const c_char,
        txt_values: *const *const c_char,
        txt_count: usize,
    ),
>;
pub type PairingPinCallback =
    Option<extern "C" fn(pin: *const c_char, context: *mut c_void)>;

#[repr(C)]
pub struct IdevicePairingResult {
    pub error: *mut c_char,
    pub device_name: *mut c_char,
    pub device_model: *mut c_char,
    pub device_udid: *mut c_char,
    pub pairing_file_path: *mut c_char,
}

impl IdevicePairingResult {
    fn empty() -> Self {
        Self {
            error: ptr::null_mut(),
            device_name: ptr::null_mut(),
            device_model: ptr::null_mut(),
            device_udid: ptr::null_mut(),
            pairing_file_path: ptr::null_mut(),
        }
    }
}

#[derive(Clone, Copy)]
struct PairingCallbacks {
    ready: PairingReadyCallback,
    pin: PairingPinCallback,
    context: *mut c_void,
}

unsafe impl Send for PairingCallbacks {}

struct PairedDevice {
    name: String,
    model: String,
    udid: String,
    path: String,
}

fn owned_c_string(value: impl Into<Vec<u8>>) -> *mut c_char {
    CString::new(value).unwrap_or_default().into_raw()
}

unsafe fn required_string(pointer: *const c_char, label: &str) -> Result<String, String> {
    if pointer.is_null() {
        return Err(format!("thiếu {label}"));
    }
    unsafe { CStr::from_ptr(pointer) }
        .to_str()
        .map(|value| value.to_string())
        .map_err(|_| format!("{label} không phải UTF-8 hợp lệ"))
}

fn sidecar_path(pairing_path: &Path) -> PathBuf {
    let mut value = pairing_path.as_os_str().to_os_string();
    value.push(".altirk");
    PathBuf::from(value)
}

fn load_pairing_identity(path: &Path, host_name: &str) -> RpPairingFile {
    std::fs::read(path)
        .ok()
        .and_then(|bytes| RpPairingFile::from_bytes(&bytes).ok())
        .unwrap_or_else(|| RpPairingFile::generate(host_name))
}

fn load_host_info(path: &Path, host_name: &str, model: &str) -> PairableHostInfo {
    let mut info = PairableHostInfo::generate(host_name, model);
    if let Ok(bytes) = std::fs::read(sidecar_path(path)) {
        if let Ok(alt_irk) = <[u8; 16]>::try_from(bytes.as_slice()) {
            info.alt_irk = alt_irk;
        }
    }
    info
}

fn emit_ready(
    callbacks: PairingCallbacks,
    service_id: &str,
    port: u16,
    host_info: &PairableHostInfo,
) {
    let Some(callback) = callbacks.ready else { return };
    let records = host_info.mdns_txt_records(service_id);
    let keys: Vec<CString> = records
        .iter()
        .map(|(key, _)| CString::new(key.as_str()).unwrap_or_default())
        .collect();
    let values: Vec<CString> = records
        .iter()
        .map(|(_, value)| CString::new(value.as_str()).unwrap_or_default())
        .collect();
    let key_pointers: Vec<*const c_char> = keys.iter().map(|value| value.as_ptr()).collect();
    let value_pointers: Vec<*const c_char> =
        values.iter().map(|value| value.as_ptr()).collect();
    let Ok(service_id) = CString::new(service_id) else {
        return;
    };

    callback(
        callbacks.context,
        service_id.as_ptr(),
        port,
        key_pointers.as_ptr(),
        value_pointers.as_ptr(),
        records.len(),
    );
}

async fn pair_host_task(
    bind_address: String,
    host_name: String,
    model: String,
    output_path: String,
    timeout_seconds: u32,
    callbacks: PairingCallbacks,
) -> Result<PairedDevice, String> {
    let bind_ip: IpAddr = bind_address
        .parse()
        .map_err(|error| format!("địa chỉ listener không hợp lệ: {error}"))?;
    let listener = TcpListener::bind(SocketAddr::new(bind_ip, 0))
        .await
        .map_err(|error| format!("không mở được listener pairing: {error}"))?;
    let port = listener
        .local_addr()
        .map_err(|error| format!("không đọc được cổng pairing: {error}"))?
        .port();

    let pairing_path = PathBuf::from(&output_path);
    if let Some(parent) = pairing_path.parent() {
        std::fs::create_dir_all(parent)
            .map_err(|error| format!("không tạo được thư mục pairing: {error}"))?;
    }

    let mut pairing_file = load_pairing_identity(&pairing_path, &host_name);
    let host_info = load_host_info(&pairing_path, &host_name, &model);
    let host_alt_irk = host_info.alt_irk;
    let service_id = pairing_file.identifier.clone();
    emit_ready(callbacks, &service_id, port, &host_info);

    let wait = Duration::from_secs(u64::from(timeout_seconds.clamp(30, 600)));
    let (stream, _) = timeout(wait, listener.accept())
        .await
        .map_err(|_| "hết thời gian chờ iPhone bắt đầu ghép nối".to_string())?
        .map_err(|error| format!("nhận kết nối pairing thất bại: {error}"))?;

    let mut host = PairableHost::new(RpPairingSocket::new_device(stream), host_info);
    let peer = timeout(
        wait,
        host.accept(&mut pairing_file, move |pin| async move {
            if let Some(callback) = callbacks.pin {
                if let Ok(pin) = CString::new(pin) {
                    callback(pin.as_ptr(), callbacks.context);
                }
            }
        }),
    )
    .await
    .map_err(|_| "hết thời gian chờ nhập mã pairing".to_string())?
    .map_err(|error| format!("ghép nối trên thiết bị thất bại: {error}"))?;

    std::fs::write(&pairing_path, pairing_file.to_bytes())
        .map_err(|error| format!("không lưu được RPPairing: {error}"))?;
    std::fs::write(sidecar_path(&pairing_path), host_alt_irk)
        .map_err(|error| format!("không lưu được định danh pairing: {error}"))?;

    Ok(PairedDevice {
        name: peer.name,
        model: peer.model,
        udid: peer.remotepairing_udid,
        path: output_path,
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn idevice_pairing_host_run(
    bind_address: *const c_char,
    host_name: *const c_char,
    model: *const c_char,
    output_path: *const c_char,
    timeout_seconds: u32,
    ready_callback: PairingReadyCallback,
    pin_callback: PairingPinCallback,
    context: *mut c_void,
    output: *mut IdevicePairingResult,
) -> c_int {
    clear_last_error();
    if output.is_null() {
        set_last_error("thiếu vùng nhận kết quả pairing");
        return 2;
    }
    unsafe { *output = IdevicePairingResult::empty() };

    let arguments = (|| unsafe {
        Ok::<_, String>((
            required_string(bind_address, "địa chỉ listener")?,
            required_string(host_name, "tên host")?,
            required_string(model, "model host")?,
            required_string(output_path, "đường dẫn pairing")?,
        ))
    })();
    let (bind_address, host_name, model, output_path) = match arguments {
        Ok(values) => values,
        Err(error) => {
            unsafe { (*output).error = owned_c_string(error.clone()) };
            set_last_error(error);
            return 2;
        }
    };

    let callbacks = PairingCallbacks {
        ready: ready_callback,
        pin: pin_callback,
        context,
    };
    let runtime = match tokio::runtime::Builder::new_multi_thread()
        .worker_threads(2)
        .enable_all()
        .build()
    {
        Ok(runtime) => runtime,
        Err(error) => {
            let message = format!("không tạo được runtime pairing: {error}");
            unsafe { (*output).error = owned_c_string(message.clone()) };
            set_last_error(message);
            return 1;
        }
    };

    match runtime.block_on(pair_host_task(
        bind_address,
        host_name,
        model,
        output_path,
        timeout_seconds,
        callbacks,
    )) {
        Ok(device) => {
            unsafe {
                (*output).device_name = owned_c_string(device.name);
                (*output).device_model = owned_c_string(device.model);
                (*output).device_udid = owned_c_string(device.udid);
                (*output).pairing_file_path = owned_c_string(device.path);
            }
            0
        }
        Err(error) => {
            unsafe { (*output).error = owned_c_string(error.clone()) };
            set_last_error(error);
            1
        }
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn idevice_pairing_result_free(result: *mut IdevicePairingResult) {
    if result.is_null() {
        return;
    }
    for pointer in unsafe {
        [
            (*result).error,
            (*result).device_name,
            (*result).device_model,
            (*result).device_udid,
            (*result).pairing_file_path,
        ]
    } {
        if !pointer.is_null() {
            drop(unsafe { CString::from_raw(pointer) });
        }
    }
    unsafe { *result = IdevicePairingResult::empty() };
}

async fn remote_session_task(
    host: String,
    pairing_port: u16,
    pairing: Vec<u8>,
    pin: String,
    ready: stdmpsc::Sender<Result<(), String>>,
    rx: mpsc::Receiver<Cmd>,
) {
    macro_rules! bail {
        ($message:expr) => {{
            let _ = ready.send(Err($message));
            return;
        }};
    }

    let address: IpAddr = match host.parse() {
        Ok(address) => address,
        Err(error) => bail!(format!("địa chỉ RPPairing không hợp lệ: {error}")),
    };
    let mut pairing_file = match RpPairingFile::from_bytes(&pairing) {
        Ok(file) => file,
        Err(error) => bail!(format!("RPPairing đã lưu không đọc được: {error}")),
    };

    let pairing_stream = match timeout(
        Duration::from_secs(12),
        TcpStream::connect(SocketAddr::new(address, pairing_port)),
    )
    .await
    {
        Ok(Ok(stream)) => stream,
        Ok(Err(error)) => bail!(format!(
            "không nối được RPPairing {host}:{pairing_port}: {error}. Hãy bật LocalDevVPN."
        )),
        Err(_) => bail!(format!(
            "RPPairing {host}:{pairing_port} không phản hồi. Hãy bật LocalDevVPN."
        )),
    };

    let mut client =
        RemotePairingClient::new(RpPairingSocket::new(pairing_stream), "AutoSpoofVN");
    if let Err(error) = client
        .connect(&mut pairing_file, || async { pin.clone() })
        .await
    {
        bail!(format!("xác thực RPPairing thất bại: {error}"));
    }

    let encryption_key = client.encryption_key().to_vec();
    let tunnel_port = match client.create_tcp_listener().await {
        Ok(port) => port,
        Err(error) => bail!(format!("không tạo được tunnel RPPairing: {error}")),
    };
    drop(client);

    let tunnel_stream = match timeout(
        Duration::from_secs(12),
        TcpStream::connect(SocketAddr::new(address, tunnel_port)),
    )
    .await
    {
        Ok(Ok(stream)) => stream,
        Ok(Err(error)) => bail!(format!("không nối được cổng tunnel {tunnel_port}: {error}")),
        Err(_) => bail!(format!("cổng tunnel {tunnel_port} không phản hồi")),
    };
    let tunnel = match connect_tls_psk_tunnel_native(tunnel_stream, &encryption_key).await {
        Ok(tunnel) => tunnel,
        Err(error) => bail!(format!("bắt tay TLS-PSK tunnel thất bại: {error}")),
    };

    let client_ip = match tunnel.info.client_address.parse::<IpAddr>() {
        Ok(address) => address,
        Err(error) => bail!(format!("địa chỉ client tunnel không hợp lệ: {error}")),
    };
    let server_ip = match tunnel.info.server_address.parse::<IpAddr>() {
        Ok(address) => address,
        Err(error) => bail!(format!("địa chỉ server tunnel không hợp lệ: {error}")),
    };
    let rsd_port = tunnel.info.server_rsd_port;
    let mtu = tunnel.info.mtu as usize;
    let stream = tunnel.into_inner();
    let mut adapter = idevice::tcp::adapter::Adapter::new(Box::new(stream), client_ip, server_ip);
    adapter.set_mss(mtu.saturating_sub(60));
    let handle = adapter.to_async_handle();
    serve_location_session(handle, rsd_port, ready, rx).await;
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn idevice_connect_dvt_remote(
    host: *const c_char,
    pairing_port: u16,
    pairing_data: *const u8,
    pairing_len: usize,
    pin: *const c_char,
) -> *mut Session {
    clear_last_error();
    if host.is_null() || pairing_data.is_null() || pairing_len == 0 {
        set_last_error("tham số RPPairing không hợp lệ");
        return ptr::null_mut();
    }

    let host = match unsafe { required_string(host, "host RPPairing") } {
        Ok(host) => host,
        Err(error) => {
            set_last_error(error);
            return ptr::null_mut();
        }
    };
    let pin = if pin.is_null() {
        "000000".to_string()
    } else {
        unsafe { CStr::from_ptr(pin) }
            .to_str()
            .unwrap_or("000000")
            .to_string()
    };
    let pairing = unsafe { std::slice::from_raw_parts(pairing_data, pairing_len) }.to_vec();

    let (command_sender, command_receiver) = mpsc::channel::<Cmd>(8);
    let (ready_sender, ready_receiver) = stdmpsc::channel::<Result<(), String>>();
    let runtime_error_sender = ready_sender.clone();

    let thread = match std::thread::Builder::new()
        .name("autospoof-rppairing-dvt".to_string())
        .spawn(move || {
            let runtime = match tokio::runtime::Builder::new_multi_thread()
                .worker_threads(2)
                .enable_all()
                .build()
            {
                Ok(runtime) => runtime,
                Err(error) => {
                    let _ = runtime_error_sender
                        .send(Err(format!("không tạo được runtime RPPairing: {error}")));
                    return;
                }
            };
            runtime.block_on(remote_session_task(
                host,
                pairing_port,
                pairing,
                pin,
                ready_sender,
                command_receiver,
            ));
        })
    {
        Ok(thread) => thread,
        Err(error) => {
            set_last_error(format!("không tạo được thread RPPairing: {error}"));
            return ptr::null_mut();
        }
    };

    match ready_receiver.recv() {
        Ok(Ok(())) => Box::into_raw(Box::new(Session {
            tx: Some(command_sender),
            thread: Some(thread),
        })),
        Ok(Err(error)) => {
            set_last_error(error);
            let _ = thread.join();
            ptr::null_mut()
        }
        Err(_) => {
            set_last_error("phiên RPPairing kết thúc trước khi kết nối DVT xong");
            let _ = thread.join();
            ptr::null_mut()
        }
    }
}
