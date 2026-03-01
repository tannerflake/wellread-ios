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

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        session = URLSession(configuration: config)
    }

    /// Sends a user message and returns the assistant's text reply. Requires ApiKeys.claude.
    func sendMessage(system: String? = nil, userMessage: String) async throws -> String {
        guard let key = ApiKeys.claude, !key.isEmpty else {
            throw NSError(domain: "ClaudeService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Claude API key not configured. Add CLAUDE_API_KEY to Secrets.plist."])
        }
        var request = URLRequest(url: messagesURL)
        request.httpMethod = "POST"
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = [
            "model": "claude-3-5-sonnet-20241022",
            "max_tokens": 1024,
            "messages": [["role": "user", "content": userMessage]]
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
