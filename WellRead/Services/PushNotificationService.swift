//
//  PushNotificationService.swift
//  WellRead
//
//  FCM registration, permission, Firestore token storage, and deep-link extraction from push payloads.
//

import Foundation
import UIKit
import UserNotifications
import FirebaseAuth
import FirebaseFirestore
import FirebaseMessaging

enum WellreadDeepLink {
    /// `wellread://post/{postUUID}` — opens Feed and the post’s comment thread.
    static func postId(from url: URL) -> String? {
        guard url.scheme?.lowercased() == "wellread" else { return nil }
        guard url.host?.lowercased() == "post" else { return nil }
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : path
    }

    /// Reads `postId` from FCM `data` (and common alternate keys).
    static func postId(fromNotificationUserInfo userInfo: [AnyHashable: Any]) -> String? {
        for key in ["postId", "post_id"] {
            if let s = userInfo[AnyHashable(key)] as? String, !s.isEmpty { return s }
        }
        return nil
    }

    /// `data.type` from FCM (e.g. `friend_review_posted`); used to tune tap behavior.
    static func pushNotificationType(from userInfo: [AnyHashable: Any]) -> String? {
        for key in ["type", "notification_type"] {
            if let s = userInfo[AnyHashable(key)] as? String, !s.isEmpty { return s }
        }
        return nil
    }
}

enum PushNotificationService {
    private static let userRepo = UserRepository()

    /// Registers with APNs without showing the permission dialog (for users who already granted alerts, or after cold start).
    static func registerForRemoteNotificationsOnly() {
        DispatchQueue.main.async {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    static func requestPermissionAndRegister() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
            guard granted else { return }
            DispatchQueue.main.async {
                UIApplication.shared.registerForRemoteNotifications()
                /// APNs/FCM can produce a token shortly after registration; delegate may have fired before auth was ready — sync once permission is granted.
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    syncFCMTokenToFirestoreIfSignedIn()
                }
            }
        }
    }

    /// Fetches the current FCM token and writes `users/{uid}/fcmTokens/{hash}`. Call after sign-in and when fixing “skipped (not signed in)” races.
    static func syncFCMTokenToFirestoreIfSignedIn() {
        guard Auth.auth().currentUser != nil else { return }
        Task {
            do {
                let token = try await Messaging.messaging().token()
                persistFCMTokenToFirestore(token)
            } catch {
                #if DEBUG
                print("syncFCMTokenToFirestoreIfSignedIn: \(error.localizedDescription)")
                #endif
            }
        }
    }

    /// If permission was denied, opens Settings; otherwise requests authorization (shows system prompt when still undetermined).
    static func requestPermissionOrOpenSettingsIfDenied() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                switch settings.authorizationStatus {
                case .denied:
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                case .notDetermined:
                    requestPermissionAndRegister()
                default:
                    requestPermissionAndRegister()
                }
            }
        }
    }

    /// `true` when we should show the recurring push nudge (no full alert permission yet).
    static func needsPushPermissionNudge(completion: @escaping (Bool) -> Void) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let needs: Bool
            switch settings.authorizationStatus {
            case .authorized:
                needs = false
            case .provisional, .ephemeral:
                needs = false
            case .denied, .notDetermined:
                needs = true
            @unknown default:
                needs = true
            }
            DispatchQueue.main.async {
                completion(needs)
            }
        }
    }

    static func persistFCMTokenToFirestore(_ token: String) {
        guard let uid = Auth.auth().currentUser?.uid else {
            PushRegistrationDiagnostics.recordFirestoreSkippedNotSignedIn()
            return
        }
        Task {
            do {
                try await userRepo.saveFCMToken(uid: uid, token: token)
                PushRegistrationDiagnostics.recordFirestoreWriteSuccess(at: Date())
            } catch {
                PushRegistrationDiagnostics.recordFirestoreWriteFailed(error)
            }
        }
    }

    static func handleRemoteNotificationTap(userInfo: [AnyHashable: Any]) {
        let type = WellreadDeepLink.pushNotificationType(from: userInfo)
        /// Friend-review pushes land on the feed scrolled to that review (no comment thread).
        if type == "friend_review_posted" {
            if let postId = WellreadDeepLink.postId(fromNotificationUserInfo: userInfo) {
                NotificationCenter.default.post(
                    name: .wellreadOpenFeedScrollToPost,
                    object: nil,
                    userInfo: ["postId": postId]
                )
            } else {
                NotificationCenter.default.post(name: .wellreadOpenFeed, object: nil)
            }
            return
        }
        guard let postId = WellreadDeepLink.postId(fromNotificationUserInfo: userInfo) else { return }
        NotificationCenter.default.post(
            name: .wellreadOpenFeedPost,
            object: nil,
            userInfo: ["postId": postId]
        )
    }
}

extension Notification.Name {
    /// Opens the Feed tab without scrolling to a post or opening comments.
    static let wellreadOpenFeed = Notification.Name("wellreadOpenFeed")
    static let wellreadOpenFeedPost = Notification.Name("wellreadOpenFeedPost")
    /// Opens the Feed tab and scrolls to the post (briefly highlighted) without opening its comment thread. `userInfo["postId"]` is the post UUID string.
    static let wellreadOpenFeedScrollToPost = Notification.Name("wellreadOpenFeedScrollToPost")
    /// After a user marks a book as read: switch to Profile tab → Read segment, scroll the tier list to Unranked, and pulse-glow the just-reviewed book until they tier it. `userInfo["bookId"]` is the `Book.id`.
    static let spineHighlightTierBook = Notification.Name("spineHighlightTierBook")
    /// After a user adds a book to their queue from the search flow: switch to Profile tab → Queue segment so they land on the queue and see it was added.
    static let spineOpenQueue = Notification.Name("spineOpenQueue")
}
