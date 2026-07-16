//
//  WellReadApp.swift
//  WellRead
//
//  Book tracking platform — modern, minimal, paper-light.
//

import SwiftUI
import FirebaseCore
import GoogleSignIn
import FirebaseFirestore
import FirebaseMessaging
import UserNotifications

/// Use the same Firestore database everywhere.
/// - `Info.plist` key `FirestoreDatabaseID`: **empty** or omit → `(default)` database (Firebase Console “default” rules apply).
/// - Non-empty (e.g. `wellread`) → named database; you **must** publish `firestore.rules` to that exact database in Console.
enum FirestoreDatabase {
    static let databaseID: String? = {
        #if DEBUG
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "FirestoreDatabaseID") as? String else {
            print("FirestoreDatabaseID raw value: nil (key missing)")
            return nil
        }
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        print("FirestoreDatabaseID raw value: [\(raw)]")
        print("FirestoreDatabaseID trimmed value: [\(t)]")
        return t.isEmpty ? nil : t
        #else
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "FirestoreDatabaseID") as? String else {
            return nil
        }
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
        #endif
    }()

    static var firestore: Firestore {
        if let id = databaseID {
            #if DEBUG
            print("Firestore: using named database [\(id)]")
            #endif
            return Firestore.firestore(database: id)
        }
        #if DEBUG
        print("Firestore: using (default) database")
        #endif
        return Firestore.firestore()
    }
}

class AppDelegate: NSObject, UIApplicationDelegate, MessagingDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        FirebaseApp.configure()
        let db = FirestoreDatabase.firestore
        db.settings.cacheSettings = PersistentCacheSettings(sizeBytes: 50 * 1024 * 1024 as NSNumber)
        Messaging.messaging().delegate = self
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
        PushRegistrationDiagnostics.setAPNsDeviceToken(deviceToken)
        Task { @MainActor in
            PushRegistrationDiagnostics.shared.apnsRegistrationError = nil
        }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        PushRegistrationDiagnostics.setAPNsRegistrationFailed(error)
    }

    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let token = fcmToken else { return }
        PushRegistrationDiagnostics.setFCMToken(token)
        PushNotificationService.persistFCMTokenToFirestore(token)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        PushNotificationService.handleRemoteNotificationTap(userInfo: userInfo)
        completionHandler()
    }

    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        if url.scheme == "wellread", url.host == "goodreads-import" {
            NotificationCenter.default.post(name: .openGoodreadsImport, object: nil)
            return true
        }
        if let postId = WellreadDeepLink.postId(from: url) {
            NotificationCenter.default.post(name: .wellreadOpenFeedPost, object: nil, userInfo: ["postId": postId])
            return true
        }
        if GIDSignIn.sharedInstance.handle(url) {
            return true
        }
        return false
    }
}

extension Notification.Name {
    static let openGoodreadsImport = Notification.Name("openGoodreadsImport")
}

@main
struct WellReadApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var authService = AuthService()
    @StateObject private var appState = AppState()
    @StateObject private var queueDragCoordinator = QueueBookDragCoordinator()
    @AppStorage(AppearancePreference.storageKey) private var appearanceRaw = AppearancePreference.defaultValue.rawValue

    private var appearance: AppearancePreference {
        AppearancePreference(rawValue: appearanceRaw) ?? .defaultValue
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(authService)
                .environmentObject(appState)
                .environmentObject(queueDragCoordinator)
                // Theme palette is fully dynamic (light paper / dark CRT); this
                // drives system materials, nav bars, keyboards, and sheets too.
                // `nil` (System) follows the device setting.
                .preferredColorScheme(appearance.colorScheme)
                .onOpenURL { url in
                    if url.scheme == "wellread", url.host == "goodreads-import" {
                        handleGoodreadsImportFromShare()
                    } else if let postId = WellreadDeepLink.postId(from: url) {
                        NotificationCenter.default.post(name: .wellreadOpenFeedPost, object: nil, userInfo: ["postId": postId])
                    } else if url.isFileURL {
                        handleFileURLFromShare(url)
                    } else {
                        GIDSignIn.sharedInstance.handle(url)
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .openGoodreadsImport)) { _ in
                    handleGoodreadsImportFromShare()
                }
                .onChange(of: scenePhase) { _, newValue in
                    // Share extensions cannot open the containing app; when user manually switches to Spines after sharing, we process the pending URL here.
                    if newValue == .active {
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 300_000_000) // 0.3s so UI is ready
                            handleGoodreadsImportFromShare()
                        }
                        WidgetDataService.shared.scheduleRefresh(appState: appState, delay: 3.0)
                    }
                }
        }
    }

    private func handleGoodreadsImportFromShare() {
        if let data = GoodreadsShareHelper.consumePendingImport(), !data.isEmpty {
            let parsed = GoodreadsCSVParser.parse(data: data)
            if !parsed.isEmpty {
                appState.pendingGoodreadsImportRows = parsed
            }
        }
        if let message = GoodreadsShareHelper.consumePendingImportError() {
            appState.pendingGoodreadsImportError = message
        }
        if let sharedURL = GoodreadsShareHelper.consumePendingImportURL() {
            appState.pendingGoodreadsImportURL = sharedURL
            Task { await appState.fetchGoodreadsImportFromURL(sharedURL) }
        }
    }

    /// When the app is opened with a file URL (e.g. user tapped Spines in share sheet and system opened app with the file).
    private func handleFileURLFromShare(_ url: URL) {
        guard url.isFileURL else { return }
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return }
        let head = String(data: data.prefix(1024), encoding: .utf8) ?? ""
        guard head.contains("Book Id") || head.contains("Title,") else { return }
        let parsed = GoodreadsCSVParser.parse(data: data)
        if !parsed.isEmpty {
            appState.pendingGoodreadsImportRows = parsed
        }
    }
}
