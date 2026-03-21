//
//  RootView.swift
//  WellRead
//
//  Root: auth gate or main tab bar. Driven by AuthService (Firebase Auth + Firestore user).
//

import SwiftUI
import FirebaseAuth

struct RootView: View {
    @EnvironmentObject var authService: AuthService
    @EnvironmentObject var appState: AppState

    var body: some View {
        Group {
            if authService.isLoading {
                loadingView
            } else if authService.firebaseUser == nil {
                OnboardingFlowView()
            } else if authService.appUser == nil {
                loadingView
            } else {
                MainTabView()
            }
        }
        .animation(.easeInOut(duration: 0.25), value: authService.isLoading)
        .animation(.easeInOut(duration: 0.25), value: authService.firebaseUser?.uid)
        .animation(.easeInOut(duration: 0.25), value: authService.appUser?.id)
        .onAppear {
            if let data = GoodreadsShareHelper.consumePendingImport(), !data.isEmpty {
                let parsed = GoodreadsCSVParser.parse(data: data)
                if !parsed.isEmpty {
                    appState.pendingGoodreadsImportRows = parsed
                }
            }
            if let message = GoodreadsShareHelper.consumePendingImportError() {
                appState.pendingGoodreadsImportError = message
            }
        }
        .onChange(of: authService.appUser) { _, newUser in
            if let user = newUser {
                appState.currentUser = user
                appState.isAuthenticated = true
                if let uid = authService.firebaseUser?.uid {
                    appState.startFirestoreListeners(uid: uid)
                }
            } else if authService.firebaseUser == nil {
                appState.signOut()
            }
        }
        .onChange(of: authService.firebaseUser?.uid) { _, newValue in
            if newValue == nil {
                appState.signOut()
            }
        }
    }

    private var loadingView: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            ProgressView()
                .tint(Theme.accent)
        }
    }
}
