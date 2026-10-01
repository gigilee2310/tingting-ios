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
    private var lastDailyRefresh: String {
        get { UserDefaults.standard.string(forKey: "lastDailyRefresh") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "lastDailyRefresh") }
    }
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
            await dailyRefreshIfNeeded()
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
        await dailyRefreshIfNeeded()
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
            backgroundedAt = nil
            if phase == .ready, let last = lastLoaded, Date().timeIntervalSince(last) > 300 {
                Task { await reload() }
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

    /// Once a day: refresh crypto + gold prices (replaces the web's daily cron) and record today's net worth.
    func dailyRefreshIfNeeded() async {
        let today = DateUtil.today
        guard phase == .ready, lastDailyRefresh != today, !portfolio.assets.isEmpty else { return }
        lastDailyRefresh = today
        let assets = portfolio.assets
        _ = try? await repo.updatePrices(.CRYPTO, assets: assets)
        _ = try? await repo.updatePrices(.GOLD, assets: assets)
        await reload()
        try? await repo.upsertSnapshot(portfolio.snapshot())
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
