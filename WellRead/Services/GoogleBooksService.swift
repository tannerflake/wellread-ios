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

struct IndustryIdentifier: Codable {
    let type: String?
    let identifier: String?
}

struct VolumeInfo: Codable {
    let title: String?
    let authors: [String]?
    let imageLinks: ImageLinks?
    let pageCount: Int?
    let publishedDate: String?
    let description: String?
    let categories: [String]?
    let industryIdentifiers: [IndustryIdentifier]?
    let averageRating: Double?
    let ratingsCount: Int?
    let language: String?
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

    /// Searches Google Books, then re-ranks and de-duplicates results client-side
    /// (see `BookSearchRanker`). `includeAllEditions` skips the junk-title filter
    /// and edition dedup for the "can't find it?" fallback. `libraryAuthors` are
    /// author names already in the user's library, used as a personalization boost.
    /// Strict `isbn:` queries bypass ranking entirely and keep Google's order.
    func search(query: String, includeAllEditions: Bool = false, libraryAuthors: Set<String> = []) async throws -> [Book] {
        let normalized = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !normalized.isEmpty else { return [] }
        let isISBNQuery = normalized.hasPrefix("isbn:")
        let cacheKey = (includeAllEditions ? "all|" : "") + normalized
        if let cached = cacheQueue.sync(execute: { searchCache[cacheKey] }) {
            return cached
        }
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "maxResults", value: isISBNQuery ? "15" : "30"),
            URLQueryItem(name: "printType", value: "books"),
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

        // Searching-as-you-type fires a request every time the debounce window elapses,
        // so several can reach Google in quick succession and trip its rate limiter
        // (HTTP 429/503 "Service temporarily unavailable"). Retry those transient throttles
        // with a short backoff so they resolve themselves instead of forcing the user to
        // tap "Try Again". Cancellation during the backoff propagates to the caller.
        let transientStatuses: Set<Int> = [429, 500, 502, 503, 504]
        let maxAttempts = 3
        let data: Data
        var attempt = 0
        while true {
            let payload: Data
            let response: URLResponse
            do {
                (payload, response) = try await session.data(for: request)
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
            if http.statusCode == 200 {
                data = payload
                break
            }
            attempt += 1
            if transientStatuses.contains(http.statusCode), attempt < maxAttempts {
                // Back off 300ms, then 600ms, before retrying.
                try await Task.sleep(nanoseconds: 300_000_000 * UInt64(attempt))
                continue
            }
            let message = (try? JSONDecoder().decode(GoogleBooksResponse.self, from: payload).error?.message)
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
        let applyJunkFilter = !includeAllEditions && !isISBNQuery
        let candidates: [BookSearchRanker.Candidate] = (decoded.items ?? []).compactMap { item in
            guard let book = mapToBook(item: item, filterJunkEditions: applyJunkFilter) else { return nil }
            return BookSearchRanker.Candidate(
                book: book,
                signals: BookSearchSignals(
                    ratingsCount: item.volumeInfo?.ratingsCount,
                    averageRating: item.volumeInfo?.averageRating,
                    language: item.volumeInfo?.language
                )
            )
        }
        let books: [Book]
        if isISBNQuery {
            books = candidates.map(\.book)
        } else {
            books = BookSearchRanker.rank(
                candidates,
                query: query,
                deduplicate: !includeAllEditions,
                libraryAuthors: libraryAuthors
            )
        }
        cacheQueue.async { [weak self] in
            guard let self = self else { return }
            if self.searchCache.count >= self.cacheMaxQueries {
                if let first = self.searchCache.keys.first { self.searchCache.removeValue(forKey: first) }
            }
            self.searchCache[cacheKey] = books
        }
        return books
    }

    /// Fetches a single volume by Google Books volume ID (same `Book.id` from search). Used to fill categories when the stored book has no genres.
    func fetchVolume(id: String) async throws -> Book? {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return nil }
        var comp = URLComponents(string: "\(baseURL)/\(encoded)")!
        var queryItems: [URLQueryItem] = []
        if let key = apiKey {
            queryItems.append(URLQueryItem(name: "key", value: key))
        }
        comp.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = comp.url else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw NSError(domain: "GoogleBooks", code: -2, userInfo: [NSLocalizedDescriptionKey: "Can't reach Google Books."])
        }
        guard let http = response as? HTTPURLResponse else { return nil }
        guard http.statusCode == 200 else { return nil }
        let item: GoogleBooksItem
        do {
            item = try JSONDecoder().decode(GoogleBooksItem.self, from: data)
        } catch {
            return nil
        }
        return mapToBook(item: item)
    }

    /// Use imageLinks in documented size order (best available first). Books without covers still map (empty coverURL — UI uses title placeholder / Open Library). Excludes obvious summary/study-guide entries unless `filterJunkEditions` is false ("show all editions" fallback).
    private func mapToBook(item: GoogleBooksItem, filterJunkEditions: Bool = true) -> Book? {
        guard let info = item.volumeInfo, let title = info.title, !title.isEmpty else { return nil }
        if filterJunkEditions {
            if title.range(of: "Summary", options: .caseInsensitive) != nil { return nil }
            if isLikelyNonBookEdition(title: title) { return nil }
        }
        let links = info.imageLinks
        // Prefer thumbnail → medium before extraLarge: very large assets are sometimes interior scans or preview pages, not the marketing cover.
        let rawOrder: [String?] = [
            links?.thumbnail,
            links?.smallThumbnail,
            links?.small,
            links?.medium,
            links?.large,
            links?.extraLarge
        ]
        var seen = Set<String>()
        let allURLs: [String] = rawOrder
            .compactMap { $0 }
            .map { $0.hasPrefix("http://") ? "https" + $0.dropFirst(4) : $0 }
            .map { Book.sanitizeGoogleBooksCoverURL($0) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
        let primary = allURLs.first ?? ""
        let fallbacks = Array(allURLs.dropFirst())
        let author = info.authors?.joined(separator: ", ") ?? "Unknown"
        let isbnDigits = Self.normalizedISBNDigits(from: info.industryIdentifiers)
        return Book(
            id: item.id,
            title: title,
            author: author,
            coverURL: primary,
            pageCount: info.pageCount,
            publishedDate: parsePublishedDate(info.publishedDate),
            description: info.description,
            genres: info.categories ?? [],
            isbn: isbnDigits,
            fallbackCoverURLs: fallbacks.isEmpty ? nil : fallbacks
        )
    }

    /// Filters junk editions that often appear in broad search (not used for strict ISBN queries).
    private func isLikelyNonBookEdition(title: String) -> Bool {
        let t = title.lowercased()
        let junk = ["summary", "study guide", "sparknotes", "cliffsnotes", "book review", "analysis of", "reading guide"]
        return junk.contains { t.contains($0) }
    }

    /// Prefer ISBN-13, then ISBN-10 (digits only).
    private static func normalizedISBNDigits(from identifiers: [IndustryIdentifier]?) -> String? {
        guard let ids = identifiers, !ids.isEmpty else { return nil }
        let upper = ids.map { ($0.type?.uppercased() ?? "", $0.identifier ?? "") }
        let isbn13 = upper.first { $0.0.contains("ISBN_13") || $0.0 == "ISBN13" }?.1
            ?? upper.first { $0.1.filter(\.isNumber).count == 13 }?.1
        let isbn10 = upper.first { $0.0.contains("ISBN_10") || $0.0 == "ISBN10" }?.1
            ?? upper.first { $0.1.filter(\.isNumber).count == 10 }?.1
        let digits = (isbn13 ?? isbn10)?.filter(\.isNumber) ?? ""
        guard digits.count == 10 || digits.count == 13 else { return nil }
        return digits
    }
}
