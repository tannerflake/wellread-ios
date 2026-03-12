//
//  BookProfileService.swift
//  WellRead
//
//  Uses Claude to produce a two-sentence summary and a notable quote for a book. Caches by book.id.
//

import Foundation

final class BookProfileService {
    static let shared = BookProfileService()
    private var summaryCache: [String: String] = [:]
    private var quoteCache: [String: String] = [:]
    private let queue = DispatchQueue(label: "com.wellread.bookprofile.cache")

    private init() {}

    /// Two-sentence summary. Uses book description if present; otherwise asks Claude to write two sentences from title/author. Cached by book.id.
    func twoSentenceSummary(for book: Book) async -> String? {
        let key = book.id
        if let cached = queue.sync(execute: { summaryCache[key] }) { return cached }
        let system = "You are a concise book summarizer. Reply with exactly two sentences that summarize the book. No heading, no bullets, no extra text. If given a long description, condense it to exactly two sentences. If given only title and author, write two sentences that describe what the book is about based on common knowledge."
        let input: String
        if let d = book.description, !d.isEmpty {
            input = "Book: \(book.title) by \(book.author).\n\nDescription:\n\(d)\n\nSummarize in exactly two sentences."
        } else {
            input = "Book: \(book.title) by \(book.author). Write exactly two sentences that describe what this book is about."
        }
        do {
            let response = try await ClaudeService.shared.sendMessage(system: system, userMessage: input)
            let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
            queue.sync { summaryCache[key] = trimmed }
            return trimmed.isEmpty ? nil : trimmed
        } catch {
            return nil
        }
    }

    /// One impactful or notable quote from the book. Cached by book.id.
    func notableQuote(for book: Book) async -> String? {
        let key = book.id
        if let cached = queue.sync(execute: { quoteCache[key] }) { return cached }
        let system = "You are a literary assistant. Reply with one impactful, famous, or notable quote from this book. Output only the quote in quotation marks, nothing else. If you don't know a real quote from the book, reply with exactly: No notable quote available."
        let input: String
        if let d = book.description, !d.isEmpty {
            input = "Book: \(book.title) by \(book.author).\n\nDescription:\n\(d)\n\nGive one notable quote from this book."
        } else {
            input = "Book: \(book.title) by \(book.author). Give one notable or famous quote from this book."
        }
        do {
            let response = try await ClaudeService.shared.sendMessage(system: system, userMessage: input)
            let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.lowercased().contains("no notable quote") {
                queue.sync { quoteCache[key] = nil }
                return nil
            }
            queue.sync { quoteCache[key] = trimmed }
            return trimmed
        } catch {
            return nil
        }
    }

    /// Books from the user's read list that are most similar to this book. Returns 2–3 books for "Similar to" section. Uses Claude to pick by title/author; empty if read list is empty or Claude returns nothing.
    func similarBooks(for book: Book, readBooks: [UserBook]) async -> [Book] {
        let readTitles = readBooks.compactMap { ub -> (title: String, book: Book)? in
            guard let b = ub.book else { return nil }
            return (b.title, b)
        }
        guard !readTitles.isEmpty else { return [] }
        let titleList = readTitles.map(\.title).joined(separator: ", ")
        let system = "You are a book comparison assistant. Given one book and a list of books the user has read, pick 2 or 3 books from the list that are most similar in theme, genre, or style. Reply with only those book titles, one per line. Use the exact title as given. If none are similar, reply with exactly: None."
        let input = "Book to compare: \(book.title) by \(book.author).\n\nBooks the user has read:\n\(titleList)\n\nList 2 or 3 titles from the user's list that are most similar (one per line), or reply None."
        do {
            let response = try await ClaudeService.shared.sendMessage(system: system, userMessage: input)
            let lines = response
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty && !$0.lowercased().hasPrefix("none") }
            var result: [Book] = []
            for line in lines.prefix(3) {
                let normalized = line.lowercased()
                if let match = readTitles.first(where: { $0.title.lowercased() == normalized || $0.title.lowercased().contains(normalized) || normalized.contains($0.title.lowercased()) }) {
                    result.append(match.book)
                }
            }
            return result
        } catch {
            return []
        }
    }
}
