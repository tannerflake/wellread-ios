//
//  UserRepository.swift
//  WellRead
//
//  Firestore user documents: get, ensure (create if missing), used for "account" for Google/Apple sign-in.
//

import Foundation
import FirebaseFirestore

/// Accounts hidden from the Feed “Your friends” strip (Apple review / internal test users).
private enum OtherReadersExclusion {
    /// `displayName` match (trimmed, case-insensitive), e.g. default Apple review accounts.
    static let displayNamesLowercased: Set<String> = ["john apple"]
    /// Firestore `email` field (synced from Firebase Auth on sign-in).
    static let emailsLowercased: Set<String> = ["review@spynesapp.com"]

    static func shouldExclude(firestoreData: [String: Any], user: User) -> Bool {
        let dn = user.displayName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if displayNamesLowercased.contains(dn) { return true }
        if let em = (firestoreData["email"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           emailsLowercased.contains(em) {
            return true
        }
        return false
    }
}

/// Outcome of a handle availability check (distinguishes "taken" from Firestore permission/network errors).
enum HandleAvailabilityCheck: Sendable {
    case available
    case taken
    /// Rules not deployed, wrong DB, offline, etc. — do not show as "taken".
    case failed(underlying: Error)
}

final class UserRepository {
    private let db = FirestoreDatabase.firestore
    private let users = "users"
    /// Doc ID = lowercase handle; fields: `uid` (Firebase Auth uid). Enables availability checks without querying `users`.
    private let handleClaims = "handleClaims"

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

    /// All user profiles for the “Your friends” strip (Firebase uid + `User`). Excludes `excludingUid` if set. Sorted by display name.
    func fetchAllReaderProfiles(excludingUid: String?, limit: Int = 300) async -> [(uid: String, user: User)] {
        do {
            let snapshot = try await db.collection(users).limit(to: limit).getDocuments()
            var rows: [(uid: String, user: User)] = []
            for doc in snapshot.documents {
                if let ex = excludingUid, doc.documentID == ex { continue }
                let data = doc.data()
                guard let u = user(from: data, uid: doc.documentID) else { continue }
                if OtherReadersExclusion.shouldExclude(firestoreData: data, user: u) { continue }
                rows.append((doc.documentID, u))
            }
            rows.sort { $0.user.displayName.localizedCaseInsensitiveCompare($1.user.displayName) == .orderedAscending }
            return rows
        } catch {
            return []
        }
    }

    /// Creates a user document in Firestore if one doesn't exist (so first-time Google/Apple sign-in gets an account).
    func ensureUserDocument(uid: String, displayName: String?, email: String?, photoURL: String?) async {
        let ref = db.collection(users).document(uid)
        do {
            let snapshot = try await ref.getDocument()
            if snapshot.exists {
                await migrateHandleClaimIfNeeded(uid: uid, data: snapshot.data())
                if let e = email?.trimmingCharacters(in: .whitespacesAndNewlines), !e.isEmpty {
                    let current = snapshot.data()?["email"] as? String
                    if current != e {
                        try? await ref.updateData(["email": e])
                    }
                }
                return
            }
            let username = email?.components(separatedBy: "@").first ?? "user_\(String(uid.prefix(8)))"
            let name = displayName?.isEmpty == false ? displayName! : (email ?? "User")
            var newUser: [String: Any] = [
                "username": username,
                "displayName": name,
                "firstName": NSNull(),
                "lastName": NSNull(),
                "profileSetupCompleted": false,
                "bio": NSNull(),
                "profileImageURL": photoURL as Any,
                "joinedAt": Timestamp(date: Date()),
                "totalBooksRead": 0,
                "totalPagesRead": 0,
                "followers": [] as [String],
                "following": [] as [String],
                "readingGoal": NSNull(),
            ]
            if let e = email?.trimmingCharacters(in: .whitespacesAndNewlines), !e.isEmpty {
                newUser["email"] = e
            }
            try await ref.setData(newUser)
            try await setHandleClaim(handle: username, uid: uid)
        } catch {
            // Log in real app; for now we continue so auth still works
        }
    }

    /// Uses `handleClaims/{handle}` single-doc read (`.server` avoids cache listener quirks in logs).
    func checkUsernameAvailability(_ rawHandle: String, excludingUid: String) async -> HandleAvailabilityCheck {
        let handle = rawHandle.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !handle.isEmpty else { return .taken }
        let ref = db.collection(handleClaims).document(handle)
        #if DEBUG
        print("HANDLE CHECK: path=\(handleClaims)/\(handle) excludingUid=\(excludingUid) source=.server")
        #endif
        do {
            let snap = try await ref.getDocument(source: .server)
            #if DEBUG
            let ownerStr = snap.data()?["uid"] as? String
            print("HANDLE CHECK SUCCESS: exists=\(snap.exists) ownerUid=\(ownerStr ?? "nil")")
            #endif
            if !snap.exists { return .available }
            if let owner = snap.data()?["uid"] as? String, owner == excludingUid {
                return .available
            }
            return .taken
        } catch {
            #if DEBUG
            print("HANDLE CHECK ERROR:", error.localizedDescription)
            print("HANDLE CHECK FULL ERROR:", error)
            #endif
            return .failed(underlying: error)
        }
    }

    /// Backward-compatible wrapper (treats failures as unavailable — prefer `checkUsernameAvailability`).
    func isUsernameAvailable(_ rawHandle: String, excludingUid: String) async -> Bool {
        switch await checkUsernameAvailability(rawHandle, excludingUid: excludingUid) {
        case .available: return true
        case .taken, .failed: return false
        }
    }

    /// First-time profile after SSO (or edit profile): name, handle, optional yearly book goal, marks onboarding complete.
    func completeProfileSetup(uid: String, firstName: String, lastName: String, handle: String, readingGoal: Int?) async throws {
        let trimmedFirst = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLast = lastName.trimmingCharacters(in: .whitespacesAndNewlines)
        let h = handle.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch await checkUsernameAvailability(h, excludingUid: uid) {
        case .available:
            break
        case .taken:
            throw NSError(domain: "UserRepository", code: 409, userInfo: [NSLocalizedDescriptionKey: "That handle is already taken."])
        case .failed(let err):
            throw NSError(
                domain: "UserRepository",
                code: 503,
                userInfo: [
                    NSLocalizedDescriptionKey: "Could not verify your handle (Firestore). Deploy rules for the \"wellread\" database, including handleClaims. Error: \(err.localizedDescription)",
                ]
            )
        }
        let display = [trimmedFirst, trimmedLast].filter { !$0.isEmpty }.joined(separator: " ")
        let userRef = db.collection(users).document(uid)
        let userSnap = try await userRef.getDocument()
        guard userSnap.exists else {
            throw NSError(domain: "UserRepository", code: 404, userInfo: [NSLocalizedDescriptionKey: "Account not found. Try signing in again."])
        }
        let oldHandle = (userSnap.data()?["username"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        var profileFields: [String: Any] = [
            "firstName": trimmedFirst,
            "lastName": trimmedLast,
            "username": h,
            "displayName": display.isEmpty ? h : display,
            "profileSetupCompleted": true,
        ]
        if let g = readingGoal {
            profileFields["readingGoal"] = g
        } else {
            profileFields["readingGoal"] = NSNull()
        }

        let batch = db.batch()
        batch.updateData(profileFields, forDocument: userRef)

        let newClaimRef = db.collection(handleClaims).document(h)
        batch.setData(["uid": uid], forDocument: newClaimRef, merge: true)

        if let old = oldHandle, old != h {
            let oldClaimRef = db.collection(handleClaims).document(old)
            let oldSnap = try await oldClaimRef.getDocument()
            if oldSnap.exists, oldSnap.data()?["uid"] as? String == uid {
                batch.deleteDocument(oldClaimRef)
            }
        }

        try await batch.commit()
    }

    private func setHandleClaim(handle: String, uid: String) async throws {
        let h = handle.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !h.isEmpty else { return }
        try await db.collection(handleClaims).document(h).setData(["uid": uid], merge: true)
    }

    /// Backfill `handleClaims` for accounts created before this collection existed.
    private func migrateHandleClaimIfNeeded(uid: String, data: [String: Any]?) async {
        guard let data, let username = data["username"] as? String else { return }
        let h = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !h.isEmpty else { return }
        let ref = db.collection(handleClaims).document(h)
        do {
            let snap = try await ref.getDocument()
            if !snap.exists {
                try await ref.setData(["uid": uid], merge: true)
                return
            }
            if let owner = snap.data()?["uid"] as? String, owner == uid { return }
            // Another user already owns this handle in claims; leave as-is.
        } catch {
            #if DEBUG
            print("UserRepository.migrateHandleClaimIfNeeded error: \(error)")
            #endif
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
        let firstName = data["firstName"] as? String
        let lastName = data["lastName"] as? String
        // Missing field used to default to true, which hid the profile sheet for legacy/incomplete accounts.
        let profileSetupCompleted: Bool
        if let explicit = data["profileSetupCompleted"] as? Bool {
            profileSetupCompleted = explicit
        } else {
            let f = firstName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let l = lastName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            profileSetupCompleted = !f.isEmpty && !l.isEmpty
        }
        return User(
            id: UUID(),
            username: username,
            displayName: displayName,
            firstName: firstName,
            lastName: lastName,
            profileSetupCompleted: profileSetupCompleted,
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
