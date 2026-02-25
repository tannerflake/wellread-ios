//
//  RootView.swift
//  WellRead
//
//  Root: auth gate or main tab bar. Driven by AuthService.
//

import SwiftUI
import FirebaseAuth

struct RootView: View {
    @EnvironmentObject var authService: AuthService
    @EnvironmentObject var appState: AppState

    var body: some View {
        Group {
            if authService.isLoading {
                ZStack {
                    Theme.background.ignoresSafeArea()
                    ProgressView()
                        .tint(Theme.accent)
                }
            } else if authService.firebaseUser == nil {
                OnboardingFlowView()
            } else {
                MainTabView()
            }
        }
        .animation(.easeInOut(duration: 0.25), value: authService.isLoading)
        .animation(.easeInOut(duration: 0.25), value: authService.firebaseUser?.uid)
        .onChange(of: authService.firebaseUser?.uid) { _, newValue in
            if let uid = newValue, let fbUser = authService.firebaseUser {
                appState.currentUser = userFromFirebase(fbUser)
                appState.isAuthenticated = true
            } else {
                appState.signOut()
            }
        }
        .onAppear {
            if authService.firebaseUser != nil {
                appState.currentUser = userFromFirebase(authService.firebaseUser!)
                appState.isAuthenticated = true
            }
        }
    }

    private func userFromFirebase(_ fb: FirebaseAuth.User) -> User {
        let displayName = fb.displayName ?? fb.email ?? fb.uid
        let username = fb.email?.components(separatedBy: "@").first ?? String(fb.uid.prefix(8))
        return User(
            id: UUID(),
            username: username,
            displayName: displayName,
            bio: nil,
            profileImageURL: fb.photoURL?.absoluteString,
            joinedAt: Date(),
            followers: [],
            following: [],
            totalBooksRead: 0,
            totalPagesRead: 0,
            readingGoal: nil
        )
    }
}
