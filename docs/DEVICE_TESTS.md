# Biên bản Kiểm chứng Thiết bị Thật — Tâm Học

**Trạng thái tổng quan:** **NOT RUN / UNVERIFIED** (thiếu macOS/Xcode và thiết bị iPhone thật).
Bất kỳ chế độ khóa hay camera nào chưa thử trên thiết bị thật đều giữ trạng thái **UNVERIFIED** theo yêu cầu kế hoạch.

## Ma trận thiết bị & kiểm thử
| Hạng mục | Thiết bị / OS | Commit | Kết quả | Ghi chú |
|---|---|---|---|---|
| Guided Access vào/ra thủ công | iPhone (iOS 15.7.x) | - | NOT RUN | Cần máy thật iOS 15.7.x |
| Guided Access vào/ra thủ công | iPhone (iOS mới hơn) | - | NOT RUN | Cần máy thật |
| Hết giờ không tự thoát khóa | iPhone | - | NOT RUN | Xác minh copy & trạng thái UI |
| Kill app / Reboot giữa phiên | iPhone | - | NOT RUN | Kiểm tra recovery tại checkpoint |
| Camera: ngồi thẳng / cúi viết / rời bàn | iPhone | - | NOT RUN | Cần đo confusion counts |
| Độ chính xác rời >60s (>=19/20) & học giấy 2h (<=1 false alarm) | iPhone | - | NOT RUN | Release gate camera |
| Pin / Nhiệt / Peak Memory (<150MB) phiên 50 phút | iPhone cũ & mới | - | NOT RUN | Cần Instruments trên macOS |
| Cài IPA ký & cập nhật giữ dữ liệu (3uTools) | iPhone | - | NOT RUN | Cần signed IPA |
