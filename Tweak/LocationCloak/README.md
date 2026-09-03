# LocationCloak

Tweak strip cờ `isSimulatedBySoftware` khỏi CoreLocation — làm cho GPS mô phỏng qua DVT trông giống GPS thật.

## Vấn đề

Khi AutoSpoofVN (hoặc Xcode) gửi toạ độ giả qua DVT LocationSimulation:

```
locationd daemon → gắn isSimulatedBySoftware = true
                → CLLocationManager trả cho MỌI app toạ độ + cờ đó
                → App kiểm tra cờ → biết GPS giả → từ chối
```

Google Maps không kiểm tra cờ → hiện bình thường.
Bump kiểm tra cờ → từ chối vị trí giả.

## Giải pháp

LocationCloak hook 3 điểm trong CoreLocation:

1. **`CLLocationSourceInformation.isSimulatedBySoftware`** → luôn trả `false`
2. **`CLLocationSourceInformation.isProducedByAccessory`** → luôn trả `false`
3. **`CLLocation.sourceInformation`** → trả `nil` (không có thông tin nguồn = GPS thật)

Kết quả: mọi app — kể cả Bump — thấy toạ độ DVT giống hệt GPS thật.

## Build

```bash
cd Tweak/LocationCloak
./build.sh
```

Output: `LocationCloak.dylib`

## Cài đặt

### TrollStore (không jailbreak)

1. Copy `LocationCloak.dylib` vào `/var/jb/usr/lib/TweakInject/`
2. Tạo `/var/jb/usr/lib/TweakInject/LocationCloak.plist` (đã có sẵn trong repo)
3. Respring

### Jailbreak (Substrate/ElleKit/Dopamine)

1. Copy `LocationCloak.dylib` vào `/Library/MobileSubstrate/DynamicLibraries/`
2. Copy `LocationCloak.plist` cạnh file `.dylib`
3. Respring

### Chỉ target Bump

Sửa `LocationCloak.plist`:

```xml
<key>Bundles</key>
<array>
    <string>com.bfriendsapp.bump</string>
</array>
```

## Verify

Sau khi cài, mở app bất kỳ dùng CLLocationManager:

```
isSimulatedBySoftware = false  ← trước đây là true
sourceInformation = nil         ← trước đây chứa simulated flag
```

Console log khi dylib load:

```
[LocationCloak] Hooked isSimulatedBySoftware → false
[LocationCloak] Hooked isProducedByAccessory → false
[LocationCloak] Hooked CLLocation.sourceInformation → nil
[LocationCloak] Ready. All simulated flags will report as real GPS.
```

## Yêu cầu

- iOS 15+ (CLLocationSourceInformation có từ iOS 15)
- TrollStore HOẶC jailbreak (Substrate/ElleKit/Dopamine)
- AutoSpoofVN đang chạy và gửi GPS qua DVT

## Lưu ý

- Tweak inject vào process của app khác — cần quyền elevated (TrollStore/jailbreak)
- Trên iPhone không TrollStore và không jailbreak: KHÔNG CÓ CÁCH nào strip cờ này vì nó gắn ở tầng daemon hệ thống
- Cờ `isSimulatedBySoftware` là per-CLLocation object, gắn bởi locationd, không phải bởi app
