# Ink Study

Ứng dụng ghi chú viết tay ngoại tuyến cho Windows. Mỗi ghi chú là một dải giấy cuộn liên tục. Sổ, ảnh và PDF đã nhập được lưu theo tài khoản Windows hiện tại.

## Sử dụng

- Bấm **Ghi chú mới** hoặc dùng Ctrl+N. Kéo chuột trái hoặc dùng bút cảm ứng để viết. Lăn chuột để cuộn và giữ Ctrl khi lăn để thu phóng.
- Bấm vào biểu tượng bút để viết ngay. Mở mũi tên bên cạnh để chọn **Bút mực**, bút bi, bút chì hoặc dạ quang và xem trước màu, độ dày, nét đứt. Bút mực cho nét thanh đậm theo hướng viết và lực tay của bút cảm ứng hỗ trợ lực nhấn.
- Dùng **Gôm** để cắt một đoạn nét viết. Quét qua cạnh đã vẽ để xóa cả hình. Mũi tên bên cạnh mở bảng chỉnh cỡ gôm từ 6 đến 72 px và các cỡ **Nhỏ, Vừa, Lớn**.
- Bấm **Chọn vùng** hoặc giữ **Shift**, rồi kéo chuột trái từ khoảng trống để khoanh qua các nét, hình, ảnh hoặc vùng PDF đã tách. Kéo bên trong khung để di chuyển cả nhóm. Phím Delete xóa nhóm, Ctrl+Z hoàn tác và Ctrl+Y làm lại.
- Dùng nút **−** và **□ / ❐** bên phải thanh công cụ để thu nhỏ, phóng to hoặc khôi phục cửa sổ. Nhấn **F11** để viết toàn màn hình và **F11** hoặc **Esc** để trở lại. Biểu tượng **Trình bày với laser** ở thanh dưới mở chế độ trình chiếu.
- Dùng **Chèn → PDF làm nền**. Để chỉnh sơ đồ, chọn **Chèn → Chỉnh vùng PDF**, khoanh vùng trong một trang rồi chọn **Tách vùng**. Kéo cạnh khung để giãn theo một chiều.
- Dán ảnh với Ctrl+V. Dùng **Chọn vùng** rồi bấm vào một ảnh hoặc hình để hiện tay nắm chỉnh kích thước. Bấm chuột phải để xem các lệnh như xoay ảnh hoặc đổi kiểu cạnh của hình.
- Bấm biểu tượng **Xuất PDF** ở thanh dưới để chọn toàn bộ, vùng đang xem hoặc một vùng khoanh trên giấy. Bản xuất PDF A4 giữ bố cục hiển thị dưới dạng ảnh có độ phân giải cao.

## Tải bộ cài Windows

Mở lần chạy thành công trong **Actions → Build Ink Study for Windows** và chọn **Tải InkStudy-Setup.exe** trong phần tóm tắt. Nếu đã dùng Ink Study, đóng ứng dụng rồi chạy bộ cài mới bằng cùng tài khoản Windows để tiếp tục dùng sổ hiện có. Sau khi cài, mở **Ink Study** từ menu Start.

## Build lại

Workflow GitHub Actions build và đóng gói trên Windows x64. Để build trên máy dành cho phát triển, dùng Flutter 3.44.0, Visual Studio với **Desktop development with C++** và Inno Setup. Chạy trong thư mục này.

```powershell
./scripts/build-windows.ps1 -VerifyInstall
```

Bộ cài tạo ở `dist/InkStudy-Setup.exe`. Script chạy phân tích tĩnh, các bài kiểm tra Flutter và kiểm tra cài, mở và gỡ ứng dụng khi dùng `-VerifyInstall`.
