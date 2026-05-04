//
//  UserBookRepository.swift
//  WellRead
//
//  Firestore userBooks: CRUD, query by userId/status, tier updates.
//

import Foundation
import FirebaseFirestore

final class UserBookRepository {
    private let db = FirestoreDatabase.firestore
    private let userBooks = "userBooks"
    private let bookRepo: BookRepository

    init(bookRepository: BookRepository = BookRepository.shared) {
        self.bookRepo = bookRepository
    }

    /// Listens to all userBooks for a user (for real-time Library updates).
    func listenUserBooks(userId: String, onUpdate: @escaping ([UserBook]) -> Void) -> ListenerRegistration {
        db.collection(userBooks)
            .whereField("userId", isEqualTo: userId)
            .order(by: "updatedAt", descending: true)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self, let snapshot = snapshot else { return }
                let list = snapshot.documents.compactMap { doc -> UserBook? in
                    self.userBook(from: doc.data(), docId: doc.documentID)
                }
                Task {
                    var withBooks: [UserBook] = []
                    for ub in list {
                        var ub = ub
                        ub.book = await self.bookRepo.getBook(id: ub.bookId)
                        withBooks.append(ub)
                    }
                    await MainActor.run { onUpdate(withBooks) }
                }
            }
    }

    /// Fetches userBooks for a user (one-shot).
    func fetchUserBooks(userId: String) async -> [UserBook] {
        do {
            let snapshot = try await db.collection(userBooks)
                .whereField("userId", isEqualTo: userId)
                .order(by: "updatedAt", descending: true)
                .getDocuments()
            var list: [UserBook] = []
            for doc in snapshot.documents {
                guard let ub = userBook(from: doc.data(), docId: doc.documentID) else { continue }
                var withBook = ub
                withBook.book = await bookRepo.getBook(id: ub.bookId)
                list.append(withBook)
            }
            return list
        } catch {
            return []
        }
    }

    /// Fetches userBooks for a user filtered by status.
    func fetchUserBooks(userId: String, status: ReadingStatus) async -> [UserBook] {
        do {
            let snapshot = try await db.collection(userBooks)
                .whereField("userId", isEqualTo: userId)
                .whereField("status", isEqualTo: status.rawValue)
                .order(by: "updatedAt", descending: true)
                .getDocuments()
            var list: [UserBook] = []
            for doc in snapshot.documents {
                guard let ub = userBook(from: doc.data(), docId: doc.documentID) else { continue }
                var withBook = ub
                withBook.book = await bookRepo.getBook(id: ub.bookId)
                list.append(withBook)
            }
            return list
        } catch {
            return []
        }
    }

    /// Adds a userBook (and ensures the book exists). Returns the created UserBook with its id.
    func addUserBook(userId: String, book: Book, status: ReadingStatus, rating: Double?, reviewText: String?, dateStarted: Date?, dateFinished: Date?) async throws -> UserBook {
        try await bookRepo.ensureBook(book)
        let id = UUID()
        let now = Date()
        let ref = db.collection(userBooks).document(id.uuidString)
        var data: [String: Any] = [
            "userId": userId,
            "bookId": book.id,
            "status": status.rawValue,
            "rating": rating.map { Theme.normalizeRatingOutOfTen($0) } as Any,
            "reviewText": reviewText as Any,
            "dateStarted": dateStarted.map { Timestamp(date: $0) } as Any,
            "dateFinished": dateFinished.map { Timestamp(date: $0) } as Any,
            "createdAt": Timestamp(date: now),
            "updatedAt": Timestamp(date: now),
            "recommendedTo": [] as [String],
            "tier": NSNull(),
            "tierOrder": NSNull(),
        ]
        var queueShelf: QueueShelf?
        var queueOrder: Int?
        if status == .wantToRead {
            queueShelf = .backlog
            queueOrder = 0
            data["queueShelf"] = QueueShelf.backlog.rawValue
            data["queueOrder"] = 0
            let snapshot = try await db.collection(userBooks)
                .whereField("userId", isEqualTo: userId)
                .whereField("status", isEqualTo: status.rawValue)
                .getDocuments()
            let batch = db.batch()
            for doc in snapshot.documents {
                let d = doc.data()
                let shelfRaw = d["queueShelf"] as? String
                // Don't bump order for books on the explicit shelves (Reading Now / Up Next) — only backlog gets pushed down by the new arrival.
                if shelfRaw == QueueShelf.upNext.rawValue { continue }
                if shelfRaw == QueueShelf.readingNow.rawValue { continue }
                let ord = (d["queueOrder"] as? Int) ?? 1_000_000
                batch.updateData([
                    "queueOrder": ord + 1,
                    "updatedAt": Timestamp(date: now),
                ], forDocument: doc.reference)
            }
            batch.setData(data, forDocument: ref)
            try await batch.commit()
        } else {
            data["queueShelf"] = NSNull()
            data["queueOrder"] = NSNull()
            try await ref.setData(data)
        }
        return UserBook(
            id: id,
            userId: userId,
            bookId: book.id,
            book: book,
            status: status,
            rating: rating,
            reviewText: reviewText,
            dateStarted: dateStarted,
            dateFinished: dateFinished,
            createdAt: now,
            updatedAt: now,
            recommendedTo: [],
            tier: nil,
            tierOrder: nil,
            queueShelf: queueShelf,
            queueOrder: queueOrder
        )
    }

    /// Updates status, rating, review, dates, tier, tierOrder.
    func updateUserBook(_ userBook: UserBook) async throws {
        let ref = db.collection(userBooks).document(userBook.id.uuidString)
        var fields: [String: Any] = [
            "status": userBook.status.rawValue,
            "rating": userBook.rating.map { Theme.normalizeRatingOutOfTen($0) } as Any,
            "reviewText": userBook.reviewText as Any,
            "dateStarted": userBook.dateStarted.map { Timestamp(date: $0) } as Any,
            "dateFinished": userBook.dateFinished.map { Timestamp(date: $0) } as Any,
            "updatedAt": Timestamp(date: userBook.updatedAt),
            "tier": userBook.tier as Any,
            "tierOrder": userBook.tierOrder as Any,
        ]
        if let qs = userBook.queueShelf {
            fields["queueShelf"] = qs.rawValue
        } else {
            fields["queueShelf"] = NSNull()
        }
        if let qo = userBook.queueOrder {
            fields["queueOrder"] = qo
        } else {
            fields["queueOrder"] = NSNull()
        }
        try await ref.updateData(fields)
    }

    /// Updates tier for a userBook.
    func setTier(userBookId: UUID, tier: String?) async throws {
        let ref = db.collection(userBooks).document(userBookId.uuidString)
        try await ref.updateData([
            "tier": tier as Any,
            "updatedAt": Timestamp(date: Date()),
        ])
    }

    /// Deletes a userBook (e.g. remove from queue). Firestore listener will update userBooks.
    func deleteUserBook(userId: String, userBookId: UUID) async throws {
        let ref = db.collection(userBooks).document(userBookId.uuidString)
        try await ref.delete()
    }

    private func userBook(from data: [String: Any], docId: String) -> UserBook? {
        guard let userId = data["userId"] as? String,
              let bookId = data["bookId"] as? String,
              let statusRaw = data["status"] as? String,
              let status = ReadingStatus(rawValue: statusRaw),
              let createdAt = (data["createdAt"] as? Timestamp)?.dateValue(),
              let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue(),
              let id = UUID(uuidString: docId) else { return nil }
        let rating = Self.decodeRatingOutOfTen(from: data["rating"])
        let reviewText = data["reviewText"] as? String
        let dateStarted = (data["dateStarted"] as? Timestamp)?.dateValue()
        let dateFinished = (data["dateFinished"] as? Timestamp)?.dateValue()
        let tier = data["tier"] as? String
        let tierOrder = data["tierOrder"] as? Int
        let queueShelfRaw = data["queueShelf"] as? String
        let queueShelf = queueShelfRaw.flatMap { QueueShelf(rawValue: $0) }
        let queueOrder = data["queueOrder"] as? Int
        return UserBook(
            id: id,
            userId: userId,
            bookId: bookId,
            book: nil,
            status: status,
            rating: rating,
            reviewText: reviewText,
            dateStarted: dateStarted,
            dateFinished: dateFinished,
            createdAt: createdAt,
            updatedAt: updatedAt,
            recommendedTo: [],
            tier: tier,
            tierOrder: tierOrder,
            queueShelf: queueShelf,
            queueOrder: queueOrder
        )
    }

    /// Firestore may store `rating` as Double or legacy Int / Int64 (1–10).
    private static func decodeRatingOutOfTen(from value: Any?) -> Double? {
        switch value {
        case nil:
            return nil
        case let d as Double:
            return Theme.normalizeRatingOutOfTen(d)
        case let i as Int:
            return Theme.normalizeRatingOutOfTen(Double(i))
        case let i64 as Int64:
            return Theme.normalizeRatingOutOfTen(Double(i64))
        case let n as NSNumber:
            return Theme.normalizeRatingOutOfTen(Double(truncating: n))
        default:
            return nil
        }
    }
}
