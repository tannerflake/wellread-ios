//
//  DiscoverSuggestionsService.swift
//  WellRead
//
//  Fetches a batch of book suggestions for Discover (Claude + Google Books). Used by AppState for prefetch.
//

import Foundation

enum DiscoverSuggestionsService {
    /// Fetches up to 5 suggested books, excluding read, queue, and dismissed. Call from background; updates go to caller via callback/state.
    /// `readingInterestTags` are onboarding picks from `Tags.csv` (same universe as book tags); passed into the recommender when non-empty.
    static func fetchBatch(readBooks: [UserBook], queueBookIds: Set<String>, dismissedBookIds: Set<String>, readingInterestTags: [String]) async -> [Book] {
        let readBookIds = Set(readBooks.map(\.bookId))
        let excludedIds = readBookIds.union(queueBookIds).union(dismissedBookIds)
        let excludedTitles = readBooks.compactMap { $0.book?.title }
        if ApiKeys.claude != nil {
            return await fetchBatchViaClaude(excludedTitles: Array(excludedTitles), excludedIds: excludedIds, readingInterestTags: readingInterestTags)
        } else {
            return await fetchBatchViaGoogleOnly(excludedIds: excludedIds, readTitles: excludedTitles, readingInterestTags: readingInterestTags)
        }
    }

    private static func fetchBatchViaClaude(excludedTitles: [String], excludedIds: Set<String>, readingInterestTags: [String]) async -> [Book] {
        let interestsLine: String
        if readingInterestTags.isEmpty {
            interestsLine = ""
        } else {
            let listed = readingInterestTags.prefix(16).joined(separator: ", ")
            interestsLine = "The user’s reading interests (prioritize books that match these topics, genres, or vibes—use them as the main guide): \(listed). "
        }

        let historyLine: String
        if excludedTitles.isEmpty {
            historyLine = "They have not finished logging any books in this app yet."
        } else {
            historyLine = "Books they have already read here—do not suggest these titles: \(excludedTitles.prefix(15).joined(separator: ", "))."
        }

        let system = """
        You are a book recommendation assistant. Reply with exactly 5 book recommendations. Each line must be only the book title (and optionally ' by Author'). No numbering, no bullets, no extra text. One book per line. Do not suggest any book from the user's excluded list. When the user has stated reading interests, most or all of your picks should clearly fit those interests.
        """
        let userMessage = "\(interestsLine)\(historyLine) Suggest 5 books they might enjoy next. Reply with exactly 5 lines, each line one book title (optionally 'Title by Author')."
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
            let q = googleFallbackQuery(readTitles: excludedTitles, readingInterestTags: readingInterestTags)
            let fallback = (try? await GoogleBooksService.shared.search(query: q))?
                .filter { !excludedIds.contains($0.id) } ?? []
            return Array(fallback.prefix(5))
        }
    }

    private static func fetchBatchViaGoogleOnly(excludedIds: Set<String>, readTitles: [String], readingInterestTags: [String]) async -> [Book] {
        try? await Task.sleep(nanoseconds: 800_000_000)
        let query = googleFallbackQuery(readTitles: readTitles, readingInterestTags: readingInterestTags)
        let books = (try? await GoogleBooksService.shared.search(query: query))?
            .filter { !excludedIds.contains($0.id) } ?? []
        return Array(books.prefix(5))
    }

    /// Search string when Claude is unavailable or errors: prefer interest tags, then recent reads, then generic.
    private static func googleFallbackQuery(readTitles: [String], readingInterestTags: [String]) -> String {
        if !readingInterestTags.isEmpty {
            return readingInterestTags.prefix(6).joined(separator: " ")
        }
        if !readTitles.isEmpty {
            return readTitles.prefix(2).joined(separator: " ")
        }
        return "popular books"
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
