//
//  MainTabView.swift
//  WellRead
//
//  Bottom tab bar: Feed, Discover, Search (center), Profile (library + profile merged).
//

import SwiftUI

struct MainTabView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var authService: AuthService
    @State private var selectedTab: Tab = .profile
    @State private var showAddBook = false
    @State private var searchDetent: PresentationDetent = AddBookFlowView.smallDetent
    @State private var showCompleteProfileSheet = false
    @State private var showWelcomeGoodreadsModal = false
    @State private var showGoodreadsImportFromWelcome = false
    @State private var showPushNotificationPromptSheet = false
    @State private var showPushNudgeModal = false

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
            // Lock the tab bar to the bottom: don't let keyboard avoidance lift it
            // above the keyboard — it should sit still and be covered by the keyboard.
            tabBar
                .ignoresSafeArea(.keyboard, edges: .bottom)
        }
        // BookProfileView reads `mainTabBarOverlapExtraHeight` and adds it as bottom padding so its action
        // bar clears the custom tab bar. With the parent safeAreaInset reserving the tab bar, this gives
        // the action bar a clean breathing-room gap above the tab bar.
        .environment(\.mainTabBarOverlapExtraHeight, Theme.mainTabBarChromeHeight)
        .toastHost()
        .sheet(isPresented: $showAddBook, onDismiss: { searchDetent = AddBookFlowView.smallDetent }) {
            AddBookFlowView(detent: $searchDetent)
                .environment(\.mainTabBarOverlapExtraHeight, 0)
                .presentationDetents([AddBookFlowView.smallDetent, AddBookFlowView.expandedDetent], selection: $searchDetent)
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showCompleteProfileSheet, onDismiss: {
            schedulePostProfileOnboardingFlow()
        }) {
            ProfileCompletionView(
                title: "Complete your profile",
                subtitle: "Add your photo, name, handle, and reading goal—then choose what you love to read.",
                onDismiss: {
                    showCompleteProfileSheet = false
                }
            )
            .environmentObject(authService)
            .environmentObject(appState)
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .interactiveDismissDisabled(true)
        }
        .sheet(isPresented: $showPushNotificationPromptSheet) {
            PushNotificationPromptView(
                onEnable: { finishPushNotificationPrompt(userRequestedEnable: true) },
                onNotNow: { finishPushNotificationPrompt(userRequestedEnable: false) }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .interactiveDismissDisabled(true)
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
        .sheet(isPresented: $showPushNudgeModal) {
            PushNotificationNudgeModal(
                onEnable: {
                    PushNotificationService.requestPermissionOrOpenSettingsIfDenied()
                    showPushNudgeModal = false
                },
                onNoThanks: {
                    if let uid = authService.firebaseUser?.uid {
                        PushNotificationNudgeStorage.snoozeOneMonth(uid: uid)
                    }
                    showPushNudgeModal = false
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .interactiveDismissDisabled(true)
        }
        .onReceive(NotificationCenter.default.publisher(for: .wellreadOpenFeed)) { _ in
            selectedTab = .feed
            appState.deepLinkFeedPostId = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: .wellreadOpenFeedPost)) { note in
            if let id = note.userInfo?["postId"] as? String {
                selectedTab = .feed
                appState.deepLinkFeedPostId = id
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .wellreadOpenFeedScrollToPost)) { note in
            if let id = note.userInfo?["postId"] as? String {
                selectedTab = .feed
                appState.scrollToFeedPostId = id
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .spineHighlightTierBook)) { _ in
            selectedTab = .profile
        }
        .onReceive(NotificationCenter.default.publisher(for: .spineOpenQueue)) { _ in
            selectedTab = .profile
        }
        .onAppear {
            appState.loadDiscoverSuggestionsIfNeeded()
            PushNotificationService.registerForRemoteNotificationsOnly()
            if appState.pendingGoodreadsImportRows != nil || appState.pendingGoodreadsImportError != nil || appState.pendingGoodreadsImportURL != nil {
                selectedTab = .profile
            }
            syncCompleteProfileSheet()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                considerShowingPushNudgeModal()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    PushNotificationService.syncFCMTokenToFirestoreIfSignedIn()
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    considerShowingPushNudgeModal()
                }
            }
        }
        .onChange(of: authService.appUser) { _, _ in
            syncCompleteProfileSheet()
        }
        .onChange(of: authService.firebaseUser?.uid) { _, _ in
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
            return
        }
        showCompleteProfileSheet = true
    }

    /// After profile completion: optional push prompt (new accounts), then Goodreads welcome once per account.
    private func schedulePostProfileOnboardingFlow() {
        guard authService.appUser?.needsProfileCompletion == false,
              let user = authService.appUser,
              authService.firebaseUser?.uid != nil else {
            scheduleWelcomeGoodreadsModalIfNeeded()
            return
        }
        if !user.hasSeenPushNotificationPrompt {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                showPushNotificationPromptSheet = true
            }
            return
        }
        scheduleWelcomeGoodreadsModalIfNeeded()
    }

    private func finishPushNotificationPrompt(userRequestedEnable: Bool) {
        if userRequestedEnable {
            PushNotificationService.requestPermissionAndRegister()
        } else if let uid = authService.firebaseUser?.uid {
            PushNotificationNudgeStorage.snoozeOneMonth(uid: uid)
        }
        Task {
            try? await authService.markPushNotificationPromptSeen()
            await MainActor.run {
                showPushNotificationPromptSheet = false
                scheduleWelcomeGoodreadsModalIfNeeded()
            }
        }
    }

    /// Recurring prompt when push permission is missing and snooze window has passed.
    private func considerShowingPushNudgeModal() {
        guard let uid = authService.firebaseUser?.uid else { return }
        guard authService.appUser?.needsProfileCompletion == false else { return }
        guard authService.appUser?.hasSeenPushNotificationPrompt == true else { return }
        guard !showCompleteProfileSheet, !showPushNotificationPromptSheet, !showWelcomeGoodreadsModal,
              !showGoodreadsImportFromWelcome, !showAddBook, !showPushNudgeModal else { return }
        guard PushNotificationNudgeStorage.isEligibleForNudge(uid: uid) else { return }

        PushNotificationService.needsPushPermissionNudge { needs in
            guard needs else { return }
            guard !showCompleteProfileSheet, !showPushNotificationPromptSheet, !showWelcomeGoodreadsModal,
                  !showGoodreadsImportFromWelcome, !showAddBook, !showPushNudgeModal else { return }
            showPushNudgeModal = true
        }
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
            tabButton(.feed, icon: "book.closed.fill", label: "Social")
            tabButton(.discover, icon: "sparkles", label: "Discover")
            tabButton(.profile, icon: "books.vertical.fill", label: "Profile")
            searchButton
        }
        .padding(.horizontal, 8)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .background(Theme.background.opacity(0.95))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Theme.chromeTeal.opacity(0.35))
                .frame(height: Theme.chromeHairline)
        }
    }

    private func tabButton(_ tab: Tab, icon: String, label: String) -> some View {
        Button {
            if tab == .add {
                showAddBook = true
            } else {
                selectedTab = tab
            }
        } label: {
            VStack(spacing: 4) {
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

    private var searchButton: some View {
        Button {
            showAddBook = true
        } label: {
            VStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 20, weight: .medium))
                Text("Search")
                    .font(Theme.caption())
            }
            .frame(maxWidth: .infinity)
            .foregroundStyle(Theme.textSecondary)
        }
        .buttonStyle(.plain)
    }
}
