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

    /// Match rows to books: ISBN first, then title+author search. Dedupes against existing user book IDs.
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
        if let isbn13 = row.isbn13, !isbn13.isEmpty, let book = await lookupByISBN(isbn13) {
            return book
        }
        if let isbn10 = row.isbn, !isbn10.isEmpty, let book = await lookupByISBN(isbn10) {
            return book
        }
        let query = "\(row.title) \(row.author)"
        if let first = try? await googleBooks.search(query: query).first {
            return first
        }
        return nil
    }

    private func lookupByISBN(_ isbn: String) async -> Book? {
        let digits = isbn.filter(\.isNumber)
        guard digits.count == 10 || digits.count == 13 else { return nil }
        let results = (try? await googleBooks.search(query: "isbn:\(digits)")) ?? []
        return results.first
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

    /// Goodreads 1–5 stars → WellRead 1–10.
    static func rating1to10(from goodreadsRating: Int?) -> Int? {
        guard let r = goodreadsRating, (1...5).contains(r) else { return nil }
        return max(1, min(10, (r * 2)))
    }
}
