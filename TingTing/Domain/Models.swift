import Foundation

// Domain types mirroring the web app (lib/types.ts). Money values are VND.

enum AssetType: String, Codable, CaseIterable, Identifiable, Sendable {
    case CASH, SAVINGS, STOCK, FUND, CRYPTO, GOLD

    var id: String { rawValue }

    var label: String {
        switch self {
        case .CASH: "Tiền mặt"
        case .SAVINGS: "Tiết kiệm"
        case .STOCK: "Chứng khoán"
        case .FUND: "Chứng chỉ quỹ"
        case .CRYPTO: "Crypto"
        case .GOLD: "Vàng"
        }
    }

    /// Lowercase label used inside sentences ("Lệnh chứng khoán · VCB").
    var shortLabel: String {
        switch self {
        case .STOCK: "chứng khoán"
        case .FUND: "quỹ"
        case .CRYPTO: "crypto"
        case .GOLD: "vàng"
        case .SAVINGS: "tiết kiệm"
        case .CASH: "tiền mặt"
        }
    }
}

enum TxType: String, Codable, CaseIterable, Sendable {
    case BUY, SELL, DEPOSIT, WITHDRAW

    var isInflow: Bool { self == .BUY || self == .DEPOSIT }
}

enum TxStatus: String, Codable, Sendable {
    case pending_review, confirmed, rejected
}

struct Asset: Codable, Identifiable, Hashable, Sendable {
    let id: String
    var type: AssetType
    var symbol: String?
    var name: String
    var currency: String
    var institution: String?

    init(id: String, type: AssetType, symbol: String?, name: String, currency: String = "VND", institution: String? = nil) {
        self.id = id
        self.type = type
        self.symbol = symbol
        self.name = name
        self.currency = currency
        self.institution = institution
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        type = try c.decode(AssetType.self, forKey: .type)
        symbol = try c.decodeIfPresent(String.self, forKey: .symbol)
        name = try c.decode(String.self, forKey: .name)
        currency = try c.decodeIfPresent(String.self, forKey: .currency) ?? "VND"
        institution = try c.decodeIfPresent(String.self, forKey: .institution)
    }
}

struct Transaction: Codable, Identifiable, Hashable, Sendable {
    let id: String
    var assetId: String
    var type: TxType
    var quantity: Double?
    var price: Double?
    var fee: Double
    var tax: Double
    var total: Double
    var date: String
    var source: String?
    var status: TxStatus
    var correctsTransactionId: String?

    init(id: String = UUID().uuidString, assetId: String = "a1", type: TxType, quantity: Double?, price: Double?,
         fee: Double = 0, tax: Double = 0, total: Double = 0, date: String = "2025-01-01",
         source: String? = nil, status: TxStatus = .confirmed, correctsTransactionId: String? = nil) {
        self.id = id
        self.assetId = assetId
        self.type = type
        self.quantity = quantity
        self.price = price
        self.fee = fee
        self.tax = tax
        self.total = total
        self.date = date
        self.source = source
        self.status = status
        self.correctsTransactionId = correctsTransactionId
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        assetId = try c.decode(String.self, forKey: .assetId)
        type = try c.decode(TxType.self, forKey: .type)
        quantity = try c.flexibleDoubleIfPresent(.quantity)
        price = try c.flexibleDoubleIfPresent(.price)
        fee = try c.flexibleDoubleIfPresent(.fee) ?? 0
        tax = try c.flexibleDoubleIfPresent(.tax) ?? 0
        total = try c.flexibleDoubleIfPresent(.total) ?? 0
        date = try c.decode(String.self, forKey: .date)
        source = try c.decodeIfPresent(String.self, forKey: .source)
        status = try c.decodeIfPresent(TxStatus.self, forKey: .status) ?? .confirmed
        correctsTransactionId = try c.decodeIfPresent(String.self, forKey: .correctsTransactionId)
    }
}

struct SavingsAccount: Codable, Identifiable, Hashable, Sendable {
    let id: String
    var assetId: String
    var institution: String
    var principal: Double
    /// Annual, e.g. 0.065
    var rate: Double
    var startDate: String
    var maturityDate: String
    var autoRenew: Bool

    init(id: String = UUID().uuidString, assetId: String = "", institution: String, principal: Double, rate: Double,
         startDate: String, maturityDate: String, autoRenew: Bool) {
        self.id = id
        self.assetId = assetId
        self.institution = institution
        self.principal = principal
        self.rate = rate
        self.startDate = startDate
        self.maturityDate = maturityDate
        self.autoRenew = autoRenew
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        assetId = try c.decode(String.self, forKey: .assetId)
        institution = try c.decode(String.self, forKey: .institution)
        principal = try c.flexibleDoubleIfPresent(.principal) ?? 0
        rate = try c.flexibleDoubleIfPresent(.rate) ?? 0
        startDate = try c.decode(String.self, forKey: .startDate)
        maturityDate = try c.decode(String.self, forKey: .maturityDate)
        autoRenew = try c.decodeIfPresent(Bool.self, forKey: .autoRenew) ?? true
    }
}

struct MarketPrice: Codable, Hashable, Sendable {
    var symbol: String
    var price: Double
    var currency: String
    var date: String
    var sourceUrl: String?
    var isStale: Bool

    init(symbol: String, price: Double, currency: String = "VND", date: String, sourceUrl: String? = nil, isStale: Bool = false) {
        self.symbol = symbol
        self.price = price
        self.currency = currency
        self.date = date
        self.sourceUrl = sourceUrl
        self.isStale = isStale
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        symbol = try c.decode(String.self, forKey: .symbol)
        price = try c.flexibleDoubleIfPresent(.price) ?? 0
        currency = try c.decodeIfPresent(String.self, forKey: .currency) ?? "VND"
        date = try c.decode(String.self, forKey: .date)
        sourceUrl = try c.decodeIfPresent(String.self, forKey: .sourceUrl)
        isStale = try c.decodeIfPresent(Bool.self, forKey: .isStale) ?? false
    }
}

struct DailySnapshot: Codable, Hashable, Sendable, Identifiable {
    var date: String
    var cashValue: Double
    var savingsValue: Double
    var stockValue: Double
    var fundValue: Double
    var cryptoValue: Double
    var totalValue: Double

    var id: String { date }

    init(date: String, cashValue: Double = 0, savingsValue: Double = 0, stockValue: Double = 0,
         fundValue: Double = 0, cryptoValue: Double = 0, totalValue: Double) {
        self.date = date
        self.cashValue = cashValue
        self.savingsValue = savingsValue
        self.stockValue = stockValue
        self.fundValue = fundValue
        self.cryptoValue = cryptoValue
        self.totalValue = totalValue
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        date = try c.decode(String.self, forKey: .date)
        cashValue = try c.flexibleDoubleIfPresent(.cashValue) ?? 0
        savingsValue = try c.flexibleDoubleIfPresent(.savingsValue) ?? 0
        stockValue = try c.flexibleDoubleIfPresent(.stockValue) ?? 0
        fundValue = try c.flexibleDoubleIfPresent(.fundValue) ?? 0
        cryptoValue = try c.flexibleDoubleIfPresent(.cryptoValue) ?? 0
        totalValue = try c.flexibleDoubleIfPresent(.totalValue) ?? 0
    }
}

enum AIProvider: String, Codable, CaseIterable, Identifiable, Sendable {
    case anthropic, openai, deepseek

    var id: String { rawValue }

    var label: String {
        switch self {
        case .anthropic: "Anthropic (Claude)"
        case .openai: "OpenAI (GPT)"
        case .deepseek: "DeepSeek"
        }
    }

    var defaultModel: String {
        switch self {
        case .anthropic: "claude-opus-5-5"
        case .openai: "gpt-4o"
        case .deepseek: "deepseek-chat"
        }
    }

    var supportsVision: Bool { self != .deepseek }
}

struct UserSettings: Codable, Sendable {
    var aiProvider: AIProvider?
    var aiApiKey: String?
    var aiModel: String?
}

/// Derived, code-computed holding view.
struct Holding: Identifiable, Hashable, Sendable {
    let asset: Asset
    let quantity: Double
    let avgCost: Double
    let cost: Double
    let price: Double
    let value: Double
    let unrealizedPl: Double
    let roi: Double
    let priceIsStale: Bool

    var id: String { asset.id }
}

extension KeyedDecodingContainer {
    /// PostgREST returns `numeric` as JSON numbers, but tolerate strings too.
    func flexibleDoubleIfPresent(_ key: Key) throws -> Double? {
        guard contains(key) else { return nil }
        if try decodeNil(forKey: key) { return nil }
        if let d = try? decode(Double.self, forKey: key) { return d }
        if let s = try? decode(String.self, forKey: key) { return Double(s) }
        return nil
    }
}
