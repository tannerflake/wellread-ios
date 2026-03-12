//
//  UserRepository.swift
//  WellRead
//
//  Firestore user documents: get, ensure (create if missing), used for "account" for Google/Apple sign-in.
//

import Foundation
import FirebaseFirestore

final class UserRepository {
    private let db = FirestoreDatabase.firestore
    private let users = "users"

    /// Returns the User document for this uid if it exists.
    func getUser(uid: String) async -> User? {
        let ref = db.collection(users).document(uid)
        do {
            let snapshot = try await ref.getDocument()
            guard snapshot.exists, let data = snapshot.data() else { return nil }
            return user(from: data, uid: uid)
        } catch {
            return nil
        }
    }

    /// Creates a user document in Firestore if one doesn't exist (so first-time Google/Apple sign-in gets an account).
    func ensureUserDocument(uid: String, displayName: String?, email: String?, photoURL: String?) async {
        let ref = db.collection(users).document(uid)
        do {
            let snapshot = try await ref.getDocument()
            guard !snapshot.exists else { return }
            let username = email?.components(separatedBy: "@").first ?? "user_\(String(uid.prefix(8)))"
            let name = displayName?.isEmpty == false ? displayName! : (email ?? "User")
            try await ref.setData([
                "username": username,
                "displayName": name,
                "bio": NSNull(),
                "profileImageURL": photoURL as Any,
                "joinedAt": Timestamp(date: Date()),
                "totalBooksRead": 0,
                "totalPagesRead": 0,
                "followers": [] as [String],
                "following": [] as [String],
                "readingGoal": NSNull(),
            ])
        } catch {
            // Log in real app; for now we continue so auth still works
        }
    }

    /// Update profile fields (only provided non-nil values are updated).
    func updateProfile(uid: String, username: String?, displayName: String?, bio: String?, readingGoal: Int?) async throws {
        let ref = db.collection(users).document(uid)
        var data: [String: Any] = [:]
        if let v = username { data["username"] = v }
        if let v = displayName { data["displayName"] = v }
        if let v = bio { data["bio"] = v }
        if let v = readingGoal { data["readingGoal"] = v }
        guard !data.isEmpty else { return }
        try await ref.updateData(data)
    }

    /// Update the user's profile image URL in Firestore.
    func updateProfileImageURL(uid: String, url: String) async throws {
        try await db.collection(users).document(uid).updateData([
            "profileImageURL": url,
        ])
    }

    /// Increment totalBooksRead by 1.
    func incrementTotalBooksRead(uid: String) async throws {
        try await db.collection(users).document(uid).updateData([
            "totalBooksRead": FieldValue.increment(Int64(1)),
        ])
    }

    /// Increment totalPagesRead by the given count.
    func incrementTotalPagesRead(uid: String, pages: Int) async throws {
        try await db.collection(users).document(uid).updateData([
            "totalPagesRead": FieldValue.increment(Int64(pages)),
        ])
    }

    private func user(from data: [String: Any], uid: String) -> User? {
        guard let username = data["username"] as? String,
              let displayName = data["displayName"] as? String,
              let joinedAt = (data["joinedAt"] as? Timestamp)?.dateValue() else { return nil }
        let totalBooksRead = (data["totalBooksRead"] as? Int) ?? 0
        let totalPagesRead = (data["totalPagesRead"] as? Int) ?? 0
        let readingGoal = data["readingGoal"] as? Int
        return User(
            id: UUID(),
            username: username,
            displayName: displayName,
            bio: data["bio"] as? String,
            profileImageURL: data["profileImageURL"] as? String,
            joinedAt: joinedAt,
            followers: [],
            following: [],
            totalBooksRead: totalBooksRead,
            totalPagesRead: totalPagesRead,
            readingGoal: readingGoal
        )
    }
}
