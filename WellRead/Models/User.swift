//
//  User.swift
//  WellRead
//

import Foundation

struct User: Identifiable, Codable, Equatable {
    var id: UUID
    var username: String
    var displayName: String
    /// Set during post–sign-in onboarding; optional for legacy accounts.
    var firstName: String?
    var lastName: String?
    /// When `false`, user must complete name + handle onboarding before the main app.
    var profileSetupCompleted: Bool
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
        firstName: "Tanner",
        lastName: nil,
        profileSetupCompleted: true,
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
