//
//  OpenLibraryService.swift
//  WellRead
//
//  Book search + ISBN lookup against Open Library. Primary source for
//  Goodreads-import ISBN resolution, and the fallback when Google Books'
//  daily quota is exhausted so users get results instead of errors.
//  Rate limits are per-IP from the device (3 req/s when the app identifies
//  itself via User-Agent), so capacity scales with the user base.
//  https://openlibrary.org/developers/api
//

import Foundation

struct OpenLibrarySearchResponse: Codable {
    let docs: [OpenLibraryDoc]?
}

struct OpenLibraryDoc: Codable {
    let key: String?               // "/works/OL17075811W"
    let title: String?
    let authorName: [String]?
    let coverI: Int?
    let firstPublishYear: Int?
    let numberOfPagesMedian: Int?
    let subject: [String]?
    let editions: OpenLibraryEditions?

    enum CodingKeys: String, CodingKey {
        case key, title, subject, editions
        case authorName = "author_name"
        case coverI = "cover_i"
        case firstPublishYear = "first_publish_year"
        case numberOfPagesMedian = "number_of_pages_median"
    }
}

/// The `editions` sub-search on a work doc: the editions of the work that matched
/// the query itself (the exact edition for an `isbn:` query), best-first for the
/// requested `lang`.
struct OpenLibraryEditions: Codable {
    let docs: [OpenLibraryEditionDoc]?
}

struct OpenLibraryEditionDoc: Codable {
    let title: String?
    let coverI: Int?
    let language: [String]?        // ISO 639-2 codes, e.g. ["eng"]

    enum CodingKeys: String, CodingKey {
        case title, language
        case coverI = "cover_i"
    }
}

final class OpenLibraryService {
    static let shared = OpenLibraryService()
    private let session: URLSession

    // Circuit breaker. Open Library throttles per-IP in ~5-minute windows, and a
    // throttled request stalls until the timeout rather than refusing quickly.
    // Every caller here has a Google fallback, so once OL looks down, fail fast
    // for a while instead of paying the timeout on each lookup — the Goodreads
    // import hits OL first for every ISBN, and those serialized stalls showed up
    // as multi-minute "Finding your book…" hangs.
    private let breakerQueue = DispatchQueue(label: "com.wellread.openlibrary.breaker")
    private var consecutiveFailures = 0
    private var unavailableUntil: Date?

    private init() {
        let config = URLSessionConfiguration.default
        // Short timeouts: healthy OL answers in ~1-2s, and every caller falls
        // back to Google Books, so waiting longer only delays the fallback.
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 12
        // Identified traffic gets a 3x rate limit vs anonymous (Open Library policy).
        config.httpAdditionalHeaders = ["User-Agent": "SPINE/2.0 (tanner@tinyhealth.com)"]
        session = URLSession(configuration: config)
    }

    private var breakerOpen: Bool {
        breakerQueue.sync {
            guard let until = unavailableUntil else { return false }
            return until > Date()
        }
    }

    /// Two consecutive failures open the breaker for 5 minutes (one throttle
    /// window). After it expires the next real attempt either resets the count
    /// or re-opens it immediately.
    private func recordFailure() {
        breakerQueue.sync {
            consecutiveFailures += 1
            if consecutiveFailures >= 2 {
                unavailableUntil = Date().addingTimeInterval(5 * 60)
            }
        }
    }

    private func recordSuccess() {
        breakerQueue.sync {
            consecutiveFailures = 0
            unavailableUntil = nil
        }
    }

    /// Free-text search. Results are work-level (one row per book, editions already
    /// collapsed), in Open Library's relevance order with covered books surfaced first.
    func search(query: String, limit: Int = 30) async throws -> [Book] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }
        if trimmed.lowercased().hasPrefix("isbn:") {
            let digits = String(trimmed.dropFirst(5)).filter(\.isNumber)
            guard let book = try await lookupISBN(digits) else { return [] }
            return [book]
        }
        let docs = try await fetchDocs(q: trimmed, limit: limit)
        let books = docs.compactMap { map(doc: $0, isbn: nil) }
        return books.filter { !$0.coverURL.isEmpty } + books.filter { $0.coverURL.isEmpty }
    }

    /// Exact ISBN lookup (10 or 13 digits); the queried ISBN becomes the book's
    /// canonical id so the same edition matches across lookups.
    func lookupISBN(_ isbn: String) async throws -> Book? {
        let digits = isbn.filter(\.isNumber)
        guard digits.count == 10 || digits.count == 13 else { return nil }
        let docs = try await fetchDocs(q: "isbn:\(digits)", limit: 2)
        guard let doc = docs.first else { return nil }
        return map(doc: doc, isbn: digits)
    }

    /// ISO 639-1 code Open Library uses to decide which edition of a work
    /// represents it in the `editions` sub-doc. English fallback — the
    /// catalog's dominant language.
    private var preferredLanguage: String {
        Locale.current.language.languageCode?.identifier.lowercased() ?? "en"
    }

    private func fetchDocs(q: String, limit: Int) async throws -> [OpenLibraryDoc] {
        guard !breakerOpen else {
            throw NSError(domain: "OpenLibrary", code: 429, userInfo: [NSLocalizedDescriptionKey: "Open Library is busy right now."])
        }
        var comp = URLComponents(string: "https://openlibrary.org/search.json")!
        comp.queryItems = [
            URLQueryItem(name: "q", value: q),
            URLQueryItem(name: "limit", value: "\(limit)"),
            URLQueryItem(name: "lang", value: preferredLanguage),
            URLQueryItem(name: "fields", value: "key,title,author_name,cover_i,first_publish_year,number_of_pages_median,subject,editions,editions.title,editions.cover_i,editions.language")
        ]
        guard let url = comp.url else { return [] }
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(from: url)
        } catch let urlError as URLError where urlError.code == .cancelled {
            // Caller cancelled — says nothing about Open Library's health.
            throw CancellationError()
        } catch {
            recordFailure()
            throw NSError(domain: "OpenLibrary", code: -2, userInfo: [NSLocalizedDescriptionKey: "Can't reach Open Library. Check your connection."])
        }
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            recordFailure()
            throw NSError(domain: "OpenLibrary", code: code, userInfo: [NSLocalizedDescriptionKey: "Open Library request failed (HTTP \(code))."])
        }
        recordSuccess()
        return (try? JSONDecoder().decode(OpenLibrarySearchResponse.self, from: data))?.docs ?? []
    }

    /// Map a work doc to the app model. `id` is the ISBN digits when the caller knows
    /// them (Book.id already sanctions ISBN ids), else the OL work key (e.g. "OL17075811W").
    private func map(doc: OpenLibraryDoc, isbn: String?) -> Book? {
        // The work-level title/cover reflect whichever edition the OL work record
        // was created from — frequently a Spanish/French translation even when the
        // queried ISBN is English. The `editions` sub-doc holds the edition that
        // matched the query itself (the exact edition for `isbn:` lookups, the
        // preferred-language edition for free-text search), so its title/cover
        // describe the book the user actually has.
        let edition = doc.editions?.docs?.first
        var title = doc.title ?? ""
        if let editionTitle = edition?.title, !editionTitle.isEmpty {
            title = editionTitle
        }
        guard !title.isEmpty else { return nil }
        let workId = doc.key?.split(separator: "/").last.map(String.init)
        guard let id = isbn ?? workId else { return nil }
        var cover = ""
        if let coverId = edition?.coverI ?? doc.coverI {
            cover = "https://covers.openlibrary.org/b/id/\(coverId)-L.jpg?default=false"
        }
        var published: Date?
        if let year = doc.firstPublishYear {
            var comps = DateComponents()
            comps.year = year
            comps.calendar = Calendar(identifier: .gregorian)
            comps.timeZone = TimeZone(identifier: "UTC")
            published = comps.date
        }
        // OL subjects are a noisy multilingual grab-bag ("SCIENCE / General",
        // "nyt:...=2015-02-08"); keep only short plain labels.
        let genres = (doc.subject ?? [])
            .filter { $0.count < 30 && !$0.contains("/") && !$0.contains(":") && !$0.contains("=") }
            .prefix(5)
        return Book(
            id: id,
            title: title,
            author: doc.authorName?.joined(separator: ", ") ?? "Unknown",
            coverURL: cover,
            pageCount: doc.numberOfPagesMedian,
            publishedDate: published,
            description: nil,
            genres: Array(genres),
            isbn: isbn
        )
    }
}
