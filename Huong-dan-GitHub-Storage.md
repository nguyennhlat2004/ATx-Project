# Đồng bộ thư viện với GitHub Storage

Ứng dụng dùng repo riêng tư `nguyennhlat2004/Storage` qua GitHub API. Không đưa token vào mã, repo, ảnh chụp màn hình hoặc chat. Token từng gửi trong chat nên được thu hồi và thay bằng token mới.

## Kết nối lần đầu

1. Kiểm tra repo **Storage** vẫn là **Private**. Ứng dụng từ chối đồng bộ nếu repo không private.
2. Trong GitHub, tạo **fine-grained personal access token**, chỉ chọn repo `Storage`. Cấp quyền repository **Contents: Read and write**; để cài lịch dọn rác cấp thêm **Workflows: Read and write**. GitHub có thể tự thêm quyền Metadata chỉ đọc. Đặt hạn sử dụng ngắn phù hợp nhu cầu.
3. Mở trang web HTTPS → **Khác → GitHub Storage**, nhập token trực tiếp vào ô mật khẩu và bấm icon kết nối. Không gửi token cho người khác hay vào chat. Trang lưu token trong sessionStorage của tab, không lưu trong code hay repo; khi tab/phiên kết thúc có thể cần nhập lại. Dùng máy tin cậy: mã JavaScript chạy trong trang có thể đọc token; không có mã hóa đầu-cuối.
4. Giữ trang mở và chờ trạng thái **Đã đồng bộ lên repo**. Danh sách, config, file và waveform sẽ xuất hiện tại repo. Dữ liệu chưa gửi được vẫn ở máy; kiểm tra dung lượng trình duyệt và không xóa dữ liệu web trước khi xác nhận.
5. Ở thiết bị khác, mở trang và kết nối bằng token tương tự. Nếu cả máy lẫn repo đã có thư viện khác nhau, app dừng và báo xung đột; **Dùng bản repo** thay dữ liệu máy, **Dùng bản máy** thay trạng thái repo. Sao lưu phần cần giữ trước khi chọn. Không tự gộp thay đổi.

## Bật dọn thùng rác khi web đóng

Trong card **GitHub Storage**, bấm icon mũi tên vòng **Bật dọn rác tự động** sau khi kết nối bằng token có quyền **Workflows** và **Contents** ghi. App sẽ cài `Config/cleanup.mjs` và `.github/workflows/cleanup.yml` nếu chưa tồn tại; nó không tự ghi đè file khác đã có. Vào tab **Actions** của repo để kiểm tra workflow **Clean expired music trash** đã bật và chạy được. Workflow chạy hằng ngày lúc 03:17 UTC; GitHub có thể trì hoãn hoặc không chạy nếu Actions bị tắt, hết hạn mức hoặc gặp lỗi. Có thể chạy thủ công bằng **Run workflow**.

Nếu không cài được workflow, nhạc vẫn đồng bộ và app sẽ dọn mục hết hạn khi web đang mở và kết nối thành công, nhưng **không đảm bảo dọn khi web đóng**. Kiểm tra token và quyền Workflows, rồi thử lại; việc tạo commit workflow cần quyền riêng này.

Mỗi mục thùng rác có ngày giờ xóa; sau 30 ngày, lần dọn thành công kế tiếp xóa mục, các phần file nhạc và waveform không còn tham chiếu, cùng config của mục đó khỏi **cây file hiện tại**. Bài còn trong playlist khác hoặc mục thùng rác chưa hết hạn vẫn được giữ. GitHub có thể còn các bản trong lịch sử commit: dọn như trên **không đảm bảo xóa vĩnh viễn khỏi lịch sử**. Xóa offline chỉ được phản ánh ở repo sau khi web kết nối và đồng bộ thành công.

## Cấu trúc và giới hạn

- `Nhac/Playlist/`: file nhạc và danh sách playlist; `Waveform/`: waveform; `Config/state.json`: trạng thái và cấu hình; `Trash/`: mục xóa, file và waveform chỉ còn trong thùng rác.
- GitHub API có giới hạn kích thước request; để tải file lớn an toàn hơn, app chia file thành các phần tối đa 8 MiB và tự ghép khi tải lại. Các file lớn sẽ xuất hiện dưới dạng `.part001`, `.part002`… trong repo, không thể phát riêng từng phần. File tối đa 100 MiB; lớn hơn bị từ chối khi nhập.
- App giữ file trong IndexedDB khi có thể để reload và phát offline nhanh. Nếu bài trước đây chỉ còn trên R2, web phải kết nối R2 để tải trước khi chuyển sang GitHub. Trình duyệt có thể xóa dữ liệu cục bộ khi thiếu dung lượng; không xem nó là bản sao lưu duy nhất.
- Kết nối repo cần mạng và token hợp lệ; upload file lớn có thể tốn thời gian, RAM và băng thông. GitHub áp hạn mức API, quota Actions và giới hạn về sức khỏe repo; Git không phải dịch vụ lưu trữ nhạc chuyên dụng. Git history và các blob tải lỗi có thể chiếm dung lượng kể cả sau khi dọn thùng rác.
- Web Audio cần giải mã trước khi phát; bản ghi rất dài có thể cần nhiều RAM dù file nén nhỏ. Chức năng chuyển định dạng/YouTube có thể cần mạng.

## Chuyển thư viện đang ở R2

Giữ R2 hoạt động và kết nối R2 trên trang trước, rồi kết nối GitHub. App sẽ tải file chưa có trên máy từ R2 và đưa lên repo. Đợi GitHub báo đồng bộ xong, thử mở trên thiết bị khác và phát một số bài trước khi ngắt hoặc xóa dữ liệu R2. Nếu không còn R2 hoặc bản local của một bài, app không thể tự tạo lại file đó. Các bản sao lưu thủ công R2 cũ không tự chuyển; khôi phục chúng vào playlist trước khi đồng bộ GitHub.
