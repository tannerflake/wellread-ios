//
//  GoogleBooksService.swift
//  WellRead
//
//  Fetches book metadata from Google Books API.
//

import Foundation

struct GoogleBooksResponse: Codable {
    let items: [GoogleBooksItem]?
    let error: GoogleBooksError?
}

struct GoogleBooksError: Codable {
    let code: Int?
    let message: String?
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
    let small: String?
    let medium: String?
    let large: String?
    let extraLarge: String?
}

/// Parses Google Books publishedDate (e.g. "2023", "2023-05", "2023-05-01") to Date.
private func parsePublishedDate(_ raw: String?) -> Date? {
    guard let raw = raw, !raw.isEmpty else { return nil }
    let utc = TimeZone(identifier: "UTC")!
    let formatters: [DateFormatter] = [
        { let f = DateFormatter(); f.dateFormat = "yyyy"; f.timeZone = utc; return f }(),
        { let f = DateFormatter(); f.dateFormat = "yyyy-MM"; f.timeZone = utc; return f }(),
        { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.timeZone = utc; return f }()
    ]
    for formatter in formatters {
        if let d = formatter.date(from: raw) { return d }
    }
    return nil
}

final class GoogleBooksService {
    static let shared = GoogleBooksService()
    private let baseURL = "https://www.googleapis.com/books/v1/volumes"
    private let session: URLSession
    private let cacheMaxQueries = 10
    private var searchCache: [String: [Book]] = [:]
    private let cacheQueue = DispatchQueue(label: "com.wellread.googlebooks.cache")

    /// API key: GoogleService-Info.plist "API_KEY", or Info.plist "GOOGLE_BOOKS_API_KEY". Enable Books API for this key in Google Cloud Console.
    private var apiKey: String? {
        if let key = keyFromPlist(named: "Secrets", key: "GOOGLE_BOOKS_API_KEY"), !key.isEmpty { return key }
        if let key = keyFromPlist(named: "Info", key: "GOOGLE_BOOKS_API_KEY"), !key.isEmpty { return key }
        if let key = keyFromPlist(named: "GoogleService-Info", key: "API_KEY"), !key.isEmpty { return key }
        return nil
    }

    private func keyFromPlist(named name: String, key: String) -> String? {
        guard let path = Bundle.main.path(forResource: name, ofType: "plist"),
              let plist = NSDictionary(contentsOfFile: path),
              let value = plist[key] as? String else { return nil }
        return value
    }

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 20
        session = URLSession(configuration: config)
    }

    func search(query: String) async throws -> [Book] {
        let normalized = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !normalized.isEmpty else { return [] }
        let cacheKey = normalized
        if let cached = cacheQueue.sync(execute: { searchCache[cacheKey] }) {
            return cached
        }
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "maxResults", value: "15"),
            URLQueryItem(name: "projection", value: "full")
        ]
        if let key = apiKey {
            queryItems.append(URLQueryItem(name: "key", value: key))
        }
        var comp = URLComponents(string: baseURL)!
        comp.queryItems = queryItems
        guard let url = comp.url else {
            throw NSError(domain: "GoogleBooks", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid search query."])
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch let urlError as URLError {
            let msg: String
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost:
                msg = "No internet connection. Check Wi‑Fi or cellular."
            case .timedOut:
                msg = "Request timed out. Check your connection and try again."
            case .cancelled:
                msg = "Search was cancelled."
            default:
                msg = urlError.localizedDescription.isEmpty ? "Can't reach Google Books. Check your connection." : urlError.localizedDescription
            }
            throw NSError(domain: "GoogleBooks", code: urlError.errorCode, userInfo: [NSLocalizedDescriptionKey: msg])
        } catch {
            throw NSError(domain: "GoogleBooks", code: -2, userInfo: [NSLocalizedDescriptionKey: "Can't reach Google Books. Check your internet connection."])
        }
        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: "GoogleBooks", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response from server. Try again."])
        }
        if http.statusCode != 200 {
            let message = (try? JSONDecoder().decode(GoogleBooksResponse.self, from: data).error?.message)
                ?? "Request failed (HTTP \(http.statusCode))."
            let hint = http.statusCode == 403
                ? " Enable the Books API in Google Cloud Console (APIs & Services → Library → Books API) and ensure your API key is allowed."
                : ""
            throw NSError(domain: "GoogleBooks", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: message + hint])
        }
        let decoded: GoogleBooksResponse
        do {
            decoded = try JSONDecoder().decode(GoogleBooksResponse.self, from: data)
        } catch {
            throw NSError(domain: "GoogleBooks", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response from server. Try again."])
        }
        if let apiError = decoded.error, let msg = apiError.message, !msg.isEmpty {
            let hint = (apiError.code == 403) ? " Enable the Books API in Google Cloud Console for your API key." : ""
            throw NSError(domain: "GoogleBooks", code: apiError.code ?? -1, userInfo: [NSLocalizedDescriptionKey: msg + hint])
        }
        let books = (decoded.items ?? []).compactMap { item in mapToBook(item: item) }
        cacheQueue.async { [weak self] in
            guard let self = self else { return }
            if self.searchCache.count >= self.cacheMaxQueries {
                if let first = self.searchCache.keys.first { self.searchCache.removeValue(forKey: first) }
            }
            self.searchCache[cacheKey] = books
        }
        return books
    }

    /// Use imageLinks in documented size order (best available first). No book is returned if no image at all.
    private func mapToBook(item: GoogleBooksItem) -> Book? {
        guard let info = item.volumeInfo, let title = info.title, !title.isEmpty else { return nil }
        let links = info.imageLinks
        let rawOrder: [String?] = [
            links?.extraLarge,
            links?.large,
            links?.medium,
            links?.small,
            links?.thumbnail,
            links?.smallThumbnail
        ]
        var seen = Set<String>()
        let allURLs: [String] = rawOrder
            .compactMap { $0 }
            .map { $0.hasPrefix("http://") ? "https" + $0.dropFirst(4) : $0 }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
        guard let primary = allURLs.first else { return nil }
        let fallbacks = Array(allURLs.dropFirst())
        let author = info.authors?.joined(separator: ", ") ?? "Unknown"
        return Book(
            id: item.id,
            title: title,
            author: author,
            coverURL: primary,
            pageCount: info.pageCount,
            publishedDate: parsePublishedDate(info.publishedDate),
            description: info.description,
            genres: info.categories ?? [],
            fallbackCoverURLs: fallbacks.isEmpty ? nil : fallbacks
        )
    }
}
