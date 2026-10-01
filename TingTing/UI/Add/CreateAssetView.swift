import SwiftUI

/// Manual entry, one tab per kind (web: components/create-asset-form.tsx).
struct CreateAssetView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var mode: Mode = .STOCK

    enum Mode: String, CaseIterable, Identifiable {
        case STOCK = "Chứng khoán", CRYPTO = "Crypto", FUND = "Quỹ", GOLD = "Vàng", SAVINGS = "Sổ TK"
        var id: String { rawValue }
        var assetType: AssetType {
            switch self {
            case .STOCK: .STOCK
            case .CRYPTO: .CRYPTO
            case .FUND: .FUND
            case .GOLD: .GOLD
            case .SAVINGS: .SAVINGS
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Loại", selection: $mode) {
                ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            switch mode {
            case .STOCK, .CRYPTO, .FUND: TradeFormView(type: mode.assetType, embedded: true).id(mode)
            case .GOLD: GoldFormView(embedded: true)
            case .SAVINGS: SavingsFormView(embedded: true)
            }
        }
        .background(Theme.background)
        .navigationTitle("Nhập thủ công")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Đóng") { dismiss() } } }
    }
}

/// Success state shared by the forms.
struct SavedView: View {
    let message: String
    var again: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 48)).foregroundStyle(Theme.positive)
            Text(message).font(.headline).multilineTextAlignment(.center)
            HStack(spacing: 10) {
                SecondaryButton(title: "Nhập tiếp", action: again)
                PrimaryButton(title: "Xong") { dismiss() }
            }
        }
        .card(padding: 24)
        .padding(16)
    }
}

struct TradeFormView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let type: AssetType
    var presetSymbol = ""
    var embedded = false

    @State private var symbol = ""
    @State private var txType = TxType.BUY
    @State private var quantity = ""
    @State private var price = ""
    @State private var date = Date()
    @State private var busy = false
    @State private var error: String?
    @State private var done: String?

    private var unit: Double { Calc.priceUnit(type) }
    private var priceLabel: String { type == .STOCK ? "Giá (nghìn đ)" : type == .FUND ? "NAV (₫)" : "Giá / coin (₫)" }
    private var total: Double { (Fmt.parse(quantity) ?? 0) * (Fmt.parse(price) ?? 0) * unit }

    var body: some View {
        Group {
            if let done {
                SavedView(message: done) { self.done = nil; quantity = ""; price = "" }
            } else {
                form
            }
        }
        .background(Theme.background)
        .onAppear { if symbol.isEmpty { symbol = presetSymbol } }
        .navigationTitle(embedded ? "" : "Thêm giao dịch")
        .toolbar {
            if !embedded { ToolbarItem(placement: .cancellationAction) { Button("Đóng") { dismiss() } } }
        }
    }

    private var form: some View {
        let options = store.portfolio.assets.filter { $0.type == type }.compactMap(\.symbol)
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Field(label: "Mã") {
                    TextField(type == .CRYPTO ? "vd BTC, ETH" : type == .FUND ? "vd VCBF-BCF" : "vd VCB, FPT", text: $symbol)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .font(.money(16))
                        .fieldStyle()
                    if !options.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(options, id: \.self) { s in
                                    Button(s) { symbol = s }.buttonStyle(.bordered).font(.caption)
                                }
                            }
                        }
                    }
                }
                Field(label: "Loại lệnh") {
                    Picker("Loại lệnh", selection: $txType) {
                        Text("Mua").tag(TxType.BUY)
                        Text("Bán").tag(TxType.SELL)
                    }
                    .pickerStyle(.segmented)
                }
                HStack(spacing: 12) {
                    Field(label: "Số lượng") { NumberField("0", text: $quantity) }
                    Field(label: priceLabel) { NumberField(type == .STOCK ? "vd 59.3" : "0", text: $price) }
                }
                Field(label: "Ngày") {
                    DatePicker("Ngày", selection: $date, displayedComponents: .date).labelsHidden()
                }
                HStack {
                    Text("Tổng (code tính)").foregroundStyle(Theme.muted)
                    Spacer()
                    Text(Fmt.vnd(total)).font(.money(18, weight: .semibold)).foregroundStyle(Theme.gold)
                }
                .card(background: Theme.panel2)
                if let error { ErrorBox(text: error) }
                PrimaryButton(title: "Ghi lệnh", busy: busy) { Task { await save() } }
            }
            .padding(16)
        }
    }

    private func save() async {
        busy = true
        error = nil
        defer { busy = false }
        var msg = ""
        error = await store.perform {
            msg = try await store.repo.createTrade(type: type, symbol: symbol, txType: txType,
                                                   quantity: Fmt.parse(quantity) ?? 0, rawPrice: Fmt.parse(price) ?? 0,
                                                   date: DateUtil.localDay(date))
        }
        if error == nil { done = msg }
    }
}

struct GoldFormView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var embedded = false

    @State private var unit = GoldUnit.chi
    @State private var qty = ""
    @State private var price = ""
    @State private var refPrice: Double = 0
    @State private var busy = false
    @State private var error: String?
    @State private var done: String?

    var body: some View {
        Group {
            if let done {
                SavedView(message: done) { self.done = nil; qty = "" }
            } else {
                form
            }
        }
        .background(Theme.background)
        .task {
            refPrice = await PriceService.shared.goldVndPerChi()
            if price.isEmpty && refPrice > 0 { price = String(Int(refPrice)) }
        }
    }

    private var form: some View {
        let value = (Fmt.parse(qty) ?? 0) * unit.chi * (Fmt.parse(price) ?? 0)
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Field(label: "Số lượng") { NumberField("vd 4.5", text: $qty) }
                    Field(label: "Đơn vị") {
                        Picker("Đơn vị", selection: $unit) { ForEach(GoldUnit.allCases) { Text($0.label).tag($0) } }
                            .pickerStyle(.menu).fieldStyle()
                    }
                }
                Field(label: "Giá vàng / chỉ (₫)") { NumberField("giá mỗi chỉ", text: $price) }
                Text(refPrice > 0
                     ? "Giá tham khảo tự lấy: \(Fmt.vnd(refPrice))/chỉ (vàng thế giới quy đổi, sửa lại theo SJC nếu cần)."
                     : "Nhập giá mỗi chỉ bạn đang thấy (SJC/PNJ).")
                    .font(.caption).foregroundStyle(Theme.muted)
                HStack {
                    Text("Giá trị (code tính)").foregroundStyle(Theme.muted)
                    Spacer()
                    Text(Fmt.vnd(value)).font(.money(18, weight: .semibold)).foregroundStyle(Theme.gold)
                }
                .card(background: Theme.panel2)
                if let error { ErrorBox(text: error) }
                PrimaryButton(title: "Thêm vàng", busy: busy) { Task { await save() } }
            }
            .padding(16)
        }
    }

    private func save() async {
        busy = true
        error = nil
        defer { busy = false }
        var msg = ""
        error = await store.perform {
            msg = try await store.repo.createGold(unit: unit, quantity: Fmt.parse(qty) ?? 0,
                                                  pricePerChi: Fmt.parse(price) ?? 0, date: DateUtil.localDay(Date()))
        }
        if error == nil { done = msg }
    }
}

struct SavingsFormView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var embedded = false

    @State private var institution = ""
    @State private var principal = ""
    @State private var rate = ""
    @State private var term = ""
    @State private var maturity = Calendar.current.date(byAdding: .month, value: 12, to: Date()) ?? Date()
    @State private var autoRenew = true
    @State private var busy = false
    @State private var error: String?
    @State private var done: String?

    var body: some View {
        Group {
            if let done {
                SavedView(message: done) { self.done = nil; institution = ""; principal = "" }
            } else {
                form
            }
        }
        .background(Theme.background)
        .navigationTitle(embedded ? "" : "Thêm sổ tiết kiệm")
        .toolbar {
            if !embedded { ToolbarItem(placement: .cancellationAction) { Button("Đóng") { dismiss() } } }
        }
    }

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Field(label: "Ngân hàng") {
                    TextField("vd Vietcombank, Timo", text: $institution).fieldStyle()
                }
                HStack(spacing: 12) {
                    Field(label: "Gốc (₫)") { NumberField("0", text: $principal) }
                    Field(label: "Lãi suất (%/năm)") { NumberField("vd 5.45", text: $rate) }
                }
                HStack(alignment: .bottom, spacing: 12) {
                    Field(label: "Kỳ hạn (tháng)") { NumberField("vd 12", text: $term, allowsDecimal: false) }
                    Field(label: "Ngày đáo hạn") {
                        DatePicker("Ngày đáo hạn", selection: $maturity, displayedComponents: .date).labelsHidden()
                    }
                }
                Text("Ngày gửi = ngày đáo hạn trừ kỳ hạn (app tự tính). Bỏ trống kỳ hạn thì ngày gửi = hôm nay.")
                    .font(.caption).foregroundStyle(Theme.muted)
                Toggle("Tự động tái tục", isOn: $autoRenew).card(padding: 12)
                if let error { ErrorBox(text: error) }
                PrimaryButton(title: "Tạo sổ tiết kiệm", busy: busy) { Task { await save() } }
            }
            .padding(16)
        }
    }

    private func save() async {
        busy = true
        error = nil
        defer { busy = false }
        var msg = ""
        error = await store.perform {
            msg = try await store.repo.createSavings(institution: institution, principal: Fmt.parse(principal) ?? 0,
                                                     ratePercent: Fmt.parse(rate) ?? 0, maturityDate: DateUtil.localDay(maturity),
                                                     termMonths: Int(Fmt.parse(term) ?? 0), autoRenew: autoRenew)
        }
        if error == nil { done = msg }
    }
}
