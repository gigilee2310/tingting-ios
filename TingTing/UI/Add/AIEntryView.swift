import SwiftUI

/// AI extraction → multi-item review → save (web: components/ai-entry.tsx).
struct AIEntryView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State var startWithImage: Bool

    @State private var text = ""
    @State private var image: UIImage?
    @State private var loading = false
    @State private var error: String?
    @State private var review: ReviewState?

    var body: some View {
        Group {
            if let review {
                ReviewView(state: review) { self.review = nil }
            } else {
                input
            }
        }
        .background(Theme.background)
        .navigationTitle(startWithImage ? "Chụp ảnh lệnh" : "Hỏi AI")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Đóng") { dismiss() } } }
    }

    private var input: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Picker("Cách nhập", selection: $startWithImage) {
                    Label("Mô tả", systemImage: "text.bubble").tag(false)
                    Label("Ảnh lệnh", systemImage: "camera").tag(true)
                }
                .pickerStyle(.segmented)

                if store.aiConfig == nil {
                    Disclaimer(AppError.aiNotConfigured.vietnamese)
                } else if startWithImage {
                    imageInput
                } else {
                    TextEditor(text: $text)
                        .frame(minHeight: 120)
                        .scrollContentBackground(.hidden)
                        .fieldStyle()
                        .overlay(alignment: .topLeading) {
                            if text.isEmpty {
                                Text("Có thể nhiều dòng, vd:\n\"Mua 200 VCB giá 93.200\nBán 50 FPT giá 135.000\"")
                                    .foregroundStyle(Theme.muted).padding(16).allowsHitTesting(false)
                            }
                        }
                    PrimaryButton(title: loading ? "Đang đọc…" : "AI trích xuất", busy: loading,
                                  disabled: text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                        Task { await run(text: text, image: nil) }
                    }
                }

                if let error { ErrorBox(text: error) }
                Disclaimer("AI chỉ đọc & trích xuất. Mọi con số tiền do hệ thống tính, và bạn luôn xác nhận trước khi lưu.")
            }
            .padding(16)
        }
    }

    @ViewBuilder private var imageInput: some View {
        if let cfg = store.aiConfig, !cfg.provider.supportsVision {
            Disclaimer(AppError.aiVisionUnsupported(cfg.provider.label).vietnamese + " DeepSeek chỉ đọc mô tả bằng chữ.")
        } else if let image {
            Image(uiImage: image)
                .resizable().scaledToFit()
                .frame(maxHeight: 280)
                .frame(maxWidth: .infinity)
                .background(Theme.panel2, in: RoundedRectangle(cornerRadius: 12))
            HStack(spacing: 10) {
                SecondaryButton(title: "Huỷ") { self.image = nil }.disabled(loading)
                PrimaryButton(title: loading ? "Đang đọc…" : "Quét ảnh này", busy: loading) {
                    Task { await run(text: nil, image: image) }
                }
            }
        } else {
            ImagePickerButtons { image = $0 }
            Text("Xem trước ảnh rồi bấm Quét (hoặc Huỷ để chọn ảnh khác). Ảnh có thể chứa nhiều mục — AI đọc hết.")
                .font(.caption).foregroundStyle(Theme.muted)
        }
    }

    private func run(text: String?, image: UIImage?) async {
        guard let cfg = store.aiConfig else { return }
        loading = true
        error = nil
        defer { loading = false }
        do {
            let ai = image?.aiImage()
            let (items, rate) = try await AIService.extract(cfg, text: text, image: ai, assets: store.portfolio.assets)
            if items.isEmpty {
                error = "AI không tìm thấy mục nào. Thử ảnh rõ hơn hoặc nhập tay."
            } else {
                review = ReviewState(items: items, usdtRate: rate, assets: store.portfolio.assets)
            }
        } catch {
            self.error = error.vietnamese
        }
    }
}

// MARK: - Review model

struct EditItem: Identifiable {
    enum Kind { case transaction, savings }
    let id = UUID()
    var kind: Kind
    var include = true
    // transaction
    var assetId = ""  // real id, "" or "__new__"
    var assetClass = AssetType.STOCK
    var symbol = ""
    var type = TxType.BUY
    var quantity = ""
    var price = ""  // per-unit price, or total value when valueMode
    var priceCurrency = "VND"
    var valueMode = false  // crypto: the field is the total current value
    var date = ""
    var note: String?
    // savings
    var institution = ""
    var principal = ""
    var rate = ""
    var termMonths = ""
    var maturityDate = ""
    var confidence: [String: Double] = [:]

    func warn(_ key: String) -> Bool { (confidence[key] ?? 1) < 0.75 }
}

struct ReviewState {
    var edits: [EditItem]
    let usdtRate: Double?
    let rawCount: Int

    init(items: [AIService.ExtractedItem], usdtRate: Double?, assets: [Asset]) {
        self.usdtRate = usdtRate
        rawCount = items.count
        let today = DateUtil.localDay(Date())
        edits = items.map { it in
            if it.kind == .savings {
                return EditItem(kind: .savings,
                                institution: it.institution ?? "",
                                principal: it.principal.map { Self.str($0) } ?? "",
                                rate: it.rate.map { Self.str($0) } ?? "",
                                termMonths: it.termMonths.map { String(Int($0)) } ?? "",
                                maturityDate: it.maturityDate ?? "",
                                confidence: it.confidence)
            }
            let cls = it.assetClass
            let qty = it.quantity ?? 0
            let valueMode = cls == .CRYPTO
            var fieldVal: Double?
            var fieldCur: String
            if valueMode {
                fieldVal = it.totalValue ?? it.price
                fieldCur = it.totalCurrency ?? it.priceCurrency ?? "USDT"
            } else {
                fieldVal = it.price
                fieldCur = it.priceCurrency ?? "VND"
                if (fieldVal ?? 0) == 0, let tv = it.totalValue, qty > 0 {
                    fieldVal = tv / qty
                    fieldCur = it.totalCurrency ?? fieldCur
                }
            }
            let matched = it.symbol.flatMap { sym in assets.first { $0.symbol?.uppercased() == sym.uppercased() } }
            return EditItem(kind: .transaction,
                            assetId: matched?.id ?? (it.symbol != nil ? "__new__" : ""),
                            assetClass: cls, symbol: it.symbol ?? "", type: it.type,
                            quantity: it.quantity.map { Self.str($0) } ?? "",
                            price: fieldVal.map { Self.str($0) } ?? "", priceCurrency: fieldCur,
                            valueMode: valueMode, date: it.date ?? today, note: it.note, confidence: it.confidence)
        }
    }

    static func str(_ d: Double) -> String {
        d == d.rounded() && abs(d) < 1e15 ? String(Int64(d)) : String(d)
    }

    /// Multiplier from the entered per-unit price to full VND.
    static func vndMult(_ cls: AssetType, _ currency: String, _ usdtRate: Double?) -> Double {
        if cls == .STOCK { return 1000 }
        if cls == .CRYPTO && currency.uppercased() == "USDT" { return usdtRate ?? 1 }
        return 1
    }

    /// Code-computed total (VND) shown on each card.
    func total(_ e: EditItem) -> Double {
        let val = Fmt.parse(e.price) ?? 0
        let isUsdt = e.priceCurrency.uppercased() == "USDT"
        if e.valueMode { return (val * (isUsdt ? (usdtRate ?? 0) : 1)).rounded() }
        return Calc.transactionTotal(type: e.type, quantity: Fmt.parse(e.quantity) ?? 0,
                                     price: val * Self.vndMult(e.assetClass, e.priceCurrency, usdtRate))
    }
}

// MARK: - Review UI

struct ReviewView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State var state: ReviewState
    var onBack: () -> Void

    @State private var saving = false
    @State private var result: (ok: Int, fail: Int, errors: [String])?

    var body: some View {
        if let result {
            VStack(spacing: 14) {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 48)).foregroundStyle(Theme.positive)
                Text("Đã lưu \(result.ok) mục").font(.headline)
                if result.fail > 0 {
                    Text("\(result.fail) mục lỗi: \(result.errors.joined(separator: "; "))")
                        .font(.footnote).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
                }
                PrimaryButton(title: "Xong") { dismiss() }
            }
            .card(padding: 24)
            .padding(16)
        } else {
            list
        }
    }

    private var list: some View {
        let chosen = state.edits.filter(\.include).count
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    SectionTitle("AI đọc được \(state.rawCount) mục — kiểm tra lại")
                    Text("Bỏ chọn mục không muốn lưu; sửa ô có ⚠.").font(.footnote).foregroundStyle(Theme.muted)
                    if let r = state.usdtRate {
                        Text("Giá coin để theo USDT; tổng tính ra VND theo tỷ giá hôm nay 1 USDT ≈ \(Fmt.amount(r, dp: 0)) ₫")
                            .font(.caption).foregroundStyle(Theme.muted)
                    }
                }
                .card()

                ForEach($state.edits) { $e in
                    if e.kind == .transaction {
                        TxCard(e: $e, total: state.total(e), usdtRate: state.usdtRate, assets: store.portfolio.assets)
                    } else {
                        SavCard(e: $e)
                    }
                }

                HStack(spacing: 10) {
                    SecondaryButton(title: "Làm lại", action: onBack)
                    PrimaryButton(title: saving ? "Đang lưu…" : "Lưu \(chosen) mục", busy: saving, disabled: chosen == 0) {
                        Task { await saveAll() }
                    }
                }
            }
            .padding(16)
        }
    }

    private func saveAll() async {
        saving = true
        defer { saving = false }
        var ok = 0
        var errors: [String] = []
        let repo = store.repo
        for e in state.edits where e.include {
            do {
                if e.kind == .transaction {
                    let qty = Fmt.parse(e.quantity) ?? 0
                    let val = Fmt.parse(e.price) ?? 0
                    guard qty > 0, val > 0 else { throw AppError.validation("thiếu số lượng/giá") }
                    var assetId = e.assetId
                    if assetId == "__new__" {
                        guard !e.symbol.isEmpty else { throw AppError.validation("thiếu mã để tạo tài sản") }
                        assetId = try await repo.createAsset(type: e.assetClass, name: e.symbol, symbol: e.symbol)
                    }
                    guard !assetId.isEmpty else { throw AppError.validation("chưa chọn tài sản") }
                    let isUsdt = e.priceCurrency.uppercased() == "USDT"
                    let priceVnd = e.valueMode
                        ? val * (isUsdt ? (state.usdtRate ?? 0) : 1) / qty  // total value → per-unit
                        : val * ReviewState.vndMult(e.assetClass, e.priceCurrency, state.usdtRate)
                    try await repo.addTransaction(assetId: assetId, assetType: e.assetClass, type: e.type, quantity: qty,
                                                  rawPrice: val, priceVnd: priceVnd, date: e.date.isEmpty ? DateUtil.localDay(Date()) : e.date,
                                                  source: "ai")
                } else {
                    guard !e.institution.isEmpty, (Fmt.parse(e.principal) ?? 0) > 0 else {
                        throw AppError.validation("thiếu ngân hàng/gốc")
                    }
                    _ = try await repo.createSavings(institution: e.institution, principal: Fmt.parse(e.principal) ?? 0,
                                                     ratePercent: Fmt.parse(e.rate) ?? 0, maturityDate: e.maturityDate,
                                                     termMonths: Int(Fmt.parse(e.termMonths) ?? 0), autoRenew: true)
                }
                ok += 1
            } catch {
                let name = e.kind == .transaction ? (e.symbol.isEmpty ? "Lệnh" : e.symbol) : (e.institution.isEmpty ? "Sổ" : e.institution)
                errors.append("\(name): \(error.vietnamese)")
            }
        }
        await store.reload()
        try? await repo.upsertSnapshot(store.portfolio.snapshot())
        result = (ok, errors.count, errors)
    }
}

private struct CardHead: View {
    let label: String
    @Binding var on: Bool
    var body: some View {
        Toggle(isOn: $on) { Text(label).fontWeight(.semibold) }
    }
}

private struct TxCard: View {
    @Binding var e: EditItem
    let total: Double
    let usdtRate: Double?
    let assets: [Asset]

    var body: some View {
        let isUsdt = e.priceCurrency.uppercased() == "USDT"
        let options = assets.filter { $0.type == e.assetClass }
        let priceLabel = e.valueMode ? (isUsdt ? "Giá trị hiện tại (USDT)" : "Giá trị hiện tại (₫)")
            : e.assetClass == .STOCK ? "Giá (nghìn đ)" : e.assetClass == .FUND ? "NAV (₫)" : "Giá (₫)"
        VStack(alignment: .leading, spacing: 10) {
            CardHead(label: "Lệnh \(e.assetClass.shortLabel) · \(e.symbol.isEmpty ? "?" : e.symbol)", on: $e.include)
            Field(label: "Tài sản", warn: e.warn("symbol")) {
                Picker("Tài sản", selection: $e.assetId) {
                    Text("— Chọn tài sản —").tag("")
                    if !e.symbol.isEmpty { Text("➕ Tạo mã mới “\(e.symbol)” (\(e.assetClass.shortLabel))").tag("__new__") }
                    ForEach(options) { a in Text("\(a.symbol.map { "\($0) · " } ?? "")\(a.name)").tag(a.id) }
                }
                .pickerStyle(.menu)
                .fieldStyle()
                if e.assetId == "__new__" {
                    Text("Sẽ tự tạo mã “\(e.symbol)” khi lưu.").font(.caption).foregroundStyle(Theme.muted)
                }
            }
            Picker("Loại", selection: $e.type) {
                Text("Mua").tag(TxType.BUY)
                Text("Bán").tag(TxType.SELL)
            }
            .pickerStyle(.segmented)
            HStack(spacing: 12) {
                Field(label: "Số lượng", warn: e.warn("quantity")) { NumberField("0", text: $e.quantity) }
                Field(label: priceLabel, warn: e.warn("price")) { NumberField("0", text: $e.price) }
            }
            if isUsdt, let r = usdtRate {
                let val = Fmt.parse(e.price) ?? 0
                Text("\(Fmt.amount(val)) USDT × \(Fmt.amount(r, dp: 0)) ₫ = \(Fmt.amount(val * r, dp: 0)) ₫")
                    .font(.caption).foregroundStyle(Theme.muted)
            }
            Field(label: "Ngày (YYYY-MM-DD)", warn: e.warn("date")) {
                TextField("YYYY-MM-DD", text: $e.date).font(.money(15)).keyboardType(.numbersAndPunctuation).fieldStyle()
            }
            if let note = e.note { Text("ⓘ \(note)").font(.caption).foregroundStyle(Theme.muted) }
            HStack {
                Text("Tổng (code tính)").font(.footnote).foregroundStyle(Theme.muted)
                Spacer()
                Text(Fmt.vnd(total)).font(.money(15, weight: .semibold)).foregroundStyle(Theme.gold)
            }
            .padding(10)
            .background(Theme.panel2, in: RoundedRectangle(cornerRadius: 10))
        }
        .card()
        .opacity(e.include ? 1 : 0.5)
    }
}

private struct SavCard: View {
    @Binding var e: EditItem

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardHead(label: "Sổ tiết kiệm · \(e.institution.isEmpty ? "?" : e.institution)", on: $e.include)
            Field(label: "Ngân hàng", warn: e.warn("institution")) { TextField("Ngân hàng", text: $e.institution).fieldStyle() }
            HStack(spacing: 12) {
                Field(label: "Gốc (₫)", warn: e.warn("principal")) { NumberField("0", text: $e.principal) }
                Field(label: "Lãi suất %/năm", warn: e.warn("rate")) { NumberField("vd 6.5", text: $e.rate) }
            }
            HStack(spacing: 12) {
                Field(label: "Kỳ hạn (tháng)", warn: e.warn("termMonths")) { NumberField("vd 12", text: $e.termMonths, allowsDecimal: false) }
                Field(label: "Đáo hạn", warn: e.warn("maturityDate")) {
                    TextField("YYYY-MM-DD", text: $e.maturityDate).font(.money(15)).keyboardType(.numbersAndPunctuation).fieldStyle()
                }
            }
        }
        .card()
        .opacity(e.include ? 1 : 0.5)
    }
}
