## Thay đổi gì

<!-- Mô tả ngắn gọn. -->

## Vì sao

<!-- Vấn đề nào được giải quyết? Nếu sửa lỗi, mô tả hành vi sai trước đó. -->

Closes #

## Đã kiểm chứng thế nào

- [ ] `xcodebuild ... test` xanh
- [ ] Đã chạy thử trên simulator
- [ ] Đã chạy thử trên máy thật
- [ ] Đã kiểm tra ở cả chế độ sáng và tối

## Danh mục tự kiểm

- [ ] Chuỗi giao diện mới đi qua `L(...)` và có ở **cả** `vi.lproj` lẫn `en.lproj`
- [ ] Không thêm giá trị màu/khoảng cách/bo góc rời rạc — dùng token trong `UI/DesignSystem/`
- [ ] Nút chỉ có biểu tượng đều có `accessibilityLabel`
- [ ] `SimulationCoordinator` vẫn là nguồn sự thật duy nhất
- [ ] Không đổi thứ tự ưu tiên nguồn (hoặc đã đổi đồng bộ ở mọi nơi)
- [ ] Không đọc file / giải mã JSON trong `body` của view
