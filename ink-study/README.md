# Ink Study

Ứng dụng ghi chú viết tay ngoại tuyến cho Windows. Mỗi ghi chú là một dải giấy cuộn liên tục. Sổ, ảnh và PDF đã nhập được lưu theo tài khoản Windows hiện tại.

## Sử dụng

- Bấm **Ghi chú mới** hoặc dùng Ctrl+N. Kéo chuột trái hoặc dùng bút cảm ứng để viết. Lăn chuột để cuộn và giữ Ctrl khi lăn để thu phóng.
- Bấm vào hình bút bi, bút chì hoặc bút đánh dấu để viết ngay. Bấm một ô màu để đổi mực. Mũi tên bên cạnh từng bút mở phần chỉnh nét. Chọn **Gôm** rồi kéo ngang nét viết để tẩy một đoạn.
- Bấm **Chọn vùng**, giữ chuột trái ở khoảng trống trên giấy rồi kéo một khung qua các nét, hình, ảnh hoặc vùng PDF đã tách. Kéo bên trong khung sau khi thả chuột để di chuyển cả nhóm. Phím Delete xóa nhóm, Ctrl+Z hoàn tác và Ctrl+Y làm lại.
- Ở góc trên bên phải, nút **−** thu ứng dụng xuống thanh tác vụ, nút **□ / ❐** phóng to hoặc khôi phục kích thước. Cũng có thể nhấp đúp tên ghi chú trên thanh tiêu đề. Nhấn **F11** để viết toàn màn hình và **F11** hoặc **Esc** để trở lại. Nút **Trình bày với laser** mở chế độ trình chiếu.
- Dùng **Chèn → PDF làm nền**. Để chỉnh sơ đồ, chọn **Chèn → Chỉnh vùng PDF**, khoanh vùng trong một trang rồi chọn **Tách vùng**. Kéo cạnh khung để giãn theo một chiều.
- Dán ảnh với Ctrl+V. Dùng **Chọn vùng** rồi bấm vào một ảnh hoặc hình để hiện tay nắm chỉnh kích thước. Bấm chuột phải để xem các lệnh như xoay ảnh hoặc đổi kiểu cạnh của hình.
- Dùng **Xuất PDF** để chọn toàn bộ, vùng đang xem hoặc một vùng khoanh trên giấy. Bản xuất PDF A4 giữ bố cục hiển thị dưới dạng ảnh có độ phân giải cao.

## Tải bộ cài Windows

Mở lần chạy thành công trong **Actions → Build Ink Study for Windows** và chọn **Tải InkStudy-Setup.exe** trong phần tóm tắt. Nếu đã dùng Ink Study, đóng ứng dụng rồi chạy bộ cài mới bằng cùng tài khoản Windows để tiếp tục dùng sổ hiện có. Sau khi cài, mở **Ink Study** từ menu Start.

## Build lại

Workflow GitHub Actions build và đóng gói trên Windows x64. Để build trên máy dành cho phát triển, dùng Flutter 3.44.0, Visual Studio với **Desktop development with C++** và Inno Setup. Chạy trong thư mục này.

```powershell
./scripts/build-windows.ps1 -VerifyInstall
```

Bộ cài tạo ở `dist/InkStudy-Setup.exe`. Script chạy phân tích tĩnh, các bài kiểm tra Flutter và kiểm tra cài, mở và gỡ ứng dụng khi dùng `-VerifyInstall`.
