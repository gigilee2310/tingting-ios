import Foundation

/// Portfolio aggregation over raw rows — port of the web app's lib/compute.ts.
struct PortfolioData: Sendable {
    var assets: [Asset] = []
    var transactions: [Transaction] = []
    var savingsAccounts: [SavingsAccount] = []
    /// Newest first.
    var marketPrices: [MarketPrice] = []
}

struct Allocation: Identifiable, Sendable {
    let type: AssetType
    let value: Double
    let cost: Double
    var id: AssetType { type }
    var label: String { type.label }
}

struct Portfolio: Sendable {
    let data: PortfolioData
    /// Point in time for savings valuation.
    var asOf: Date = Date()

    static let allocationTypes: [AssetType] = [.SAVINGS, .STOCK, .FUND, .CRYPTO, .GOLD]

    var assets: [Asset] { data.assets }
    var savingsAccounts: [SavingsAccount] { data.savingsAccounts }

    func latestPrice(_ symbol: String?) -> MarketPrice? {
        guard let symbol else { return nil }
        return data.marketPrices.first { $0.symbol == symbol }
    }

    func transactions(for assetId: String) -> [Transaction] {
        data.transactions.filter { $0.assetId == assetId }
    }

    func holdings(_ type: AssetType) -> [Holding] {
        data.assets
            .filter { $0.type == type }
            .map { Calc.computeHolding(asset: $0, txs: transactions(for: $0.id), latestPrice: latestPrice($0.symbol)) }
            .filter { $0.quantity > 0 }
    }

    func holding(assetId: String) -> Holding? {
        guard let a = data.assets.first(where: { $0.id == assetId }) else { return nil }
        return Calc.computeHolding(asset: a, txs: transactions(for: a.id), latestPrice: latestPrice(a.symbol))
    }

    func savingsAccount(_ id: String) -> SavingsAccount? {
        data.savingsAccounts.first { $0.id == id }
    }

    func savingsValue() -> Double {
        data.savingsAccounts.reduce(0) { $0 + Calc.savingsState($1, asOf: asOf).value }
    }

    func typeValue(_ type: AssetType) -> Double {
        if type == .SAVINGS { return savingsValue() }
        return holdings(type).reduce(0) { $0 + $1.value }
    }

    func typeCost(_ type: AssetType) -> Double {
        if type == .SAVINGS {
            return data.savingsAccounts.reduce(0) { $0 + (Calc.savingsState($1, asOf: asOf).closed ? 0 : $1.principal) }
        }
        return holdings(type).reduce(0) { $0 + $1.cost }
    }

    func allocation() -> [Allocation] {
        Self.allocationTypes.map { Allocation(type: $0, value: typeValue($0), cost: typeCost($0)) }
    }

    func totalAssets() -> Double { allocation().reduce(0) { $0 + $1.value } }

    func totalCost() -> Double { allocation().reduce(0) { $0 + $1.cost } }

    /// Synthetic net-worth history until real snapshots exist (same curve as the web).
    func netWorthHistory(days: Int = 180) -> [DailySnapshot] {
        let total = totalAssets()
        var out: [DailySnapshot] = []
        let cal = Calendar.current
        for i in stride(from: days, through: 0, by: -1) {
            let dt = cal.date(byAdding: .day, value: -i, to: Date()) ?? Date()
            let progress = Double(days - i) / Double(days)
            let wobble = sin(Double(i) / 9) * 0.012
            let factor = 0.86 + 0.14 * progress + wobble
            out.append(DailySnapshot(date: DateUtil.isoDay(dt), totalValue: Calc.round(total * factor, 0)))
        }
        if !out.isEmpty { out[out.count - 1].totalValue = total }
        return out
    }

    static func fromSnapshots(_ snaps: [DailySnapshot]) -> [DailySnapshot] {
        snaps.sorted { $0.date < $1.date }
    }

    /// Today's snapshot row for daily_snapshots.
    func snapshot(date: String = DateUtil.today) -> DailySnapshot {
        DailySnapshot(date: date, cashValue: 0, savingsValue: savingsValue(), stockValue: typeValue(.STOCK),
                      fundValue: typeValue(.FUND), cryptoValue: typeValue(.CRYPTO), totalValue: totalAssets())
    }

    /// Savings whose current cycle matures within 7 days (dashboard reminder).
    func maturingSoon() -> [(account: SavingsAccount, days: Int)] {
        data.savingsAccounts
            .map { s -> (SavingsAccount, Calc.SavingsState, Int) in
                let st = Calc.savingsState(s, asOf: asOf)
                return (s, st, DateUtil.daysUntil(st.cycleMaturity, from: asOf))
            }
            .filter { !$0.1.closed && $0.2 <= 7 }
            .sorted { $0.2 < $1.2 }
            .map { ($0.0, $0.2) }
    }

    /// Average savings rate weighted by principal, 6% when there is none (same as the web Tương lai page).
    func averageSavingsRate() -> Double {
        let totalPrincipal = data.savingsAccounts.reduce(0) { $0 + $1.principal }
        guard totalPrincipal > 0 else { return 0.06 }
        return data.savingsAccounts.reduce(0) { $0 + $1.rate * $1.principal } / totalPrincipal
    }
}
