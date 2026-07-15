//
//  GoodreadsImportService.swift
//  WellRead
//
//  Matches Goodreads rows to catalog books and maps Goodreads fields to app values.
//
//  Matching order (confident-only — a row that can't be matched confidently is
//  reported unmatched, never guessed):
//    1. ISBN-13, then ISBN-10, via Google Books `isbn:` query, verified against
//       the returned volume's own identifiers.
//    2. Title + author search, accepted only when the normalized main title and
//       the author's last name both agree with the export row. This recovers the
//       large share of Goodreads rows with no ISBN (Kindle/audio editions) and
//       ISBNs Google hasn't indexed — the two failure modes that made the old
//       ISBN-only pass drop most of a library.
//

import Foundation

/// Result of trying to resolve one Goodreads row against the catalog.
/// `failed` (network/API error) is kept distinct from `noMatch` so a transient
/// outage is never recorded as a permanent "couldn't match" skip.
enum GoodreadsMatchOutcome {
    case matched(Book)
    /// Every lookup completed cleanly and nothing met the confidence bar.
    case noMatch
    /// A lookup errored (offline, rate limit, timeout) — retryable.
    case failed
}

final class GoodreadsImportService {
    private let googleBooks = GoogleBooksService.shared

    /// Resolve one Goodreads row to a catalog book. Errors from the search API
    /// surface as `.failed`, never as `.noMatch`.
    func matchRow(_ row: GoodreadsRow) async -> GoodreadsMatchOutcome {
        var sawError = false
        var book: Book?
        for isbn in [row.isbn13, row.isbn].compactMap({ $0 }) where !isbn.isEmpty {
            do {
                if let b = try await lookupByISBN(isbn) { book = b; break }
            } catch {
                sawError = true
            }
        }
        if book == nil {
            do {
                book = try await lookupByTitleAuthor(row)
            } catch {
                sawError = true
            }
        }
        guard var merged = book else { return sawError ? .failed : .noMatch }
        // Goodreads ISBN (for Open Library covers); prefer export row over API when present.
        let fromRow = [row.isbn13, row.isbn]
            .compactMap { $0 }
            .map { $0.filter(\.isNumber) }
            .first { $0.count == 10 || $0.count == 13 }
        if let d = fromRow {
            merged.isbn = d
        }
        return .matched(merged)
    }

    /// Query Google with `isbn:…` and only accept a volume whose catalog ISBN matches (or a single unambiguous hit).
    private func lookupByISBN(_ isbn: String) async throws -> Book? {
        let digits = isbn.filter(\.isNumber)
        guard digits.count == 10 || digits.count == 13 else { return nil }
        let results = try await googleBooks.search(query: "isbn:\(digits)")
        for book in results {
            if let bid = book.isbn, ISBNMatcher.equivalent(digits, bid) {
                return book
            }
        }
        // Rare: API omits industryIdentifiers; if exactly one volume returned for isbn: query, trust it.
        if results.count == 1, let only = results.first {
            return only
        }
        return nil
    }

    /// Title + author search, verified strictly against the export row.
    private func lookupByTitleAuthor(_ row: GoodreadsRow) async throws -> Book? {
        let mainTitle = GoodreadsTitleMatcher.mainTitle(row.title)
        let primaryAuthor = GoodreadsTitleMatcher.primaryAuthor(row.author)
        guard !mainTitle.isEmpty else { return nil }

        var query = "intitle:\"\(mainTitle)\""
        if let lastName = GoodreadsTitleMatcher.authorLastName(primaryAuthor) {
            query += " inauthor:\"\(lastName)\""
        }
        let results = try await googleBooks.search(query: query)
        let rowISBNs = [row.isbn13, row.isbn].compactMap { $0 }.map { $0.filter(\.isNumber) }

        var confident: [Book] = []
        for candidate in results {
            // An ISBN agreement is the strongest possible signal — accept immediately.
            if let cid = candidate.isbn, rowISBNs.contains(where: { ISBNMatcher.equivalent($0, cid) }) {
                return candidate
            }
            if GoodreadsTitleMatcher.isConfidentMatch(rowTitle: row.title, rowAuthor: row.author, candidate: candidate) {
                confident.append(candidate)
            }
        }
        // Prefer a verified candidate that has a cover and an ISBN (a real edition, not a stub).
        return confident.first { !$0.coverURL.isEmpty && $0.isbn != nil }
            ?? confident.first { !$0.coverURL.isEmpty }
            ?? confident.first
    }

    /// Map Goodreads exclusive shelf to ReadingStatus.
    static func status(for exclusiveShelf: String?) -> ReadingStatus {
        guard let s = exclusiveShelf?.lowercased() else { return .wantToRead }
        switch s {
        case "read": return .read
        case "currently-reading", "currently reading": return .currentlyReading
        case "to-read", "to read", "want to read": return .wantToRead
        default: return .wantToRead
        }
    }

    /// Goodreads 1–5 stars → WellRead out of 10 (whole numbers: 2, 4, … 10).
    static func ratingOutOfTen(from goodreadsRating: Int?) -> Double? {
        guard let r = goodreadsRating, (1...5).contains(r) else { return nil }
        return Theme.normalizeRatingOutOfTen(Double(max(1, min(10, r * 2))))
    }
}

// MARK: - Title / author verification

enum GoodreadsTitleMatcher {
    /// "Harry Potter and the Sorcerer's Stone (Harry Potter, #1)" → "Harry Potter and the Sorcerer's Stone";
    /// "The Hobbit: or There and Back Again" → "The Hobbit".
    static func mainTitle(_ raw: String) -> String {
        var t = raw
        if let idx = t.firstIndex(of: "(") { t = String(t[..<idx]) }
        if let idx = t.firstIndex(of: ":") { t = String(t[..<idx]) }
        return t.trimmingCharacters(in: .whitespaces)
    }

    /// Goodreads joins multiple authors with commas; the first entry is the primary author.
    static func primaryAuthor(_ raw: String) -> String {
        raw.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespaces) ?? raw
    }

    static func authorLastName(_ author: String) -> String? {
        let words = normalize(author).components(separatedBy: " ").filter { $0.count > 1 }
        return words.last
    }

    /// Lowercased, diacritics folded, punctuation removed, whitespace collapsed.
    static func normalize(_ s: String) -> String {
        let folded = s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US"))
        let scalars = folded.unicodeScalars.map { scalar -> Character in
            if CharacterSet.alphanumerics.contains(scalar) { return Character(scalar) }
            return " "
        }
        return String(scalars).components(separatedBy: .whitespaces).filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// True when the candidate's normalized main title equals (or extends) the row's,
    /// and the row's primary-author last name appears in the candidate's authors.
    static func isConfidentMatch(rowTitle: String, rowAuthor: String, candidate: Book) -> Bool {
        let rowNorm = normalize(mainTitle(rowTitle))
        let candNorm = normalize(mainTitle(candidate.title))
        guard !rowNorm.isEmpty, !candNorm.isEmpty else { return false }
        let titlesAgree = rowNorm == candNorm
            || candNorm.hasPrefix(rowNorm + " ")
            || rowNorm.hasPrefix(candNorm + " ")
        guard titlesAgree else { return false }
        guard let lastName = authorLastName(primaryAuthor(rowAuthor)) else { return false }
        return normalize(candidate.author).components(separatedBy: " ").contains(lastName)
    }
}

// MARK: - ISBN comparison (10 vs 13)

enum ISBNMatcher {
    static func digitsOnly(_ s: String) -> String { s.filter(\.isNumber) }

    static func equivalent(_ a: String, _ b: String) -> Bool {
        let da = digitsOnly(a)
        let db = digitsOnly(b)
        if da == db { return true }
        if da.count == 10 && db.count == 13 { return isbn10MatchesIsbn13Body(da, db) }
        if da.count == 13 && db.count == 10 { return isbn10MatchesIsbn13Body(db, da) }
        return false
    }

    private static func isbn10MatchesIsbn13Body(_ isbn10: String, _ isbn13: String) -> Bool {
        guard isbn10.count == 10, isbn13.count == 13 else { return false }
        let p = String(isbn13.prefix(3))
        guard p == "978" || p == "979" else { return false }
        let nineFrom10 = String(isbn10.prefix(9))
        let nineFrom13 = String(isbn13.dropFirst(3).prefix(9))
        return nineFrom10 == nineFrom13
    }
}
