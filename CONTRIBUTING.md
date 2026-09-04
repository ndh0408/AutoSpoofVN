# Đóng góp cho LocationX

Cảm ơn bạn đã quan tâm. Tài liệu này mô tả cách làm việc với dự án.

## Chuẩn bị

```bash
brew install xcodegen
git clone https://github.com/ndh0408/LocationX.git
cd LocationX
xcodegen generate
open LocationX.xcodeproj
```

Chạy kiểm thử trước khi gửi thay đổi:

```bash
xcodebuild -project LocationX.xcodeproj -scheme LocationX \
  -destination 'platform=iOS Simulator,name=iPhone 17' test
```

`project.yml` là nguồn sự thật của cấu hình project. **Không** commit `LocationX.xcodeproj` —
nó được sinh ra và đã nằm trong `.gitignore`. Sửa cấu hình thì sửa `project.yml` rồi chạy lại
`xcodegen generate`.

## Nguyên tắc kiến trúc

Ba quy tắc này quan trọng hơn phong cách viết mã:

1. **`SimulationCoordinator` là nguồn sự thật duy nhất.** Mọi toạ độ đi qua nó. View *quan sát*
   trạng thái, không giữ bản sao. Đừng thêm một máy trạng thái mô phỏng thứ hai.

2. **Nhiễu GPS áp đúng một lần**, ở thời điểm gửi ra thiết bị. Vị trí nội bộ luôn là vị trí thật.
   Ghi giá trị đã nhiễu ngược vào vị trí nội bộ sẽ khiến nhiễu tích luỹ thành trôi vị trí — lỗi
   này đã từng xảy ra.

3. **Thứ tự ưu tiên nguồn không được đổi:**
   `Thủ công 100 > Kịch bản 80 > Chuyến bay 60 > Tuyến 50 > Chu trình 40 > Phát lại 20`.
   Đổi thì phải đổi cả `SimulationSource.priority` lẫn nhánh phân xử trong `LiveActivityManager`.

## Chuỗi hiển thị

Mọi chữ người dùng nhìn thấy phải đi qua `L("khoa")` và có mặt ở **cả hai**
`Resources/vi.lproj/` và `en.lproj/Localizable.strings`.

- Quy ước khoá: `<vùng>.<thứ>` — ví dụ `route.detail.title`, `map.start_spoof`.
- Chuỗi có tham số dùng `L("khoa", giá_trị)` với `%d` / `%@` / `%.1f`. Số lượng và thứ tự
  specifier phải giống nhau ở hai ngôn ngữ.
- Tiếng Việt phải **đủ dấu**.
- `LocalizationTests` sẽ báo lỗi nếu thiếu bản dịch hoặc lệch định dạng.

Ghi chú trong mã nguồn giữ nguyên tiếng Việt — chúng không phải chuỗi giao diện.

## Phong cách viết mã

- Ghi chú giải thích **vì sao**, không mô tả lại điều mã đã nói rõ. Ghi chú giá trị nhất là ghi chú
  nêu ràng buộc không tự nhìn ra được, hoặc kể lại một lỗi đã sửa.
- Không dùng giá trị rời rạc trong view: màu, khoảng cách, bo góc, chữ đều lấy từ
  `UI/DesignSystem/`.
- Nút chỉ có biểu tượng **bắt buộc** có `accessibilityLabel`.
- Không dựa vào riêng màu để biểu đạt trạng thái — luôn kèm biểu tượng hoặc chữ.
- Tránh làm việc nặng trong `body`: không đọc file, không giải mã JSON, không tính toán O(n).

## Gửi thay đổi

1. Tạo nhánh từ `main`.
2. Mỗi commit làm một việc; phần thân commit nêu **vì sao**, không chỉ *cái gì*.
3. Kiểm thử phải xanh.
4. Mở Pull Request theo mẫu có sẵn.

Sửa lỗi thì kèm một bài kiểm thử tái hiện lỗi đó, nếu tái hiện được.

## Báo lỗi

Dùng mẫu Issue. Nêu rõ phiên bản iOS, mẫu iPhone, phiên bản Shadowrocket, và **đường spoof** bạn
đang dùng — phần lớn báo cáo "không chạy" hoá ra là chứng chỉ Shadowrocket chưa được tin cậy đầy đủ.
