//
//  Comment.swift
//  WellRead
//

import Foundation

struct Comment: Identifiable, Codable {
    var id: UUID
    var postId: String   // Firestore post document id (UUID string)
    var userId: String   // Firebase Auth uid
    var text: String
    var createdAt: Date
}
