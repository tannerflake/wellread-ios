//
//  Book.swift
//  WellRead
//

import Foundation

struct Book: Identifiable, Equatable, Hashable {
    var id: String  // Google Books ID or ISBN
    var title: String
    var author: String
    var coverURL: String
    var pageCount: Int?
    var publishedDate: Date?
    var description: String?
    var genres: [String]
    /// Normalized ISBN-10 or ISBN-13 (digits only). Used for Open Library cover URLs; optional for older Firestore docs.
    var isbn: String? = nil
    /// Alternate cover URLs to try if the primary fails (e.g. from Google Books search). Not persisted to Firestore.
    var fallbackCoverURLs: [String]? = nil
    /// When true, `coverImageURLsToTry` is empty (e.g. Firestore metadata timed out — show title-only placeholder only).
    var suppressCoverImageFetch: Bool = false

    /// Open Library cover API: try large, then medium, then small. See https://openlibrary.org/dev/docs/api/covers
    static func openLibraryCoverURLs(isbnDigits: String) -> [String] {
        let d = isbnDigits.filter(\.isNumber)
        guard d.count == 10 || d.count == 13 else { return [] }
        return ["L", "M", "S"].map { "https://covers.openlibrary.org/b/isbn/\(d)-\($0).jpg" }
    }

    /// URL used for loading the cover image. Uses high-res variant for Google Books URLs when possible.
    var coverURLRequest: URL? {
        let urlString = Self.highResCoverURLString(coverURL)
        return URL(string: urlString)
    }

    /// Forces `books/content` URLs to use the marketing **front cover** (`printsec=frontcover`, `img=1`). Without this, Google sometimes serves an interior/title page.
    static func sanitizeGoogleBooksCoverURL(_ urlString: String) -> String {
        guard urlString.contains("books.google.com"),
              urlString.contains("/books/content"),
              var components = URLComponents(string: urlString) else { return urlString }
        var q = components.queryItems ?? []
        q.removeAll { $0.name.lowercased() == "printsec" }
        q.removeAll { $0.name.lowercased() == "img" }
        q.append(URLQueryItem(name: "printsec", value: "frontcover"))
        q.append(URLQueryItem(name: "img", value: "1"))
        components.queryItems = q
        return components.string ?? urlString
    }

    /// Rewrites Google Books image URLs to request highest resolution (zoom=0). Other URLs unchanged.
    static func highResCoverURLString(_ urlString: String) -> String {
        let base = sanitizeGoogleBooksCoverURL(urlString)
        guard base.contains("books.google.com"),
              var components = URLComponents(string: base) else { return base }
        var query = components.queryItems ?? []
        func setZoom(_ value: Int) {
            query.removeAll { $0.name.lowercased() == "zoom" }
            query.append(URLQueryItem(name: "zoom", value: "\(value)"))
        }
        setZoom(0)
        components.queryItems = query
        return components.string ?? base
    }

    /// For Google Books URLs, returns multiple URLs with zoom=0,1,2,3,4,5 so we can try lower resolutions if high-res fails. Non-Google URLs return a single-element array.
    static func coverURLsToTry(from urlString: String) -> [String] {
        let sanitized = sanitizeGoogleBooksCoverURL(urlString)
        guard sanitized.contains("books.google.com"),
              var components = URLComponents(string: sanitized) else {
            return sanitized.isEmpty ? [] : [sanitized]
        }
        var result: [String] = []
        let query = components.queryItems ?? []
        for zoom in [0, 1, 2, 3, 4, 5] {
            var q = query
            q.removeAll { $0.name.lowercased() == "zoom" }
            q.append(URLQueryItem(name: "zoom", value: "\(zoom)"))
            components.queryItems = q
            if let s = components.string, !result.contains(s) {
                result.append(s)
            }
        }
        return result.isEmpty ? [sanitized] : result
    }

    /// Builds standard Google Books cover URLs from a volume ID (e.g. from API). Use as last-resort fallbacks when API image links fail or return placeholders.
    /// Returns none for UUID-shaped ids (custom / manually added books) — those are not Google volume ids; synthesizing URLs would only waste timeouts.
    static func coverURLsFromBookId(_ bookId: String) -> [String] {
        let id = bookId.trimmingCharacters(in: .whitespaces)
        if UUID(uuidString: id) != nil { return [] }
        guard id.count >= 5, id.count <= 50, id.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }) else { return [] }
        guard let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return [] }
        return (0...5).map { "https://books.google.com/books/content?id=\(encoded)&printsec=frontcover&img=1&zoom=\($0)" }
    }

    /// Whether to append Google `books/content?id=<bookId>` zoom fallbacks. Skip when we already have a non-Google cover URL (e.g. Firebase/custom) or a non–Google-Books id.
    private static func shouldAppendGoogleIdCoverFallbacks(coverURL: String, bookId: String) -> Bool {
        if UUID(uuidString: bookId.trimmingCharacters(in: .whitespacesAndNewlines)) != nil {
            return false
        }
        let trimmed = coverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, !trimmed.contains("books.google.com") {
            return false
        }
        return true
    }

    /// Ordered URLs for loading cover art (same pipeline as `BookCoverView`).
    var coverImageURLsToTry: [URL] {
        if suppressCoverImageFetch { return [] }
        var list: [String] = []
        let trimmedCover = coverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        /// Custom / CDN / Firebase covers — try these before Open Library so we don’t re-hit OL on every navigation.
        let tryNonGooglePrimaryFirst = !trimmedCover.isEmpty && !trimmedCover.contains("books.google.com")

        let primaryVariants = Book.coverURLsToTry(from: coverURL)
        if tryNonGooglePrimaryFirst {
            for v in primaryVariants where !list.contains(v) { list.append(v) }
        }

        if let isbn = isbn {
            for u in Book.openLibraryCoverURLs(isbnDigits: isbn) where !list.contains(u) { list.append(u) }
        }

        if !tryNonGooglePrimaryFirst {
            for v in primaryVariants where !list.contains(v) { list.append(v) }
        }

        for s in fallbackCoverURLs ?? [] {
            let variants = Book.coverURLsToTry(from: s)
            for v in variants where !list.contains(v) { list.append(v) }
        }
        if Self.shouldAppendGoogleIdCoverFallbacks(coverURL: coverURL, bookId: id) {
            let idBased = Book.coverURLsFromBookId(id)
            for v in idBased where !list.contains(v) { list.append(v) }
        }
        return list.compactMap { URL(string: $0) }.filter { !$0.absoluteString.isEmpty }
    }

    /// Minimal book used when Firestore is slower than the client budget — UI shows `TitleOnlyBookCover` only (no network covers).
    static func metadataLoadTimeoutPlaceholder(id: String) -> Book {
        var b = Book(
            id: id,
            title: "Book",
            author: "Unknown",
            coverURL: "",
            pageCount: nil,
            publishedDate: nil,
            description: nil,
            genres: []
        )
        b.suppressCoverImageFetch = true
        return b
    }
}

extension Book: Codable {
    enum CodingKeys: String, CodingKey {
        case id, title, author, coverURL, pageCount, publishedDate, description, genres, isbn
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        author = try c.decode(String.self, forKey: .author)
        coverURL = try c.decode(String.self, forKey: .coverURL)
        pageCount = try c.decodeIfPresent(Int.self, forKey: .pageCount)
        publishedDate = try c.decodeIfPresent(Date.self, forKey: .publishedDate)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        genres = try c.decode([String].self, forKey: .genres)
        isbn = try c.decodeIfPresent(String.self, forKey: .isbn)
        fallbackCoverURLs = nil
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(author, forKey: .author)
        try c.encode(coverURL, forKey: .coverURL)
        try c.encode(pageCount, forKey: .pageCount)
        try c.encode(publishedDate, forKey: .publishedDate)
        try c.encode(description, forKey: .description)
        try c.encode(genres, forKey: .genres)
        try c.encodeIfPresent(isbn, forKey: .isbn)
    }
}

typealias BookID = String
