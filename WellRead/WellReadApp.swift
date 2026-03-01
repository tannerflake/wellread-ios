//
//  WellReadApp.swift
//  WellRead
//
//  Book tracking platform — modern, minimal, dark-first.
//

import SwiftUI
import FirebaseCore
import GoogleSignIn
import FirebaseFirestore

/// Use the same Firestore database everywhere. Set databaseID to your named database (e.g. "wellread") or nil for (default).
enum FirestoreDatabase {
    static let databaseID: String? = "wellread"
    static var firestore: Firestore {
        if let id = databaseID {
            return Firestore.firestore(database: id)
        }
        return Firestore.firestore()
    }
}

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        FirebaseApp.configure()
        let db = FirestoreDatabase.firestore
        db.settings.cacheSettings = PersistentCacheSettings(sizeBytes: 50 * 1024 * 1024 as NSNumber)
        return true
    }

    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        if GIDSignIn.sharedInstance.handle(url) {
            return true
        }
        return false
    }
}

@main
struct WellReadApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var authService = AuthService()
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(authService)
                .environmentObject(appState)
                .preferredColorScheme(.dark)
                .onOpenURL { url in
                    GIDSignIn.sharedInstance.handle(url)
                }
        }
    }
}
