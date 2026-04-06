//
//  BookRepository.swift
//  WellRead
//
//  Firestore books collection: get or create by Google Books ID. In-memory cache for fast repeat lookups.
//

import Foundation
import FirebaseFirestore

final class BookRepository {
    static let shared = BookRepository()

    private let db = FirestoreDatabase.firestore
    private let books = "books"
    private var memoryCache: [String: Book] = [:]
    private let cacheQueue = DispatchQueue(label: "com.wellread.bookrepo.cache")

    /// Prewarm cache with books (e.g. from disk-loaded library) so getBook returns immediately for these ids.
    func prewarmCache(with books: [Book]) {
        cacheQueue.sync {
            for b in books {
                memoryCache[b.id] = b
            }
        }
    }

    /// Clear in-memory cache (e.g. on sign-out). Optional.
    func clearCache() {
        cacheQueue.sync { memoryCache.removeAll() }
    }

    /// Gets a book by id. Checks in-memory cache first, then Firestore (aborts after **2s** and returns a title-only placeholder so lists don’t spin forever).
    func getBook(id: String) async -> Book? {
        if let cached = cacheQueue.sync(execute: { memoryCache[id] }) {
            return cached
        }
        let ref = db.collection(books).document(id)
        enum Race: Sendable {
            case loaded(Book?)
            case timedOut
        }
        return await withTaskGroup(of: Race.self) { group in
            group.addTask { [self] in
                do {
                    let snapshot = try await ref.getDocument()
                    guard snapshot.exists, let data = snapshot.data(), let b = book(from: data, id: id) else {
                        return .loaded(nil)
                    }
                    return .loaded(b)
                } catch {
                    return .loaded(nil)
                }
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                return .timedOut
            }
            guard let first = await group.next() else {
                group.cancelAll()
                return nil
            }
            switch first {
            case .timedOut:
                group.cancelAll()
                return Book.metadataLoadTimeoutPlaceholder(id: id)
            case .loaded(let b):
                group.cancelAll()
                if let b {
                    cacheQueue.sync { memoryCache[id] = b }
                    return b
                }
                return nil
            }
        }
    }

    /// Ensures a book document exists; creates it if missing. Use when a user adds a book.
    func ensureBook(_ book: Book) async throws {
        let ref = db.collection(books).document(book.id)
        let snapshot = try await ref.getDocument()
        guard !snapshot.exists else { return }
        var data: [String: Any] = [
            "title": book.title,
            "author": book.author,
            "coverURL": book.coverURL,
            "pageCount": book.pageCount as Any,
            "publishedDate": book.publishedDate.map { Timestamp(date: $0) } as Any,
            "description": book.description as Any,
            "genres": book.genres,
        ]
        if let isbn = book.isbn { data["isbn"] = isbn }
        try await ref.setData(data)
    }
}

extension BookRepository {
    fileprivate func book(from data: [String: Any], id: String) -> Book? {
        guard let title = data["title"] as? String,
              let author = data["author"] as? String,
              let coverURL = data["coverURL"] as? String else { return nil }
        let pageCount = data["pageCount"] as? Int
        var publishedDate: Date?
        if let ts = data["publishedDate"] as? Timestamp {
            publishedDate = ts.dateValue()
        }
        return Book(
            id: id,
            title: title,
            author: author,
            coverURL: coverURL,
            pageCount: pageCount,
            publishedDate: publishedDate,
            description: data["description"] as? String,
            genres: data["genres"] as? [String] ?? [],
            isbn: data["isbn"] as? String
        )
    }
}
