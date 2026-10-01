import SwiftUI

// MARK: - Hub

struct AssetsHubView: View {
    @Environment(AppStore.self) private var store
    @State private var showAdd = false

    var body: some View {
        let p = store.portfolio
        let total = p.totalAssets()
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text(Fmt.vnd(total)).font(.money(15)).foregroundStyle(Theme.muted).padding(.bottom, 6)
                ForEach(p.allocation()) { a in
                    NavigationLink { AssetTypeDestination(type: a.type) } label: {
                        HStack(spacing: 12) {
                            Dot(color: Theme.accent(a.type))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(a.label).fontWeight(.semibold).foregroundStyle(Color.primary)
                                Text("\(total > 0 ? Int((a.value / total * 100).rounded()) : 0)% danh mục")
                                    .font(.money(12.5)).foregroundStyle(Theme.muted)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(Fmt.vnd(a.value, compact: true)).font(.money(14, weight: .semibold)).foregroundStyle(Color.primary)
                                if a.type != .SAVINGS && a.cost > 0 {
                                    Text(Fmt.percent((a.value - a.cost) / a.cost)).font(.money(12)).foregroundStyle(Theme.pl(a.value - a.cost))
                                }
                            }
                            Image(systemName: "chevron.right").foregroundStyle(Theme.muted)
                        }
                        .card(padding: 14)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
        }
        .screen()
        .refreshable { await store.refreshAll() }
        .navigationTitle("Tài sản")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAdd = true } label: { Label("Thêm", systemImage: "plus") }
            }
        }
        .sheet(isPresented: $showAdd) { NavigationStack { CreateAssetView() } }
    }
}

// MARK: - Holdings list (stocks / funds / crypto / gold)

struct HoldingListView: View {
    @Environment(AppStore.self) private var store
    let type: AssetType

    enum Sort: String, CaseIterable { case value = "Giá trị", pl = "Lãi/lỗ", roi = "ROI %", name = "Tên A–Z" }
    enum Filter: String, CaseIterable { case all = "Tất cả", profit = "Đang lãi", loss = "Đang lỗ" }

    @State private var query = ""
    @State private var sort = Sort.value
    @State private var filter = Filter.all
    @State private var pendingDelete: Holding?
    @State private var error: String?

    var body: some View {
        let holdings = store.portfolio.holdings(type)
        let shown = filtered(holdings)
        List {
            Section {
                Picker("Lọc", selection: $filter) {
                    ForEach(Filter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
            if let error { ErrorBox(text: error).listRowBackground(Color.clear) }
            Section {
                ForEach(shown) { h in
                    NavigationLink { HoldingDetailView(assetId: h.asset.id) } label: { HoldingRow(h: h) }
                        .swipeActions {
                            Button("Xoá", systemImage: "trash", role: .destructive) { pendingDelete = h }
                        }
                }
                if shown.isEmpty {
                    Text(holdings.isEmpty ? "Chưa có tài sản trong mục này." : "Không có kết quả khớp bộ lọc.")
                        .font(.footnote).foregroundStyle(Theme.muted)
                }
            } header: {
                Text(Fmt.vnd(holdings.reduce(0) { $0 + $1.value })).font(.money(14))
            }
            Section {
                Text("Định giá tham khảo, không phải khuyến nghị đầu tư. Giá tự cập nhật khi mở app (chứng khoán: SSI · quỹ: Fmarket · vàng: PNJ giá mua vào · coin: Binance). Kéo xuống để lấy giá mới; sửa tay nếu mã không có giá.")
                    .font(.footnote).foregroundStyle(Theme.muted)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .searchable(text: $query, prompt: "Tìm mã / tên…")
        .navigationTitle(type.label)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Sắp xếp", selection: $sort) {
                        ForEach(Sort.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                } label: { Label("Sắp xếp", systemImage: "arrow.up.arrow.down") }
            }
        }
        .refreshable { await store.refreshAll() }
        .confirmationDialog("Xoá \(pendingDelete?.asset.symbol ?? "") và toàn bộ giao dịch của nó?",
                            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                            titleVisibility: .visible) {
            Button("Xoá", role: .destructive) {
                guard let h = pendingDelete else { return }
                Task { error = await store.perform { try await store.repo.deleteAsset(h.asset.id) } }
            }
        }
    }

    private func filtered(_ list: [Holding]) -> [Holding] {
        list.filter { h in
            let text = "\(h.asset.symbol ?? "") \(h.asset.name)".lowercased()
            if !query.isEmpty && !text.contains(query.lowercased()) { return false }
            if filter == .profit && h.unrealizedPl < 0 { return false }
            if filter == .loss && h.unrealizedPl >= 0 { return false }
            return true
        }
        .sorted { a, b in
            switch sort {
            case .name: (a.asset.symbol ?? a.asset.name) < (b.asset.symbol ?? b.asset.name)
            case .pl: a.unrealizedPl > b.unrealizedPl
            case .roi: a.roi > b.roi
            case .value: a.value > b.value
            }
        }
    }
}

struct HoldingRow: View {
    let h: Holding

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(h.asset.symbol ?? h.asset.name).font(.money(15, weight: .semibold))
                    if h.priceIsStale { Pill(text: "giá cũ") }
                }
                Text("\(Fmt.quantity(h.quantity)) · \(h.asset.name)").font(.footnote).foregroundStyle(Theme.muted).lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(Fmt.vnd(h.value, compact: true)).font(.money(14, weight: .semibold))
                Text("\(Fmt.vnd(h.unrealizedPl, compact: true, sign: true)) (\(Fmt.percent(h.roi)))")
                    .font(.money(12)).foregroundStyle(Theme.pl(h.unrealizedPl))
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Holding detail

struct HoldingDetailView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let assetId: String

    @State private var txFilter = 0  // 0 all, 1 buy, 2 sell
    @State private var editingPrice = false
    @State private var priceText = ""
    @State private var confirmDelete = false
    @State private var showAddTx = false
    @State private var message: String?

    var body: some View {
        if let h = store.portfolio.holding(assetId: assetId) {
            content(h)
        } else {
            ContentUnavailableView("Không tìm thấy tài sản", systemImage: "questionmark.folder")
        }
    }

    private func content(_ h: Holding) -> some View {
        let txs = store.portfolio.transactions(for: assetId).sorted { $0.date > $1.date }
        let shown = txs.filter { txFilter == 0 ? true : txFilter == 1 ? $0.type.isInflow : !$0.type.isInflow }
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Giá trị").font(.footnote).foregroundStyle(Theme.muted)
                    Text(Fmt.vnd(h.value)).font(.money(28, weight: .bold))
                    Text("\(Fmt.vnd(h.unrealizedPl, sign: true)) (\(Fmt.percent(h.roi)))")
                        .font(.money(14)).foregroundStyle(Theme.pl(h.unrealizedPl))
                }
                .card()

                if h.asset.symbol != nil { priceCard(h) }

                LedgerRows(rows: [
                    ("Số lượng", Fmt.quantity(h.quantity)),
                    ("Giá vốn TB", Fmt.vnd(h.avgCost)),
                    ("Tổng vốn", Fmt.vnd(h.cost)),
                    ("Giá trị", Fmt.vnd(h.value)),
                ])

                HStack {
                    SectionTitle("Lịch sử giao dịch")
                    Spacer()
                    Picker("Lọc", selection: $txFilter) {
                        Text("Tất cả").tag(0); Text("Mua").tag(1); Text("Bán").tag(2)
                    }
                    .pickerStyle(.segmented).frame(width: 190)
                }
                VStack(spacing: 0) {
                    ForEach(Array(shown.enumerated()), id: \.element.id) { i, tx in
                        HStack {
                            Pill(text: tx.type.rawValue, color: tx.type.isInflow ? Theme.positive : Theme.negative)
                            Text(Fmt.date(tx.date)).font(.footnote).foregroundStyle(Theme.muted)
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("\(Fmt.quantity(tx.quantity ?? 0)) @ \(Fmt.vnd(tx.price ?? 0, compact: true))").font(.money(13))
                                Text(Fmt.vnd(tx.total, compact: true)).font(.money(12)).foregroundStyle(Theme.muted)
                            }
                        }
                        .padding(.vertical, 10)
                        if i < shown.count - 1 { Divider().overlay(Theme.border) }
                    }
                    if shown.isEmpty {
                        Text("Không có giao dịch.").font(.footnote).foregroundStyle(Theme.muted).padding(8)
                    }
                }
                .card(padding: 14)

                SecondaryButton(title: "Thêm giao dịch cho mã này", systemImage: "plus") { showAddTx = true }
                if let message { Text(message).font(.footnote).foregroundStyle(Theme.muted) }
                SecondaryButton(title: "Xoá tài sản này", systemImage: "trash", role: .destructive) { confirmDelete = true }
            }
            .padding(16)
        }
        .screen()
        .navigationTitle(h.asset.symbol ?? h.asset.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showAddTx) {
            NavigationStack { TradeFormView(type: h.asset.type, presetSymbol: h.asset.symbol ?? "") }
        }
        .confirmationDialog("Xoá tài sản này và toàn bộ giao dịch của nó?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Xoá", role: .destructive) {
                Task {
                    message = await store.perform { try await store.repo.deleteAsset(assetId) }
                    if message == nil { dismiss() }
                }
            }
        }
    }

    private func priceCard(_ h: Holding) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Giá hiện tại\(h.priceIsStale ? " (chưa cập nhật)" : "")").font(.footnote).foregroundStyle(Theme.muted)
                Text("Sửa tay nếu không quét được giá.").font(.caption).foregroundStyle(Theme.muted)
            }
            Spacer()
            if editingPrice {
                NumberField("Giá ₫", text: $priceText).frame(width: 140)
                Button { Task { await savePrice(h) } } label: { Image(systemName: "checkmark") }.foregroundStyle(Theme.positive)
                Button { editingPrice = false } label: { Image(systemName: "xmark") }.foregroundStyle(Theme.muted)
            } else {
                Button {
                    priceText = String(Int(h.price.rounded()))
                    editingPrice = true
                } label: {
                    HStack(spacing: 6) {
                        Text(Fmt.vnd(h.price)).font(.money(15, weight: .semibold)).foregroundStyle(Color.primary)
                        Image(systemName: "pencil").font(.caption).foregroundStyle(Theme.muted)
                    }
                }
            }
        }
        .card(padding: 14)
    }

    private func savePrice(_ h: Holding) async {
        guard let p = Fmt.parse(priceText), p > 0, let sym = h.asset.symbol else { return }
        message = await store.perform { try await store.repo.saveReadPrices([(sym, p)]) }
        editingPrice = false
    }
}
