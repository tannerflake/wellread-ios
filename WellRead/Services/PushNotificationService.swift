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
}

enum PushNotificationService {
    private static let userRepo = UserRepository()

    static func requestPermissionAndRegister() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
            guard granted else { return }
            DispatchQueue.main.async {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
    }

    static func persistFCMTokenToFirestore(_ token: String) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        Task {
            try? await userRepo.saveFCMToken(uid: uid, token: token)
        }
    }

    static func handleRemoteNotificationTap(userInfo: [AnyHashable: Any]) {
        guard let postId = WellreadDeepLink.postId(fromNotificationUserInfo: userInfo) else { return }
        NotificationCenter.default.post(
            name: .wellreadOpenFeedPost,
            object: nil,
            userInfo: ["postId": postId]
        )
    }
}

extension Notification.Name {
    static let wellreadOpenFeedPost = Notification.Name("wellreadOpenFeedPost")
}
