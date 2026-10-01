import Foundation

/// Display formatting, same output as the web's lib/format.ts (comma thousands, "₫").
enum Fmt {
    private static func formatter(min: Int, max: Int) -> NumberFormatter {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "en_US")
        f.numberStyle = .decimal
        f.minimumFractionDigits = min
        f.maximumFractionDigits = max
        f.roundingMode = .halfUp
        return f
    }

    private static let integer = formatter(min: 0, max: 0)

    static func vnd(_ n: Double, compact: Bool = false, sign: Bool = false) -> String {
        let s = sign && n > 0 ? "+" : ""
        if compact {
            let a = abs(n)
            if a >= 1_000_000_000 { return "\(s)\(trim(n / 1_000_000_000)) tỷ" }
            if a >= 1_000_000 { return "\(s)\(trim(n / 1_000_000)) tr" }
            if a >= 1_000 { return "\(s)\(trim(n / 1_000))k" }
        }
        let rounded = (n + 0.5).rounded(.down)
        return "\(s)\(integer.string(from: NSNumber(value: rounded)) ?? "0") ₫"
    }

    static func number(_ n: Double, decimals: Int = 0) -> String {
        formatter(min: decimals, max: decimals).string(from: NSNumber(value: n)) ?? "0"
    }

    /// Group with commas, keep up to `dp` decimals.
    static func amount(_ n: Double, dp: Int = 2) -> String {
        formatter(min: 0, max: dp).string(from: NSNumber(value: n)) ?? "0"
    }

    static func percent(_ ratio: Double, decimals: Int = 1) -> String {
        let s = ratio > 0 ? "+" : ""
        return s + String(format: "%.\(decimals)f%%", ratio * 100)
    }

    /// Rate without sign, e.g. "5.45%".
    static func rate(_ ratio: Double, decimals: Int = 2) -> String {
        String(format: "%.\(decimals)f%%", ratio * 100)
    }

    static func date(_ iso: String) -> String { DateUtil.display(iso) }

    /// Quantity with sensible decimals (same rule as the web lists).
    static func quantity(_ q: Double) -> String {
        number(q, decimals: q < 1 ? 4 : (q == q.rounded() ? 0 : 2))
    }

    private static func trim(_ n: Double) -> String {
        let r = ((n * 10) + 0.5).rounded(.down) / 10
        return r == r.rounded() ? String(Int(r)) : String(r)
    }

    /// Parses user input like "1,250,000" or "59.3" (commas are thousand separators).
    static func parse(_ s: String) -> Double? {
        let cleaned = s.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: " ", with: "")
        guard !cleaned.isEmpty else { return nil }
        return Double(cleaned)
    }
}
