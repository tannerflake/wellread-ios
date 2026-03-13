//
//  Post.swift
//  WellRead
//

import Foundation

enum PostType: String, Codable {
    case finishedBook
    case review
    case recommendation
    case tierListUpdate
}

struct Post: Identifiable, Codable {
    var id: UUID
    var userId: String  // Firebase Auth uid
    var type: PostType
    var bookId: String?
    var book: Book?
    var caption: String?
    var createdAt: Date
    var likeCount: Int
    var commentCount: Int
    var user: User?
    /// Rating 1–100 when posted from "Mark as read" (shown in feed).
    var ratingPercent: Int?
    /// Date the user finished the book (shown in feed with minimal weight).
    var dateFinished: Date?
    
    static let demoFeed: [Post] = {
        let b = Book(id: "1", title: "Atomic Habits", author: "James Clear", coverURL: "https://books.google.com/books/content?id=wRqtDwAAQBAJ&printsec=frontcover&img=1", pageCount: 320, publishedDate: nil, description: nil, genres: [])
        return [
            Post(id: UUID(), userId: "demo-user-id", type: .finishedBook, bookId: b.id, book: b, caption: "Just finished. Highly recommend.", createdAt: Date(), likeCount: 4, commentCount: 1, user: .demo, ratingPercent: 85, dateFinished: Date())
        ]
    }()
}
