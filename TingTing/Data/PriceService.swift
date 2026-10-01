import Foundation

/// Free, keyless market data — same sources as the web app (lib/fx.ts, lib/gold.ts, Binance).
actor PriceService {
    static let shared = PriceService()

    private var fxCache: (rate: Double, at: Date)?
    static let fallbackRate = 26_000.0

    /// USD→VND (USDT ≈ USD), cached 6h, falls back to a sane constant.
    func usdToVnd() async -> Double {
        if let c = fxCache, Date().timeIntervalSince(c.at) < 6 * 3600 { return c.rate }
        if let j = await json("https://open.er-api.com/v6/latest/USD"),
           let rates = j["rates"] as? [String: Any],
           let rate = (rates["VND"] as? NSNumber)?.doubleValue, rate > 1000 {
            fxCache = (rate, Date())
            return rate
        }
        return fxCache?.rate ?? Self.fallbackRate
    }

    /// World gold spot converted to VND per "chỉ" (3.75 g). 0 if unavailable.
    func goldVndPerChi() async -> Double {
        guard let j = await json("https://api.gold-api.com/price/XAU"),
              let usdPerOz = (j["price"] as? NSNumber)?.doubleValue, usdPerOz > 0 else { return 0 }
        let rate = await usdToVnd()
        return ((usdPerOz / 31.1035) * rate * 3.75 + 0.5).rounded(.down)
    }

    /// Binance spot price in USDT, nil if the pair doesn't exist.
    func binanceUSDT(_ symbol: String) async -> Double? {
        let s = symbol.uppercased().addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? symbol
        // data-api.binance.vision is the public market-data mirror (not geo-blocked like api.binance.com)
        guard let j = await json("https://data-api.binance.vision/api/v3/ticker/price?symbol=\(s)USDT"),
              let p = (j["price"] as? String).flatMap({ Double($0) }), p > 0 else { return nil }
        return p
    }

    private func json(_ urlString: String) async -> [String: Any]? {
        guard let url = URL(string: urlString) else { return nil }
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        guard let result = try? await URLSession.shared.data(for: req),
              (result.1 as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try? JSONSerialization.jsonObject(with: result.0) as? [String: Any]
    }
}

enum GoldUnit: String, CaseIterable, Identifiable {
    case chi, phan, luong, cay

    var id: String { rawValue }

    var label: String {
        switch self {
        case .chi: "Chỉ"
        case .phan: "Phân"
        case .luong: "Lượng"
        case .cay: "Cây"
        }
    }

    var chi: Double {
        switch self {
        case .chi: 1
        case .phan: 0.1
        case .luong, .cay: 10
        }
    }
}
