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
    /// Alternate cover URLs to try if the primary fails (e.g. from Google Books search). Not persisted to Firestore.
    var fallbackCoverURLs: [String]? = nil

    /// URL used for loading the cover image. Uses high-res variant for Google Books URLs when possible.
    var coverURLRequest: URL? {
        let urlString = Self.highResCoverURLString(coverURL)
        return URL(string: urlString)
    }

    /// Rewrites Google Books image URLs to request highest resolution (zoom=0). Other URLs unchanged.
    static func highResCoverURLString(_ urlString: String) -> String {
        guard urlString.contains("books.google.com"),
              var components = URLComponents(string: urlString) else { return urlString }
        var query = components.queryItems ?? []
        func setZoom(_ value: Int) {
            query.removeAll { $0.name.lowercased() == "zoom" }
            query.append(URLQueryItem(name: "zoom", value: "\(value)"))
        }
        setZoom(0)
        components.queryItems = query
        return components.string ?? urlString
    }

    /// For Google Books URLs, returns multiple URLs with zoom=0,1,2,3,4,5 so we can try lower resolutions if high-res fails. Non-Google URLs return a single-element array.
    static func coverURLsToTry(from urlString: String) -> [String] {
        guard urlString.contains("books.google.com"),
              var components = URLComponents(string: urlString) else {
            return urlString.isEmpty ? [] : [urlString]
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
        return result.isEmpty ? [urlString] : result
    }

    /// Builds standard Google Books cover URLs from a volume ID (e.g. from API). Use as last-resort fallbacks when API image links fail or return placeholders.
    static func coverURLsFromBookId(_ bookId: String) -> [String] {
        let id = bookId.trimmingCharacters(in: .whitespaces)
        guard id.count >= 5, id.count <= 50, id.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }) else { return [] }
        guard let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return [] }
        return (0...5).map { "https://books.google.com/books/content?id=\(encoded)&printsec=frontcover&img=1&zoom=\($0)" }
    }
}

extension Book: Codable {
    enum CodingKeys: String, CodingKey {
        case id, title, author, coverURL, pageCount, publishedDate, description, genres
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
    }
}

typealias BookID = String
