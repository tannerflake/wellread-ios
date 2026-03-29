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
    /// Firebase Auth UIDs this user follows (`users/{id}/following` in Firestore). Used for push eligibility and profile.
    var following: [String]
    /// When true, the one-time “everyone follows everyone” mesh has been applied; avoids re-adding follows after intentional unfollows.
    var communityMeshApplied: Bool
    /// Firestore `hasSeenFollowCommunityModal`; one-time feed modal explaining default mutual follows (syncs across devices).
    var hasSeenFollowCommunityModal: Bool
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
        following: [],
        communityMeshApplied: true,
        hasSeenFollowCommunityModal: true,
        totalBooksRead: 12,
        totalPagesRead: 3840,
        readingGoal: 24
    )
}

typealias UserID = UUID
