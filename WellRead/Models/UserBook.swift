//
//  UserBook.swift
//  WellRead
//
//  Relationship between User and Book: status, rating, dates, tier.
//

import Foundation

enum ReadingStatus: String, Codable, CaseIterable {
    case wantToRead = "Want to Read"
    case currentlyReading = "Currently Reading"
    case read = "Read"
}

struct UserBook: Identifiable, Codable, Equatable {
    var id: UUID
    var userId: UUID
    var bookId: String
    var book: Book?
    var status: ReadingStatus
    var rating: Int?  // 1–10
    var reviewText: String?
    var dateStarted: Date?
    var dateFinished: Date?
    var createdAt: Date
    var updatedAt: Date
    var recommendedTo: [UUID]
    var tier: String?  // S, A, B, C, D for tier list
    
    static let demoList: [UserBook] = {
        let b1 = Book(id: "1", title: "Atomic Habits", author: "James Clear", coverURL: "https://books.google.com/books/content?id=wRqtDwAAQBAJ&printsec=frontcover&img=1", pageCount: 320, publishedDate: nil, description: nil, genres: ["Self-Help"])
        let b2 = Book(id: "2", title: "Deep Work", author: "Cal Newport", coverURL: "https://books.google.com/books/content?id=6h76CwAAQBAJ&printsec=frontcover&img=1", pageCount: 296, publishedDate: nil, description: nil, genres: ["Productivity"])
        let b3 = Book(id: "3", title: "The Midnight Library", author: "Matt Haig", coverURL: "https://books.google.com/books/content?id=zLk9DwAAQBAJ&printsec=frontcover&img=1", pageCount: 304, publishedDate: nil, description: nil, genres: ["Fiction"])
        let now = Date()
        let userId = User.demo.id
        return [
            UserBook(id: UUID(), userId: userId, bookId: b1.id, book: b1, status: .read, rating: 9, reviewText: "Life-changing.", dateStarted: now.addingTimeInterval(-86400*30), dateFinished: now.addingTimeInterval(-86400*7), createdAt: now, updatedAt: now, recommendedTo: [], tier: "S"),
            UserBook(id: UUID(), userId: userId, bookId: b2.id, book: b2, status: .read, rating: 8, reviewText: "Essential for focus.", dateStarted: now.addingTimeInterval(-86400*60), dateFinished: now.addingTimeInterval(-86400*35), createdAt: now, updatedAt: now, recommendedTo: [], tier: "A"),
            UserBook(id: UUID(), userId: userId, bookId: b3.id, book: b3, status: .currentlyReading, rating: nil, reviewText: nil, dateStarted: now.addingTimeInterval(-86400*3), dateFinished: nil, createdAt: now, updatedAt: now, recommendedTo: [], tier: nil)
        ]
    }()
}
