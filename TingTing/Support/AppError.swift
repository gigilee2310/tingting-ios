import Foundation

/// User-facing errors with Vietnamese messages.
enum AppError: LocalizedError {
    case notConfigured
    case notSignedIn
    case invalidCredentials
    case server(Int, String)
    case network(String)
    case badResponse
    case validation(String)
    case aiNotConfigured
    case aiVisionUnsupported(String)
    case ai(String)
    case aiRefused

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "App chưa được cấu hình Supabase (thiếu SUPABASE_URL / SUPABASE_ANON_KEY khi build)."
        case .notSignedIn:
            return "Phiên đăng nhập đã hết. Hãy đăng nhập lại."
        case .invalidCredentials:
            return "Email hoặc mật khẩu không đúng."
        case .server(let code, let msg):
            if code == 401 || code == 403 {
                return "Không có quyền thực hiện (\(code)). \(msg)"
            }
            return "Máy chủ báo lỗi (\(code)): \(msg)"
        case .network(let msg):
            return "Không kết nối được mạng: \(msg)"
        case .badResponse:
            return "Dữ liệu trả về không đúng định dạng."
        case .validation(let msg):
            return msg
        case .aiNotConfigured:
            return "Chưa cấu hình AI. Vào Cài đặt → Trợ lý AI để chọn nhà cung cấp và nhập API key."
        case .aiVisionUnsupported(let provider):
            return "Nhà cung cấp hiện tại (\(provider)) không đọc được ảnh. Vào Cài đặt → Trợ lý AI đổi sang OpenAI hoặc Anthropic."
        case .ai(let msg):
            return "Lỗi gọi AI: \(msg)"
        case .aiRefused:
            return "AI từ chối yêu cầu này. Thử diễn đạt lại hoặc nhập tay."
        }
    }
}

extension Error {
    var vietnamese: String { (self as? LocalizedError)?.errorDescription ?? localizedDescription }
}
