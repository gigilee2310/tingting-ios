import XCTest
@testable import TingTing

/// Port of the web's tests/calc.test.ts — the app must compute exactly the same numbers.
final class CalcTests: XCTestCase {
    private func tx(_ type: TxType, _ q: Double, _ p: Double, status: TxStatus = .confirmed) -> Transaction {
        Transaction(type: type, quantity: q, price: p, status: status)
    }

    func testAveragesCostAcrossTwoBuys() {
        let pos = Calc.computePosition([tx(.BUY, 100, 90_000), tx(.BUY, 100, 110_000)])
        XCTAssertEqual(pos.quantity, 200)
        XCTAssertEqual(pos.avgCost, 100_000)
        XCTAssertEqual(pos.cost, 20_000_000)
    }

    func testSellKeepsAvgCost() {
        let pos = Calc.computePosition([tx(.BUY, 200, 100_000), tx(.SELL, 50, 130_000)])
        XCTAssertEqual(pos.quantity, 150)
        XCTAssertEqual(pos.avgCost, 100_000)
    }

    func testIgnoresNonConfirmed() {
        XCTAssertEqual(Calc.computePosition([tx(.BUY, 100, 100_000, status: .pending_review)]).quantity, 0)
    }

    func testTransactionTotal() {
        XCTAssertEqual(Calc.transactionTotal(type: .BUY, quantity: 200, price: 93_200, fee: 10_000, tax: 0), 18_650_000)
        XCTAssertEqual(Calc.transactionTotal(type: .SELL, quantity: 100, price: 100_000, fee: 5_000, tax: 10_000), 9_985_000)
    }

    func testCompoundFutureValue() {
        XCTAssertEqual(Calc.compoundFutureValue(100_000_000, 0.065, 5), 137_008_666)
        XCTAssertEqual(Calc.compoundFutureValue(50_000_000, 0.07, 0), 50_000_000)
    }

    func testGoalAlreadyReached() {
        let r = Calc.goalMonthlyContribution(currentTotal: 1_000_000_000, goal: 1_100_000_000, years: 5, annualRate: 0.1)
        XCTAssertTrue(r.alreadyReached)
        XCTAssertEqual(r.requiredMonthly, 0)
    }

    func testGoalNeedsContribution() {
        let r = Calc.goalMonthlyContribution(currentTotal: 100_000_000, goal: 1_000_000_000, years: 10, annualRate: 0.1)
        XCTAssertFalse(r.alreadyReached)
        XCTAssertGreaterThan(r.requiredMonthly, 0)
        XCTAssertLessThan(r.projectedFromCurrent, 1_000_000_000)
    }

    func testGoalZeroRate() {
        let r = Calc.goalMonthlyContribution(currentTotal: 0, goal: 120_000_000, years: 10, annualRate: 0)
        XCTAssertEqual(r.requiredMonthly, 1_000_000)
    }

    func testScenario() {
        XCTAssertEqual(Calc.scenarioFutureValue(200_000_000, 0.1, 3), 266_200_000)
    }

    func testAccruedInterest() {
        XCTAssertEqual(Calc.accruedInterest(100_000_000, 0.065, startDate: "2030-01-01", asOf: DateUtil.parse("2029-01-01")), 0)
        let v = Calc.accruedInterest(100_000_000, 0.06, startDate: "2025-01-01", asOf: DateUtil.parse("2025-07-02"))
        XCTAssertGreaterThan(v, 2_900_000)
        XCTAssertLessThan(v, 3_100_000)
    }

    func testAnnuity() {
        XCTAssertEqual(Calc.annuityFutureValue(1_000_000, 0, 1, 1), 12_000_000)
        XCTAssertEqual(Calc.annuityFutureValue(0, 0.1, 5, 6), 0)
    }

    // MARK: Savings renewal cycles

    func testSavingsAutoRenewCompounds() {
        let s = SavingsAccount(institution: "VCB", principal: 100_000_000, rate: 0.06,
                               startDate: "2024-01-01", maturityDate: "2025-01-01", autoRenew: true)
        let st = Calc.savingsState(s, asOf: DateUtil.parse("2025-07-01"))
        XCTAssertFalse(st.closed)
        XCTAssertEqual(st.history.count, 1)
        XCTAssertGreaterThan(st.principal, 100_000_000)  // rolled interest into principal
        XCTAssertEqual(st.cycleStart, "2025-01-01")
    }

    func testSavingsNoRenewCloses() {
        let s = SavingsAccount(institution: "ACB", principal: 150_000_000, rate: 0.062,
                               startDate: "2024-06-15", maturityDate: "2025-06-15", autoRenew: false)
        let st = Calc.savingsState(s, asOf: DateUtil.parse("2025-08-01"))
        XCTAssertTrue(st.closed)
        XCTAssertEqual(st.value, 0)
        XCTAssertGreaterThan(st.maturedBalance, 150_000_000)
    }

    // MARK: Portfolio aggregation

    func testPortfolioTotals() {
        let assets = [Asset(id: "a", type: .STOCK, symbol: "VCB", name: "Vietcombank"),
                      Asset(id: "b", type: .CRYPTO, symbol: "BTC", name: "Bitcoin")]
        let txs = [Transaction(assetId: "a", type: .BUY, quantity: 100, price: 90_000),
                   Transaction(assetId: "b", type: .BUY, quantity: 0.1, price: 2_000_000_000)]
        let prices = [MarketPrice(symbol: "VCB", price: 100_000, date: "2025-01-02"),
                      MarketPrice(symbol: "VCB", price: 50_000, date: "2025-01-01")]
        let p = Portfolio(data: PortfolioData(assets: assets, transactions: txs, savingsAccounts: [], marketPrices: prices))
        XCTAssertEqual(p.typeValue(.STOCK), 10_000_000)  // newest price wins
        XCTAssertEqual(p.typeValue(.CRYPTO), 200_000_000)  // no price → avg cost
        XCTAssertEqual(p.totalAssets(), 210_000_000)
        XCTAssertEqual(p.totalCost(), 209_000_000)
    }

    func testPriceChangesSinceLastOpen() {
        let assets = [Asset(id: "a", type: .STOCK, symbol: "VCB", name: "VCB"),
                      Asset(id: "b", type: .FUND, symbol: "DCDS", name: "DCDS")]
        let txs = [Transaction(assetId: "a", type: .BUY, quantity: 100, price: 50_000),
                   Transaction(assetId: "b", type: .BUY, quantity: 10, price: 90_000)]
        let oldPrices = [MarketPrice(symbol: "VCB", price: 58_000, date: "2026-09-30"),
                         MarketPrice(symbol: "DCDS", price: 93_000, date: "2026-09-30")]
        let newPrices = [MarketPrice(symbol: "VCB", price: 57_600, date: "2026-10-01")] + oldPrices
        let before = Portfolio(data: PortfolioData(assets: assets, transactions: txs, marketPrices: oldPrices))
        let after = Portfolio(data: PortfolioData(assets: assets, transactions: txs, marketPrices: newPrices))
        let changes = PriceChange.compute(before: before, after: after)
        XCTAssertEqual(changes.count, 1)  // DCDS unchanged → not listed
        XCTAssertEqual(changes.first?.symbol, "VCB")
        XCTAssertEqual(changes.first?.valueDelta, -40_000)
        XCTAssertEqual(changes.first?.percent ?? 0, -400.0 / 58_000, accuracy: 1e-9)
    }

    func testPriceUnit() {
        XCTAssertEqual(Calc.priceUnit(.STOCK), 1000)
        XCTAssertEqual(Calc.priceUnit(.FUND), 1)
    }
}

final class FormatTests: XCTestCase {
    func testVND() {
        XCTAssertEqual(Fmt.vnd(25_000), "25,000 ₫")
        XCTAssertEqual(Fmt.vnd(1_500_000_000, compact: true), "1.5 tỷ")
        XCTAssertEqual(Fmt.vnd(2_000_000, compact: true, sign: true), "+2 tr")
        XCTAssertEqual(Fmt.vnd(-1_250, compact: true), "-1.2k")  // JS Math.round(-12.5) = -12
    }

    func testPercent() {
        XCTAssertEqual(Fmt.percent(0.1234), "+12.3%")
        XCTAssertEqual(Fmt.percent(-0.05), "-5.0%")
    }

    func testParse() {
        XCTAssertEqual(Fmt.parse("1,250,000"), 1_250_000)
        XCTAssertEqual(Fmt.parse("59.3"), 59.3)
        XCTAssertNil(Fmt.parse(""))
    }

    func testNumberFieldGrouping() {
        XCTAssertEqual(NumberField.grouped("1250000"), "1,250,000")
        XCTAssertEqual(NumberField.grouped("1234.5"), "1,234.5")
        XCTAssertEqual(NumberField.raw("1,250,000", allowsDecimal: true), "1250000")
    }

    func testAIJSONTolerance() {
        let obj = AIJSON.object("```json\n{\"items\":[{\"kind\":\"transaction\"}]}\n```")
        XCTAssertNotNil(obj?["items"])
        XCTAssertNil(AIJSON.object("no json"))
    }
}
