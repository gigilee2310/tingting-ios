import SwiftUI

/// "Kho Bạc" design system from the web (globals.css), dark + light.
enum Theme {
    static let gold = Color.dynamic(light: 0xA9791F, dark: 0xC9A961)
    static let positive = Color.dynamic(light: 0x1A7F4B, dark: 0x4CAF7D)
    static let negative = Color.dynamic(light: 0xCF3B34, dark: 0xE5484D)
    static let background = Color.dynamic(light: 0xF4F5F7, dark: 0x0F1115)
    static let panel = Color.dynamic(light: 0xFFFFFF, dark: 0x171A20)
    static let panel2 = Color.dynamic(light: 0xEDEFF2, dark: 0x1D212A)
    static let muted = Color.dynamic(light: 0x6B7280, dark: 0x8B8F99)
    static let border = Color.primary.opacity(0.08)
    static let onGold = Color(hex: 0x17130A)
    static let warning = Color(hex: 0xE5A34C)

    static func accent(_ type: AssetType) -> Color {
        switch type {
        case .CASH: Color(hex: 0x6AA0C9)
        case .SAVINGS: Color(hex: 0xC9A961)
        case .STOCK: Color(hex: 0x4CAF7D)
        case .FUND: Color(hex: 0xE5A34C)
        case .CRYPTO: Color(hex: 0x7C8CF8)
        case .GOLD: Color(hex: 0xF5C542)
        }
    }

    static func pl(_ v: Double) -> Color { v >= 0 ? positive : negative }

    static let mono = Font.system(.body, design: .monospaced)
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }

    static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(Color(hex: dark)) : UIColor(Color(hex: light)) })
    }
}

extension Font {
    /// Ledger numbers: monospaced digits.
    static func money(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded).monospacedDigit()
    }
}
