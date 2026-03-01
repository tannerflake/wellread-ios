//
//  Book.swift
//  WellRead
//

import Foundation

struct Book: Identifiable, Codable, Equatable {
    var id: String  // Google Books ID or ISBN
    var title: String
    var author: String
    var coverURL: String
    var pageCount: Int?
    var publishedDate: Date?
    var description: String?
    var genres: [String]

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

typealias BookID = String
