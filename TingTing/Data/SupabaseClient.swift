import Foundation

struct AuthSession: Codable, Sendable {
    var accessToken: String
    var refreshToken: String
    /// Unix seconds.
    var expiresAt: Double
    var userId: String
    var email: String?
}

/// Thin REST client for Supabase Auth (GoTrue) + PostgREST. Talks to the same project as the web app;
/// Row Level Security keeps every user to their own rows. Only the publishable/anon key ships in the app.
actor SupabaseClient {
    static let shared = SupabaseClient()

    private let baseURL: URL?
    private let apiKey: String
    private var session: AuthSession?
    private var refreshTask: Task<AuthSession, Error>?
    private let keychainAccount = "supabase-session"

    init() {
        let url = Secrets.supabaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        baseURL = url.isEmpty ? nil : URL(string: url)
        apiKey = Secrets.supabaseKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if let data = Keychain.data(keychainAccount) {
            session = try? JSONDecoder().decode(AuthSession.self, from: data)
        }
    }

    nonisolated var isConfigured: Bool {
        !Secrets.supabaseURL.isEmpty && !Secrets.supabaseKey.isEmpty
    }

    func currentSession() -> AuthSession? { session }

    // MARK: - Auth

    func signIn(email: String, password: String) async throws -> AuthSession {
        let body: [String: Any] = ["email": email, "password": password]
        let data = try await authRequest(path: "token", query: [URLQueryItem(name: "grant_type", value: "password")], body: body)
        let s = try parseSession(data)
        store(s)
        return s
    }

    func signOut() async {
        if let s = session, let url = authURL("logout") {
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue(apiKey, forHTTPHeaderField: "apikey")
            req.setValue("Bearer \(s.accessToken)", forHTTPHeaderField: "Authorization")
            _ = try? await URLSession.shared.data(for: req)
        }
        store(nil)
    }

    func updatePassword(_ password: String) async throws {
        let s = try await validSession()
        guard let url = authURL("user") else { throw AppError.notConfigured }
        var req = URLRequest(url: url)
        req.httpMethod = "PUT"
        req.setValue(apiKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(s.accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["password": password])
        _ = try await send(req)
    }

    func validSession() async throws -> AuthSession {
        guard let s = session else { throw AppError.notSignedIn }
        if s.expiresAt - 60 > Date().timeIntervalSince1970 { return s }
        return try await refresh()
    }

    private func refresh() async throws -> AuthSession {
        if let task = refreshTask { return try await task.value }
        guard let s = session else { throw AppError.notSignedIn }
        let task = Task { () throws -> AuthSession in
            let data = try await self.authRequest(path: "token", query: [URLQueryItem(name: "grant_type", value: "refresh_token")],
                                                  body: ["refresh_token": s.refreshToken])
            return try await self.parseSession(data)
        }
        refreshTask = task
        defer { refreshTask = nil }
        do {
            let fresh = try await task.value
            store(fresh)
            return fresh
        } catch let AppError.server(code, _) where code == 400 || code == 401 {
            store(nil)  // refresh token revoked/expired → must sign in again
            throw AppError.notSignedIn
        }
    }

    private func store(_ s: AuthSession?) {
        session = s
        Keychain.set(s.flatMap { try? JSONEncoder().encode($0) }, for: keychainAccount)
    }

    private func parseSession(_ data: Data) throws -> AuthSession {
        guard let j = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let access = j["access_token"] as? String,
              let refresh = j["refresh_token"] as? String,
              let user = j["user"] as? [String: Any],
              let uid = user["id"] as? String else { throw AppError.badResponse }
        let expiresAt = (j["expires_at"] as? Double)
            ?? Date().timeIntervalSince1970 + ((j["expires_in"] as? Double) ?? 3600)
        return AuthSession(accessToken: access, refreshToken: refresh, expiresAt: expiresAt, userId: uid,
                           email: user["email"] as? String)
    }

    private func authURL(_ path: String, query: [URLQueryItem] = []) -> URL? {
        guard let baseURL else { return nil }
        var c = URLComponents(url: baseURL.appendingPathComponent("auth/v1/\(path)"), resolvingAgainstBaseURL: false)
        if !query.isEmpty { c?.queryItems = query }
        return c?.url
    }

    private func authRequest(path: String, query: [URLQueryItem], body: [String: Any]) async throws -> Data {
        guard let url = authURL(path, query: query) else { throw AppError.notConfigured }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(apiKey, forHTTPHeaderField: "apikey")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        do {
            return try await send(req)
        } catch AppError.server(let code, let msg) where code == 400 && msg.lowercased().contains("invalid login") {
            throw AppError.invalidCredentials
        }
    }

    // MARK: - PostgREST

    private func restURL(_ table: String, query: [URLQueryItem]) -> URL? {
        guard let baseURL else { return nil }
        var c = URLComponents(url: baseURL.appendingPathComponent("rest/v1/\(table)"), resolvingAgainstBaseURL: false)
        if !query.isEmpty { c?.queryItems = query }
        // PostgREST filter values may contain "," etc.; "+" must be escaped explicitly.
        let encoded = c?.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        c?.percentEncodedQuery = encoded
        return c?.url
    }

    private func rest(_ method: String, _ table: String, query: [URLQueryItem] = [], body: Data? = nil,
                      prefer: String? = nil, retry: Bool = true) async throws -> Data {
        guard let url = restURL(table, query: query) else { throw AppError.notConfigured }
        let s = try await validSession()
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue(apiKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(s.accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let prefer { req.setValue(prefer, forHTTPHeaderField: "Prefer") }
        req.httpBody = body
        do {
            return try await send(req)
        } catch AppError.server(let code, _) where code == 401 && retry {
            _ = try await refresh()
            return try await rest(method, table, query: query, body: body, prefer: prefer, retry: false)
        }
    }

    func select<T: Decodable>(_ table: String, _ type: T.Type, query: [URLQueryItem]) async throws -> [T] {
        let data = try await rest("GET", table, query: [URLQueryItem(name: "select", value: "*")] + query)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        do {
            return try decoder.decode([T].self, from: data)
        } catch {
            throw AppError.badResponse
        }
    }

    /// Inserts rows; returns the inserted rows as JSON objects.
    @discardableResult
    func insert(_ table: String, _ rows: [[String: Any]]) async throws -> [[String: Any]] {
        let body = try JSONSerialization.data(withJSONObject: rows)
        let data = try await rest("POST", table, body: body, prefer: "return=representation")
        return (try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
    }

    func upsert(_ table: String, _ rows: [[String: Any]], onConflict: String) async throws {
        let body = try JSONSerialization.data(withJSONObject: rows)
        _ = try await rest("POST", table, query: [URLQueryItem(name: "on_conflict", value: onConflict)], body: body,
                           prefer: "resolution=merge-duplicates,return=minimal")
    }

    func update(_ table: String, _ values: [String: Any], filters: [URLQueryItem]) async throws {
        let body = try JSONSerialization.data(withJSONObject: values)
        _ = try await rest("PATCH", table, query: filters, body: body, prefer: "return=minimal")
    }

    func delete(_ table: String, filters: [URLQueryItem]) async throws {
        _ = try await rest("DELETE", table, query: filters, prefer: "return=minimal")
    }

    /// Deletes and returns how many rows were actually removed.
    func deleteCount(_ table: String, filters: [URLQueryItem]) async throws -> Int {
        let data = try await rest("DELETE", table, query: filters, prefer: "return=representation")
        return ((try? JSONSerialization.jsonObject(with: data)) as? [Any])?.count ?? 0
    }

    // MARK: - HTTP

    private func send(_ req: URLRequest) async throws -> Data {
        let result: (Data, URLResponse)
        do {
            result = try await URLSession.shared.data(for: req)
        } catch {
            throw AppError.network(error.localizedDescription)
        }
        let (data, response) = result
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            throw AppError.server(code, Self.errorMessage(data))
        }
        return data
    }

    static func errorMessage(_ data: Data) -> String {
        guard let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return String(data: data, encoding: .utf8) ?? ""
        }
        for key in ["msg", "message", "error_description", "error", "hint"] {
            if let s = j[key] as? String, !s.isEmpty { return s }
        }
        return ""
    }
}

/// PostgREST filter helper: `.eq("user_id", id)` → `user_id=eq.<id>`.
extension URLQueryItem {
    static func eq(_ column: String, _ value: String) -> URLQueryItem {
        URLQueryItem(name: column, value: "eq.\(value)")
    }
}
