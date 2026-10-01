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

    // MARK: - Vietnam market (unofficial public endpoints — may change; callers keep old prices on failure)

    /// Last matched price of a VN stock in full VND, from SSI iBoard (falls back to the reference price
    /// before the session opens).
    func vnStock(_ symbol: String) async -> Double? {
        let s = symbol.uppercased().addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? symbol
        guard let j = await json("https://iboard-query.ssi.com.vn/stock/\(s)"),
              let d = j["data"] as? [String: Any] else { return nil }
        for key in ["matchedPrice", "lastMatchedPrice", "refPrice", "priorClosePrice"] {
            if let p = (d[key] as? NSNumber)?.doubleValue, p > 0 { return p }
        }
        return nil
    }

    /// NAV per unit of all open-ended funds on Fmarket, keyed by upper-cased short name / code.
    func fundNAVs() async -> [String: Double] {
        let body: [String: Any] = [
            "types": ["NEW_FUND", "TRADING_FUND"], "issuerIds": [String](), "sortOrder": "DESC", "sortField": "navTo6Months",
            "page": 1, "pageSize": 200, "isIpo": false, "fundAssetTypes": [String](), "bondRemainPeriods": [String](),
            "searchField": "", "isBuyByReward": false, "thirdAppIds": [String](),
        ]
        guard let j = await json("https://api.fmarket.vn/res/products/filter", body: body),
              let data = j["data"] as? [String: Any],
              let rows = data["rows"] as? [[String: Any]] else { return [:] }
        var out: [String: Double] = [:]
        for r in rows {
            guard let nav = (r["nav"] as? NSNumber)?.doubleValue, nav > 0 else { continue }
            for key in ["shortName", "code"] {
                if let k = (r[key] as? String)?.uppercased(), !k.isEmpty { out[k] = nav }
            }
        }
        return out
    }

    /// Domestic gold prices from PNJ in VND per chỉ: product code (SJC, N24K, PNJ…) → (buy, sell).
    /// PNJ quotes thousands of đồng per chỉ.
    func domesticGold() async -> [String: (buy: Double, sell: Double)] {
        guard let j = await json("https://edge-api.pnj.io/ecom-frontend/v1/get-gold-price?zone=00"),
              let rows = j["data"] as? [[String: Any]] else { return [:] }
        var out: [String: (buy: Double, sell: Double)] = [:]
        for r in rows {
            guard let code = (r["masp"] as? String)?.uppercased(),
                  let buy = (r["giamua"] as? NSNumber)?.doubleValue, buy > 0 else { continue }
            let sell = (r["giaban"] as? NSNumber)?.doubleValue ?? buy
            out[code] = (buy * 1000, sell * 1000)
        }
        return out
    }

    private func json(_ urlString: String, body: [String: Any]? = nil) async -> [String: Any]? {
        guard let url = URL(string: urlString) else { return nil }
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")
        if let body {
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }
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
