//
//  GoogleBooksService.swift
//  WellRead
//
//  Fetches book metadata from Google Books API.
//

import Foundation

struct GoogleBooksResponse: Codable {
    let items: [GoogleBooksItem]?
}

struct GoogleBooksItem: Codable {
    let id: String
    let volumeInfo: VolumeInfo?
}

struct VolumeInfo: Codable {
    let title: String?
    let authors: [String]?
    let imageLinks: ImageLinks?
    let pageCount: Int?
    let publishedDate: String?
    let description: String?
    let categories: [String]?
}

struct ImageLinks: Codable {
    let thumbnail: String?
    let smallThumbnail: String?
}

final class GoogleBooksService {
    static let shared = GoogleBooksService()
    private let baseURL = "https://www.googleapis.com/books/v1/volumes"
    private let session: URLSession = .shared
    
    private init() {}
    
    func search(query: String) async throws -> [Book] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        var comp = URLComponents(string: baseURL)!
        comp.queryItems = [URLQueryItem(name: "q", value: query), URLQueryItem(name: "maxResults", value: "15")]
        guard let url = comp.url else { return [] }
        let (data, _) = try await session.data(from: url)
        let decoded = try JSONDecoder().decode(GoogleBooksResponse.self, from: data)
        return (decoded.items ?? []).compactMap { item in mapToBook(item: item) }
    }
    
    private func mapToBook(item: GoogleBooksItem) -> Book? {
        guard let info = item.volumeInfo, let title = info.title, !title.isEmpty else { return nil }
        let author = info.authors?.joined(separator: ", ") ?? "Unknown"
        var coverURL = info.imageLinks?.thumbnail ?? info.imageLinks?.smallThumbnail ?? ""
        if coverURL.hasPrefix("http://") { coverURL = "https" + coverURL.dropFirst(4) }
        return Book(
            id: item.id,
            title: title,
            author: author,
            coverURL: coverURL.isEmpty ? "" : coverURL,
            pageCount: info.pageCount,
            publishedDate: nil,
            description: info.description,
            genres: info.categories ?? []
        )
    }
}
