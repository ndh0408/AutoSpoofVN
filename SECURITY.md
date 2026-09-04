# Chính sách bảo mật

## Phiên bản được hỗ trợ

Chỉ nhánh `main` được hỗ trợ.

## Báo cáo lỗ hổng

**Đừng** mở Issue công khai cho lỗ hổng bảo mật.

Hãy dùng [GitHub Security Advisories](https://github.com/ndh0408/LocationX/security/advisories/new)
để báo cáo riêng tư. Tôi sẽ phản hồi trong vòng 7 ngày.

Khi báo cáo, xin nêu:

- Loại lỗ hổng và mức ảnh hưởng
- Các bước tái hiện
- Phiên bản iOS và bản dựng LocationX

## Phạm vi

Dự án này chạy một máy chủ HTTP nội bộ ở `127.0.0.1:8765` để phục vụ toạ độ cho ứng dụng proxy trên
cùng thiết bị. Những điểm sau đặc biệt được quan tâm:

- Máy chủ đó có thể bị ứng dụng khác trên máy truy cập ngoài ý muốn không
- Dữ liệu ghép nối hoặc dữ liệu vị trí có bị rò ra ngoài sandbox không
- Script MITM có thể bị lợi dụng để làm hỏng dữ liệu ngoài phạm vi định vị không

## Ngoài phạm vi

- Bản thân việc giả mạo vị trí — đó là mục đích của công cụ này
- Việc giả mạo vị trí vi phạm điều khoản dịch vụ của bên thứ ba
