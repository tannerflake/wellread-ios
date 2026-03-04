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
