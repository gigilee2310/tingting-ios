import Charts
import SwiftUI

struct HomeView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let p = store.portfolio
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let warning = ProvisioningInfo.expiryWarning {
                    Disclaimer("⏳ \(warning)")
                }
                if let err = store.loadError { ErrorBox(text: err) }
                if store.isRefreshingPrices {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Đang cập nhật giá chứng khoán, quỹ, vàng, coin…").font(.caption).foregroundStyle(Theme.muted)
                    }
                }

                if p.assets.isEmpty && !store.isLoading {
                    emptyState
                } else {
                    content(p)
                }
            }
            .padding(16)
        }
        .screen()
        .refreshable { await store.refreshAll() }
        .navigationTitle("Ting Ting")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink { SettingsView() } label: {
                    Text(initials)
                        .font(.caption.bold())
                        .frame(width: 32, height: 32)
                        .background(Theme.gold.opacity(0.18), in: Circle())
                        .foregroundStyle(Theme.gold)
                }
                .accessibilityLabel("Cài đặt")
            }
        }
        .overlay { if store.isLoading && p.assets.isEmpty { ProgressView() } }
    }

    private var initials: String {
        String((store.email ?? "?").split(separator: "@").first?.prefix(2) ?? "?").uppercased()
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading) {
                Text("Tổng tài sản").font(.footnote).foregroundStyle(Theme.muted)
                Text(Fmt.vnd(0)).font(.money(34, weight: .bold))
            }
            VStack(spacing: 10) {
                Text("Chưa có dữ liệu").fontWeight(.semibold)
                Text("Bấm nút + ở thanh dưới để thêm tài sản: nhập tay, gõ cho AI hoặc chụp ảnh lệnh.")
                    .font(.footnote).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .card(padding: 24)
        }
    }

    @ViewBuilder
    private func content(_ p: Portfolio) -> some View {
        let total = p.totalAssets()
        let cost = p.totalCost()
        let pl = total - cost
        let roi = cost > 0 ? pl / cost : 0
        let maturing = p.maturingSoon()

        if !maturing.isEmpty {
            NavigationLink { SavingsListView() } label: {
                Disclaimer("🔔 " + maturing.map { m in
                    let when = m.days < 0 ? "đã đáo hạn" : m.days == 0 ? "đáo hạn hôm nay" : "đáo hạn còn \(m.days) ngày"
                    let renew = m.account.autoRenew ? "sẽ tự tái tục gốc + lãi" : "không tự tái tục, nhớ tất toán/gia hạn"
                    return "Sổ \(m.account.institution) \(when) — \(renew)."
                }.joined(separator: " "))
            }
            .buttonStyle(.plain)
        }

        VStack(alignment: .leading, spacing: 4) {
            Text("Tổng tài sản").font(.footnote).foregroundStyle(Theme.muted)
            Text(Fmt.vnd(total)).font(.money(34, weight: .bold)).minimumScaleFactor(0.6).lineLimit(1)
            HStack(spacing: 6) {
                Text("\(Fmt.vnd(pl, sign: true)) (\(Fmt.percent(roi)))").foregroundStyle(Theme.pl(pl))
                Text("so với vốn").foregroundStyle(Theme.muted)
            }
            .font(.money(14))
        }

        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("Phân bổ tài sản")
            DonutChart(allocation: p.allocation(), total: total)
        }
        .card()

        NavigationLink { AIChatView() } label: {
            HStack(spacing: 10) {
                Image(systemName: "sparkles").foregroundStyle(Theme.gold)
                Text("Hỏi AI về tài sản của bạn…").foregroundStyle(Theme.muted)
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(Theme.muted)
            }
            .card(padding: 14)
        }
        .buttonStyle(.plain)

        VStack(spacing: 10) {
            ForEach(Portfolio.allocationTypes) { type in
                let value = p.typeValue(type)
                let c = p.typeCost(type)
                NavigationLink { AssetTypeDestination(type: type) } label: {
                    HStack(spacing: 12) {
                        Dot(color: Theme.accent(type))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(type.label).fontWeight(.semibold).foregroundStyle(Color.primary)
                            Text(Fmt.vnd(value, compact: true)).font(.money(12.5)).foregroundStyle(Theme.muted)
                        }
                        Spacer()
                        if type != .SAVINGS {
                            Text(c > 0 ? Fmt.percent((value - c) / c) : "—")
                                .font(.money(13)).foregroundStyle(Theme.pl(value - c))
                        }
                        Image(systemName: "chevron.right").foregroundStyle(Theme.muted)
                    }
                    .card(padding: 14)
                }
                .buttonStyle(.plain)
            }
        }

        NetWorthChart(history: store.history)
    }
}

/// Routes an asset type to its list screen.
struct AssetTypeDestination: View {
    let type: AssetType
    var body: some View {
        if type == .SAVINGS { SavingsListView() } else { HoldingListView(type: type) }
    }
}

struct DonutChart: View {
    let allocation: [Allocation]
    let total: Double

    var body: some View {
        let shown = allocation.filter { $0.value > 0 }
        HStack(spacing: 18) {
            ZStack {
                Chart(shown) { a in
                    SectorMark(angle: .value("Giá trị", a.value), innerRadius: .ratio(0.68), angularInset: 1.5)
                        .foregroundStyle(Theme.accent(a.type))
                        .cornerRadius(3)
                }
                .chartLegend(.hidden)
                VStack(spacing: 0) {
                    Text("Tổng").font(.caption2).foregroundStyle(Theme.muted)
                    Text(Fmt.vnd(total, compact: true)).font(.money(14, weight: .semibold))
                }
            }
            .frame(width: 130, height: 130)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(shown) { a in
                    HStack(spacing: 8) {
                        Dot(color: Theme.accent(a.type), size: 9)
                        Text(a.label).font(.footnote)
                        Spacer()
                        Text(total > 0 ? String(format: "%.0f%%", a.value / total * 100) : "0%")
                            .font(.money(12.5)).foregroundStyle(Theme.muted)
                    }
                }
            }
        }
    }
}

struct NetWorthChart: View {
    let history: [DailySnapshot]
    @State private var range = 180

    private let ranges: [(String, Int)] = [("7N", 7), ("1T", 30), ("3T", 90), ("6T", 180), ("1N", 365), ("Tất cả", 100_000)]

    var body: some View {
        let data = Array(history.suffix(range))
        let first = data.first?.totalValue ?? 0
        let last = data.last?.totalValue ?? 0
        let delta = last - first
        let minV = data.map(\.totalValue).min() ?? 0
        let maxV = data.map(\.totalValue).max() ?? 1

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    SectionTitle("Net worth")
                    Text(Fmt.vnd(last, compact: true)).font(.money(15, weight: .semibold))
                }
                Spacer()
                Text(Fmt.vnd(delta, compact: true, sign: true)).font(.money(13)).foregroundStyle(Theme.pl(delta))
            }
            Chart(data) { s in
                AreaMark(x: .value("Ngày", DateUtil.parse(s.date)), yStart: .value("min", minV), yEnd: .value("Tổng", s.totalValue))
                    .foregroundStyle(LinearGradient(colors: [Theme.gold.opacity(0.35), Theme.gold.opacity(0)], startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Ngày", DateUtil.parse(s.date)), y: .value("Tổng", s.totalValue))
                    .foregroundStyle(Theme.gold)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .interpolationMethod(.monotone)
            }
            .chartYScale(domain: minV...max(maxV, minV + 1))
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .frame(height: 130)

            Picker("Khoảng thời gian", selection: $range) {
                ForEach(ranges, id: \.1) { Text($0.0).tag($0.1) }
            }
            .pickerStyle(.segmented)
        }
        .card()
    }
}
