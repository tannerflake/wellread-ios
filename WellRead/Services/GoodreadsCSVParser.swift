//
//  GoodreadsCSVParser.swift
//  WellRead
//
//  Parses Goodreads library export CSV. Deterministic parse; normalizes messy fields.
//

import Foundation

/// One row from a Goodreads export (relevant fields only).
struct GoodreadsRow: Identifiable, Equatable {
    let id: String
    let title: String
    let author: String
    let isbn: String?
    let isbn13: String?
    let myRating: Int?
    let dateRead: Date?
    let dateAdded: Date?
    let exclusiveShelf: String?
    let bookshelves: [String]
    let myReview: String?
}

/// Goodreads CSV column names (export format).
private enum GoodreadsColumn: String, CaseIterable {
    case bookId = "Book Id"
    case title = "Title"
    case author = "Author"
    case isbn = "ISBN"
    case isbn13 = "ISBN13"
    case myRating = "My Rating"
    case dateRead = "Date Read"
    case dateAdded = "Date Added"
    case exclusiveShelf = "Exclusive Shelf"
    case bookshelves = "Bookshelves"
    case myReview = "My Review"
}

final class GoodreadsCSVParser {
    private static let utf8 = String.Encoding.utf8
    private static let isoLatin1 = String.Encoding.isoLatin1

    /// Parses Goodreads CSV data into rows. Tries UTF-8 then ISO-Latin-1. Returns empty array on parse failure.
    static func parse(data: Data) -> [GoodreadsRow] {
        let raw: String
        if let s = String(data: data, encoding: .utf8) {
            raw = s
        } else if let s = String(data: data, encoding: .isoLatin1) {
            raw = s
        } else {
            return []
        }
        return parse(csv: raw)
    }

    static func parse(csv: String) -> [GoodreadsRow] {
        var rows: [GoodreadsRow] = []
        let lines = csv.components(separatedBy: .newlines)
        guard let headerLine = lines.first, !headerLine.isEmpty else { return [] }
        // Goodreads export is often tab-separated when copied (e.g. from file preview or Sheets).
        let isTSV = headerLine.contains("\t")
        let headers: [String] = isTSV ? headerLine.components(separatedBy: "\t").map { $0.trimmingCharacters(in: .whitespaces) } : parseCSVLine(headerLine)
        let columnIndex: [GoodreadsColumn: Int] = {
            var map: [GoodreadsColumn: Int] = [:]
            for (idx, h) in headers.enumerated() {
                if let col = GoodreadsColumn(rawValue: h) {
                    map[col] = idx
                }
            }
            return map
        }()
        for line in lines.dropFirst() {
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            let values: [String] = isTSV ? line.components(separatedBy: "\t").map { $0.trimmingCharacters(in: .whitespaces) } : parseCSVLine(line)
            guard values.count > 0 else { continue }
            let bookId = value(at: .bookId, from: values, map: columnIndex) ?? ""
            let title = normalizeTitle(value(at: .title, from: values, map: columnIndex))
            let author = normalizeAuthor(value(at: .author, from: values, map: columnIndex))
            guard !title.isEmpty else { continue }
            let isbn = normalizeISBN(value(at: .isbn, from: values, map: columnIndex))
            let isbn13 = normalizeISBN(value(at: .isbn13, from: values, map: columnIndex))
            let rating = parseRating(value(at: .myRating, from: values, map: columnIndex))
            let dateRead = parseDate(value(at: .dateRead, from: values, map: columnIndex))
            let dateAdded = parseDate(value(at: .dateAdded, from: values, map: columnIndex))
            let exclusiveShelf = value(at: .exclusiveShelf, from: values, map: columnIndex)?.trimmingCharacters(in: .whitespaces).nilIfEmpty
            let shelves = parseBookshelves(value(at: .bookshelves, from: values, map: columnIndex))
            let myReview = value(at: .myReview, from: values, map: columnIndex)?.trimmingCharacters(in: .whitespaces).nilIfEmpty
            rows.append(GoodreadsRow(
                id: bookId.isEmpty ? UUID().uuidString : bookId,
                title: title,
                author: author,
                isbn: isbn,
                isbn13: isbn13,
                myRating: rating,
                dateRead: dateRead,
                dateAdded: dateAdded,
                exclusiveShelf: exclusiveShelf,
                bookshelves: shelves,
                myReview: myReview
            ))
        }
        return rows
    }

    private static func value(at column: GoodreadsColumn, from values: [String], map: [GoodreadsColumn: Int]) -> String? {
        guard let idx = map[column], idx < values.count else { return nil }
        return values[idx].trimmingCharacters(in: .whitespaces)
    }

    /// Handles quoted fields and commas inside quotes.
    private static func parseCSVLine(_ line: String) -> [String] {
        var result: [String] = []
        var current = ""
        var inQuotes = false
        for ch in line {
            if ch == "\"" {
                inQuotes.toggle()
                continue
            }
            if !inQuotes && ch == "," {
                result.append(current)
                current = ""
                continue
            }
            current.append(ch)
        }
        result.append(current)
        return result
    }

    private static func normalizeTitle(_ s: String?) -> String {
        guard let s = s?.trimmingCharacters(in: .whitespaces), !s.isEmpty else { return "" }
        return s
    }

    private static func normalizeAuthor(_ s: String?) -> String {
        guard let s = s?.trimmingCharacters(in: .whitespaces), !s.isEmpty else { return "Unknown" }
        return s
    }

    /// Goodreads sometimes exports ISBN as ="0060590297". Strip equals and quotes.
    private static func normalizeISBN(_ s: String?) -> String? {
        guard var t = s?.trimmingCharacters(in: .whitespaces), !t.isEmpty else { return nil }
        if t.hasPrefix("=\"") && t.hasSuffix("\"") { t = String(t.dropFirst(2).dropLast(1)) }
        if t.hasPrefix("=") { t = String(t.dropFirst(1)) }
        t = t.replacingOccurrences(of: "\"", with: "")
        let digits = t.filter(\.isNumber)
        return digits.isEmpty ? nil : digits
    }

    private static func parseRating(_ s: String?) -> Int? {
        guard let s = s?.trimmingCharacters(in: .whitespaces), !s.isEmpty else { return nil }
        if let i = Int(s), (1...5).contains(i) { return i }
        return nil
    }

    private static func parseDate(_ s: String?) -> Date? {
        guard let s = s?.trimmingCharacters(in: .whitespaces), !s.isEmpty else { return nil }
        let formatters: [DateFormatter] = [
            { let f = DateFormatter(); f.dateFormat = "yyyy/MM/dd"; f.locale = Locale(identifier: "en_US_POSIX"); return f }(),
            { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX"); return f }(),
            { let f = DateFormatter(); f.dateFormat = "MM/dd/yyyy"; f.locale = Locale(identifier: "en_US_POSIX"); return f }(),
            { let f = DateFormatter(); f.dateFormat = "yyyy"; f.locale = Locale(identifier: "en_US_POSIX"); return f }()
        ]
        for f in formatters {
            if let d = f.date(from: s) { return d }
        }
        return nil
    }

    private static func parseBookshelves(_ s: String?) -> [String] {
        guard let s = s?.trimmingCharacters(in: .whitespaces), !s.isEmpty else { return [] }
        return s.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
