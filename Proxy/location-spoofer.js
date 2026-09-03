/**
 * AutoSpoofVN — Apple Location Services MITM Script
 * 
 * Chặn response từ gs-loc.apple.com/clls/wloc (WiFi positioning)
 * và thay toạ độ trong response bằng toạ độ giả.
 *
 * Apple WiFi Location Protocol:
 * - Request: danh sách WiFi BSSID (binary protobuf-like)
 * - Response: toạ độ tương ứng cho mỗi BSSID (binary)
 *
 * Response format (big-endian):
 * Offset  Size  Field
 * 0       2     header (0x0001)
 * 2       2     status
 * ...     ...   AP entries
 *
 * Mỗi AP entry:
 * +0      1     AP header (0x01)
 * +1      6     BSSID
 * +7      2     channel
 * +9      4     latitude (int32, ×1e-8 degrees)
 * +13     4     longitude (int32, ×1e-8 degrees)
 * +17     4     horizontalAccuracy (int32, mm)
 * +21     ...   remaining fields
 *
 * Script tìm mọi entry có lat/lon hợp lệ và thay thế.
 */

const SCALE = 1e8; // Apple dùng fixed-point: int32 × 1e-8 = degrees

function getArgs() {
    const raw = typeof $argument !== 'undefined' ? $argument : '';
    const params = {};
    raw.split('&').forEach(pair => {
        const [k, v] = pair.split('=');
        if (k && v) params[k.trim()] = v.trim();
    });
    return {
        latitude: parseFloat(params.latitude || '21.0285'),
        longitude: parseFloat(params.longitude || '105.8542'),
        horizontalAccuracy: parseInt(params.horizontalAccuracy || '39', 10)
    };
}

function run() {
    const args = getArgs();
    const targetLat = Math.round(args.latitude * SCALE);
    const targetLon = Math.round(args.longitude * SCALE);
    const accuracy = args.horizontalAccuracy * 1000; // mm

    const body = $response.body;
    if (!body || body.byteLength < 10) {
        $done({});
        return;
    }

    const data = new Uint8Array(body);
    const view = new DataView(data.buffer);
    let modified = false;
    let offset = 0;

    // Duyệt response tìm AP entries
    // Mỗi entry bắt đầu với byte marker, theo sau là BSSID + coords
    // Chiến lược: tìm mọi cặp int32 liên tiếp mà giá trị nằm trong
    // phạm vi toạ độ hợp lệ (-90e8 ~ +90e8, -180e8 ~ +180e8),
    // và thay thế chúng.

    while (offset + 8 <= data.byteLength) {
        try {
            const val1 = view.getInt32(offset, false); // big-endian
            const val2 = view.getInt32(offset + 4, false);

            const lat = val1 / SCALE;
            const lon = val2 / SCALE;

            // Kiểm tra xem có phải toạ độ hợp lệ không
            if (lat >= -90 && lat <= 90 && lon >= -180 && lon <= 180 &&
                Math.abs(lat) > 0.001 && Math.abs(lon) > 0.001) {
                
                // Thay toạ độ
                view.setInt32(offset, targetLat, false);
                view.setInt32(offset + 4, targetLon, false);

                // Thay accuracy nếu có (thường ở offset +8)
                if (offset + 12 <= data.byteLength) {
                    const accVal = view.getInt32(offset + 8, false);
                    if (accVal > 0 && accVal < 1000000000) {
                        view.setInt32(offset + 8, accuracy, false);
                    }
                }

                modified = true;
                offset += 12; // nhảy qua entry vừa sửa
                continue;
            }
        } catch (e) {
            // ignore parse errors
        }
        offset += 1;
    }

    if (modified) {
        console.log(`[AutoSpoofVN] Rewrote location to ${args.latitude}, ${args.longitude}`);
    }

    $done({ body: data.buffer });
}

run();
