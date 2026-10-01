import Foundation

/// Reads the expiry date of the free-Apple-ID signature (embedded.mobileprovision) so the app
/// can remind the user to re-install with Sideloadly before it stops opening.
enum ProvisioningInfo {
    static let expirationDate: Date? = {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let raw = try? Data(contentsOf: url),
              let text = String(data: raw, encoding: .isoLatin1),
              let start = text.range(of: "<?xml"),
              let end = text.range(of: "</plist>") else { return nil }
        let xml = String(text[start.lowerBound..<end.upperBound])
        guard let data = xml.data(using: .isoLatin1),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return nil }
        return plist["ExpirationDate"] as? Date
    }()

    static var daysLeft: Int? {
        guard let d = expirationDate else { return nil }
        return Int((d.timeIntervalSinceNow / 86_400).rounded(.down))
    }

    /// Shown on Home when ≤ 2 days remain.
    static var expiryWarning: String? {
        guard let days = daysLeft, days <= 2 else { return nil }
        return days <= 0
            ? "App hết hạn trong hôm nay. Cắm iPhone vào máy tính và cài lại bằng Sideloadly để tiếp tục dùng."
            : "App còn \(days) ngày nữa là hết hạn. Nhớ cài lại bằng Sideloadly (dữ liệu vẫn giữ nguyên)."
    }

    static var expiryText: String {
        guard let d = expirationDate else { return "Không rõ" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "vi_VN")
        f.dateFormat = "HH:mm dd/MM/yyyy"
        return f.string(from: d) + (daysLeft.map { " (còn \(max(0, $0)) ngày)" } ?? "")
    }
}
