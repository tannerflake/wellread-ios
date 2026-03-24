//
//  GoodreadsImportService.swift
//  WellRead
//
//  Matches Goodreads rows to catalog (ISBN / title+author), builds preview, performs import.
//

import Foundation

struct GoodreadsMatchedItem: Identifiable {
    let id: String
    let row: GoodreadsRow
    let book: Book?
    let isDuplicate: Bool
}

struct GoodreadsImportPreview {
    var matched: [GoodreadsMatchedItem]
    var unmatched: [GoodreadsRow]
    var duplicateCount: Int
}

final class GoodreadsImportService {
    private let googleBooks = GoogleBooksService.shared
    private let bookRepo = BookRepository.shared

    /// Match rows to books by **ISBN only** (verified against Google Books metadata). Rows without a usable ISBN or no confident API match go to `unmatched` — no title/author guessing.
    func buildPreview(rows: [GoodreadsRow], existingBookIds: Set<String>) async -> GoodreadsImportPreview {
        var matched: [GoodreadsMatchedItem] = []
        var unmatched: [GoodreadsRow] = []
        var duplicateCount = 0

        for row in rows {
            let book = await matchRowToBook(row)
            let isDup = book.map { existingBookIds.contains($0.id) } ?? false
            if isDup { duplicateCount += 1 }
            if let book = book {
                matched.append(GoodreadsMatchedItem(id: row.id, row: row, book: book, isDuplicate: isDup))
            } else {
                unmatched.append(row)
            }
        }
        return GoodreadsImportPreview(matched: matched, unmatched: unmatched, duplicateCount: duplicateCount)
    }

    private func matchRowToBook(_ row: GoodreadsRow) async -> Book? {
        var book: Book?
        if let isbn13 = row.isbn13, !isbn13.isEmpty, let b = await lookupByISBN(isbn13) {
            book = b
        } else if let isbn10 = row.isbn, !isbn10.isEmpty, let b = await lookupByISBN(isbn10) {
            book = b
        }
        guard var merged = book else { return nil }
        // Goodreads ISBN (for Open Library covers); prefer export row over API when present.
        let fromRow = [row.isbn13, row.isbn]
            .compactMap { $0 }
            .map { $0.filter(\.isNumber) }
            .first { $0.count == 10 || $0.count == 13 }
        if let d = fromRow {
            merged.isbn = d
        }
        return merged
    }

    /// Query Google with `isbn:…` and only accept a volume whose catalog ISBN matches (or a single unambiguous hit).
    private func lookupByISBN(_ isbn: String) async -> Book? {
        let digits = isbn.filter(\.isNumber)
        guard digits.count == 10 || digits.count == 13 else { return nil }
        let results = (try? await googleBooks.search(query: "isbn:\(digits)")) ?? []
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

// MARK: - ISBN comparison (10 vs 13)

private enum ISBNMatcher {
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
