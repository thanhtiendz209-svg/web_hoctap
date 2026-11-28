# Ink Study

Ứng dụng ghi chú viết tay ngoại tuyến cho Windows. Mỗi ghi chú là một dải giấy cuộn liên tục. Sổ, ảnh và PDF đã nhập được lưu theo tài khoản Windows hiện tại.

## Sử dụng

- Bấm **Ghi chú mới** hoặc dùng Ctrl+N. Kéo chuột trái hoặc dùng bút cảm ứng để viết. Lăn chuột để cuộn và giữ Ctrl khi lăn để thu phóng.
- Bấm một chấm màu để chọn bút và mở bảng chỉnh kiểu, màu, độ dày và nét. Ban đầu có ba bút. Bấm **+** cạnh bộ bút để thêm cấu hình. Có thể cuộn ngang bộ bút khi đã thêm nhiều bút.
- Dùng **Gôm** để cắt một đoạn nét viết. Quét qua cạnh đã vẽ để xóa cả hình. Mũi tên bên cạnh mở bảng chỉnh cỡ gôm từ 6 đến 72 px và các cỡ **Nhỏ, Vừa, Lớn**.
- Bấm **Chọn vùng** hoặc giữ **Shift**, rồi kéo chuột trái từ khoảng trống để khoanh qua các nét, hình, ảnh hoặc vùng PDF đã tách. Kéo trong khung, hoặc bấm **Di chuyển** rồi bấm vị trí mới. Bấm **Xóa** hoặc Delete để xóa nhóm, Ctrl+Z để hoàn tác.
- Chọn **Laser** trên thanh công cụ để trỏ tạm trên giấy. Dấu laser tự mờ sau khi nhấc bút.
- Dùng biểu tượng thư mục ở thanh dưới để **Sao lưu ghi chú (.inkstudy)** hoặc **Nhập ghi chú (.inkstudy)**. Tệp lưu nét viết, hình, ảnh và PDF đi kèm. Ghi chú nhập được thêm riêng vào thư viện. Trong menu **⋮** cạnh ghi chú, chọn **Nhân bản ghi chú** nếu muốn sửa một bản sao.
- Dùng nút **−** và **□ / ❐** bên phải thanh công cụ để thu nhỏ, phóng to hoặc khôi phục cửa sổ. Nhấn **F11** để viết toàn màn hình và **F11** hoặc **Esc** để trở lại. Biểu tượng **Trình bày với laser** ở thanh dưới mở chế độ trình chiếu.
- Dùng **Chèn → PDF làm nền**. Để chỉnh sơ đồ, chọn **Chèn → Chỉnh vùng PDF**, khoanh vùng trong một trang rồi chọn **Tách vùng**. Kéo cạnh khung để giãn theo một chiều.
- Chọn **Chèn → Chèn khoảng viết**, đặt chuột giữa hai dòng rồi kéo xuống. Phần PDF phía dưới dịch xuống và khoảng mới dùng nền giấy của ghi chú. Kéo xuống trong một khoảng đã có để mở rộng thêm. Bấm **Xong** để viết hoặc **Ctrl+Z** để hoàn tác. Khoảng viết được lưu trong ghi chú, có trong bản sao `.inkstudy` và khi xuất PDF.
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
