# AutoSpoofVN — Proxy Location Module

Module MITM cho Shadowrocket/Surge/Loon — thay đổi WiFi positioning response từ Apple, bypass `isSimulatedBySoftware`.

## Cách hoạt động

```
iPhone scan WiFi → gửi BSSID list tới gs-loc.apple.com
                                    ↓
                    Shadowrocket chặn response
                                    ↓
                    Script thay toạ độ trong response
                                    ↓
                    iPhone nghĩ mình ở toạ độ giả
                                    ↓
                    isSimulatedBySoftware = false ✓
                                    ↓
                    Bump nhận bình thường ✓
```

## Cài đặt Shadowrocket

### 1. Import module

Shadowrocket → Config → Modules → Add Module → nhập URL:

```
https://raw.githubusercontent.com/ndh0408/AutoSpoofVN/main/Proxy/autospoof-location.sgmodule
```

### 2. Bật MITM

Shadowrocket → Settings → HTTPS Decryption → bật → Generate Certificate → Install → Trust

Trên iPhone:
```
Settings → General → About → Certificate Trust Settings → bật CA của Shadowrocket
```

### 3. Đổi toạ độ

Sửa tham số trong module:

```
latitude=21.0285        ← Hoàn Kiếm, Hà Nội
longitude=105.8542
horizontalAccuracy=39   ← mét
```

Ví dụ toạ độ:

| Địa điểm | Latitude | Longitude |
|-----------|----------|-----------|
| Hoàn Kiếm, Hà Nội | 21.0285 | 105.8542 |
| Bitexco, HCM | 10.7717 | 106.7048 |
| Đà Nẵng | 16.0544 | 108.2022 |
| Tokyo Tower | 35.6586 | 139.7454 |
| Eiffel Tower | 48.8584 | 2.2945 |
| Times Square, NYC | 40.7580 | -73.9855 |

### 4. Buộc iOS dùng WiFi positioning

Quan trọng — nếu GPS hardware lock mạnh (ngoài trời), iOS sẽ ưu tiên GPS thật thay vì WiFi positioning. Để buộc dùng WiFi:

```
1. Bật Airplane Mode
2. Tắt Location Services (Settings → Privacy → Location Services → OFF)
3. Restart iPhone
4. Tắt Airplane Mode
5. Bật WiFi
6. Bật Shadowrocket → Connect VPN
7. Bật Location Services
8. Mở Bump
```

Thứ tự này xoá GPS cache và buộc iOS dùng WiFi positioning qua server → bị MITM → toạ độ giả.

### 5. Verify

M�� Apple Maps hoặc Google Maps — vị trí hiện tại phải là toạ độ giả.

## Hạn chế

| Hạn chế | Chi tiết |
|---------|----------|
| GPS ngoài trời | Nếu GPS hardware lock mạnh, iOS ưu tiên GPS → vị trí thật. Dùng airplane mode trick |
| Cần WiFi | WiFi positioning cần WiFi bật. Không WiFi = không hoạt động |
| MITM cert | Cần trust certificate trong Settings. Cert hết hạn cần generate lại |
| iOS 26/27 | Có thể cần airplane mode trick kỹ hơn — xem section bên dưới |

## iOS 26/27 (nếu trick trên không hoạt động)

```
1. Set toạ độ trong module trước
2. Bật Airplane Mode
3. Tắt Location Services
4. Restart iPhone
5. Tắt Airplane Mode (WiFi TẮT)
6. Bật Shadowrocket VPN (chờ VPN icon xuất hiện)
7. Bật Location Services
8. Bật WiFi
9. Mở Bump
```

## File

| File | Dùng cho |
|------|---------|
| `autospoof-location.sgmodule` | Shadowrocket |
| `autospoof-location.surge.sgmodule` | Surge |
| `location-spoofer.js` | Script MITM (dùng chung) |
