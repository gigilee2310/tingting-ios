import Foundation
import LocalAuthentication
import Observation
import SwiftUI

/// App-wide state: session, lock, data, settings.
@MainActor
@Observable
final class AppStore {
    enum Phase { case launching, signedOut, ready }

    var phase: Phase = .launching
    var email: String?
    var portfolio = Portfolio(data: PortfolioData())
    var snapshots: [DailySnapshot] = []
    var settings: UserSettings?
    var isLoading = false
    var loadError: String?
    var lastLoaded: Date?

    // Face ID lock
    var isLocked = false
    var faceIDEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "faceIDEnabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "faceIDEnabled") }
    }
    var isRefreshingPrices = false
    var lastPriceNotes: [String] = []
    /// "Biến động giá" sheet shown after each refresh when something moved.
    var priceChanges: [PriceChange] = []
    var totalChange: Double = 0
    var showPriceChanges = false
    private var backgroundedAt: Date?

    let repo = Repository()

    var aiConfig: AIConfig? { AIConfig(settings: settings) }
    var isConfigured: Bool { SupabaseClient.shared.isConfigured }

    // MARK: - Lifecycle

    func start() async {
        guard isConfigured else { phase = .signedOut; return }
        if let s = await SupabaseClient.shared.currentSession() {
            email = s.email
            phase = .ready
            if faceIDEnabled { isLocked = true }
            await reload()
            await refreshPricesIfNeeded()
        } else {
            phase = .signedOut
        }
    }

    func signIn(email: String, password: String) async throws {
        let s = try await SupabaseClient.shared.signIn(email: email.trimmingCharacters(in: .whitespaces), password: password)
        self.email = s.email
        phase = .ready
        isLocked = false
        await reload()
        await refreshPricesIfNeeded()
    }

    func signOut() async {
        await SupabaseClient.shared.signOut()
        portfolio = Portfolio(data: PortfolioData())
        snapshots = []
        settings = nil
        phase = .signedOut
    }

    func scenePhaseChanged(_ newPhase: ScenePhase) {
        switch newPhase {
        case .background:
            backgroundedAt = Date()
        case .active:
            // Re-lock after 60 s in the background.
            if phase == .ready, faceIDEnabled, let t = backgroundedAt, Date().timeIntervalSince(t) > 60 {
                isLocked = true
            }
            let wasAwayAt = backgroundedAt
            backgroundedAt = nil
            // Coming back after > 60 s counts as opening the app again: fetch fresh prices.
            if phase == .ready, let t = wasAwayAt, Date().timeIntervalSince(t) > 60 {
                Task { await refreshPricesIfNeeded() }
            }
        default:
            break
        }
    }

    func unlock() async -> Bool {
        let ctx = LAContext()
        ctx.localizedCancelTitle = "Huỷ"
        do {
            // Face ID, falling back to the device passcode.
            let ok = try await ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Mở khoá Ting Ting")
            if ok { isLocked = false }
            return ok
        } catch {
            return false
        }
    }

    // MARK: - Data

    func reload() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let (data, snaps) = try await repo.loadAll()
            portfolio = Portfolio(data: data)
            snapshots = snaps
            settings = try? await repo.loadSettings()
            loadError = nil
            lastLoaded = Date()
        } catch AppError.notSignedIn {
            phase = .signedOut
        } catch {
            loadError = error.vietnamese
        }
    }

    /// Auto price update each time the app is opened (replaces the web's daily cron):
    /// stocks (SSI), funds (Fmarket), gold (PNJ), crypto (Binance). Then shows what moved since last time
    /// and records today's net worth.
    func refreshPricesIfNeeded(force: Bool = false) async {
        guard phase == .ready, !isRefreshingPrices, !portfolio.assets.isEmpty else { return }
        isRefreshingPrices = true
        defer { isRefreshingPrices = false }
        let before = portfolio
        lastPriceNotes = await repo.updateAllPrices(assets: before.assets)
        await reload()
        let changes = PriceChange.compute(before: before, after: portfolio)
        if !changes.isEmpty {
            priceChanges = changes
            totalChange = portfolio.totalAssets() - before.totalAssets()
            showPriceChanges = true
        }
        try? await repo.upsertSnapshot(portfolio.snapshot())
    }

    /// Pull-to-refresh: fresh prices + data.
    func refreshAll() async {
        await reload()
        await refreshPricesIfNeeded(force: true)
    }

    /// Runs a write, then reloads. Returns an error message or nil.
    @discardableResult
    func perform(_ work: () async throws -> Void) async -> String? {
        do {
            try await work()
            await reload()
            try? await repo.upsertSnapshot(portfolio.snapshot())
            return nil
        } catch {
            return error.vietnamese
        }
    }

    /// Net-worth history: real snapshots when there are at least 2, otherwise the synthetic curve (like the web).
    var history: [DailySnapshot] {
        snapshots.count > 1 ? Portfolio.fromSnapshots(snapshots) : portfolio.netWorthHistory()
    }
}
