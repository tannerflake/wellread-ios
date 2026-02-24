//
//  Comment.swift
//  WellRead
//

import Foundation

struct Comment: Identifiable, Codable {
    var id: UUID
    var postId: UUID
    var userId: UUID
    var text: String
    var createdAt: Date
}
