//
//  DiscoverSuggestionsService.swift
//  WellRead
//
//  Fetches a batch of book suggestions for Discover (Claude + Google Books). Used by AppState for prefetch.
//

import Foundation

enum DiscoverSuggestionsService {
    /// Fetches up to 5 suggested books, excluding read, queue, and dismissed. Call from background; updates go to caller via callback/state.
    static func fetchBatch(readBooks: [UserBook], queueBookIds: Set<String>, dismissedBookIds: Set<String>) async -> [Book] {
        let readBookIds = Set(readBooks.map(\.bookId))
        let excludedIds = readBookIds.union(queueBookIds).union(dismissedBookIds)
        let excludedTitles = readBooks.compactMap { $0.book?.title }
        if ApiKeys.claude != nil {
            return await fetchBatchViaClaude(excludedTitles: Array(excludedTitles), excludedIds: excludedIds)
        } else {
            return await fetchBatchViaGoogleOnly(excludedIds: excludedIds, readTitles: excludedTitles)
        }
    }

    private static func fetchBatchViaClaude(excludedTitles: [String], excludedIds: Set<String>) async -> [Book] {
        let context: String
        if excludedTitles.isEmpty {
            context = "The user hasn't finished any books yet."
        } else {
            context = "Books the user has already read (do not suggest these): \(excludedTitles.prefix(15).joined(separator: ", "))."
        }
        let system = "You are a book recommendation assistant. Reply with exactly 5 book recommendations. Each line must be only the book title (and optionally ' by Author'). No numbering, no bullets, no extra text. One book per line. Do not suggest any book from the user's excluded list."
        let userMessage = "\(context) Suggest 5 books they might enjoy next. Reply with exactly 5 lines, each line one book title (optionally 'Title by Author')."
        do {
            let response = try await ClaudeService.shared.sendMessage(system: system, userMessage: userMessage)
            let lines = parseClaudeBookLines(response)
            var books: [Book] = []
            for line in lines.prefix(5) {
                let query = line.replacingOccurrences(of: " by ", with: " ")
                if let first = try? await GoogleBooksService.shared.search(query: String(query)).first,
                   !excludedIds.contains(first.id) {
                    books.append(first)
                }
            }
            return books
        } catch {
            let fallback = (try? await GoogleBooksService.shared.search(query: "popular books"))?
                .filter { !excludedIds.contains($0.id) } ?? []
            return Array(fallback.prefix(5))
        }
    }

    private static func fetchBatchViaGoogleOnly(excludedIds: Set<String>, readTitles: [String]) async -> [Book] {
        try? await Task.sleep(nanoseconds: 800_000_000)
        let query = !readTitles.isEmpty ? readTitles.prefix(2).joined(separator: " ") : "popular books"
        let books = (try? await GoogleBooksService.shared.search(query: query))?
            .filter { !excludedIds.contains($0.id) } ?? []
        return Array(books.prefix(5))
    }

    private static func parseClaudeBookLines(_ response: String) -> [String] {
        response
            .components(separatedBy: .newlines)
            .map { line in
                var t = line.trimmingCharacters(in: .whitespaces)
                if let match = t.range(of: #"^\d+[\.\)]\s*"#, options: .regularExpression) {
                    t = String(t[match.upperBound...]).trimmingCharacters(in: .whitespaces)
                }
                if t.hasPrefix("- ") || t.hasPrefix("* ") {
                    t = String(t.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                }
                return t
            }
            .filter { !$0.isEmpty }
    }
}
