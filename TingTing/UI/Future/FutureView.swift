import SwiftUI

/// Projections (web: app/future + components/future-tabs.tsx). Simulations, not predictions.
struct FutureView: View {
    @Environment(AppStore.self) private var store
    @State private var tab = FutureTab.goal

    enum FutureTab: String, CaseIterable, Identifiable {
        case goal = "Mục tiêu", savings = "Tiết kiệm", stock = "Chứng khoán", fund = "Quỹ", crypto = "Crypto", gold = "Vàng"
        var id: String { rawValue }
    }

    static let horizons = [1, 3, 5, 10, 15, 20, 30]
    static let disclaimer = "Mô phỏng theo giả định bạn chọn, KHÔNG phải dự đoán/khuyến nghị đầu tư. Kết quả thực tế có thể khác nhiều."

    var body: some View {
        let p = store.portfolio
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Tổng tài sản hiện tại").foregroundStyle(Theme.muted)
                    Spacer()
                    Text(Fmt.vnd(p.totalAssets())).font(.money(16, weight: .semibold))
                }
                .card()

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(FutureTab.allCases) { t in
                            Button(t.rawValue) { tab = t }
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 14).padding(.vertical, 8)
                                .background(tab == t ? Theme.gold : Theme.panel, in: Capsule())
                                .foregroundStyle(tab == t ? Theme.onGold : Color.primary)
                        }
                    }
                }

                switch tab {
                case .goal:
                    GoalPlanner(currentTotal: p.totalAssets())
                case .savings:
                    let rate = p.averageSavingsRate()
                    MilestoneCard(title: "Tiết kiệm", current: p.savingsValue(), rate: rate,
                                  note: "Lãi kép ở lãi suất bình quân \(String(format: "%.2f", rate * 100))%/năm, giả định tái tục.")
                case .stock:
                    ScenarioCard(title: "Chứng khoán", current: p.typeValue(.STOCK),
                                 scenarios: [("Thận trọng", 0.06), ("Trung bình", 0.1), ("Lạc quan", 0.15)],
                                 note: "10%/năm tham khảo tăng trưởng lịch sử VN-Index.")
                case .fund:
                    ScenarioCard(title: "Chứng chỉ quỹ", current: p.typeValue(.FUND),
                                 scenarios: [("Thận trọng", 0.07), ("Trung bình", 0.1), ("Lạc quan", 0.13)],
                                 note: "Quỹ mở cân bằng thường 8–12%/năm dài hạn (tham khảo).")
                case .crypto:
                    ScenarioCard(title: "Crypto", current: p.typeValue(.CRYPTO),
                                 scenarios: [("Giảm sâu", -0.2), ("Đi ngang", 0.05), ("Tăng mạnh", 0.4)],
                                 note: "Crypto biến động rất mạnh; kịch bản chỉ minh hoạ dải kết quả.")
                case .gold:
                    ScenarioCard(title: "Vàng", current: p.typeValue(.GOLD),
                                 scenarios: [("Thận trọng", 0.03), ("Trung bình", 0.06), ("Lạc quan", 0.1)],
                                 note: "Vàng dài hạn thường giữ giá trị, tăng ~gần lạm phát (tham khảo).")
                }
            }
            .padding(16)
        }
        .screen()
        .navigationTitle("Tương lai")
    }
}

private struct ProjectionTable: View {
    let rows: [(year: Int, fv: Double, base: Double)]

    var body: some View {
        VStack(spacing: 0) {
            HStack { SectionTitle("Sau"); Spacer(); SectionTitle("Giá trị dự phóng") }.padding(.bottom, 8)
            Divider().overlay(Theme.border)
            ForEach(rows.indices, id: \.self) { i in
                let r = rows[i]
                HStack {
                    Text("\(r.year) năm").fontWeight(.semibold)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(Fmt.vnd(r.fv)).font(.money(15, weight: .semibold))
                        Text(Fmt.vnd(r.fv - r.base, compact: true, sign: true)).font(.money(12)).foregroundStyle(Theme.pl(r.fv - r.base))
                    }
                }
                .padding(.vertical, 10)
                if i < rows.count - 1 { Divider().overlay(Theme.border) }
            }
        }
        .card(padding: 14)
    }
}

private struct MilestoneCard: View {
    let title: String
    let current: Double
    let rate: Double
    let note: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text("\(title) hiện tại").foregroundStyle(Theme.muted); Spacer(); Text(Fmt.vnd(current)).font(.money(15, weight: .semibold)) }
                .card()
            ProjectionTable(rows: FutureView.horizons.map { ($0, Calc.compoundFutureValue(current, rate, Double($0)), current) })
            Text(note).font(.caption).foregroundStyle(Theme.muted)
        }
    }
}

private struct ScenarioCard: View {
    let title: String
    let current: Double
    let scenarios: [(String, Double)]
    let note: String
    @State private var idx = 1

    var body: some View {
        let rate = scenarios[idx].1
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text("\(title) hiện tại").foregroundStyle(Theme.muted); Spacer(); Text(Fmt.vnd(current)).font(.money(15, weight: .semibold)) }
                .card()
            Picker("Kịch bản", selection: $idx) {
                ForEach(scenarios.indices, id: \.self) { i in
                    Text("\(scenarios[i].0) \(Int((scenarios[i].1 * 100).rounded()))%").tag(i)
                }
            }
            .pickerStyle(.segmented)
            ProjectionTable(rows: FutureView.horizons.map { ($0, Calc.scenarioFutureValue(current, rate, Double($0)), current) })
            Disclaimer("\(note) \(FutureView.disclaimer)")
        }
    }
}

private struct GoalPlanner: View {
    let currentTotal: Double

    static let cats: [(key: String, label: String, ret: Double, type: AssetType)] = [
        ("savings", "Tiết kiệm", 0.06, .SAVINGS), ("fund", "Chứng chỉ quỹ", 0.09, .FUND),
        ("stock", "Chứng khoán", 0.11, .STOCK), ("crypto", "Crypto", 0.2, .CRYPTO), ("gold", "Vàng", 0.05, .GOLD),
    ]
    static let curRate = 0.08  // assumed blended growth of existing assets

    @State private var goal = "2000000000"
    @State private var years = 15.0
    @State private var amounts: [String: String] = [:]
    @State private var months: [String: Int] = [:]

    var body: some View {
        let g = Fmt.parse(goal) ?? 0
        let currentProj = Calc.compoundFutureValue(currentTotal, Self.curRate, years)
        let perCat = Self.cats.map { c in
            (c, Calc.annuityFutureValue(Fmt.parse(amounts[c.key] ?? "") ?? 0, c.ret, years, Double(months[c.key] ?? 6)))
        }
        let planFv = perCat.reduce(0) { $0 + $1.1 }
        let projected = currentProj + planFv
        let reached = projected >= g

        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 12) {
                Field(label: "Mục tiêu (₫)") {
                    NumberField("vd 2,000,000,000", text: $goal)
                    Text("= \(Fmt.vnd(g, compact: true))").font(.money(12)).foregroundStyle(Theme.muted)
                }
                Field(label: "Trong \(Int(years)) năm") {
                    Slider(value: $years, in: 1...30, step: 1).tint(Theme.gold)
                }
            }
            .card()

            VStack(spacing: 10) {
                row("Đang có → sau \(Int(years)) năm (~\(Int(Self.curRate * 100))%/năm)", Fmt.vnd(currentProj, compact: true))
                row("Kế hoạch góp thêm", Fmt.vnd(planFv, compact: true))
                Divider().overlay(Theme.border)
                HStack {
                    Text("Tổng dự kiến").fontWeight(.semibold)
                    Spacer()
                    Text(Fmt.vnd(projected, compact: true)).font(.money(15, weight: .semibold))
                }
                HStack {
                    Text(reached ? "Vượt mục tiêu" : "Còn thiếu").foregroundStyle(Theme.muted)
                    Spacer()
                    Text((reached ? "+" : "") + Fmt.vnd(reached ? projected - g : max(0, g - projected), compact: true))
                        .font(.money(15, weight: .semibold)).foregroundStyle(reached ? Theme.positive : Theme.negative)
                }
                if reached { Text("🎉 Kế hoạch này đạt mục tiêu!").fontWeight(.semibold).foregroundStyle(Theme.positive) }
            }
            .card()

            SectionTitle("Kế hoạch góp mỗi kênh — chỉnh số tiền & tần suất")
            ForEach(perCat.indices, id: \.self) { i in
                let c = perCat[i].0
                let fv = perCat[i].1
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Dot(color: Theme.accent(c.type), size: 10)
                        Text(c.label).fontWeight(.semibold)
                        Text("~\(Int(c.ret * 100))%/năm").font(.money(11.5)).foregroundStyle(Theme.muted)
                        Spacer()
                        Text("→ \(Fmt.vnd(fv, compact: true))").font(.money(13, weight: .semibold)).foregroundStyle(Theme.gold)
                    }
                    HStack(alignment: .bottom, spacing: 10) {
                        Field(label: c.key == "savings" ? "Gửi mỗi lần (₫)" : "Mua thêm mỗi lần (₫)") {
                            NumberField("0", text: Binding(get: { amounts[c.key] ?? "" }, set: { amounts[c.key] = $0 }))
                        }
                        Field(label: "Mỗi") {
                            Picker("Mỗi", selection: Binding(get: { months[c.key] ?? 6 }, set: { months[c.key] = $0 })) {
                                ForEach([1, 3, 6, 12], id: \.self) { Text("\($0) tháng").tag($0) }
                            }
                            .pickerStyle(.menu).fieldStyle()
                        }
                        .frame(width: 130)
                    }
                    if c.key == "savings", let a = Fmt.parse(amounts[c.key] ?? ""), a > 0 {
                        Text("Gửi \(Fmt.vnd(a, compact: true)) mỗi \(months[c.key] ?? 6) tháng, tái tục kèm lãi kép trong \(Int(years)) năm.")
                            .font(.caption).foregroundStyle(Theme.muted)
                    }
                }
                .card()
            }
            Disclaimer("Nhập số tiền góp + tần suất cho từng kênh → app tính giá trị tương lai (lãi kép) rồi cộng với số đang có để so với mục tiêu. \(FutureView.disclaimer)")
        }
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack { Text(k).foregroundStyle(Theme.muted); Spacer(); Text(v).font(.money(14)) }
    }
}
