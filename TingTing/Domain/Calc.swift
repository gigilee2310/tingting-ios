import Foundation

/// Pure financial calculations, ported 1:1 from the web app's lib/calc.ts.
/// AI must NEVER perform these — code only. Covered by CalcTests.
enum Calc {
    // MARK: - Rounding (matches JS Math.round((n + EPSILON) * f) / f)

    static func round(_ n: Double, _ decimals: Int = 0) -> Double {
        let f = pow(10, Double(decimals))
        return ((n + Double.ulpOfOne) * f + 0.5).rounded(.down) / f
    }

    // MARK: - Positions

    /// Weighted-average cost and net quantity. SELL/WITHDRAW reduce quantity
    /// without changing the average cost.
    static func computePosition(_ txs: [Transaction]) -> (quantity: Double, avgCost: Double, cost: Double) {
        var qty = 0.0
        var costBasis = 0.0
        for t in txs where t.status == .confirmed {
            let q = t.quantity ?? 0
            if t.type == .BUY || t.type == .DEPOSIT {
                qty += q
                costBasis += q * (t.price ?? 0) + t.fee
            } else {
                let avg = qty > 0 ? costBasis / qty : 0
                let sellQty = min(q, qty)
                qty -= sellQty
                costBasis -= sellQty * avg
            }
        }
        let avgCost = qty > 0 ? costBasis / qty : 0
        return (round(qty, 8), round(avgCost, 4), round(qty * avgCost, 0))
    }

    /// Total for a single transaction — code computes this, never AI.
    static func transactionTotal(type: TxType, quantity: Double?, price: Double?, fee: Double = 0, tax: Double = 0) -> Double {
        let gross = (quantity ?? 0) * (price ?? 0)
        if type == .SELL || type == .WITHDRAW { return round(gross - fee - tax, 0) }
        return round(gross + fee + tax, 0)
    }

    static func computeHolding(asset: Asset, txs: [Transaction], latestPrice: MarketPrice?) -> Holding {
        let pos = computePosition(txs)
        let price = latestPrice?.price ?? pos.avgCost
        let value = round(pos.quantity * price, 0)
        let pl = round(value - pos.cost, 0)
        let roi = pos.cost > 0 ? pl / pos.cost : 0
        return Holding(asset: asset, quantity: pos.quantity, avgCost: pos.avgCost, cost: pos.cost, price: price,
                       value: value, unrealizedPl: pl, roi: roi, priceIsStale: latestPrice?.isStale ?? true)
    }

    // MARK: - Projections

    /// FV = P × (1+r)^n
    static func compoundFutureValue(_ principal: Double, _ annualRate: Double, _ years: Double) -> Double {
        round(principal * pow(1 + annualRate, years), 0)
    }

    static func compoundCurve(_ principal: Double, _ annualRate: Double, _ years: Int) -> [(year: Int, value: Double)] {
        (0...max(0, years)).map { ($0, compoundFutureValue(principal, annualRate, Double($0))) }
    }

    static func scenarioFutureValue(_ currentValue: Double, _ annualRate: Double, _ years: Double) -> Double {
        round(currentValue * pow(1 + annualRate, years), 0)
    }

    /// Future value of contributing every `periodMonths` (ordinary annuity).
    static func annuityFutureValue(_ contribution: Double, _ annualRate: Double, _ years: Double, _ periodMonths: Double) -> Double {
        guard contribution > 0, years > 0, periodMonths > 0 else { return 0 }
        let periods = (years * 12) / periodMonths
        let rp = annualRate * (periodMonths / 12)
        if rp == 0 { return round(contribution * periods, 0) }
        return round(contribution * ((pow(1 + rp, periods) - 1) / rp), 0)
    }

    /// Required monthly contribution to reach `goal`.
    static func goalMonthlyContribution(currentTotal: Double, goal: Double, years: Double, annualRate: Double)
        -> (requiredMonthly: Double, projectedFromCurrent: Double, alreadyReached: Bool) {
        let nMonths = max(1, (years * 12 + 0.5).rounded(.down))
        let rMonth = annualRate / 12
        let projected = round(currentTotal * pow(1 + rMonth, nMonths), 0)
        if projected >= goal { return (0, projected, true) }
        let remaining = goal - projected
        let factor = rMonth == 0 ? nMonths : (pow(1 + rMonth, nMonths) - 1) / rMonth
        return (round(remaining / factor, 0), projected, false)
    }

    /// Savings growth when re-depositing every `periodMonths` (SavingsProjection on the web).
    static func periodicCompound(_ principal: Double, _ annualRate: Double, years: Double, periodMonths: Double) -> Double {
        let periodsPerYear = 12 / periodMonths
        let ratePerPeriod = annualRate * (periodMonths / 12)
        return (principal * pow(1 + ratePerPeriod, years * periodsPerYear) + 0.5).rounded(.down)
    }

    // MARK: - Savings

    struct SavingsCycle: Hashable, Sendable {
        let start: String
        let maturity: String
        let startPrincipal: Double
        let interest: Double
        let endBalance: Double
    }

    struct SavingsState: Sendable {
        let principal: Double
        let cycleStart: String
        let cycleMaturity: String
        let accrued: Double
        /// Counted toward net worth (0 once closed).
        let value: Double
        /// Matured & not renewed → withdrawn.
        let closed: Bool
        let maturedBalance: Double
        let history: [SavingsCycle]
    }

    static let day: TimeInterval = 86_400

    /// Roll a savings deposit forward through renewal cycles (see web calc.ts).
    static func savingsState(_ s: SavingsAccount, asOf: Date = Date()) -> SavingsState {
        let startT = DateUtil.parse(s.startDate).timeIntervalSince1970
        let maturityT = DateUtil.parse(s.maturityDate).timeIntervalSince1970
        let now = asOf.timeIntervalSince1970
        let term = maturityT - startT
        var history: [SavingsCycle] = []

        if term <= 0 {
            let accrued = accruedInterest(s.principal, s.rate, startDate: s.startDate, asOf: asOf)
            return SavingsState(principal: s.principal, cycleStart: s.startDate, cycleMaturity: s.maturityDate,
                                accrued: accrued, value: s.principal + accrued, closed: false,
                                maturedBalance: s.principal, history: history)
        }

        let termYears = term / (365.25 * day)
        var cycleStart = startT
        var principal = s.principal

        for _ in 0..<400 {
            let cycleMaturity = cycleStart + term
            if now < cycleMaturity {
                let accrued = round(principal * s.rate * ((now - cycleStart) / (365.25 * day)), 0)
                return SavingsState(principal: principal, cycleStart: DateUtil.isoDay(cycleStart),
                                    cycleMaturity: DateUtil.isoDay(cycleMaturity), accrued: accrued,
                                    value: round(principal + accrued, 0), closed: false,
                                    maturedBalance: principal, history: history)
            }
            let interest = round(principal * s.rate * termYears, 0)
            let endBalance = round(principal + interest, 0)
            history.append(SavingsCycle(start: DateUtil.isoDay(cycleStart), maturity: DateUtil.isoDay(cycleMaturity),
                                        startPrincipal: principal, interest: interest, endBalance: endBalance))
            if !s.autoRenew {
                return SavingsState(principal: principal, cycleStart: DateUtil.isoDay(cycleStart),
                                    cycleMaturity: DateUtil.isoDay(cycleMaturity), accrued: interest, value: 0,
                                    closed: true, maturedBalance: endBalance, history: history)
            }
            principal = endBalance
            cycleStart = cycleMaturity
        }
        return SavingsState(principal: principal, cycleStart: DateUtil.isoDay(cycleStart), cycleMaturity: s.maturityDate,
                            accrued: 0, value: round(principal, 0), closed: false, maturedBalance: principal, history: history)
    }

    /// Accrued interest up to `asOf` (simple daily proration over 365 days).
    static func accruedInterest(_ principal: Double, _ annualRate: Double, startDate: String, asOf: Date = Date()) -> Double {
        let start = DateUtil.parse(startDate).timeIntervalSince1970
        let now = asOf.timeIntervalSince1970
        if now <= start { return 0 }
        let days = (now - start) / day
        return round(principal * annualRate * (days / 365), 0)
    }

    /// Term of a savings account in years (maturity − start).
    static func termYears(_ s: SavingsAccount) -> Double {
        max(0, (DateUtil.parse(s.maturityDate).timeIntervalSince1970 - DateUtil.parse(s.startDate).timeIntervalSince1970) / (365.25 * day))
    }

    // MARK: - Units

    /// Vietnamese stock prices are quoted in thousands of đồng (59.3 = 59,300₫).
    static func priceUnit(_ type: AssetType) -> Double {
        type == .STOCK ? 1000 : 1
    }
}

/// Date helpers that match JS `new Date("YYYY-MM-DD")` (UTC midnight) and `toISOString().slice(0, 10)`.
enum DateUtil {
    private static let utc = TimeZone(identifier: "UTC")!

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = utc
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let displayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "vi_VN")
        f.timeZone = utc
        f.dateFormat = "dd/MM/yyyy"
        return f
    }()

    static func parse(_ s: String) -> Date {
        dayFormatter.date(from: String(s.prefix(10))) ?? Date(timeIntervalSince1970: 0)
    }

    static func isoDay(_ t: TimeInterval) -> String {
        dayFormatter.string(from: Date(timeIntervalSince1970: t))
    }

    static func isoDay(_ d: Date) -> String {
        dayFormatter.string(from: d)
    }

    /// A date picked in the UI, as YYYY-MM-DD in the phone's own time zone.
    static func localDay(_ d: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: d)
    }

    /// Today as YYYY-MM-DD in UTC (same as the web's `new Date().toISOString().slice(0, 10)`).
    static var today: String { isoDay(Date()) }

    static func display(_ s: String) -> String {
        displayFormatter.string(from: parse(s))
    }

    /// Adds calendar months to a YYYY-MM-DD string (UTC).
    static func addMonths(_ s: String, _ months: Int) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = utc
        let d = cal.date(byAdding: .month, value: months, to: parse(s)) ?? parse(s)
        return isoDay(d)
    }

    static func daysUntil(_ s: String, from now: Date = Date()) -> Int {
        Int(((parse(s).timeIntervalSince1970 - now.timeIntervalSince1970) / Calc.day).rounded(.up))
    }
}
