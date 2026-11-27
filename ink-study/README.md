# Ink Study

Ứng dụng ghi chú viết tay ngoại tuyến cho Windows. Mỗi ghi chú là một dải giấy cuộn liên tục. Sổ, ảnh và PDF đã nhập được lưu theo tài khoản Windows hiện tại.

## Sử dụng

- Bấm **Ghi chú mới** hoặc dùng Ctrl+N. Kéo chuột trái hoặc dùng bút cảm ứng để viết. Lăn chuột để cuộn và giữ Ctrl khi lăn để thu phóng.
- Dùng **Tẩy một phần** để cắt nét. Ctrl+Z hoàn tác. Ctrl+Y làm lại.
- Dùng **Chèn → PDF làm nền**. Để chỉnh sơ đồ, chọn **Chèn → Chỉnh vùng PDF**, khoanh vùng trong một trang rồi chọn **Tách vùng**. Kéo cạnh khung để giãn theo một chiều.
- Dán ảnh với Ctrl+V. Dùng **Chọn** để di chuyển hoặc chỉnh đối tượng. Bấm chuột phải để xem lệnh phù hợp cho đối tượng, chẳng hạn xoay ảnh hoặc đổi kiểu cạnh của hình.
- Dùng **Xuất PDF** để chọn toàn bộ, vùng đang xem hoặc một vùng khoanh trên giấy. Bản xuất PDF A4 giữ bố cục hiển thị dưới dạng ảnh có độ phân giải cao.

## Tải bộ cài Windows

Mở lần chạy thành công trong **Actions → Build Ink Study for Windows** và chọn **Tải InkStudy-Setup.exe** trong phần tóm tắt. Sau khi cài, mở **Ink Study** từ menu Start. Quy trình đóng gói đi kèm thư viện cần thiết.

## Build lại

Workflow GitHub Actions build và đóng gói trên Windows x64. Để build trên máy dành cho phát triển, dùng Flutter 3.44.0, Visual Studio với **Desktop development with C++** và Inno Setup. Chạy trong thư mục này.

```powershell
./scripts/build-windows.ps1 -VerifyInstall
```

Bộ cài tạo ở `dist/InkStudy-Setup.exe`. Script chạy phân tích tĩnh, các bài kiểm tra Flutter và kiểm tra cài, mở và gỡ ứng dụng khi dùng `-VerifyInstall`.
