import Foundation

struct AIConfig: Sendable {
    let provider: AIProvider
    let apiKey: String
    let model: String

    /// From the user's saved settings (same row the web uses). nil when no key.
    init?(settings: UserSettings?) {
        guard let key = settings?.aiApiKey, !key.isEmpty else { return nil }
        let provider = settings?.aiProvider ?? .anthropic
        self.provider = provider
        apiKey = key
        let m = settings?.aiModel?.trimmingCharacters(in: .whitespaces) ?? ""
        model = m.isEmpty ? provider.defaultModel : m
    }
}

struct AIImage: Sendable {
    let base64: String
    let mediaType: String
}

/// One-shot completions across providers via raw HTTPS (no SDK for Swift).
enum AIClient {
    static func complete(_ cfg: AIConfig, system: String, user: String?, image: AIImage? = nil) async throws -> String {
        if image != nil && !cfg.provider.supportsVision { throw AppError.aiVisionUnsupported(cfg.provider.label) }
        switch cfg.provider {
        case .anthropic:
            return try await anthropic(cfg, system: system, user: user, image: image, webSearch: false)
        case .openai, .deepseek:
            return try await openAICompatible(cfg, system: system, user: user, image: image)
        }
    }

    /// Needs live web data (current prices). Anthropic uses the server-side web search tool;
    /// other providers fall back to a plain completion (may be outdated) — same as the web app.
    static func lookup(_ cfg: AIConfig, system: String, user: String) async throws -> String {
        if cfg.provider == .anthropic {
            if let text = try? await anthropic(cfg, system: system, user: user, image: nil, webSearch: true),
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return text
            }
        }
        return try await complete(cfg, system: system, user: user)
    }

    // MARK: - Anthropic Messages API

    /// Models that accept the server-side refusal fallback (`fallbacks: "default"`).
    private static let fallbackModels: Set<String> = ["claude-opus-5-5", "claude-opus-5", "claude-sonnet-5-5", "claude-fable-5-1"]

    private static func webSearchToolType(_ model: String) -> String {
        let modern = ["claude-opus-5", "claude-sonnet-5", "claude-fable-5", "claude-opus-4-6", "claude-opus-4-7",
                      "claude-opus-4-8", "claude-sonnet-4-6"]
        return modern.contains { model.hasPrefix($0) } ? "web_search_20260209" : "web_search_20250305"
    }

    private static func anthropic(_ cfg: AIConfig, system: String, user: String?, image: AIImage?, webSearch: Bool) async throws -> String {
        var content: [[String: Any]] = []
        if let image {
            content.append(["type": "image",
                            "source": ["type": "base64", "media_type": image.mediaType, "data": image.base64]])
        }
        if let user, !user.isEmpty { content.append(["type": "text", "text": user]) }

        var messages: [[String: Any]] = [["role": "user", "content": content]]
        let useFallback = fallbackModels.contains(cfg.model)

        // pause_turn (long server-tool turns): send the partial assistant turn back to continue.
        for _ in 0..<4 {
            var body: [String: Any] = ["model": cfg.model, "max_tokens": 16000, "system": system, "messages": messages]
            if webSearch {
                body["tools"] = [["type": webSearchToolType(cfg.model), "name": "web_search", "max_uses": 5]]
            }
            if useFallback { body["fallbacks"] = "default" }

            var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!, timeoutInterval: 180)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue(cfg.apiKey, forHTTPHeaderField: "x-api-key")
            req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            if useFallback { req.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta") }
            req.httpBody = try JSONSerialization.data(withJSONObject: body)

            let j = try await send(req)
            let stop = j["stop_reason"] as? String
            if stop == "refusal" { throw AppError.aiRefused }
            let blocks = j["content"] as? [[String: Any]] ?? []
            if stop == "pause_turn" {
                messages.append(["role": "assistant", "content": blocks])
                continue
            }
            return blocks.filter { $0["type"] as? String == "text" }
                .compactMap { $0["text"] as? String }
                .joined(separator: "\n")
        }
        throw AppError.ai("AI chạy quá lâu, hãy thử lại.")
    }

    // MARK: - OpenAI / DeepSeek (Chat Completions)

    private static func openAICompatible(_ cfg: AIConfig, system: String, user: String?, image: AIImage?) async throws -> String {
        let endpoint = cfg.provider == .deepseek
            ? "https://api.deepseek.com/chat/completions"
            : "https://api.openai.com/v1/chat/completions"
        var userContent: Any = user ?? ""
        if let image {
            var parts: [[String: Any]] = []
            if let user, !user.isEmpty { parts.append(["type": "text", "text": user]) }
            parts.append(["type": "image_url", "image_url": ["url": "data:\(image.mediaType);base64,\(image.base64)"]])
            userContent = parts
        }
        var body: [String: Any] = [
            "model": cfg.model,
            "messages": [["role": "system", "content": system], ["role": "user", "content": userContent]],
        ]
        if cfg.provider == .deepseek { body["max_tokens"] = 8000 } else { body["max_completion_tokens"] = 16000 }

        var req = URLRequest(url: URL(string: endpoint)!, timeoutInterval: 180)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(cfg.apiKey)", forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let j = try await send(req)
        let choices = j["choices"] as? [[String: Any]]
        let message = choices?.first?["message"] as? [String: Any]
        return message?["content"] as? String ?? ""
    }

    // MARK: - HTTP

    private static func send(_ req: URLRequest) async throws -> [String: Any] {
        let result: (Data, URLResponse)
        do {
            result = try await URLSession.shared.data(for: req)
        } catch {
            throw AppError.network(error.localizedDescription)
        }
        let (data, response) = result
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            let err = json["error"] as? [String: Any]
            let msg = err?["message"] as? String ?? String(data: data, encoding: .utf8) ?? "HTTP \(code)"
            if code == 401 || code == 403 { throw AppError.ai("API key không hợp lệ (\(code)). Kiểm tra lại trong Cài đặt → Trợ lý AI.") }
            if code == 429 { throw AppError.ai("Đã vượt giới hạn gọi AI (429). Thử lại sau ít phút.") }
            throw AppError.ai("\(code): \(msg)")
        }
        return json
    }
}

/// Parses a JSON object out of a model reply, tolerating ```json fences (web lib/ai/client.ts).
enum AIJSON {
    static func object(_ text: String) -> [String: Any]? {
        let cleaned = text.replacingOccurrences(of: "```json", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "```", with: "")
        guard let start = cleaned.firstIndex(of: "{"), let end = cleaned.lastIndex(of: "}"), start < end,
              let data = String(cleaned[start...end]).data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    static func double(_ v: Any?) -> Double? {
        if let n = v as? NSNumber { return n.doubleValue }
        if let s = v as? String { return Fmt.parse(s) }
        return nil
    }

    static func string(_ v: Any?) -> String? {
        if let s = v as? String, !s.isEmpty { return s }
        if let n = v as? NSNumber { return n.stringValue }
        return nil
    }
}
