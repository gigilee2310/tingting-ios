# Ting Ting cho iPhone

App iPhone **thật** (giao diện SwiftUI) của Ting Ting, ứng dụng quản lý tài sản cá nhân.
App dùng **chung tài khoản và dữ liệu** với web Ting Ting (Supabase): thêm tài sản ở app thì web thấy ngay, và ngược lại.
App **không phụ thuộc web**: tự tính toán, tự lấy giá, tự gọi AI. Sau này tắt web thì app vẫn chạy.

Tính năng giống web:
- **Home:** tổng tài sản, lãi/lỗ, biểu đồ phân bổ, biểu đồ net worth, nhắc sổ sắp đáo hạn.
- **Tài sản:** chứng khoán, quỹ, crypto, vàng, tiết kiệm. Có tìm kiếm, lọc, sắp xếp, vuốt để xoá.
  Màn hình chi tiết có sửa giá, lịch sử giao dịch, tiến độ kỳ hạn sổ, mô phỏng tái tục.
- **Nút +:** chụp ảnh lệnh để AI đọc, gõ cho AI, hoặc nhập thủ công (CK / coin / quỹ / vàng / sổ).
- **Tương lai:** kế hoạch mục tiêu, dự phóng theo kịch bản.
- **AI:** hỏi đáp về tài sản (AI chỉ diễn giải số do code tính).
- **Cài đặt:**
  - Cập nhật giá crypto/vàng/USDT; AI đọc giá từ ảnh hoặc tra giá theo mã.
  - Cấu hình AI (dùng chung với web), Face ID, đổi mật khẩu, giao diện sáng/tối.
- **Khoá Face ID** mỗi lần mở app (và sau 1 phút ở chế độ nền).
- **Mỗi ngày tự cập nhật giá** crypto và vàng, đồng thời lưu net worth để biểu đồ có lịch sử thật.
- **Nhắc hết hạn** 2 ngày trước khi app (cài bằng Apple ID miễn phí) hết hạn.

---

## Bước 1 (một lần): cấp quyền cho app trong Supabase

App iPhone nói chuyện thẳng với Supabase. Một số việc trước đây web làm bằng "khoá bí mật" trên server
(ghi giá thị trường, xoá dữ liệu) cần thêm quyền:

1. Vào <https://supabase.com/dashboard>, chọn project Ting Ting, mở **SQL Editor**.
2. Mở file [`supabase/migration-4-mobile-app.sql`](supabase/migration-4-mobile-app.sql), sao chép toàn bộ nội dung.
3. Dán vào SQL Editor, bấm **Run**. Thấy "Success" là xong. Chạy lại nhiều lần cũng không sao.

Nếu chưa làm bước này, app vẫn **xem** và **thêm** được dữ liệu, nhưng **cập nhật giá** và **xoá** sẽ báo lỗi kèm hướng dẫn.

## Bước 2: tải file cài đặt

<https://github.com/gigilee2310/tingting-ios/releases/download/latest/tingting.ipa>

## Bước 3: cài bằng Sideloadly

Làm giống app baoboiii:
1. Cắm iPhone vào máy tính bằng **cáp USB-A** (cáp Type-C trên máy bạn chỉ sạc được).
2. Mở **Sideloadly** → kéo `tingting.ipa` vào → nhập Apple ID → bấm **Start**.
3. Trên iPhone: **Cài đặt → Cài đặt chung → VPN & Quản lý thiết bị** → Apple ID của bạn → **Tin cậy**.
4. Mở app **Ting Ting** → đăng nhập bằng **email và mật khẩu như trên web**.

Apple ID miễn phí cài tối đa 3 app tự ký: baoboiii + Ting Ting = 2 app, vẫn còn chỗ.

## App hết hạn sau 7 ngày

App cài bằng Apple ID miễn phí chỉ chạy được 7 ngày. Hai ngày trước hạn, app sẽ hiện nhắc ở trang Home.
Đến lúc đó cắm cáp, mở Sideloadly, bấm **Start** lại. **Dữ liệu không mất** vì nằm trên Supabase.
Xem ngày hết hạn chính xác ở **Cài đặt → Hết hạn chữ ký**.

---

## Dành cho người phát triển

- Build trên GitHub Actions (macOS 26 + Xcode 26), project sinh bằng XcodeGen (`project.yml`). Không commit `.xcodeproj`.
- Supabase URL và publishable key nằm trong **GitHub Secrets** (`SUPABASE_URL`, `SUPABASE_ANON_KEY`).
  CI sinh ra `TingTing/Support/Secrets.swift` (đã gitignore). **Secret key của Supabase không bao giờ nằm trong app.**
- `Domain/Calc.swift` và `Domain/Portfolio.swift` là bản chuyển 1:1 của `lib/calc.ts` và `lib/compute.ts` trên web, có unit test giữ đúng số.
- AI gọi trực tiếp Anthropic / OpenAI / DeepSeek bằng key trong bảng `user_settings` (giống web).
  Với Claude, model mặc định là `claude-opus-5-5`, có bật `fallbacks: "default"` khi AI từ chối.

```
TingTing/
  App/       TingTingApp (đăng nhập, khoá Face ID), AppStore (trạng thái)
  Domain/    Models, Calc, Portfolio
  Data/      SupabaseClient (Auth + PostgREST), Repository (các thao tác), PriceService
  AI/        AIClient (Anthropic/OpenAI/DeepSeek), AIService (chat, trích xuất, đọc giá)
  UI/        Home, Assets, Add, Future, AI, Settings, Components
TingTingTests/  CalcTests (chuyển từ tests/calc.test.ts của web)
supabase/       migration-4-mobile-app.sql
```
