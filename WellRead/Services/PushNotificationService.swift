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

    /// Reads `commentId` from FCM `data` — set on comment-targeted pushes (liked,
    /// replied, mentioned, commented) so the tap can scroll the thread to the
    /// exact comment.
    static func commentId(fromNotificationUserInfo userInfo: [AnyHashable: Any]) -> String? {
        for key in ["commentId", "comment_id"] {
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

    /// Blend push tapped before the UI was mounted (cold start): stashed here and
    /// consumed by `MainTabView.onAppear`, since a NotificationCenter post at tap
    /// time would land before any listener exists.
    private static var pendingBlendId: String?

    static func consumePendingBlendTap() -> String? {
        defer { pendingBlendId = nil }
        return pendingBlendId
    }

    /// Cold-start stashes for the non-blend pushes (same problem as `pendingBlendId`:
    /// the tap fires before MainTabView mounts, so the NotificationCenter post is lost).
    /// Warm taps are handled by the observers, which also consume the stash.
    private static var pendingScrollToFeedPostId: String?
    private static var pendingOpenPostCommentsId: String?
    /// Set alongside `pendingOpenPostCommentsId` when the push targets one comment
    /// (liked, replied, mentioned, commented): the thread scrolls to and flashes it.
    private static var pendingOpenPostCommentsCommentId: String?
    private static var pendingProfileUserId: String?
    /// Book-recommendation push tapped on a cold start: the tap lands on the
    /// queue (Recommended shelf), no id needed — just "go there" once mounted.
    private static var pendingOpenQueue = false

    static func consumePendingScrollToFeedPostTap() -> String? {
        defer { pendingScrollToFeedPostId = nil }
        return pendingScrollToFeedPostId
    }

    static func consumePendingOpenPostCommentsTap() -> String? {
        defer { pendingOpenPostCommentsId = nil }
        return pendingOpenPostCommentsId
    }

    static func consumePendingOpenPostCommentsCommentTap() -> String? {
        defer { pendingOpenPostCommentsCommentId = nil }
        return pendingOpenPostCommentsCommentId
    }

    static func consumePendingProfileUserTap() -> String? {
        defer { pendingProfileUserId = nil }
        return pendingProfileUserId
    }

    static func consumePendingOpenQueueTap() -> Bool {
        defer { pendingOpenQueue = false }
        return pendingOpenQueue
    }

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

    /// The requester withdrew a Book Blend request: clear the matching invite
    /// alert from this device's Notification Center (arrives as a silent push
    /// so the withdrawal itself never makes a sound).
    static func removeDeliveredBlendRequestNotifications(blendId: String, completion: @escaping () -> Void) {
        let center = UNUserNotificationCenter.current()
        center.getDeliveredNotifications { delivered in
            let ids = delivered
                .filter { note in
                    let info = note.request.content.userInfo
                    return WellreadDeepLink.pushNotificationType(from: info) == "blend_request"
                        && (info[AnyHashable("blendId")] as? String) == blendId
                }
                .map(\.request.identifier)
            if !ids.isEmpty {
                center.removeDeliveredNotifications(withIdentifiers: ids)
            }
            DispatchQueue.main.async { completion() }
        }
    }

    /// When the user last tapped a push (any type). Launch nudges stand down for a
    /// while afterwards so they don't cover the screen the tap navigated to.
    private(set) static var lastDeepLinkTapAt: Date?

    static var recentlyHandledDeepLinkTap: Bool {
        guard let t = lastDeepLinkTapAt else { return false }
        return Date().timeIntervalSince(t) < 30
    }

    static func handleRemoteNotificationTap(userInfo: [AnyHashable: Any]) {
        lastDeepLinkTapAt = Date()
        let type = WellreadDeepLink.pushNotificationType(from: userInfo)
        /// Book Blend pushes (invite or ready) land on the blend landing screen,
        /// which routes by the doc's status — both types carry `blendId`.
        if type == "blend_request" || type == "blend_ready" {
            if let blendId = userInfo[AnyHashable("blendId")] as? String, !blendId.isEmpty {
                pendingBlendId = blendId
                NotificationCenter.default.post(
                    name: .spineOpenBookBlend,
                    object: nil,
                    userInfo: ["blendId": blendId]
                )
            }
            return
        }
        /// Friend-review, review-liked, and review-mention pushes land on the feed
        /// scrolled to that review (highlighted, no comment thread).
        if type == "friend_review_posted" || type == "review_liked" || type == "review_mentioned" {
            if let postId = WellreadDeepLink.postId(fromNotificationUserInfo: userInfo) {
                pendingScrollToFeedPostId = postId
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
        /// New-follower pushes land on the follower's profile (their tier list).
        /// Legacy payloads without `followerId` fall back to the feed.
        if type == "new_follower" {
            if let followerId = userInfo[AnyHashable("followerId")] as? String, !followerId.isEmpty {
                pendingProfileUserId = followerId
                NotificationCenter.default.post(
                    name: .spineOpenUserProfile,
                    object: nil,
                    userInfo: ["userId": followerId]
                )
            } else {
                NotificationCenter.default.post(name: .wellreadOpenFeed, object: nil)
            }
            return
        }
        /// Book-recommendation pushes land on the queue, whose Recommended shelf
        /// holds the pending recommendation.
        if type == "book_recommended" {
            pendingOpenQueue = true
            NotificationCenter.default.post(name: .spineOpenQueue, object: nil)
            return
        }
        /// Everything else (review_commented, comment_replied, thread_commented,
        /// comment_mentioned, comment_liked) opens the post's comment thread.
        /// Each carries `commentId` so the thread scrolls to the exact comment
        /// (legacy payloads without it just open the thread).
        guard let postId = WellreadDeepLink.postId(fromNotificationUserInfo: userInfo) else { return }
        let commentId = WellreadDeepLink.commentId(fromNotificationUserInfo: userInfo)
        pendingOpenPostCommentsId = postId
        pendingOpenPostCommentsCommentId = commentId
        var info: [AnyHashable: Any] = ["postId": postId]
        if let commentId { info["commentId"] = commentId }
        NotificationCenter.default.post(
            name: .wellreadOpenFeedPost,
            object: nil,
            userInfo: info
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
    /// Blend push tapped: present the Book Blend landing screen. `userInfo["blendId"]` is the pair doc id.
    static let spineOpenBookBlend = Notification.Name("spineOpenBookBlend")
    /// New-follower push tapped: present the follower's profile (tier list). `userInfo["userId"]` is their Firebase UID.
    static let spineOpenUserProfile = Notification.Name("spineOpenUserProfile")
    /// Feed tab tapped while already selected: FeedView scrolls to top if scrolled down, or refreshes if already at top.
    static let spineFeedTabTappedAgain = Notification.Name("spineFeedTabTappedAgain")
    /// Discover tab tapped while already selected: DiscoverView pops any pushed pages back to its root.
    static let spineDiscoverTabTappedAgain = Notification.Name("spineDiscoverTabTappedAgain")
    /// Search tab tapped while already selected: SearchView pops any pushed pages back to its root.
    static let spineSearchTabTappedAgain = Notification.Name("spineSearchTabTappedAgain")
    /// Profile tab tapped while already selected: ProfileLibraryView pops any pushed pages back to its root.
    static let spineProfileTabTappedAgain = Notification.Name("spineProfileTabTappedAgain")
}
