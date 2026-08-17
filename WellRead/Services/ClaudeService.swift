//
//  ClaudeService.swift
//  WellRead
//
//  Calls Anthropic Messages API for AI suggestions. Uses ApiKeys.claude.
//

import Foundation

private let messagesURL = URL(string: "https://api.anthropic.com/v1/messages")!
private let apiVersion = "2023-06-01"

struct ClaudeMessageRequest: Encodable {
    let model: String
    let maxTokens: Int
    let messages: [Message]
    let system: String?

    struct Message: Encodable {
        let role: String
        let content: String
    }

    enum CodingKeys: String, CodingKey {
        case model
        case maxTokens = "max_tokens"
        case messages
        case system
    }
}

struct ClaudeMessageResponse: Decodable {
    let content: [ContentBlock]
    let stopReason: String?

    struct ContentBlock: Decodable {
        let type: String
        let text: String?
    }

    enum CodingKeys: String, CodingKey {
        case content
        case stopReason = "stop_reason"
    }

    var text: String {
        content.compactMap { $0.text }.joined()
    }
}

final class ClaudeService {
    static let shared = ClaudeService()
    private let session: URLSession

    /// Which model a call runs on. Pick the cheapest tier that doesn't meaningfully
    /// hurt quality; each tier is a fallback chain (404/400 falls through to the next).
    enum ModelTier {
        /// Haiku ($1/$5 per MTok): high-volume, well-scoped tasks — condensing a
        /// provided description, picking tags from a fixed list, matching similar
        /// titles, short recommendation lists.
        case simple
        /// Sonnet ($3/$15 per MTok): tasks that lean on deep knowledge of a book's
        /// actual contents, where a small model is likelier to fabricate — verbatim
        /// quotes, spoiler-aware prose and Q&A, refreshers, blend generation.
        case complex

        fileprivate var modelsToTry: [String] {
            switch self {
            case .simple: return ["claude-haiku-4-5", "claude-sonnet-5"]
            case .complex: return ["claude-sonnet-5", "claude-haiku-4-5"]
            }
        }
    }

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        session = URLSession(configuration: config)
    }

    /// Sends a user message and returns the assistant's text reply. Requires ApiKeys.claude.
    /// `timeout` caps the wait for the (non-streaming) response — callers with a user
    /// staring at a spinner should pass one and fall back when it trips.
    func sendMessage(system: String? = nil, userMessage: String, maxTokens: Int = 1024, timeout: TimeInterval? = nil, tier: ModelTier = .complex) async throws -> String {
        try await sendConversation(
            system: system,
            messages: [.init(role: "user", content: userMessage)],
            maxTokens: maxTokens,
            timeout: timeout,
            tier: tier
        )
    }

    /// Multi-turn variant: sends alternating user/assistant turns (e.g. refresher Q&A follow-ups).
    func sendConversation(system: String? = nil, messages: [ClaudeMessageRequest.Message], maxTokens: Int = 1024, timeout: TimeInterval? = nil, tier: ModelTier = .complex) async throws -> String {
        guard let key = ApiKeys.claude, !key.isEmpty else {
            throw NSError(domain: "ClaudeService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Claude API key not configured. Add CLAUDE_API_KEY to Secrets.plist."])
        }
        var lastError: Error?
        for model in tier.modelsToTry {
            do {
                return try await send(model: model, key: key, system: system, messages: messages, maxTokens: maxTokens, timeout: timeout)
            } catch {
                lastError = error
                let ns = error as NSError
                if ns.domain == "ClaudeService", (ns.code == 404 || ns.code == 400) {
                    continue
                }
                throw error
            }
        }
        throw lastError ?? NSError(domain: "ClaudeService", code: -2, userInfo: [NSLocalizedDescriptionKey: "No model available."])
    }

    private func send(model: String, key: String, system: String?, messages: [ClaudeMessageRequest.Message], maxTokens: Int, timeout: TimeInterval? = nil) async throws -> String {
        var request = URLRequest(url: messagesURL)
        request.httpMethod = "POST"
        // The response arrives as one body after generation, so the idle timeout
        // effectively bounds total wait.
        if let timeout { request.timeoutInterval = timeout }
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "messages": messages.map { ["role": $0.role, "content": $0.content] }
        ]
        if let system = system, !system.isEmpty {
            body["system"] = system
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: "ClaudeService", code: -2, userInfo: [NSLocalizedDescriptionKey: "Invalid response."])
        }
        if http.statusCode != 200 {
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? [String: Any]
            let detail = message?["message"] as? String ?? "Request failed (HTTP \(http.statusCode))."
            throw NSError(domain: "ClaudeService", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: detail])
        }
        let decoded = try JSONDecoder().decode(ClaudeMessageResponse.self, from: data)
        return decoded.text
    }
}
