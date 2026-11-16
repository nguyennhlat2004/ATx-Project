# Cài đặt Cloudflare R2 và đồng bộ thư viện

Cần hai file `index.html` và `cloudflare-worker.js`. Worker chạy trên tài khoản Cloudflare của bạn, không phải một trang HTML thứ hai. Cấu hình bên dưới cần làm trên Cloudflare thật; chạy thử bằng giả lập không tự tạo bucket hay triển khai Worker.

## 1. Đưa trang lên HTTPS

Đưa `index.html` lên một trang HTTPS ổn định, ví dụ GitHub Pages hoặc Cloudflare Pages. Nếu dùng Pages Direct Upload: trong Dashboard chọn **Workers & Pages → Create application → Pages → Direct Upload**, tải thư mục chứa `index.html` và deploy. Ghi lại origin, ví dụ `https://ten-du-an.pages.dev` (không có đường dẫn hay dấu `/` cuối).

Dữ liệu trình duyệt gắn với origin: đổi từ file cục bộ sang trang HTTPS sẽ không tự mang thư viện theo. Giữ nguyên bản cũ cho đến khi sao lưu/chuyển dữ liệu và kiểm tra xong. Khung xem trước bị sandbox hoặc `file://` có thể không kết nối được và có thể không phát YouTube.

## 2. Tạo R2 và Worker

1. Trong Cloudflare Dashboard, mở **R2 object storage**, kích hoạt R2 nếu cần và **Create bucket**. Giữ bucket riêng tư. Kiểm tra giá và hạn mức tại https://developers.cloudflare.com/r2/pricing/.
2. Vào **Workers & Pages**, tạo Worker, mở **Edit code**, thay mã mẫu bằng toàn bộ nội dung `cloudflare-worker.js`, rồi deploy.
3. Vào **Settings → Bindings**, thêm R2 bucket binding tên chính xác `MUSIC_BUCKET` trỏ đến bucket trên.
4. Trong **Settings → Variables and Secrets**, thêm:
   - Secret `MUSIC_TOKEN`: chuỗi ngẫu nhiên ít nhất 32 ký tự, nên dùng 40–64 ký tự. Đây là mật khẩu riêng cho thư viện, không phải API key Cloudflare. Đừng đưa vào mã, GitHub hay chat.
   - Biến văn bản `ALLOWED_ORIGINS`: origin HTTPS của trang, ví dụ `https://ten-du-an.pages.dev`. Nhiều origin cách nhau bằng dấu phẩy; không dùng `*`, không có dấu `/` cuối.
5. Lưu và deploy lại nếu Dashboard yêu cầu. Ghi URL Worker dạng `https://ten-worker.ten-tai-khoan.workers.dev`, không kèm đường dẫn. Binding và biến phải thuộc môi trường Production đang chạy.
6. Trong Worker, vào **Settings → Triggers → Cron Triggers** (tên mục có thể thay đổi), thêm lịch `0 3 * * *` và deploy/lưu. Lịch chạy lúc 03:00 **UTC** mỗi ngày. Không bật Cron Trigger thì thùng rác không được dọn tự động. Xem https://developers.cloudflare.com/workers/configuration/cron-triggers/.

Browser gọi Worker, không gọi bucket trực tiếp, nên không cần bật public access hay thiết lập CORS trên bucket; Worker tự xử lý CORS bằng `ALLOWED_ORIGINS`.

## 3. Kết nối và đồng bộ

1. Trên trang HTTPS, mở tab **Khác → Cloudflare R2**, nhập URL Worker và `MUSIC_TOKEN`, bấm **Kết nối**. Để ý dòng trạng thái đồng bộ.
2. Thư viện gồm playlist, thứ tự, tên bài, cấu hình playlist, Cue, Skip, Auto Upload, file và waveform được tự động đẩy lên R2. Đợi thông báo đồng bộ xong trước khi đóng trang hoặc xóa dữ liệu trình duyệt. Bài chưa xử lý thành công và file quá lớn sẽ giữ trên máy; sửa lỗi rồi thử lại.
3. Ở thiết bị khác, mở cùng trang, nhập URL và token, rồi kết nối. Nếu máy có dữ liệu cục bộ khác hoặc hai máy cùng sửa, ứng dụng báo xung đột thay vì tự ghi đè. Nút **Dùng bản R2** thay toàn bộ bản trên máy; **Dùng bản máy** thay trạng thái trên R2. Hai thao tác có xác nhận và có thể làm mất các thay đổi phía bị thay thế; hãy sao lưu trước khi chọn. Không phải chức năng tự gộp thay đổi.
4. URL Worker lưu trong localStorage, token lưu trong sessionStorage của tab. Khi mở tab/phiên mới có thể phải nhập lại token. Tránh dùng máy công cộng. Người biết URL và token có quyền đọc/ghi; CORS không thay thế xác thực.

## 4. Xóa và khôi phục

Xóa một bài trong playlist chỉ gỡ bài khỏi playlist đó; các playlist khác vẫn giữ bài. Vào **Khác → Thùng rác**, chọn bài đã xóa và bấm khôi phục. Bài được đưa về playlist cũ (playlist bị xóa có thể được tạo lại). Xóa lịch sử, xóa playlist và **Xóa Upload** chuyển bài vào thùng rác; Xóa Upload làm trống danh sách bài ở mọi playlist nhưng giữ tên playlist, không xóa ngay file vĩnh viễn.

Thời hạn tính từ lúc xóa trên thiết bị là 30 ngày. Khi offline, thay đổi chỉ nằm trên máy cho đến khi kết nối và đồng bộ thành công; R2 chưa nhận lệnh xóa lúc offline. Sau hạn, lần Cron Trigger kế tiếp mới dọn mục hết hạn và file/waveform không còn được playlist hoặc mục thùng rác còn hạn tham chiếu. Vì chạy định kỳ và phụ thuộc Worker/R2, không cam kết xóa đúng ngay giây thứ 30 ngày. Nếu một thiết bị lâu không đồng bộ có dữ liệu đã hết hạn, không ép bản máy lên R2 mà chưa kiểm tra: file cũ có thể đã bị xóa.

## 5. Offline và giới hạn

- Import và phát file mới vẫn hoạt động cục bộ khi R2 lỗi hoặc mất mạng, trong giới hạn trình duyệt và dung lượng thiết bị. File chưa được xác nhận đồng bộ được giữ trong IndexedDB; trang phải được mở lại và kết nối hợp lệ để tiếp tục thử. Không xóa dữ liệu trình duyệt trước khi xác nhận.
- Sau khi đồng bộ thành công, bản file và waveform trong IndexedDB được xóa để tiết kiệm chỗ; metadata vẫn còn. Vì vậy bài chỉ còn trên R2 **không thể tải lại khi offline hoặc R2 lỗi**, trừ khi đã được tải sẵn trong bộ nhớ của phiên hiện tại. Hai mục tiêu xóa bản cục bộ và phát offline mọi bài sau khi reload không thể cùng đảm bảo.
- Giới hạn mỗi file đồng bộ là 90 MiB; waveform tối đa 2 MiB; trạng thái gửi lên tối đa 5 MiB, 5.000 bài, 5.000 mục thùng rác và 500 playlist. Một file lỗi hoặc vượt giới hạn có thể làm lần đồng bộ chưa hoàn thành; file mới vẫn ở máy. Các giới hạn, dung lượng IndexedDB và hạn mức Cloudflare cần theo dõi.
- Các object chưa được tham chiếu do upload thất bại, thay file, hoặc các bản sao lưu thủ công đời cũ có thể vẫn nằm trong bucket và phát sinh phí. Không tự xóa object đang được tham chiếu. Danh sách mã đã hết hạn được giữ trong trạng thái để ngăn thiết bị cũ khôi phục nhầm file đã bị dọn; danh sách này tăng dần theo thời gian.
- File không được mã hóa đầu-cuối bởi ứng dụng. Các thư viện CDN, chuyển đổi định dạng và YouTube có thể cần mạng; công cụ tìm kiếm YouTube không dùng key phụ thuộc dịch vụ bên thứ ba.

## 6. Bản sao lưu cũ

Các nút **Tải danh sách / Khôi phục** của bản sao lưu thủ công v1 vẫn dùng được: kết nối Worker mới, tải danh sách, chọn bản cũ và khôi phục thành playlist mới. Đợi file tải về, waveform dựng xong và đồng bộ v2 thành công trước khi xóa bản cũ. Bản sao lưu thủ công v1 và object của nó không tự được Cron xóa. Việc khôi phục này không gộp tự động các bản sao hoặc xóa chúng.

## Xử lý lỗi

- **403/CORS:** `ALLOWED_ORIGINS` phải khớp chính xác origin của trang HTTPS; deploy lại Worker.
- **401:** token trên trang phải khớp `MUSIC_TOKEN` secret. Nếu token lộ, đổi secret ngay.
- **503:** kiểm tra binding `MUSIC_BUCKET`, secret đủ dài và phiên bản Worker đã deploy.
- **413:** kiểm tra giới hạn file, waveform hoặc trạng thái; dữ liệu chưa đồng bộ vẫn trên máy.
- **410 / file hết hạn:** bản máy đang tham chiếu file đã bị dọn; không thể khôi phục từ R2. Chọn bản R2 sau khi sao lưu các thay đổi cục bộ cần giữ, hoặc nhập lại file từ nguồn riêng.
- Nếu mới thay Worker nhưng báo phiên bản cũ, deploy lại đúng môi trường và kiểm tra URL Worker.

Tài liệu: https://developers.cloudflare.com/r2/get-started/workers-api/ · https://developers.cloudflare.com/workers/configuration/environment-variables/ · https://developers.cloudflare.com/workers/configuration/cron-triggers/
