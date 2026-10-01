import Foundation

/// Data operations — direct ports of the web's server actions (app/actions/*.ts),
/// going straight to Supabase with the signed-in user's token (RLS).
struct Repository: Sendable {
    let db = SupabaseClient.shared
    let prices = PriceService.shared

    private func uid() async throws -> String { try await db.validSession().userId }

    // MARK: - Load

    func loadAll() async throws -> (PortfolioData, [DailySnapshot]) {
        let u = try await uid()
        async let assets = db.select("assets", Asset.self, query: [.eq("user_id", u)])
        async let txs = db.select("transactions", Transaction.self, query: [.eq("user_id", u)])
        async let sav = db.select("savings_accounts", SavingsAccount.self, query: [.eq("user_id", u)])
        async let mp = db.select("market_prices", MarketPrice.self, query: [URLQueryItem(name: "order", value: "date.desc")])
        async let snaps = db.select("daily_snapshots", DailySnapshot.self,
                                    query: [.eq("user_id", u), URLQueryItem(name: "order", value: "date.asc")])
        let data = try await PortfolioData(assets: assets, transactions: txs, savingsAccounts: sav, marketPrices: mp)
        let snapshots = (try? await snaps) ?? []
        return (data, snapshots)
    }

    // MARK: - Settings (user_settings, shared with the web)

    func loadSettings() async throws -> UserSettings? {
        let u = try await uid()
        return try await db.select("user_settings", UserSettings.self, query: [.eq("user_id", u)]).first
    }

    func saveSettings(provider: AIProvider, model: String?, apiKey: String?) async throws {
        let u = try await uid()
        var row: [String: Any] = ["user_id": u, "ai_provider": provider.rawValue,
                                  "ai_model": (model?.isEmpty ?? true) ? NSNull() as Any : model! as Any,
                                  "updated_at": ISO8601DateFormatter().string(from: Date())]
        // Blank key = keep the existing one (same as the web).
        if let apiKey, !apiKey.isEmpty { row["ai_api_key"] = apiKey }
        try await db.upsert("user_settings", [row], onConflict: "user_id")
    }

    // MARK: - Transactions & assets

    /// One transaction. `priceVnd` (full VND) wins over `rawPrice` (entered unit).
    func addTransaction(assetId: String, assetType: AssetType, type: TxType, quantity: Double, rawPrice: Double,
                        priceVnd: Double? = nil, fee: Double = 0, tax: Double = 0, date: String,
                        source: String = "manual") async throws {
        let price = (priceVnd ?? 0) > 0 ? priceVnd! : rawPrice * Calc.priceUnit(assetType)
        guard quantity > 0, price > 0 else { throw AppError.validation("Thiếu tài sản, số lượng hoặc giá.") }
        let u = try await uid()
        let total = Calc.transactionTotal(type: type, quantity: quantity, price: price, fee: fee, tax: tax)
        try await db.insert("transactions", [[
            "user_id": u, "asset_id": assetId, "type": type.rawValue, "quantity": quantity, "price": price,
            "fee": fee, "tax": tax, "total": total, "date": date, "source": source, "status": "confirmed",
        ]])
    }

    /// Creates an asset; optional initial market price. Returns the new id.
    @discardableResult
    func createAsset(type: AssetType, name: String, symbol: String?, institution: String? = nil, price: Double = 0) async throws -> String {
        let sym = symbol?.trimmingCharacters(in: .whitespaces).uppercased()
        let symbolValue = (sym?.isEmpty ?? true) ? nil : sym
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { throw AppError.validation("Cần nhập tên tài sản.") }
        if type != .CASH && symbolValue == nil { throw AppError.validation("Cần nhập mã (symbol).") }
        let u = try await uid()
        let rows = try await db.insert("assets", [[
            "user_id": u, "type": type.rawValue, "symbol": symbolValue.map { $0 as Any } ?? NSNull(), "name": name,
            "institution": institution.map { $0 as Any } ?? NSNull(), "currency": "VND",
        ]])
        guard let id = rows.first?["id"] as? String else { throw AppError.badResponse }
        if let s = symbolValue, price > 0 { try await saveReadPrices([(s, price)]) }
        return id
    }

    private func findOrCreateAsset(type: AssetType, symbol: String, name: String, institution: String? = nil) async throws -> String {
        let u = try await uid()
        let existing = try await db.select("assets", Asset.self,
                                           query: [.eq("user_id", u), .eq("type", type.rawValue), .eq("symbol", symbol)])
        if let a = existing.first { return a.id }
        return try await createAsset(type: type, name: name, symbol: symbol, institution: institution)
    }

    /// Manual BUY/SELL for stock/crypto/fund; finds or creates the asset by symbol.
    func createTrade(type: AssetType, symbol rawSymbol: String, txType: TxType, quantity: Double, rawPrice: Double,
                     priceVnd: Double? = nil, date: String) async throws -> String {
        let symbol = rawSymbol.trimmingCharacters(in: .whitespaces).uppercased()
        guard [.STOCK, .CRYPTO, .FUND].contains(type) else { throw AppError.validation("Loại không hợp lệ.") }
        guard !symbol.isEmpty else { throw AppError.validation("Cần nhập mã.") }
        guard quantity > 0, rawPrice > 0 || (priceVnd ?? 0) > 0 else { throw AppError.validation("Cần số lượng và giá.") }
        let assetId = try await findOrCreateAsset(type: type, symbol: symbol, name: symbol)
        try await addTransaction(assetId: assetId, assetType: type, type: txType, quantity: quantity, rawPrice: rawPrice,
                                 priceVnd: priceVnd, date: date)
        return "Đã ghi lệnh \(txType == .BUY ? "MUA" : "BÁN") \(symbol)."
    }

    /// Gold: quantity in chỉ/phân/lượng/cây at a price per chỉ.
    func createGold(symbol rawSymbol: String = "SJC", unit: GoldUnit, quantity: Double, pricePerChi: Double, date: String) async throws -> String {
        let trimmed = rawSymbol.trimmingCharacters(in: .whitespaces).uppercased()
        let symbol = trimmed.isEmpty ? "SJC" : trimmed
        guard quantity > 0 else { throw AppError.validation("Số lượng phải lớn hơn 0.") }
        guard pricePerChi > 0 else { throw AppError.validation("Cần giá vàng (mỗi chỉ).") }
        let qtyChi = quantity * unit.chi
        let assetId = try await findOrCreateAsset(type: .GOLD, symbol: symbol, name: "Vàng \(symbol)", institution: "SJC")
        try await addTransaction(assetId: assetId, assetType: .GOLD, type: .BUY, quantity: qtyChi, rawPrice: pricePerChi, date: date)
        try await saveReadPrices([(symbol, pricePerChi)])
        return "Đã thêm \(Fmt.amount(quantity)) \(unit.label.lowercased()) vàng \(symbol)."
    }

    /// Savings account (+ its backing asset). `ratePercent` like 5.45.
    func createSavings(institution: String, principal: Double, ratePercent: Double, maturityDate: String,
                       termMonths: Int, autoRenew: Bool) async throws -> String {
        let inst = institution.trimmingCharacters(in: .whitespaces)
        guard !inst.isEmpty else { throw AppError.validation("Cần nhập ngân hàng.") }
        guard principal > 0 else { throw AppError.validation("Gốc phải lớn hơn 0.") }
        guard !maturityDate.isEmpty else { throw AppError.validation("Cần ngày đáo hạn.") }
        // Deposit date = maturity − term when given, otherwise today.
        let startDate = termMonths > 0 ? DateUtil.addMonths(maturityDate, -termMonths) : DateUtil.today
        let u = try await uid()
        let rows = try await db.insert("assets", [[
            "user_id": u, "type": "SAVINGS", "name": "Sổ \(inst)", "institution": inst, "currency": "VND",
        ]])
        guard let assetId = rows.first?["id"] as? String else { throw AppError.badResponse }
        try await db.insert("savings_accounts", [[
            "user_id": u, "asset_id": assetId, "institution": inst, "principal": principal,
            "rate": ratePercent / 100, "start_date": startDate, "maturity_date": maturityDate, "auto_renew": autoRenew,
        ]])
        return "Đã tạo sổ tiết kiệm \(inst)."
    }

    func updateSavingsRenew(id: String, autoRenew: Bool) async throws {
        let u = try await uid()
        try await db.update("savings_accounts", ["auto_renew": autoRenew], filters: [.eq("id", id), .eq("user_id", u)])
    }

    // MARK: - Delete (needs the delete policies from migration-4)

    /// Without a DELETE policy PostgREST silently deletes 0 rows, so the asset delete checks the count.
    func deleteAsset(_ id: String) async throws {
        let u = try await uid()
        try await mapRLS {
            try await db.delete("transactions", filters: [.eq("asset_id", id), .eq("user_id", u)])
            try await db.delete("savings_accounts", filters: [.eq("asset_id", id), .eq("user_id", u)])
            let n = try await db.deleteCount("assets", filters: [.eq("id", id), .eq("user_id", u)])
            if n == 0 { throw AppError.server(403, "row-level security") }
        }
    }

    func deleteSavings(_ s: SavingsAccount) async throws {
        try await deleteAsset(s.assetId)
    }

    func resetAll(expectedAssets: Int) async throws {
        let u = try await uid()
        try await mapRLS {
            try await db.delete("transactions", filters: [.eq("user_id", u)])
            try await db.delete("savings_accounts", filters: [.eq("user_id", u)])
            let n = try await db.deleteCount("assets", filters: [.eq("user_id", u)])
            if n == 0, expectedAssets > 0 { throw AppError.server(403, "row-level security") }
        }
    }

    // MARK: - Prices (shared market_prices table; needs migration-4 write policy)

    func saveReadPrices(_ entries: [(symbol: String, priceVnd: Double)]) async throws {
        let today = DateUtil.today
        let rows: [[String: Any]] = entries.filter { !$0.symbol.isEmpty && $0.priceVnd > 0 }.map {
            ["symbol": $0.symbol.uppercased(), "price": ($0.priceVnd + 0.5).rounded(.down), "currency": "VND",
             "date": today, "is_stale": false]
        }
        guard !rows.isEmpty else { throw AppError.validation("Không có giá hợp lệ để lưu.") }
        try await mapRLS { try await db.upsert("market_prices", rows, onConflict: "symbol,date") }
    }

    enum PriceClass: String, CaseIterable {
        case STOCK, FUND, GOLD, CRYPTO, USDT

        var label: String {
            switch self {
            case .STOCK: "Chứng khoán"
            case .FUND: "Quỹ"
            case .GOLD: "Vàng"
            case .CRYPTO: "Crypto"
            case .USDT: "USDT"
            }
        }

        var assetType: AssetType? {
            switch self {
            case .STOCK: .STOCK
            case .FUND: .FUND
            case .GOLD: .GOLD
            case .CRYPTO: .CRYPTO
            case .USDT: nil
            }
        }
    }

    /// Fetches today's prices for one class and saves them to market_prices.
    /// Stocks: SSI by symbol · Funds: Fmarket NAV · Gold: PNJ domestic BUY price (world spot as fallback)
    /// · Crypto: Binance × USD rate · USDT: the rate itself.
    func updatePrices(_ cls: PriceClass, assets: [Asset]) async throws -> (message: String, updated: [(String, Double)]) {
        guard let type = cls.assetType else {
            let r = (await prices.usdToVnd() + 0.5).rounded(.down)
            try? await saveReadPrices([("USDT", r)])
            return ("Tỷ giá hôm nay: 1 USDT ≈ \(Fmt.amount(r, dp: 0)) ₫.", [("1 USDT", r)])
        }
        let symbols = Array(Set(assets.filter { $0.type == type }.compactMap { $0.symbol?.uppercased() })).sorted()
        guard !symbols.isEmpty else { return ("Chưa có mã \(cls.label.lowercased()) nào để cập nhật.", []) }

        var updated: [(String, Double)] = []
        var errs: [String] = []
        switch cls {
        case .STOCK:
            let svc = prices
            let results = await withTaskGroup(of: (String, Double?).self) { group -> [(String, Double?)] in
                for s in symbols { group.addTask { (s, await svc.vnStock(s)) } }
                var out: [(String, Double?)] = []
                for await r in group { out.append(r) }
                return out
            }
            for (s, p) in results {
                if let p { updated.append((s, p)) } else { errs.append("\(s) (không thấy trên SSI)") }
            }
        case .FUND:
            let navs = await prices.fundNAVs()
            if navs.isEmpty {
                throw AppError.validation("Không lấy được NAV quỹ từ Fmarket (nguồn tạm lỗi). Sửa giá tay trong mã.")
            }
            for s in symbols {
                if let nav = navs[s] { updated.append((s, (nav + 0.5).rounded(.down))) } else { errs.append("\(s) (không có trên Fmarket)") }
            }
        case .GOLD:
            let domestic = await prices.domesticGold()
            let sjc = domestic["SJC"]?.buy
            var world: Double?
            for s in symbols {
                if let p = domestic[s]?.buy ?? sjc {
                    updated.append((s, p))
                } else {
                    if world == nil { world = await prices.goldVndPerChi() }
                    if let w = world, w > 0 { updated.append((s, w)) } else { errs.append("\(s) (không lấy được giá)") }
                }
            }
        default:
            let rate = await prices.usdToVnd()
            for s in symbols {
                if let usdt = await prices.binanceUSDT(s) {
                    updated.append((s, (usdt * rate + 0.5).rounded(.down)))
                } else {
                    errs.append("\(s) (không có trên Binance)")
                }
            }
        }
        updated.sort { $0.0 < $1.0 }
        if !updated.isEmpty { try await saveReadPrices(updated.map { ($0.0, $0.1) }) }
        if updated.isEmpty { throw AppError.validation("Không cập nhật được: \(errs.joined(separator: ", "))") }
        let tail = errs.isEmpty ? "" : " · chưa được: \(errs.joined(separator: ", "))"
        return ("Đã cập nhật \(updated.count) mã \(cls.label.lowercased())\(tail).", updated)
    }

    /// Refreshes every market-priced class (stocks, funds, gold, crypto). Errors are collected, not thrown.
    func updateAllPrices(assets: [Asset]) async -> [String] {
        var notes: [String] = []
        for cls in [PriceClass.STOCK, .FUND, .GOLD, .CRYPTO] where assets.contains(where: { $0.type == cls.assetType }) {
            do { notes.append(try await updatePrices(cls, assets: assets).message) } catch { notes.append(error.vietnamese) }
        }
        return notes
    }

    // MARK: - Snapshots

    /// Records today's net worth so the chart builds real history (one row per day).
    func upsertSnapshot(_ s: DailySnapshot) async throws {
        let u = try await uid()
        try await db.upsert("daily_snapshots", [[
            "user_id": u, "date": s.date, "cash_value": s.cashValue, "savings_value": s.savingsValue,
            "stock_value": s.stockValue, "fund_value": s.fundValue, "crypto_value": s.cryptoValue,
            "total_value": s.totalValue,
        ]], onConflict: "user_id,date")
    }

    // MARK: - Helpers

    /// Turns RLS rejections into a Vietnamese hint about the one-time SQL migration.
    private func mapRLS(_ work: () async throws -> Void) async throws {
        do {
            try await work()
        } catch AppError.server(let code, let msg) where code == 401 || code == 403 || msg.contains("row-level security") {
            throw AppError.validation("Supabase chưa cho phép app làm thao tác này. Chạy file supabase/migration-4-mobile-app.sql một lần trong Supabase → SQL Editor (xem README).")
        }
    }
}
