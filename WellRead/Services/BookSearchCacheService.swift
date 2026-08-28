//
//  BookSearchCacheService.swift
//  WellRead
//
//  Shared, cross-user Firestore cache for book search results. Book metadata is
//  effectively immutable, so once any user's search resolves a query, every other
//  user gets the result without spending Google Books quota (a hard 1,000/day
//  project-wide) or an Open Library round trip.
//

import CryptoKit
import FirebaseFirestore
import Foundation

final class BookSearchCacheService {
    static let shared = BookSearchCacheService()
    // FirestoreDatabase (not Firestore.firestore()): the app's data — and the
    // deployed rules — live on the named "wellread" database; the default
    // database has no rules, so requests there fail silently.
    private var db: Firestore { FirestoreDatabase.firestore }
    private let collection = "bookSearchCache"

    /// ISBNdb/Google-sourced entries carry full metadata and ranking — serve for
    /// a month. Open Library entries (written during API outages) expire fast so
    /// a later search can upgrade the entry.
    private let primaryTTL: TimeInterval = 30 * 24 * 3600
    private let openLibraryTTL: TimeInterval = 24 * 3600

    /// Don't let a slow Firestore round trip delay live search — past this, treat as a miss.
    private let lookupTimeout: UInt64 = 1_200_000_000

    enum Source: String {
        case isbndb
        case google
        case openLibrary = "openlibrary"
    }

    /// Bumped when ranking/filtering changes enough that old entries can be
    /// wrong in ways read-time filtering can't repair (v2: ISBN-implied language
    /// joined the ranking, so a legacy entry may have dedup-merged a foreign
    /// edition over the English one; v3: results are canonicalized against the
    /// community catalog — older entries carry pre-dedup ids and get upgraded
    /// in place on first read). Entries written before the field exists read
    /// as version 1.
    static let currentSchemaVersion = 3

    struct CachedEntry {
        let books: [Book]
        let schemaVersion: Int
        let source: Source
    }

    private init() {}

    /// Doc id is a hash: queries contain slashes/case/length Firestore ids can't take.
    private func docId(for cacheKey: String) -> String {
        SHA256.hash(data: Data(cacheKey.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// Cached books for the key, or nil on miss/expiry/timeout/error. Never throws —
    /// a cache problem must never break search.
    func lookup(cacheKey: String) async -> CachedEntry? {
        await withTaskGroup(of: CachedEntry?.self) { group in
            group.addTask { await self.fetchEntry(cacheKey: cacheKey) }
            group.addTask { [lookupTimeout] in
                try? await Task.sleep(nanoseconds: lookupTimeout)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    private func fetchEntry(cacheKey: String) async -> CachedEntry? {
        guard let snapshot = try? await db.collection(collection).document(docId(for: cacheKey)).getDocument(),
              snapshot.exists, let data = snapshot.data() else { return nil }
        guard let updated = (data["updatedAt"] as? Timestamp)?.dateValue() else { return nil }
        let source = Source(rawValue: data["source"] as? String ?? "") ?? .openLibrary
        let ttl = source == .openLibrary ? openLibraryTTL : primaryTTL
        guard Date().timeIntervalSince(updated) < ttl else { return nil }
        guard let raw = data["books"] as? [[String: Any]] else { return nil }
        let books = raw.compactMap(book(from:))
        guard !books.isEmpty else { return nil }
        return CachedEntry(books: books, schemaVersion: data["schemaVersion"] as? Int ?? 1, source: source)
    }

    /// Fire-and-forget write-through after a successful API fetch.
    func store(cacheKey: String, books: [Book], source: Source) {
        guard !books.isEmpty else { return }
        let payload: [String: Any] = [
            "query": String(cacheKey.prefix(200)),
            "source": source.rawValue,
            "schemaVersion": Self.currentSchemaVersion,
            "updatedAt": FieldValue.serverTimestamp(),
            "books": books.prefix(30).map(data(from:))
        ]
        db.collection(collection).document(docId(for: cacheKey)).setData(payload)
    }

    private func data(from book: Book) -> [String: Any] {
        var d: [String: Any] = [
            "id": book.id,
            "title": book.title,
            "author": book.author,
            "coverURL": book.coverURL,
            "genres": book.genres
        ]
        if let v = book.pageCount { d["pageCount"] = v }
        if let v = book.publishedDate { d["publishedDate"] = Timestamp(date: v) }
        if let v = book.description { d["description"] = v }
        if let v = book.isbn { d["isbn"] = v }
        if let v = book.fallbackCoverURLs, !v.isEmpty { d["fallbackCoverURLs"] = v }
        return d
    }

    private func book(from data: [String: Any]) -> Book? {
        guard let id = data["id"] as? String, !id.isEmpty,
              let title = data["title"] as? String, !title.isEmpty else { return nil }
        return Book(
            id: id,
            title: title,
            author: data["author"] as? String ?? "Unknown",
            coverURL: data["coverURL"] as? String ?? "",
            pageCount: data["pageCount"] as? Int,
            publishedDate: (data["publishedDate"] as? Timestamp)?.dateValue(),
            description: data["description"] as? String,
            genres: data["genres"] as? [String] ?? [],
            isbn: data["isbn"] as? String,
            fallbackCoverURLs: data["fallbackCoverURLs"] as? [String]
        )
    }
}
