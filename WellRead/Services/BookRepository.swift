//
//  BookRepository.swift
//  WellRead
//
//  Firestore books collection: get or create by Google Books ID.
//

import Foundation
import FirebaseFirestore

final class BookRepository {
    private let db = FirestoreDatabase.firestore
    private let books = "books"

    /// Gets a book by id (Google Books ID). Returns nil if not found.
    func getBook(id: String) async -> Book? {
        let ref = db.collection(books).document(id)
        do {
            let snapshot = try await ref.getDocument()
            guard snapshot.exists, let data = snapshot.data() else { return nil }
            return book(from: data, id: id)
        } catch {
            return nil
        }
    }

    /// Ensures a book document exists; creates it if missing. Use when a user adds a book.
    func ensureBook(_ book: Book) async throws {
        let ref = db.collection(books).document(book.id)
        let snapshot = try await ref.getDocument()
        guard !snapshot.exists else { return }
        try await ref.setData([
            "title": book.title,
            "author": book.author,
            "coverURL": book.coverURL,
            "pageCount": book.pageCount as Any,
            "publishedDate": book.publishedDate.map { Timestamp(date: $0) } as Any,
            "description": book.description as Any,
            "genres": book.genres,
        ])
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
            genres: data["genres"] as? [String] ?? []
        )
    }
}
