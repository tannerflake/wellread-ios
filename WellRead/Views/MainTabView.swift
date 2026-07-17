//
//  MainTabView.swift
//  WellRead
//
//  Floating liquid-glass tab bar: Feed, Discover, Profile, Search — a glass lens
//  slides over the selected tab (Blackbird-style).
//

import SwiftUI
import Combine

struct MainTabView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var authService: AuthService
    @State private var selectedTab: Tab = .profile
    @State private var showAddBook = false
    @State private var showCompleteProfileSheet = false
    @State private var showWelcomeGoodreadsModal = false
    @State private var showGoodreadsImportFromWelcome = false
    @State private var showPushNotificationPromptSheet = false
    @State private var showPushNudgeModal = false
    @State private var keyboardVisible = false
    @Namespace private var tabLensNamespace

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
            // The inset participates in keyboard avoidance no matter what the bar
            // itself ignores, so the bar would ride up above the keyboard — hide it
            // while the keyboard is up instead.
            if !keyboardVisible {
                tabBar
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            withAnimation(.easeOut(duration: 0.2)) { keyboardVisible = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            withAnimation(.easeOut(duration: 0.2)) { keyboardVisible = false }
        }
        // BookProfileView reads `mainTabBarOverlapExtraHeight` and adds it as bottom padding so its action
        // bar clears the custom tab bar. With the parent safeAreaInset reserving the tab bar, this gives
        // the action bar a clean breathing-room gap above the tab bar.
        .environment(\.mainTabBarOverlapExtraHeight, Theme.mainTabBarChromeHeight)
        .toastHost()
        // Custom overlay drawer (not a .sheet): sheet detents re-resolve when the
        // keyboard appears and jump to full height; this stays at its height, period.
        .overlay {
            ZStack(alignment: .bottom) {
                if showAddBook {
                    Color.black.opacity(0.25)
                        .ignoresSafeArea()
                        .onTapGesture {
                            // Drop the keyboard with the drawer, not after it.
                            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                            showAddBook = false
                        }
                        .transition(.opacity)
                    AddBookFlowView(onDismiss: { showAddBook = false })
                        .environment(\.mainTabBarOverlapExtraHeight, 0)
                        .transition(.move(edge: .bottom))
                }
            }
            .animation(.spring(response: 0.38, dampingFraction: 0.86), value: showAddBook)
            // `.all` = container + keyboard: the drawer must reach the physical
            // bottom edge (past the home-indicator inset, where the tab bar shows
            // through) and stay pinned when the keyboard rises.
            .ignoresSafeArea(.all, edges: .bottom)
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
        // Blend pushes (invite / ready) present the Book Blend landing full-screen.
        .bookBlendPushPresenter()
        .onAppear {
            #if DEBUG
            // `-uiPreviewTab feed|discover|profile|search` (with `-uiPreview`) starts on a
            // given tab — or with the search drawer open — for simulator UI verification.
            if let raw = UserDefaults.standard.string(forKey: "uiPreviewTab") {
                if raw == "search" {
                    showAddBook = true
                } else if let t = Tab(rawValue: raw) {
                    selectedTab = t
                }
            }
            #endif
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

    // MARK: - Floating tab bar with sliding lens

    /// The lens slides between tabs via matchedGeometryEffect and sits BEHIND the
    /// icon/label (in `.background`), so the selected item stays crisp. The bar is a
    /// material capsule — never `glassEffect` — so the lens is the only glass element
    /// on iOS 26+ (glass sampling glass renders as white mush).
    private var tabBar: some View {
        HStack(spacing: 0) {
            tabButton(.feed, icon: "person.2.fill", label: "Social")
            tabButton(.discover, icon: "sparkles", label: "Discover")
            tabButton(.profile, icon: "books.vertical.fill", label: "Profile")
            searchButton
        }
        .padding(5)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(Capsule().fill(Theme.surfaceElevated.opacity(0.6)))
                .overlay(Capsule().strokeBorder(Theme.chrome.opacity(0.22), lineWidth: 1))
                .shadow(color: Theme.shadowInk.opacity(0.14), radius: 16, y: 6)
        }
        .padding(.horizontal, 24)
        .padding(.top, 2)
        // Negative bottom padding sinks the bar into the home-indicator safe
        // area (Blackbird-style) — it sits low and hands the freed height back
        // to the content above.
        .padding(.bottom, -15)
        .sensoryFeedback(.selection, trigger: selectedTab)
    }

    private func tabButton(_ tab: Tab, icon: String, label: String) -> some View {
        Button {
            if tab == .add {
                showAddBook = true
            } else if selectedTab != tab {
                withAnimation(.snappy(duration: 0.3, extraBounce: 0.12)) {
                    selectedTab = tab
                }
            }
        } label: {
            tabItemLabel(icon: icon, label: label, isSelected: selectedTab == tab)
                .background {
                    if selectedTab == tab {
                        tabLens
                            .matchedGeometryEffect(id: "tabLens", in: tabLensNamespace)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    /// Glass capsule on iOS 26+ (single glass element over a non-glass bar);
    /// elevated paper pill as the pre-26 fallback.
    @ViewBuilder
    private var tabLens: some View {
        if #available(iOS 26.0, *) {
            Capsule()
                .fill(.clear)
                .glassEffect(.regular.interactive(), in: .capsule)
        } else {
            Capsule()
                .fill(Theme.surfaceElevated)
                .overlay(Capsule().strokeBorder(Theme.chrome.opacity(0.35), lineWidth: 1))
                .shadow(color: Theme.shadowInk.opacity(0.12), radius: 4, y: 1)
        }
    }

    private var searchButton: some View {
        Button {
            showAddBook = true
        } label: {
            tabItemLabel(icon: "magnifyingglass", label: "Search", isSelected: false)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func tabItemLabel(icon: String, label: String, isSelected: Bool) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .medium))
                .symbolEffect(.bounce.down.byLayer, value: isSelected)
            Text(label)
                .font(.system(size: 9, weight: isSelected ? .semibold : .regular))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 7)
        .foregroundStyle(isSelected ? Theme.accent : Theme.textSecondary)
    }
}
