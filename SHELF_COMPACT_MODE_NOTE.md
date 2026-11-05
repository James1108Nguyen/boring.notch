# Shelf & Compact Mode Limitation

## 1. Vấn đề
Khi bật **Compact Mode** (`Defaults[.compactMode] == true`), người dùng kéo file vào Notch thì Notch chỉ bung ra giao diện nghe nhạc thu nhỏ (`CompactHomeView`), hoàn toàn không hiển thị giao diện **Shelf / AirDrop** và không nhận file.

## 2. Nguyên nhân kỹ thuật
- **`boringNotch/ContentView.swift` (~dòng 540-570):**
  Nhánh hiển thị khi mở Notch kiểm tra `if Defaults[.compactMode]` trước. Nếu đang bật, nó ép hiển thị `CompactHomeView` và bỏ qua hoàn toàn `switch coordinator.currentView` (nơi chứa `ShelfView`).
  > Comment từ tác giả: *"Player only — no tab switching, so currentView is ignored here rather than offering a shelf the compact layout has no room (or tab bar) for."*
- **`boringNotch/ContentView.swift` (`showsHeader`):** Ẩn thanh header/tab bar khi `compactMode == true`.
- **`boringNotch/sizing/matters.swift`:**
  - `compactOpenContentWidth = 336 pt` (chỉ vừa cho mini player, không đủ chỗ cho layout Shelf chuẩn).
  - `openNotchSize = 640 x 190 pt` (kích thước đầy đủ của Shelf gồm 2 panel: AirDrop + Drop files zone).

## 3. Gợi ý hướng phát triển tiếp theo (cho Claude Code)
1. **Dynamic Expansion:** Khi có tương tác kéo file (`dragDetectorTargeting` / `anyDropZoneTargeting`), tạm thời bung Notch ra kích thước chuẩn (640pt) để hiển thị Shelf, sau khi kéo/thả xong hoặc đóng thì thu về lại Compact (336pt).
2. **Compact Shelf UI:** Thiết kế một layout Shelf thu nhỏ dành riêng cho kích thước 336pt (chẳng hạn hiển thị icon AirDrop + vùng drop gọn gàng thay vì 2 panel lớn).
3. **Cài đặt linh hoạt:** Thêm tùy chọn cho phép tùy chỉnh kích thước Notch trong Compact Mode hoặc toggle "Cho phép Shelf trong Compact Mode".
