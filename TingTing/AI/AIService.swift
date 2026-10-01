import Foundation

/// AI features — prompts ported from the web API routes (app/api/ai/*). AI only reads/extracts;
/// every money figure is computed by code.
enum AIService {
    // MARK: - Chat

    static func chat(_ cfg: AIConfig, question: String, portfolio p: Portfolio) async throws -> String {
        let total = p.totalAssets()
        let cost = p.totalCost()
        let pl = total - cost
        var holdingLines: [String] = []
        for t in [AssetType.STOCK, .CRYPTO, .GOLD, .FUND] {
            for h in p.holdings(t) {
                holdingLines.append("- \(t.label) \(h.asset.symbol ?? h.asset.name): SL \(Fmt.amount(h.quantity, dp: 8)), giá vốn \(Fmt.vnd(h.avgCost)), giá \(Fmt.vnd(h.price)), giá trị \(Fmt.vnd(h.value)), lãi/lỗ \(Fmt.vnd(h.unrealizedPl)) (\(Fmt.percent(h.roi)))")
            }
        }
        let alloc = p.allocation().filter { $0.value > 0 }
        let facts = ([
            "Tổng tài sản: \(Fmt.vnd(total))",
            "Tổng vốn: \(Fmt.vnd(cost))",
            "Lãi/lỗ tổng: \(Fmt.vnd(pl)) (\(Fmt.percent(cost > 0 ? pl / cost : 0)))",
            "Tiết kiệm: \(Fmt.vnd(p.savingsValue()))",
            "Phân bổ:",
        ] + alloc.map { "- \($0.label): \(Fmt.vnd($0.value)) (\(String(format: "%.1f", total > 0 ? $0.value / total * 100 : 0))%)" }
          + ["Chi tiết nắm giữ:"] + (holdingLines.isEmpty ? ["- (không có)"] : holdingLines)).joined(separator: "\n")

        let system = [
            "Bạn là trợ lý tài chính cá nhân cho app Ting Ting.",
            "CHỈ dùng đúng các con số trong phần DỮ LIỆU dưới đây. TUYỆT ĐỐI không tự tính toán mới, không bịa số, không dự đoán.",
            "Nếu câu hỏi cần số liệu không có trong DỮ LIỆU, nói rõ là chưa có dữ liệu đó.",
            "Trả lời ngắn gọn, tiếng Việt, thân thiện. Không đưa lời khuyên đầu tư.",
            "",
            "DỮ LIỆU (hệ thống tính sẵn):",
            facts,
        ].joined(separator: "\n")
        return try await AIClient.complete(cfg, system: system, user: question)
    }

    // MARK: - Extraction (transactions / savings from text or a photo)

    struct ExtractedItem: Sendable {
        enum Kind: Sendable { case transaction, savings }
        var kind: Kind
        // transaction
        var assetClass: AssetType = .STOCK
        var type: TxType = .BUY
        var symbol: String?
        var quantity: Double?
        var price: Double?
        var priceCurrency: String?
        var totalValue: Double?
        var totalCurrency: String?
        var date: String?
        var note: String?
        // savings
        var institution: String?
        var principal: Double?
        var rate: Double?
        var termMonths: Double?
        var maturityDate: String?
        var confidence: [String: Double] = [:]
    }

    private static func known(_ assets: [Asset]) -> String {
        assets.compactMap { a in a.symbol.map { "\($0) (\(a.type.rawValue))" } }.joined(separator: ", ")
    }

    static func extract(_ cfg: AIConfig, text: String?, image: AIImage?, assets: [Asset]) async throws -> (items: [ExtractedItem], usdtRate: Double?) {
        let k = known(assets)
        let system = [
            "Bạn trích xuất TẤT CẢ các mục tài chính từ câu chữ hoặc ảnh (VN). Một ảnh/đoạn có thể chứa NHIỀU dòng: nhiều lệnh, NHIỀU coin/mã trong danh mục hoặc ví, và/hoặc nhiều sổ tiết kiệm.",
            "QUAN TRỌNG: Đọc HẾT, KHÔNG bỏ sót. MỖI mã cổ phiếu / MỖI coin / MỖI sổ là MỘT mục riêng trong 'items'. Nếu ảnh là danh mục/ví hiển thị nhiều coin (mỗi dòng có tên coin + số lượng + giá hoặc giá trị), tạo một mục transaction cho TỪNG coin.",
            "Chỉ TRÍCH XUẤT, KHÔNG tính toán (không tính thành tiền/tổng).",
            "Có 2 loại mục:",
            "- \"transaction\": {kind:\"transaction\", assetClass:\"STOCK|FUND|CRYPTO|GOLD\", type:\"BUY|SELL\", symbol, quantity, price, priceCurrency, totalValue, totalCurrency, date, confidence:{...}}. type chỉ BUY hoặc SELL.",
            "assetClass: mã 3 chữ cái VN như VCB/FPT/HPG là STOCK; BTC/ETH/DOGE là CRYPTO; SJC/vàng là GOLD; mã quỹ như VCBF-BCF là FUND.",
            "RẤT QUAN TRỌNG — phân biệt GIÁ MỖI ĐƠN VỊ và TỔNG:",
            "• Nếu nguồn ghi GIÁ 1 ĐƠN VỊ (giá 1 cổ / 1 coin / NAV 1 đơn vị quỹ) → điền \"price\" (per-unit), để totalValue=null.",
            "• Nếu nguồn CHỈ ghi TỔNG (thành tiền / tổng giá trị của lệnh, ví dụ lệnh quỹ ghi \"1.000.000đ - 23,94 đơn vị\") → điền \"totalValue\" = số tổng đó, \"totalCurrency\" (USDT/VND), và để \"price\"=null.",
            "• CRYPTO (RẤT QUAN TRỌNG): số USDT bên cạnh số coin là GIÁ TRỊ HIỆN TẠI của cả số coin, KHÔNG phải giá 1 coin. Ví dụ \"0.0083 BTC ≈ 633 USDT\" → quantity=0.0083, totalValue=633, totalCurrency=\"USDT\", price=null. Đừng bao giờ coi số USDT đó là giá của 1 coin.",
            "priceCurrency / totalCurrency: \"USDT\" nếu hiển thị theo USDT/$, ngược lại \"VND\". Chứng khoán/quỹ/vàng dùng VND.",
            "Chứng khoán VN giữ giá dạng nghìn đồng (vd 59.3). NAV quỹ và giá vàng ghi VND đầy đủ.",
            "- \"savings\" (sổ tiết kiệm): {kind:\"savings\", institution, principal, rate, termMonths, startDate, maturityDate, confidence:{...}}. termMonths = kỳ hạn số tháng (vd 6, 12). Nếu chỉ có ngày đáo hạn + kỳ hạn thì để startDate=null (hệ thống tự tính ngày gửi).",
            "Giá & số tiền tính bằng VND, giữ nguyên số ghi trong nguồn (chứng khoán VN giữ dạng nghìn đồng, vd 59.3). rate là lãi suất %/năm (vd 6.5). Ngày định dạng YYYY-MM-DD; thiếu để null.",
            k.isEmpty ? "" : "Các mã đang có của người dùng: \(k). Ưu tiên khớp symbol vào các mã này.",
            "confidence là 0..1 cho từng trường; không chắc thì null và confidence 0.",
            "Trả về DUY NHẤT một JSON: {\"items\":[ ...tất cả các mục... ]}. Không thêm chữ ngoài JSON. Nếu không thấy mục nào, trả {\"items\":[]}.",
        ].filter { !$0.isEmpty }.joined(separator: "\n")

        let userText = image != nil ? "Trích xuất tất cả các mục trong ảnh này." : text
        let out = try await AIClient.complete(cfg, system: system, user: userText, image: image)
        guard let obj = AIJSON.object(out) else { throw AppError.ai("AI không đọc được. Thử lại hoặc nhập tay.") }
        let raw = obj["items"] as? [[String: Any]] ?? []
        let items: [ExtractedItem] = raw.map(parseItem)

        let hasUsdt = items.contains {
            $0.kind == .transaction && $0.assetClass == .CRYPTO &&
                (($0.priceCurrency ?? "").uppercased() == "USDT" || ($0.totalCurrency ?? "").uppercased() == "USDT")
        }
        let rate: Double? = hasUsdt ? await PriceService.shared.usdToVnd() : nil
        return (items, rate)
    }

    private static func parseItem(_ d: [String: Any]) -> ExtractedItem {
        var conf: [String: Double] = [:]
        for (k, v) in d["confidence"] as? [String: Any] ?? [:] { conf[k] = AIJSON.double(v) ?? 0 }
        if (d["kind"] as? String) == "savings" {
            return ExtractedItem(kind: .savings, institution: AIJSON.string(d["institution"]),
                                 principal: AIJSON.double(d["principal"]), rate: AIJSON.double(d["rate"]),
                                 termMonths: AIJSON.double(d["termMonths"]), maturityDate: AIJSON.string(d["maturityDate"]),
                                 confidence: conf)
        }
        return ExtractedItem(
            kind: .transaction,
            assetClass: AssetType(rawValue: (d["assetClass"] as? String ?? "").uppercased()) ?? .STOCK,
            type: TxType(rawValue: (d["type"] as? String ?? "").uppercased()) ?? .BUY,
            symbol: AIJSON.string(d["symbol"])?.uppercased(),
            quantity: AIJSON.double(d["quantity"]),
            price: AIJSON.double(d["price"]),
            priceCurrency: AIJSON.string(d["priceCurrency"]),
            totalValue: AIJSON.double(d["totalValue"]),
            totalCurrency: AIJSON.string(d["totalCurrency"]),
            date: AIJSON.string(d["date"]),
            note: AIJSON.string(d["note"]),
            confidence: conf)
    }

    // MARK: - Prices (read from a photo, or look up by symbol)

    struct ReadPrice: Identifiable, Sendable {
        let id = UUID()
        var symbol: String
        var assetClass: AssetType
        var price: Double
        var currency: String

        /// Full VND (stock ×1000, USDT × rate).
        func vnd(usdtRate: Double?) -> Double {
            if assetClass == .STOCK { return price * 1000 }
            if assetClass == .CRYPTO && currency.uppercased() == "USDT" { return price * (usdtRate ?? 0) }
            return price
        }
    }

    static func prices(_ cfg: AIConfig, text: String?, image: AIImage?, assets: [Asset]) async throws -> (prices: [ReadPrice], usdtRate: Double?) {
        let k = known(assets)
        let system = [
            image != nil
                ? "Bạn đọc GIÁ HIỆN TẠI của các mã trong ảnh (bảng giá, app chứng khoán/quỹ, ví crypto)."
                : "Bạn TRA CỨU GIÁ HIỆN TẠI (hoặc giá đóng cửa gần nhất) trên internet của các mã người dùng hỏi. Với chứng khoán/quỹ VN, tìm trên Google/CafeF/nguồn tài chính. Dùng số mới nhất bạn tìm được.",
            "Chỉ TRÍCH XUẤT/tra cứu, không bịa. Mỗi mã một mục.",
            "Trả về DUY NHẤT JSON: {\"prices\":[{\"symbol\":..,\"assetClass\":\"STOCK|FUND|CRYPTO|GOLD\",\"price\":<số>,\"currency\":\"VND|USDT\"}]}",
            "price là giá 1 đơn vị hiện tại. Chứng khoán VN giữ dạng nghìn đồng (vd 59.3). NAV quỹ ghi VND đầy đủ. Crypto có thể USDT.",
            k.isEmpty ? "" : "Mã người dùng đang có: \(k). Ưu tiên khớp đúng các mã này.",
            "Nếu không tìm được mã nào, trả {\"prices\":[]}. Không thêm chữ ngoài JSON.",
        ].filter { !$0.isEmpty }.joined(separator: "\n")

        let out: String
        if let image {
            out = try await AIClient.complete(cfg, system: system, user: "Đọc giá hiện tại của các mã trong ảnh này.", image: image)
        } else {
            out = try await AIClient.lookup(cfg, system: system, user: text ?? "")
        }
        guard let obj = AIJSON.object(out) else { throw AppError.ai("AI không đọc được. Thử ảnh rõ hơn.") }
        let list: [ReadPrice] = (obj["prices"] as? [[String: Any]] ?? []).compactMap { d in
            guard let sym = AIJSON.string(d["symbol"]), let p = AIJSON.double(d["price"]), p > 0 else { return nil }
            return ReadPrice(symbol: sym.uppercased(),
                             assetClass: AssetType(rawValue: (d["assetClass"] as? String ?? "").uppercased()) ?? .STOCK,
                             price: p, currency: AIJSON.string(d["currency"]) ?? "VND")
        }
        let hasUsdt = list.contains { $0.assetClass == .CRYPTO && $0.currency.uppercased() == "USDT" }
        let rate: Double? = hasUsdt ? await PriceService.shared.usdToVnd() : nil
        return (list, rate)
    }
}
