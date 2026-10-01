import Charts
import SwiftUI

struct SavingsListView: View {
    @Environment(AppStore.self) private var store

    enum Sort: String, CaseIterable { case maturity = "Sắp đáo hạn", principal = "Gốc", rate = "Lãi suất" }

    @State private var query = ""
    @State private var sort = Sort.maturity
    @State private var pendingDelete: SavingsAccount?
    @State private var error: String?
    @State private var showAdd = false

    var body: some View {
        let accounts = store.portfolio.savingsAccounts
        let rows = accounts
            .filter { query.isEmpty || $0.institution.lowercased().contains(query.lowercased()) }
            .map { s -> SavingsRow in
                let st = Calc.savingsState(s)
                return SavingsRow(s: s, st: st, endInterest: Calc.round(st.principal * s.rate * Calc.termYears(s), 0))
            }
            .sorted { a, b in
                switch sort {
                case .rate: a.s.rate > b.s.rate
                case .principal: a.st.value > b.st.value
                case .maturity: a.st.cycleMaturity < b.st.cycleMaturity
                }
            }
        List {
            if let error { ErrorBox(text: error).listRowBackground(Color.clear) }
            Section {
                ForEach(rows) { row in
                    let s = row.s, st = row.st, endInterest = row.endInterest
                    NavigationLink { SavingsDetailView(id: s.id) } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 8) {
                                    Text(s.institution).fontWeight(.semibold)
                                    if st.closed { Pill(text: "đã tất toán") }
                                }
                                Text("\(Fmt.rate(s.rate))/năm · đáo hạn \(Fmt.date(st.cycleMaturity))")
                                    .font(.footnote).foregroundStyle(Theme.muted)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 3) {
                                Text(Fmt.vnd(st.closed ? st.maturedBalance : st.value, compact: true)).font(.money(14, weight: .semibold))
                                if !st.closed {
                                    Text("+\(Fmt.vnd(endInterest, compact: true)) lãi kỳ này").font(.money(12)).foregroundStyle(Theme.positive)
                                }
                            }
                        }
                        .opacity(st.closed ? 0.55 : 1)
                        .padding(.vertical, 4)
                    }
                    .swipeActions {
                        Button("Xoá", systemImage: "trash", role: .destructive) { pendingDelete = s }
                    }
                }
                if rows.isEmpty {
                    Text(accounts.isEmpty ? "Chưa có sổ tiết kiệm." : "Không có kết quả khớp.")
                        .font(.footnote).foregroundStyle(Theme.muted)
                }
            } header: {
                Text(Fmt.vnd(store.portfolio.savingsValue())).font(.money(14))
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .searchable(text: $query, prompt: "Tìm ngân hàng…")
        .navigationTitle("Tiết kiệm")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    Picker("Sắp xếp", selection: $sort) { ForEach(Sort.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                } label: { Label("Sắp xếp", systemImage: "arrow.up.arrow.down") }
                Button { showAdd = true } label: { Label("Thêm sổ", systemImage: "plus") }
            }
        }
        .sheet(isPresented: $showAdd) { NavigationStack { SavingsFormView() } }
        .refreshable { await store.reload() }
        .confirmationDialog("Xoá sổ \(pendingDelete?.institution ?? "")?",
                            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                            titleVisibility: .visible) {
            Button("Xoá", role: .destructive) {
                guard let s = pendingDelete else { return }
                Task { error = await store.perform { try await store.repo.deleteSavings(s) } }
            }
        }
    }
}

struct SavingsRow: Identifiable {
    let s: SavingsAccount
    let st: Calc.SavingsState
    let endInterest: Double
    var id: String { s.id }
}

struct SavingsDetailView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let id: String

    @State private var message: String?
    @State private var confirmDelete = false

    var body: some View {
        if let s = store.portfolio.savingsAccount(id) {
            content(s)
        } else {
            ContentUnavailableView("Không tìm thấy sổ", systemImage: "questionmark.folder")
        }
    }

    private func content(_ s: SavingsAccount) -> some View {
        let st = Calc.savingsState(s)
        let cStart = DateUtil.parse(st.cycleStart).timeIntervalSince1970
        let cEnd = DateUtil.parse(st.cycleMaturity).timeIntervalSince1970
        let progress = st.closed ? 1 : min(1, max(0, (Date().timeIntervalSince1970 - cStart) / max(1, cEnd - cStart)))
        let termYears = Calc.termYears(s)
        let termMonths = Int((termYears * 12).rounded())
        let cycleEndInterest = (st.principal * s.rate * termYears).rounded()

        var rows: [(String, String)] = [
            ("Gốc ban đầu", Fmt.vnd(s.principal)),
            ("Lãi suất", "\(Fmt.rate(s.rate))/năm"),
            ("Kỳ hạn", "\(termMonths) tháng"),
        ]
        if !st.history.isEmpty { rows.append(("Gốc kỳ hiện tại", Fmt.vnd(st.principal))) }
        rows += [
            ("Lãi tích lũy kỳ này", Fmt.vnd(st.accrued)),
            ("Lãi cuối kỳ (dự kiến)", Fmt.vnd(cycleEndInterest)),
            ("Số dư cuối kỳ", Fmt.vnd(st.principal + cycleEndInterest)),
            ("Kỳ hiện tại", "\(Fmt.date(st.cycleStart)) → \(Fmt.date(st.cycleMaturity))"),
            ("Tái tục", s.autoRenew ? "Gốc + lãi" : "Không"),
        ]

        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(st.closed ? "Đã tất toán (không tái tục)" : "Giá trị hiện tại").font(.footnote).foregroundStyle(Theme.muted)
                    Text(Fmt.vnd(st.closed ? st.maturedBalance : st.value)).font(.money(28, weight: .bold))
                    if st.closed {
                        Text("Đã rút \(Fmt.vnd(st.maturedBalance)) vào \(Fmt.date(st.cycleMaturity)) — không còn tính vào tổng.")
                            .font(.footnote).foregroundStyle(Theme.muted)
                    } else {
                        HStack {
                            Text("Tiến độ kỳ hiện tại")
                            Spacer()
                            Text("\(Int((progress * 100).rounded()))%").font(.money(12))
                        }
                        .font(.caption).foregroundStyle(Theme.muted)
                        ProgressView(value: progress).tint(Theme.gold)
                    }
                }
                .card()

                LedgerRows(rows: rows)

                if !st.history.isEmpty {
                    SectionTitle("Lịch sử tái tục (\(st.history.count))")
                    VStack(spacing: 0) {
                        ForEach(Array(st.history.enumerated()), id: \.offset) { i, c in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Kỳ \(i + 1)").fontWeight(.semibold).font(.subheadline)
                                    Text("\(Fmt.date(c.start)) → \(Fmt.date(c.maturity))").font(.caption).foregroundStyle(Theme.muted)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(Fmt.vnd(c.endBalance)).font(.money(13))
                                    Text("+\(Fmt.vnd(c.interest, compact: true)) lãi").font(.money(12)).foregroundStyle(Theme.positive)
                                }
                            }
                            .padding(.vertical, 10)
                            if i < st.history.count - 1 { Divider().overlay(Theme.border) }
                        }
                    }
                    .card(padding: 14)
                }

                renewCard(s)

                if !st.closed { SavingsProjection(principal: st.principal, rate: s.rate) }

                if let message { Text(message).font(.footnote).foregroundStyle(Theme.muted) }
                SecondaryButton(title: "Xoá sổ này", systemImage: "trash", role: .destructive) { confirmDelete = true }
            }
            .padding(16)
        }
        .screen()
        .navigationTitle(s.institution)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Xoá sổ tiết kiệm này?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Xoá", role: .destructive) {
                Task {
                    message = await store.perform { try await store.repo.deleteSavings(s) }
                    if message == nil { dismiss() }
                }
            }
        }
    }

    private func renewCard(_ s: SavingsAccount) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("Khi đáo hạn")
            Picker("Khi đáo hạn", selection: Binding(get: { s.autoRenew }, set: { v in
                Task {
                    let err = await store.perform { try await store.repo.updateSavingsRenew(id: s.id, autoRenew: v) }
                    message = err ?? (v ? "Sẽ tự tái tục gốc + lãi." : "Đã tắt tự tái tục.")
                }
            })) {
                Text("Tái tục gốc + lãi").tag(true)
                Text("Không tái tục").tag(false)
            }
            .pickerStyle(.segmented)
            Text(s.autoRenew
                 ? "Đến ngày đáo hạn, sổ tự gửi lại cả gốc lẫn lãi cho kỳ mới (lãi kép)."
                 : "Đến ngày đáo hạn, sổ dừng lại — bạn tự tất toán hoặc mở sổ mới.")
                .font(.caption).foregroundStyle(Theme.muted)
        }
        .card()
    }
}

struct SavingsProjection: View {
    let principal: Double
    let rate: Double
    @State private var years = 6.0
    @State private var periodMonths = 6.0

    var body: some View {
        let curve = (0...Int(years)).map { y in ChartPoint(x: y, y: Calc.periodicCompound(principal, rate, years: Double(y), periodMonths: periodMonths)) }
        let end = Calc.periodicCompound(principal, rate, years: years, periodMonths: periodMonths)
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionTitle("Mô phỏng tái tục · \(Int(years)) năm")
                Spacer()
                Text(Fmt.vnd(end, compact: true)).font(.money(15, weight: .semibold)).foregroundStyle(Theme.gold)
            }
            SectionTitle("Tái tục mỗi")
            Picker("Tái tục mỗi", selection: $periodMonths) {
                ForEach([1.0, 3, 6, 12], id: \.self) { Text("\(Int($0)) tháng").tag($0) }
            }
            .pickerStyle(.segmented)
            Chart(curve) { p in
                LineMark(x: .value("Năm", p.x), y: .value("Giá trị", p.y))
                    .foregroundStyle(Theme.gold)
                    .interpolationMethod(.monotone)
            }
            .chartXAxis(.hidden).chartYAxis(.hidden)
            .chartYScale(domain: .automatic(includesZero: false))
            .frame(height: 120)
            Slider(value: $years, in: 1...30, step: 1).tint(Theme.gold)
            HStack {
                Text("1 năm"); Spacer()
                Text("Lãi thêm ~\(Fmt.vnd(end - principal, compact: true))"); Spacer()
                Text("30 năm")
            }
            .font(.caption).foregroundStyle(Theme.muted)
            Text("Tái tục càng ngắn kỳ (vd 6 tháng) thì lãi kép cộng dồn càng nhiều hơn so với để 12 tháng.")
                .font(.caption).foregroundStyle(Theme.muted)
        }
        .card()
    }
}

struct ChartPoint: Identifiable {
    let x: Int
    let y: Double
    var id: Int { x }
}
