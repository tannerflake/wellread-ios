//
//  GoogleBooksService.swift
//  WellRead
//
//  The app's book-search hub. Despite the name, `search` runs the full lookup
//  chain: shared Firestore cache → ISBNdb (paid, primary) → Google Books
//  (keyed, then keyless long shot) → Open Library. Every book search in the
//  app goes through here.
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

    /// Set when Google's shared anonymous (keyless) pool reports its *daily* quota
    /// exhausted — that won't recover for hours, so skip straight to keyed requests
    /// for a while instead of paying a doomed round trip on every search.
    private var keylessQuotaExhaustedUntil: Date?

    private var shouldSkipKeyless: Bool {
        cacheQueue.sync {
            guard let until = keylessQuotaExhaustedUntil else { return false }
            return until > Date()
        }
    }

    private func markKeylessQuotaExhausted() {
        cacheQueue.sync {
            keylessQuotaExhaustedUntil = Date().addingTimeInterval(30 * 60)
        }
    }

    /// Primary API key (project quota, 1,000/day shared across all users). Keyless
    /// requests draw from Google's single *global* anonymous pool, which has been
    /// permanently exhausted since ~2025 (429 on first request), so keyless is only
    /// attempted as a long-shot fallback when the keyed quota is also dry.
    /// Sources: Secrets.plist / Info.plist "GOOGLE_BOOKS_API_KEY", or
    /// GoogleService-Info.plist "API_KEY".
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
    /// `languageRestriction` (ISO 639-1, e.g. "en") hard-filters results to that
    /// language via Google's `langRestrict` — used by the Goodreads import, where a
    /// same-title foreign edition is worse than no match. Interactive search leaves
    /// it nil (the ranker's soft device-language preference applies instead).
    func search(query: String, includeAllEditions: Bool = false, libraryAuthors: Set<String> = [], languageRestriction: String? = nil) async throws -> [Book] {
        let normalized = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !normalized.isEmpty else { return [] }
        let isISBNQuery = normalized.hasPrefix("isbn:")
        let cacheKey = (languageRestriction.map { "lang=\($0)|" } ?? "") + (includeAllEditions ? "all|" : "") + normalized
        if let cached = cacheQueue.sync(execute: { searchCache[cacheKey] }) {
            return cached
        }
        // Shared cross-user Firestore cache: a query any user has run before resolves
        // without touching any API. (Entries keep the ranking of whoever populated
        // them — the libraryAuthors personalization boost isn't re-applied.)
        if let shared = await BookSearchCacheService.shared.lookup(cacheKey: cacheKey) {
            storeInMemory(cacheKey: cacheKey, books: shared)
            return shared
        }
        // Tier 1: ISBNdb (paid, dedicated quota). Google runs only when ISBNdb
        // errors, is rate-limited, or has nothing for the query.
        if ISBNdbService.shared.isConfigured {
            do {
                let books = try await searchISBNdb(
                    query: query,
                    isISBNQuery: isISBNQuery,
                    includeAllEditions: includeAllEditions,
                    libraryAuthors: libraryAuthors,
                    languageRestriction: languageRestriction
                )
                if !books.isEmpty {
                    storeInMemory(cacheKey: cacheKey, books: books)
                    BookSearchCacheService.shared.store(cacheKey: cacheKey, books: books, source: .isbndb)
                    return books
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // ISBNdb unavailable or throttled — fall through to Google.
            }
        }
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "maxResults", value: isISBNQuery ? "15" : "30"),
            URLQueryItem(name: "printType", value: "books"),
            URLQueryItem(name: "projection", value: "full")
        ]
        if let lang = languageRestriction, !lang.isEmpty {
            queryItems.append(URLQueryItem(name: "langRestrict", value: lang))
        }
        let data: Data
        do {
            data = try await googleSearchData(queryItems: queryItems)
        } catch let googleError as NSError where Self.isRetryableWithFallback(googleError) {
            // Both Google pools are dry — serve Open Library results instead of an error.
            // Cached with a short TTL so a later search upgrades to Google ranking.
            do {
                let books = try await OpenLibraryService.shared.search(query: query)
                guard !books.isEmpty else { throw googleError }
                storeInMemory(cacheKey: cacheKey, books: books)
                BookSearchCacheService.shared.store(cacheKey: cacheKey, books: books, source: .openLibrary)
                return books
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw googleError
            }
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
        storeInMemory(cacheKey: cacheKey, books: books)
        BookSearchCacheService.shared.store(cacheKey: cacheKey, books: books, source: .google)
        return books
    }

    /// ISBNdb tier of the search chain, shaped to match the Google path:
    /// same junk-edition filter, same ranker, same language restriction
    /// (applied client-side — ISBNdb has no langRestrict parameter; records
    /// with no language stay in, the import's title gate catches translations).
    private func searchISBNdb(
        query: String,
        isISBNQuery: Bool,
        includeAllEditions: Bool,
        libraryAuthors: Set<String>,
        languageRestriction: String?
    ) async throws -> [Book] {
        if isISBNQuery {
            let digits = query.trimmingCharacters(in: .whitespaces).dropFirst(5).filter(\.isNumber)
            guard let book = try await ISBNdbService.shared.lookupISBN(String(digits)) else { return [] }
            return [book]
        }
        var matches = try await ISBNdbService.shared.search(query: query)
        if let lang = languageRestriction?.lowercased(), !lang.isEmpty {
            matches = matches.filter { $0.languageCode == nil || $0.languageCode == lang }
        }
        let applyJunkFilter = !includeAllEditions
        let candidates: [BookSearchRanker.Candidate] = matches.compactMap { match in
            if applyJunkFilter, isJunkEditionTitle(match.book.title) { return nil }
            return BookSearchRanker.Candidate(
                book: match.book,
                signals: BookSearchSignals(ratingsCount: nil, averageRating: nil, language: match.languageCode)
            )
        }
        return BookSearchRanker.rank(
            candidates,
            query: query,
            deduplicate: !includeAllEditions,
            libraryAuthors: libraryAuthors
        )
    }

    private func storeInMemory(cacheKey: String, books: [Book]) {
        cacheQueue.sync {
            if searchCache.count >= cacheMaxQueries {
                if let first = searchCache.keys.first { searchCache.removeValue(forKey: first) }
            }
            searchCache[cacheKey] = books
        }
    }

    /// Keyed first: the project quota is the only Google pool that reliably works
    /// (the global anonymous pool 429s essentially always). If the keyed request is
    /// throttled or refused even after backoff, try keyless once as a long shot —
    /// unless keyless already reported its daily quota dry recently.
    private func googleSearchData(queryItems: [URLQueryItem]) async throws -> Data {
        guard apiKey != nil else {
            return try await requestData(queryItems: queryItems, usingKey: false)
        }
        do {
            return try await requestData(queryItems: queryItems, usingKey: true)
        } catch let keyedError as NSError where Self.isRetryableWithFallback(keyedError) && !shouldSkipKeyless {
            do {
                return try await requestData(queryItems: queryItems, usingKey: false)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // Surface the keyed error — its message (project quota) is the actionable one.
                throw keyedError
            }
        }
    }

    /// HTTP failures worth retrying on the other quota pool: throttles, server errors,
    /// and refusals. Network errors (offline, timeout, cancelled) surface negative codes
    /// and are excluded — a second request can't help there.
    private static func isRetryableWithFallback(_ error: NSError) -> Bool {
        error.domain == "GoogleBooks" && [403, 429, 500, 502, 503, 504].contains(error.code)
    }

    /// Performs a volumes search request, retrying transient throttles with backoff.
    ///
    /// Searching-as-you-type fires a request every time the debounce window elapses,
    /// so several can reach Google in quick succession and trip its rate limiter
    /// (HTTP 429/503 "Service temporarily unavailable"). Retry those transient throttles
    /// with a short backoff so they resolve themselves instead of forcing the user to
    /// tap "Try Again". Cancellation during the backoff propagates to the caller.
    private func requestData(queryItems: [URLQueryItem], usingKey: Bool) async throws -> Data {
        var items = queryItems
        if usingKey, let key = apiKey {
            items.append(URLQueryItem(name: "key", value: key))
        }
        var comp = URLComponents(string: baseURL)!
        comp.queryItems = items
        guard let url = comp.url else {
            throw NSError(domain: "GoogleBooks", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid search query."])
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        let transientStatuses: Set<Int> = [429, 500, 502, 503, 504]
        let maxAttempts = 3
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
                return payload
            }
            attempt += 1
            let errorMessage = try? JSONDecoder().decode(GoogleBooksResponse.self, from: payload).error?.message
            // A "Queries per day" 429 is a daily quota that won't recover for hours —
            // backoff can't help, so fail fast (and remember, so later searches skip
            // the keyless attempt entirely).
            let isDailyQuota = http.statusCode == 429 && (errorMessage?.localizedCaseInsensitiveContains("per day") ?? false)
            if isDailyQuota, !usingKey {
                markKeylessQuotaExhausted()
            }
            if transientStatuses.contains(http.statusCode), !isDailyQuota, attempt < maxAttempts {
                // Back off 300ms, then 600ms, before retrying.
                try await Task.sleep(nanoseconds: 300_000_000 * UInt64(attempt))
                continue
            }
            let message = errorMessage ?? "Request failed (HTTP \(http.statusCode))."
            let hint = (usingKey && http.statusCode == 403)
                ? " Enable the Books API in Google Cloud Console (APIs & Services → Library → Books API) and ensure your API key is allowed."
                : ""
            throw NSError(domain: "GoogleBooks", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: message + hint])
        }
    }

    /// Fetches a single volume by Google Books volume ID (same `Book.id` from search). Used to fill categories when the stored book has no genres.
    func fetchVolume(id: String) async throws -> Book? {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return nil }
        // Keyed first; one keyless long-shot retry if the project quota is dry.
        var result = try await volumeData(encodedId: encoded, usingKey: apiKey != nil)
        if case .retryable = result, apiKey != nil, !shouldSkipKeyless {
            result = try await volumeData(encodedId: encoded, usingKey: false)
        }
        guard case .success(let data) = result else { return nil }
        let item: GoogleBooksItem
        do {
            item = try JSONDecoder().decode(GoogleBooksItem.self, from: data)
        } catch {
            return nil
        }
        return mapToBook(item: item)
    }

    private enum VolumeFetchResult {
        case success(Data)
        /// Throttle/refusal status where a keyed retry might succeed.
        case retryable
        case failed
    }

    private func volumeData(encodedId: String, usingKey: Bool) async throws -> VolumeFetchResult {
        var comp = URLComponents(string: "\(baseURL)/\(encodedId)")!
        if usingKey, let key = apiKey {
            comp.queryItems = [URLQueryItem(name: "key", value: key)]
        }
        guard let url = comp.url else { return .failed }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw NSError(domain: "GoogleBooks", code: -2, userInfo: [NSLocalizedDescriptionKey: "Can't reach Google Books."])
        }
        guard let http = response as? HTTPURLResponse else { return .failed }
        guard http.statusCode == 200 else {
            if !usingKey, http.statusCode == 429,
               let msg = try? JSONDecoder().decode(GoogleBooksResponse.self, from: data).error?.message,
               msg.localizedCaseInsensitiveContains("per day") {
                markKeylessQuotaExhausted()
            }
            return [403, 429, 500, 502, 503, 504].contains(http.statusCode) ? .retryable : .failed
        }
        return .success(data)
    }

    /// Use imageLinks in documented size order (best available first). Books without covers still map (empty coverURL — UI uses title placeholder / Open Library). Excludes obvious summary/study-guide entries unless `filterJunkEditions` is false ("show all editions" fallback).
    private func mapToBook(item: GoogleBooksItem, filterJunkEditions: Bool = true) -> Book? {
        guard let info = item.volumeInfo, let title = info.title, !title.isEmpty else { return nil }
        if filterJunkEditions, isJunkEditionTitle(title) { return nil }
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

    /// Filters junk editions that often appear in broad search (not used for
    /// strict ISBN queries) — shared by the ISBNdb and Google tiers.
    private func isJunkEditionTitle(_ title: String) -> Bool {
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
