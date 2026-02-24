//
//  User.swift
//  WellRead
//

import Foundation

struct User: Identifiable, Codable, Equatable {
    var id: UUID
    var username: String
    var displayName: String
    var bio: String?
    var profileImageURL: String?
    var joinedAt: Date
    var followers: [UUID]
    var following: [UUID]
    var totalBooksRead: Int
    var totalPagesRead: Int
    var readingGoal: Int?
    
    static let demo = User(
        id: UUID(),
        username: "tanner",
        displayName: "Tanner",
        bio: "Building WellRead.",
        profileImageURL: nil,
        joinedAt: Date(),
        followers: [],
        following: [],
        totalBooksRead: 12,
        totalPagesRead: 3840,
        readingGoal: 24
    )
}

typealias UserID = UUID
