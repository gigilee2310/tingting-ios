import Foundation

/// One held symbol whose price moved between two portfolio states (old price = last saved price).
struct PriceChange: Identifiable, Sendable {
    let symbol: String
    let type: AssetType
    let oldPrice: Double
    let newPrice: Double
    let quantity: Double

    var id: String { "\(type.rawValue)-\(symbol)" }
    var percent: Double { oldPrice > 0 ? (newPrice - oldPrice) / oldPrice : 0 }
    /// Change in the value of what you hold.
    var valueDelta: Double { Calc.round((newPrice - oldPrice) * quantity, 0) }

    static func compute(before: Portfolio, after: Portfolio) -> [PriceChange] {
        var out: [PriceChange] = []
        for type in [AssetType.STOCK, .FUND, .GOLD, .CRYPTO] {
            for h in after.holdings(type) {
                guard let sym = h.asset.symbol, let old = before.latestPrice(sym)?.price, old > 0 else { continue }
                if abs(h.price - old) / old < 0.0001 { continue }
                out.append(PriceChange(symbol: sym, type: type, oldPrice: old, newPrice: h.price, quantity: h.quantity))
            }
        }
        return out.sorted { abs($0.valueDelta) > abs($1.valueDelta) }
    }
}
