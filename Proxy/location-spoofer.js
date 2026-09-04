/**
 * LocationX — Apple Location Services MITM Script
 *
 * Chặn response từ gs-loc.apple.com/clls/wloc (WiFi positioning) và thay toạ độ
 * trong response bằng toạ độ giả.
 *
 * ---------------------------------------------------------------------------
 * GIAO THỨC
 * ---------------------------------------------------------------------------
 * Response là **protobuf**, không phải mảng struct nhị phân cố định.
 * Message `Location` (theo acheong08/apple-corelocation-experiments):
 *
 *     field 1  latitude             int64 varint, đơn vị 1e-8 độ
 *     field 2  longitude            int64 varint, đơn vị 1e-8 độ
 *     field 3  horizontal_accuracy  int64 varint
 *     field 5  altitude             int64 varint
 *     field 6  vertical_accuracy    int64 varint
 *
 * Bản script trước quét từng cặp int32 big-endian rồi ghi đè TẠI CHỖ. Cách đó sai
 * ở hai điểm không sửa vặt được:
 *
 *   1. Toạ độ là varint 64-bit, không phải int32 big-endian — đọc ra số vô nghĩa.
 *   2. Varint có ĐỘ DÀI THAY ĐỔI (1..10 byte). Ghi đè tại chỗ làm lệch mọi trường
 *      phía sau và làm sai luôn `length` của các message bao ngoài → protobuf hỏng,
 *      CoreLocation vứt cả response.
 *
 * Nên ở đây ta giải mã protobuf thật, sửa trường, rồi **mã hoá lại từ trong ra
 * ngoài** để mọi độ dài được tính lại cho đúng.
 *
 * Không cần biết toàn bộ schema: ta đi đệ quy, message con nào có field 1 và 2 là
 * varint mà quy ra được vĩ độ/kinh độ hợp lệ thì coi là `Location` và thay.
 */

const SCALE = 1e8;

/* ------------------------------------------------------------------ tham số */

function getArgs() {
    const raw = typeof $argument !== 'undefined' && $argument ? String($argument) : '';
    const params = {};
    raw.split('&').forEach(function (pair) {
        const idx = pair.indexOf('=');
        if (idx > 0) params[pair.slice(0, idx).trim()] = pair.slice(idx + 1).trim();
    });
    return {
        latitude: parseFloat(params.latitude || '21.0285'),
        longitude: parseFloat(params.longitude || '105.8542'),
        horizontalAccuracy: parseInt(params.horizontalAccuracy || '39', 10),
    };
}

/* --------------------------------------------------------------- varint I/O */

/** Đọc một varint. Trả về [BigInt, vị trí kế tiếp] hoặc null nếu hỏng. */
function readVarint(bytes, pos) {
    let result = 0n;
    let shift = 0n;
    while (pos < bytes.length) {
        const b = bytes[pos++];
        result |= BigInt(b & 0x7f) << shift;
        if ((b & 0x80) === 0) return [result, pos];
        shift += 7n;
        if (shift > 63n) return null; // varint quá 10 byte -> dữ liệu hỏng
    }
    return null;
}

/** Mã hoá BigInt thành varint. Số âm dùng bù hai 64-bit, đúng như proto3 `int64`. */
function writeVarint(value) {
    let v = BigInt(value);
    if (v < 0n) v += 1n << 64n; // bù hai -> luôn ra đúng 10 byte
    const out = [];
    do {
        let b = Number(v & 0x7fn);
        v >>= 7n;
        if (v > 0n) b |= 0x80;
        out.push(b);
    } while (v > 0n);
    return out;
}

/* ------------------------------------------------------------ parse / build */

/**
 * Tách một message thành danh sách trường.
 * Trả về null nếu byte không phải protobuf hợp lệ — đây cũng là cách ta thử xem
 * một trường length-delimited là message lồng hay chỉ là chuỗi/bytes thường.
 */
function parseMessage(bytes) {
    const fields = [];
    let pos = 0;
    while (pos < bytes.length) {
        const key = readVarint(bytes, pos);
        if (!key) return null;
        const tag = key[0];
        pos = key[1];

        const field = Number(tag >> 3n);
        const wire = Number(tag & 7n);
        if (field === 0) return null;

        if (wire === 0) {
            const v = readVarint(bytes, pos);
            if (!v) return null;
            fields.push({ field: field, wire: 0, value: v[0] });
            pos = v[1];
        } else if (wire === 1) {
            if (pos + 8 > bytes.length) return null;
            fields.push({ field: field, wire: 1, raw: bytes.slice(pos, pos + 8) });
            pos += 8;
        } else if (wire === 2) {
            const len = readVarint(bytes, pos);
            if (!len) return null;
            const n = Number(len[0]);
            pos = len[1];
            if (n < 0 || pos + n > bytes.length) return null;
            fields.push({ field: field, wire: 2, raw: bytes.slice(pos, pos + n) });
            pos += n;
        } else if (wire === 5) {
            if (pos + 4 > bytes.length) return null;
            fields.push({ field: field, wire: 5, raw: bytes.slice(pos, pos + 4) });
            pos += 4;
        } else {
            return null; // wire type 3/4 (group) đã bỏ từ proto3
        }
    }
    return fields;
}

/** Ghép danh sách trường trở lại thành bytes, tính lại toàn bộ độ dài. */
function buildMessage(fields) {
    const out = [];
    for (let i = 0; i < fields.length; i++) {
        const f = fields[i];
        const tag = (BigInt(f.field) << 3n) | BigInt(f.wire);
        pushAll(out, writeVarint(tag));

        if (f.wire === 0) {
            pushAll(out, writeVarint(f.value));
        } else if (f.wire === 2) {
            pushAll(out, writeVarint(BigInt(f.raw.length)));
            pushAll(out, f.raw);
        } else {
            pushAll(out, f.raw);
        }
    }
    return Uint8Array.from(out);
}

function pushAll(target, src) {
    for (let i = 0; i < src.length; i++) target.push(src[i]);
}

/* -------------------------------------------------------- nhận diện Location */

/**
 * Message này có phải `Location` không?
 * Dấu hiệu: có field 1 và field 2 đều là varint, quy ra vĩ/kinh độ hợp lệ và
 * khác 0. Ngưỡng 0.001 loại các message toàn số nhỏ (mcc/mnc/channel...) vô tình
 * lọt vào dải hợp lệ.
 */
function looksLikeLocation(fields) {
    let lat = null;
    let lon = null;
    for (let i = 0; i < fields.length; i++) {
        const f = fields[i];
        if (f.wire !== 0) continue;
        if (f.field === 1) lat = toSigned(f.value);
        else if (f.field === 2) lon = toSigned(f.value);
    }
    if (lat === null || lon === null) return false;

    const latDeg = Number(lat) / SCALE;
    const lonDeg = Number(lon) / SCALE;
    return (
        latDeg >= -90 && latDeg <= 90 &&
        lonDeg >= -180 && lonDeg <= 180 &&
        (Math.abs(latDeg) > 0.001 || Math.abs(lonDeg) > 0.001)
    );
}

/** Varint lưu bù hai 64-bit; đưa về BigInt có dấu. */
function toSigned(v) {
    const value = BigInt(v);
    return value >= (1n << 63n) ? value - (1n << 64n) : value;
}

/* ------------------------------------------------------------- biến đổi cây */

let rewriteCount = 0;

/**
 * Đi đệ quy toàn bộ cây message, thay toạ độ ở mọi `Location` gặp được,
 * rồi dựng lại. Vì dựng lại từ trong ra ngoài nên độ dài luôn khớp.
 */
function transform(bytes, args, depth) {
    if (depth > 12) return bytes; // chặn lồng quá sâu / dữ liệu ác ý
    const fields = parseMessage(bytes);
    if (!fields) return bytes; // không phải message -> giữ nguyên (chuỗi, bytes...)

    if (looksLikeLocation(fields)) {
        const targetLat = BigInt(Math.round(args.latitude * SCALE));
        const targetLon = BigInt(Math.round(args.longitude * SCALE));
        const targetAcc = BigInt(Math.max(1, args.horizontalAccuracy));

        for (let i = 0; i < fields.length; i++) {
            const f = fields[i];
            if (f.wire !== 0) continue;
            if (f.field === 1) f.value = targetLat;
            else if (f.field === 2) f.value = targetLon;
            else if (f.field === 3) f.value = targetAcc;
        }
        rewriteCount++;
        return buildMessage(fields);
    }

    let changed = false;
    for (let i = 0; i < fields.length; i++) {
        const f = fields[i];
        if (f.wire !== 2 || f.raw.length === 0) continue;
        const replaced = transform(f.raw, args, depth + 1);
        if (replaced !== f.raw) {
            f.raw = replaced;
            changed = true;
        }
    }
    return changed ? buildMessage(fields) : bytes;
}

/* -------------------------------------------------------------------- chạy */

/* ------------------------------------------------- lay toa do song luc chay */

/// Dia chi CoordinateServer cua ung dung.
const LIVE_COORD_URL = 'http://127.0.0.1:8765/coord';

/**
 * Lay toa do hien tai.
 *
 * Vi sao phai fetch luc CHAY chu khong nuong san vao script: Shadowrocket CACHE script
 * sau lan tai dau tien. Toa do nuong cung se dung yen mai mai — nguoi dung di chuyen
 * trong ung dung ma vi tri gia khong doi theo.
 *
 * Neu ung dung dang ngu (iOS treo tien trinh, cong 8765 dong) thi fetch that bai va ta
 * lui ve tham so tinh trong `$argument`. Nho vay mat tinh realtime chu khong mat luon
 * kha nang dinh vi.
 */
function resolveArgs(callback) {
    const fallback = getArgs();

    if (typeof $httpClient === 'undefined' || !$httpClient.get) {
        callback(fallback);
        return;
    }

    let settled = false;
    function finish(args) {
        if (settled) return;
        settled = true;
        callback(args);
    }

    try {
        $httpClient.get({ url: LIVE_COORD_URL, timeout: 2 }, function (error, response, body) {
            if (error || !body) { finish(fallback); return; }
            try {
                const live = JSON.parse(body);
                if (typeof live.lat === 'number' && typeof live.lon === 'number') {
                    finish({
                        latitude: live.lat,
                        longitude: live.lon,
                        horizontalAccuracy: typeof live.acc === 'number'
                            ? live.acc : fallback.horizontalAccuracy,
                    });
                    return;
                }
            } catch (e) {}
            finish(fallback);
        });
    } catch (e) {
        finish(fallback);
    }
}

/* -------------------------------------------------------------------- chay */

/// Thay toa do trong response roi tra ve cho he thong.
function rewrite(args) {
    const body = $response.body;

    if (!body || body.byteLength < 8) {
        $done({});
        return;
    }

    try {
        const input = new Uint8Array(body);
        rewriteCount = 0;
        const output = transform(input, args, 0);

        if (rewriteCount === 0) {
            // Khong nhan ra Location nao: TRA NGUYEN response.
            // Tra ve du lieu da dung cham nua voi con te hon khong lam gi — CoreLocation
            // se vut ca response va nguoi dung mat luon dinh vi.
            $done({});
            return;
        }

        console.log(
            '[LocationX] rewrote ' + rewriteCount + ' location(s) -> ' +
            args.latitude + ', ' + args.longitude
        );
        $done({ body: output.buffer });
    } catch (e) {
        console.log('[LocationX] error: ' + e);
        $done({}); // loi thi de response goc di qua
    }
}

resolveArgs(rewrite);
