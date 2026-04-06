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
