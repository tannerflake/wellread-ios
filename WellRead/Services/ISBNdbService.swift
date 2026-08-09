//
//  ISBNdbService.swift
//  WellRead
//
//  Primary book metadata source (paid). The app-wide lookup chain is
//  ISBNdb → Google Books → Open Library, orchestrated in GoogleBooksService's
//  search hub; this client only talks to ISBNdb.
//
//  The account is the Basic plan: 1 request/second, so every request is paced
//  through a serial throttle — bursts (Goodreads-import prefetch, bulk import)
//  queue up instead of tripping 429s. Failures open a short circuit breaker so
//  the chain falls through to Google fast instead of stalling per lookup.
//

import Foundation

/// Paces requests so consecutive starts are at least `minInterval` apart
/// (ISBNdb enforces a per-second cap server-side).
private actor ISBNdbRequestPacer {
    private let minInterval: TimeInterval
    private var nextAllowed = Date.distantPast

    init(minInterval: TimeInterval) {
        self.minInterval = minInterval
    }

    func waitTurn() async throws {
        let now = Date()
        let start = max(now, nextAllowed)
        nextAllowed = start.addingTimeInterval(minInterval)
        let delay = start.timeIntervalSince(now)
        if delay > 0 {
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
    }
}

/// One ISBNdb record. Fields decode leniently (`try?` per field) — the API
/// mixes types across records (e.g. `date_published` as "2021-05-04" or 2021)
/// and one odd field must not drop the whole result set.
struct ISBNdbBook {
    let title: String?
    let isbn13: String?
    let isbn10: String?
    let authors: [String]?
    let image: String?
    let synopsis: String?
    let subjects: [String]?
    let pages: Int?
    let datePublished: String?
    let language: String?
}

extension ISBNdbBook: Decodable {
    private enum CodingKeys: String, CodingKey {
        case title, isbn, isbn13, isbn10, authors, image, synopsis, subjects, pages, language
        case titleLong = "title_long"
        case datePublished = "date_published"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = (try? c.decodeIfPresent(String.self, forKey: .title))
            ?? (try? c.decodeIfPresent(String.self, forKey: .titleLong))
        isbn13 = (try? c.decodeIfPresent(String.self, forKey: .isbn13))
            ?? (try? c.decodeIfPresent(String.self, forKey: .isbn))
        isbn10 = try? c.decodeIfPresent(String.self, forKey: .isbn10)
        authors = try? c.decodeIfPresent([String].self, forKey: .authors)
        image = try? c.decodeIfPresent(String.self, forKey: .image)
        synopsis = try? c.decodeIfPresent(String.self, forKey: .synopsis)
        subjects = try? c.decodeIfPresent([String].self, forKey: .subjects)
        pages = (try? c.decodeIfPresent(Int.self, forKey: .pages))
            ?? (try? c.decodeIfPresent(String.self, forKey: .pages)).flatMap { Int($0) }
        datePublished = (try? c.decodeIfPresent(String.self, forKey: .datePublished))
            ?? (try? c.decodeIfPresent(Int.self, forKey: .datePublished)).map { String($0) }
        language = try? c.decodeIfPresent(String.self, forKey: .language)
    }
}

private struct ISBNdbBookResponse: Decodable {
    let book: ISBNdbBook?
}

private struct ISBNdbSearchResponse: Decodable {
    let books: [ISBNdbBook]?
}

final class ISBNdbService {
    static let shared = ISBNdbService()

    /// A mapped book plus the record's language code — `Book` doesn't carry
    /// language, and the search hub needs it for ranking and lang filtering.
    struct Match {
        let book: Book
        let languageCode: String?
    }

    private let baseURL = "https://api2.isbndb.com"
    private let session: URLSession
    private let pacer = ISBNdbRequestPacer(minInterval: 1.05)

    // Circuit breaker, same shape as OpenLibraryService's: two consecutive
    // failures fail lookups fast for a while so the Google fallback runs
    // immediately instead of after a timeout per book.
    private let breakerQueue = DispatchQueue(label: "com.wellread.isbndb.breaker")
    private var consecutiveFailures = 0
    private var unavailableUntil: Date?

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 15
        session = URLSession(configuration: config)
    }

    /// Sources: Secrets.plist / Info.plist "ISBNDB_API_KEY".
    private var apiKey: String? {
        for plist in ["Secrets", "Info"] {
            if let path = Bundle.main.path(forResource: plist, ofType: "plist"),
               let dict = NSDictionary(contentsOfFile: path),
               let key = dict["ISBNDB_API_KEY"] as? String, !key.isEmpty {
                return key
            }
        }
        return nil
    }

    /// False when no API key is bundled — the chain skips straight to Google.
    var isConfigured: Bool { apiKey != nil }

    private var breakerOpen: Bool {
        breakerQueue.sync {
            guard let until = unavailableUntil else { return false }
            return until > Date()
        }
    }

    private func recordFailure() {
        breakerQueue.sync {
            consecutiveFailures += 1
            if consecutiveFailures >= 2 {
                unavailableUntil = Date().addingTimeInterval(2 * 60)
            }
        }
    }

    private func recordSuccess() {
        breakerQueue.sync {
            consecutiveFailures = 0
            unavailableUntil = nil
        }
    }

    /// Exact ISBN lookup (10 or 13 digits). Returns nil when ISBNdb doesn't
    /// know the ISBN; throws only for service problems (so callers can
    /// distinguish "no match" from "try the fallback source").
    func lookupISBN(_ isbn: String) async throws -> Book? {
        let digits = isbn.filter(\.isNumber)
        guard digits.count == 10 || digits.count == 13 else { return nil }
        guard let data = try await getData(path: "/book/\(digits)") else { return nil }
        guard let record = try? JSONDecoder().decode(ISBNdbBookResponse.self, from: data).book else { return nil }
        return map(record, queriedISBN: digits)?.book
    }

    /// Free-text search. Result order is ISBNdb's relevance — the search hub
    /// re-ranks with `BookSearchRanker`.
    func search(query: String, limit: Int = 30) async throws -> [Match] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }
        if trimmed.lowercased().hasPrefix("isbn:") {
            let digits = String(trimmed.dropFirst(5)).filter(\.isNumber)
            guard let book = try await lookupISBN(digits) else { return [] }
            return [Match(book: book, languageCode: nil)]
        }
        guard let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return [] }
        guard let data = try await getData(path: "/books/\(encoded)", queryItems: [URLQueryItem(name: "pageSize", value: "\(limit)")]) else { return [] }
        let records = (try? JSONDecoder().decode(ISBNdbSearchResponse.self, from: data).books) ?? []
        return records.compactMap { map($0, queriedISBN: nil) }
    }

    /// Returns response data, nil for "not found" (400/404 — ISBNdb answers
    /// both for unknown ISBNs/queries), and throws for service failures.
    private func getData(path: String, queryItems: [URLQueryItem] = []) async throws -> Data? {
        guard let key = apiKey else {
            throw NSError(domain: "ISBNdb", code: -3, userInfo: [NSLocalizedDescriptionKey: "ISBNdb API key is not configured."])
        }
        guard !breakerOpen else {
            throw NSError(domain: "ISBNdb", code: 429, userInfo: [NSLocalizedDescriptionKey: "ISBNdb is busy right now."])
        }
        var comp = URLComponents(string: baseURL + path)!
        if !queryItems.isEmpty { comp.queryItems = queryItems }
        guard let url = comp.url else { return nil }
        var request = URLRequest(url: url)
        request.setValue(key, forHTTPHeaderField: "Authorization")

        var attempt = 0
        while true {
            try await pacer.waitTurn()
            let (data, response): (Data, URLResponse)
            do {
                (data, response) = try await session.data(for: request)
            } catch let urlError as URLError where urlError.code == .cancelled {
                throw CancellationError()
            } catch {
                recordFailure()
                throw NSError(domain: "ISBNdb", code: -2, userInfo: [NSLocalizedDescriptionKey: "Can't reach ISBNdb. Check your connection."])
            }
            guard let http = response as? HTTPURLResponse else {
                recordFailure()
                throw NSError(domain: "ISBNdb", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response from ISBNdb."])
            }
            switch http.statusCode {
            case 200:
                recordSuccess()
                return data
            case 400, 404:
                // Unknown ISBN / no results — the service itself is healthy.
                recordSuccess()
                return nil
            case 429 where attempt == 0:
                // Rode over the per-second cap (e.g. another device on the same
                // account) — one paced retry before giving up.
                attempt += 1
                continue
            default:
                recordFailure()
                throw NSError(domain: "ISBNdb", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "ISBNdb request failed (HTTP \(http.statusCode))."])
            }
        }
    }

    // MARK: Mapping

    private func map(_ record: ISBNdbBook, queriedISBN: String?) -> Match? {
        guard let rawTitle = record.title?.trimmingCharacters(in: .whitespacesAndNewlines), !rawTitle.isEmpty else { return nil }
        let isbn13 = record.isbn13?.filter(\.isNumber)
        let isbn10 = record.isbn10?.filter(\.isNumber)
        let isbn = [queriedISBN, isbn13, isbn10]
            .compactMap { $0 }
            .first { $0.count == 10 || $0.count == 13 }
        // Book.id already sanctions ISBN ids (Open Library lookups use them too);
        // ISBNdb has no other stable identifier.
        guard let id = isbn else { return nil }
        // `image` is the stable CDN URL; `image_original` carries an expiring
        // signed token, so it must never be persisted.
        let cover = record.image ?? ""
        // Synopses arrive as HTML fragments, same as Goodreads reviews.
        let description = GoodreadsCSVParser.plainText(fromReviewHTML: record.synopsis)
        // Subjects mix plain labels with BISAC paths ("FICTION / Thrillers");
        // keep only short plain ones, as the Open Library mapping does.
        let genres = (record.subjects ?? [])
            .filter { $0.count < 30 && !$0.contains("/") && !$0.contains(":") && !$0.contains("=") }
            .prefix(5)
        let joinedAuthors = record.authors?.joined(separator: ", ").trimmingCharacters(in: .whitespaces) ?? ""
        let book = Book(
            id: id,
            title: rawTitle,
            author: joinedAuthors.isEmpty ? "Unknown" : joinedAuthors,
            coverURL: cover,
            pageCount: record.pages,
            publishedDate: Self.parseDate(record.datePublished),
            description: description,
            genres: Array(genres),
            isbn: isbn
        )
        return Match(book: book, languageCode: Self.languageCode(record.language))
    }

    /// "2021-05-04", "2021-05", or "2021".
    private static func parseDate(_ raw: String?) -> Date? {
        guard let raw = raw?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return nil }
        let utc = TimeZone(identifier: "UTC")!
        for format in ["yyyy-MM-dd", "yyyy-MM", "yyyy"] {
            let f = DateFormatter()
            f.dateFormat = format
            f.timeZone = utc
            f.locale = Locale(identifier: "en_US_POSIX")
            if let d = f.date(from: raw) { return d }
        }
        return nil
    }

    /// ISBNdb is inconsistent: "en" on some records, "English" on others.
    private static func languageCode(_ raw: String?) -> String? {
        guard let l = raw?.trimmingCharacters(in: .whitespaces).lowercased(), !l.isEmpty else { return nil }
        if l.count == 2 { return l }
        let names = [
            "english": "en", "spanish": "es", "french": "fr", "german": "de",
            "italian": "it", "portuguese": "pt", "dutch": "nl", "japanese": "ja",
            "chinese": "zh", "russian": "ru", "korean": "ko", "arabic": "ar"
        ]
        if let code = names[l] { return code }
        // "en_US"-style tags.
        if l.count > 2, l[l.index(l.startIndex, offsetBy: 2)] == "_" || l[l.index(l.startIndex, offsetBy: 2)] == "-" {
            return String(l.prefix(2))
        }
        return nil
    }
}
