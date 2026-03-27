//
//  MainTabView.swift
//  WellRead
//
//  Bottom tab bar: Feed, Discover, Add (center), Profile (library + profile merged).
//

import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var authService: AuthService
    @State private var selectedTab: Tab = .profile
    @State private var showAddBook = false
    @State private var showCompleteProfileSheet = false
    /// After the user dismisses the sheet without finishing, don't nag until the next app launch.
    @State private var userDismissedIncompleteProfileThisSession = false
    @State private var showWelcomeGoodreadsModal = false
    @State private var showGoodreadsImportFromWelcome = false
    
    enum Tab: String, CaseIterable {
        case feed
        case discover
        case add
        case profile
    }
    
    var body: some View {
        Group {
            switch selectedTab {
            case .feed: FeedView()
            case .discover: DiscoverView()
            case .add: Color.clear
            case .profile: ProfileLibraryView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Reserve space for the tab bar in layout (avoids full-screen content drawing under it).
        .safeAreaInset(edge: .bottom, spacing: 0) {
            tabBar
        }
        .ignoresSafeArea(.keyboard)
        .sheet(isPresented: $showAddBook) { AddBookFlowView() }
        .sheet(isPresented: $showCompleteProfileSheet, onDismiss: {
            if authService.appUser?.needsProfileCompletion == true {
                userDismissedIncompleteProfileThisSession = true
            }
        }) {
            ProfileCompletionView(
                title: "Complete your profile",
                subtitle: "Add your first name, last name, handle, and your reading goal for this year so friends can find you.",
                onDismiss: {
                    showCompleteProfileSheet = false
                    scheduleWelcomeGoodreadsModalIfNeeded()
                }
            )
            .environmentObject(authService)
            .environmentObject(appState)
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showWelcomeGoodreadsModal, onDismiss: {
            if let uid = authService.firebaseUser?.uid {
                WelcomeSpinesGoodreadsPromptStorage.markShown(for: uid)
            }
        }) {
            WelcomeSpinesGoodreadsModal(
                onLetsGo: {
                    showWelcomeGoodreadsModal = false
                    selectedTab = .profile
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        showGoodreadsImportFromWelcome = true
                    }
                },
                onLater: {
                    showWelcomeGoodreadsModal = false
                }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showGoodreadsImportFromWelcome) {
            GoodreadsImportView(initialRows: nil)
                .environmentObject(appState)
        }
        .onAppear {
            appState.loadDiscoverSuggestionsIfNeeded()
            if appState.pendingGoodreadsImportRows != nil || appState.pendingGoodreadsImportError != nil || appState.pendingGoodreadsImportURL != nil {
                selectedTab = .profile
            }
            syncCompleteProfileSheet()
        }
        .onChange(of: authService.appUser) { _, _ in
            syncCompleteProfileSheet()
        }
        .onChange(of: authService.firebaseUser?.uid) { _, _ in
            // New login (e.g. reviewer email path): allow the sheet again after dismiss.
            userDismissedIncompleteProfileThisSession = false
            syncCompleteProfileSheet()
        }
        .onChange(of: appState.pendingGoodreadsImportRows) { _, rows in
            if rows != nil { selectedTab = .profile }
        }
        .onChange(of: appState.pendingGoodreadsImportError) { _, message in
            if message != nil { selectedTab = .profile }
        }
        .onChange(of: appState.pendingGoodreadsImportURL) { _, u in
            if u != nil { selectedTab = .profile }
        }
    }

    private func syncCompleteProfileSheet() {
        guard authService.appUser?.needsProfileCompletion == true else {
            showCompleteProfileSheet = false
            userDismissedIncompleteProfileThisSession = false
            return
        }
        if userDismissedIncompleteProfileThisSession {
            showCompleteProfileSheet = false
            return
        }
        showCompleteProfileSheet = true
    }

    /// After profile completion sheet dismisses successfully, show the Goodreads welcome modal once per account.
    private func scheduleWelcomeGoodreadsModalIfNeeded() {
        guard authService.appUser?.needsProfileCompletion == false,
              let uid = authService.firebaseUser?.uid,
              !WelcomeSpinesGoodreadsPromptStorage.hasShown(for: uid) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            showWelcomeGoodreadsModal = true
        }
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            tabButton(.feed, icon: "book.closed.fill", label: "Feed")
            tabButton(.discover, icon: "sparkles", label: "Discover")
            tabButton(.profile, icon: "books.vertical.fill", label: "Profile")
            addButton
        }
        .padding(.horizontal, 8)
        .padding(.top, 4)
        .padding(.bottom, 6)
        .background(Theme.background.opacity(0.95))
        .overlay(
            Rectangle()
                .fill(Theme.textTertiary.opacity(0.2))
                .frame(height: 1),
            alignment: .top
        )
    }
    
    private func tabButton(_ tab: Tab, icon: String, label: String) -> some View {
        Button {
            if tab == .add {
                showAddBook = true
            } else {
                selectedTab = tab
            }
        } label: {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))
                Text(label)
                    .font(Theme.caption())
            }
            .frame(maxWidth: .infinity)
            .foregroundStyle(selectedTab == tab ? Theme.accent : Theme.textSecondary)
        }
        .buttonStyle(.plain)
    }
    
    private var addButton: some View {
        Button {
            showAddBook = true
        } label: {
            VStack(spacing: 2) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 32))
                Text("Add")
                    .font(Theme.caption())
            }
            .frame(maxWidth: .infinity)
            .foregroundStyle(Theme.accent)
        }
        .buttonStyle(.plain)
    }
}
