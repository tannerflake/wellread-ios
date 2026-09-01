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
    @State private var showCompleteProfileSheet = false
    @State private var showWelcomeGoodreadsModal = false
    @State private var showGoodreadsImportFromWelcome = false
    @State private var showPushNotificationPromptSheet = false
    @State private var showPushNudgeModal = false
    @State private var showProfilePhotoNudgeModal = false
    @State private var showPhoneNumberNudgeModal = false
    @State private var showCurrentlyReadingPrompt = false
    @State private var keyboardVisible = false
    /// New-follower push tapped: the follower's profile presented full-height over any tab.
    @State private var deepLinkProfile: DeepLinkUserProfile?
    /// Pending Book Blend invite surfaced as a launch modal (push-independent).
    @State private var incomingBlendInvite: BookBlend?
    /// True once a modal button decided the invite's fate — a plain swipe-down
    /// dismissal (no decision) snoozes it two days like "Remind me in a bit".
    @State private var blendInviteDecided = false
    /// Kept through dismissal so onDismiss can snooze the undecided invite
    /// (`incomingBlendInvite` is already nil by then).
    @State private var lastPresentedBlendInvite: BookBlend?
    @Namespace private var tabLensNamespace

    private struct DeepLinkUserProfile: Identifiable {
        let id: String
    }

    enum Tab: String, CaseIterable {
        case feed
        case discover
        case search
        case profile

        /// Posted when this tab's bar item is tapped while already selected; each
        /// tab's root view listens and pops any pushed pages back to its root.
        var tappedAgainNotification: Notification.Name {
            switch self {
            case .feed: return .spineFeedTabTappedAgain
            case .discover: return .spineDiscoverTabTappedAgain
            case .search: return .spineSearchTabTappedAgain
            case .profile: return .spineProfileTabTappedAgain
            }
        }
    }

    /// Tab switch + tab bar (split out of `body`: the full modifier chain became
    /// too much for the type-checker in one expression).
    private var tabContent: some View {
        Group {
            switch selectedTab {
            case .feed: FeedView()
            case .discover: DiscoverView()
            case .search: SearchView()
            case .profile: ProfileLibraryView()
            }
        }
        // The tab switch runs inside a `withAnimation`, which the incoming page's
        // layout would otherwise ride in on — subviews sliding up from the origin
        // as they take their positions. The lens (outside this scope) still slides;
        // the page itself just appears, fully formed.
        .animation(nil, value: selectedTab)
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
            setKeyboardVisible(true)
            // Keyboard notifications lie on the way out of a full-screen cover:
            // UIKit briefly restores the presenter's first responder, which posts
            // a `willShow` whose matching `willHide` never arrives. Left alone the
            // bar stays gone for the rest of the session (only a relaunch brings
            // it back), so every show is re-checked against the real responder
            // chain a beat later.
            scheduleKeyboardReconcile()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { note in
            // A keyboard that slides off-screen without a `willHide` (interactive
            // dismissal, responder torn down mid-transition) still reports its end
            // frame here.
            guard let end = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
            if end.isEmpty || end.minY >= UIScreen.main.bounds.height {
                setKeyboardVisible(false)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            setKeyboardVisible(false)
        }
        // Second backstop: whatever the "will" notifications claimed, once the
        // keyboard is actually down the bar comes back.
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidHideNotification)) { _ in
            setKeyboardVisible(false)
        }
        // BookProfileView reads `mainTabBarOverlapExtraHeight` and adds it as bottom padding so its action
        // bar clears the custom tab bar. With the parent safeAreaInset reserving the tab bar, this gives
        // the action bar a clean breathing-room gap above the tab bar.
        .environment(\.mainTabBarOverlapExtraHeight, Theme.mainTabBarChromeHeight)
        .toastHost()
    }

    /// Onboarding/nudge sheets attached to the tab content.
    private var tabContentWithSheets: some View {
        tabContent
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
        .sheet(isPresented: $showProfilePhotoNudgeModal, onDismiss: {
            // “Not now” and swipe-down both count toward the 4-dismissal cap; a
            // successful upload sets the photo before closing, so it doesn’t.
            if let uid = authService.firebaseUser?.uid,
               (authService.appUser?.profileImageURL ?? "").isEmpty {
                ProfilePhotoNudgeStorage.recordDismissal(uid: uid)
            }
        }) {
            ProfilePhotoNudgeModal(
                onPhotoAdded: { showProfilePhotoNudgeModal = false },
                onNotNow: { showProfilePhotoNudgeModal = false }
            )
            .environmentObject(authService)
            .environmentObject(appState)
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showPhoneNumberNudgeModal, onDismiss: {
            // "Later" and swipe-down both count toward the 4-dismissal cap; a
            // successful save sets the number before closing, so it doesn't.
            if let uid = authService.firebaseUser?.uid,
               (authService.appUser?.phoneNumber ?? "").isEmpty {
                PhoneNumberNudgeStorage.recordDismissal(uid: uid)
            }
        }) {
            PhoneNumberNudgeModal(
                onSaved: { showPhoneNumberNudgeModal = false },
                onNotNow: { showPhoneNumberNudgeModal = false }
            )
            .environmentObject(authService)
            .environmentObject(appState)
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showCurrentlyReadingPrompt, onDismiss: {
            if let uid = authService.firebaseUser?.uid {
                OnboardingCurrentlyReadingPromptStorage.markShown(for: uid)
            }
            scheduleWelcomeGoodreadsModalIfNeeded()
        }) {
            OnboardingCurrentlyReadingView(onDone: { showCurrentlyReadingPrompt = false })
                .environmentObject(appState)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }

    var body: some View {
        tabContentWithSheets
        .onReceive(NotificationCenter.default.publisher(for: .wellreadOpenFeed)) { _ in
            selectedTab = .feed
            appState.deepLinkFeedPostId = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: .wellreadOpenFeedPost)) { note in
            // Consume the cold-start stash too, so onAppear doesn't re-handle.
            _ = PushNotificationService.consumePendingOpenPostCommentsTap()
            _ = PushNotificationService.consumePendingOpenPostCommentsCommentTap()
            if let id = note.userInfo?["postId"] as? String {
                selectedTab = .feed
                appState.deepLinkFeedCommentId = note.userInfo?["commentId"] as? String
                appState.deepLinkFeedPostId = id
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .spineOpenUserProfile)) { note in
            _ = PushNotificationService.consumePendingProfileUserTap()
            if let uid = note.userInfo?["userId"] as? String, !uid.isEmpty {
                presentDeepLinkProfile(userId: uid)
            }
        }
        .sheet(item: $deepLinkProfile) { profile in
            NavigationStack {
                UserLibraryDetailView(userId: profile.id)
            }
            .environmentObject(authService)
            .environmentObject(appState)
        }
        .sheet(item: $incomingBlendInvite, onDismiss: {
            // Swipe-down without choosing = "Remind me in a bit".
            if !blendInviteDecided, let uid = authService.firebaseUser?.uid,
               let invite = lastPresentedBlendInvite {
                BookBlendInviteModalStorage.snoozeTwoDays(uid: uid, blend: invite)
            }
            lastPresentedBlendInvite = nil
        }) { invite in
            BookBlendInviteNudgeModal(
                blend: invite,
                onBlend: {
                    if let uid = authService.firebaseUser?.uid {
                        // Snoozed, not consumed: if they bail out of the landing
                        // without deciding, the invite can resurface later.
                        BookBlendInviteModalStorage.snoozeTwoDays(uid: uid, blend: invite)
                    }
                    blendInviteDecided = true
                    incomingBlendInvite = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        NotificationCenter.default.post(
                            name: .spineOpenBookBlend,
                            object: nil,
                            // They already said "Let's Blend" — the landing
                            // accepts immediately instead of re-pitching.
                            userInfo: ["blendId": invite.id, "autoAccept": true]
                        )
                    }
                },
                onRemindLater: {
                    if let uid = authService.firebaseUser?.uid {
                        BookBlendInviteModalStorage.snoozeTwoDays(uid: uid, blend: invite)
                    }
                    blendInviteDecided = true
                    incomingBlendInvite = nil
                },
                onNoThanks: {
                    if let uid = authService.firebaseUser?.uid {
                        BookBlendInviteModalStorage.dismissForever(uid: uid, blend: invite)
                    }
                    blendInviteDecided = true
                    incomingBlendInvite = nil
                }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .onReceive(NotificationCenter.default.publisher(for: .spineHighlightTierBook)) { _ in
            selectedTab = .profile
        }
        .onReceive(NotificationCenter.default.publisher(for: .spineOpenQueue)) { _ in
            _ = PushNotificationService.consumePendingOpenQueueTap()
            selectedTab = .profile
        }
        // Blend pushes (invite / ready) present the Book Blend landing full-screen.
        .bookBlendPushPresenter()
        .onAppear {
            #if DEBUG
            // `-uiPreviewTab feed|discover|search|profile` (with `-uiPreview`) starts on a
            // given tab for simulator UI verification.
            if let raw = UserDefaults.standard.string(forKey: "uiPreviewTab") {
                if raw == "discoverLoading" {
                    // Discover pinned to its loading state (spinner verification).
                    selectedTab = .discover
                    appState.isLoadingDiscoverSuggestions = true
                } else if let t = Tab(rawValue: raw) {
                    selectedTab = t
                }
            }
            // `-uiPreviewPhotoNudge` / `-uiPreviewPhoneNudge` / `-uiPreviewCurrentlyReading`
            // force the launch modals open for simulator UI verification.
            if ProcessInfo.processInfo.arguments.contains("-uiPreviewPhotoNudge") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { showProfilePhotoNudgeModal = true }
            }
            if ProcessInfo.processInfo.arguments.contains("-uiPreviewPhoneNudge") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { showPhoneNumberNudgeModal = true }
            }
            if ProcessInfo.processInfo.arguments.contains("-uiPreviewCurrentlyReading") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { showCurrentlyReadingPrompt = true }
            }
            // `-uiPreviewBlendInviteModal`: force the blend invite launch modal on
            // demo data for simulator UI verification.
            if ProcessInfo.processInfo.arguments.contains("-uiPreviewBlendInviteModal") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    blendInviteDecided = false
                    lastPresentedBlendInvite = .uiPreviewDemo
                    incomingBlendInvite = .uiPreviewDemo
                }
            }
            #endif
            appState.loadDiscoverSuggestionsIfNeeded()
            PushNotificationService.registerForRemoteNotificationsOnly()
            // Push tapped on a cold start: the tap fired before this view mounted,
            // so its NotificationCenter post was lost — replay it from the stash.
            // (Blend taps are replayed the same way by bookBlendPushPresenter.)
            if let postId = PushNotificationService.consumePendingOpenPostCommentsTap() {
                selectedTab = .feed
                appState.deepLinkFeedCommentId = PushNotificationService.consumePendingOpenPostCommentsCommentTap()
                appState.deepLinkFeedPostId = postId
            }
            if let uid = PushNotificationService.consumePendingProfileUserTap() {
                presentDeepLinkProfile(userId: uid)
            }
            if PushNotificationService.consumePendingOpenQueueTap() {
                selectedTab = .profile
                // Re-post once the profile tab (and LibraryView's observer) is
                // mounted so the segment lands on Queue, not the default.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    NotificationCenter.default.post(name: .spineOpenQueue, object: nil)
                }
            }
            if appState.pendingGoodreadsImportRows != nil || appState.pendingGoodreadsImportError != nil || appState.pendingGoodreadsImportURL != nil {
                selectedTab = .profile
            }
            syncCompleteProfileSheet()
            // Recovery for accounts killed mid-wizard after the profile commit:
            // profile is complete but the push prompt (and the currently-reading
            // and Goodreads steps behind it) never ran, and nothing else would
            // ever ask again. The legacy chain picks up exactly there. Wizard
            // graduates have the flag set, so this is a no-op for them.
            if !OnboardingWizardModel.justCompletedThisLaunch,
               authService.appUser?.needsProfileCompletion == false,
               authService.appUser?.hasSeenPushNotificationPrompt == false {
                schedulePostProfileOnboardingFlow()
            }
            // Blend invite outranks the photo/push nudges — it's another person waiting.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                considerShowingBlendInviteModal()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                considerShowingProfilePhotoNudge()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                considerShowingPhoneNumberNudge()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                considerShowingPushNudgeModal()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                reconcileKeyboardVisibility()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    PushNotificationService.syncFCMTokenToFirestoreIfSignedIn()
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    considerShowingBlendInviteModal()
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

    // MARK: - Keyboard visibility

    private func setKeyboardVisible(_ visible: Bool) {
        guard keyboardVisible != visible else { return }
        withAnimation(.easeOut(duration: 0.2)) { keyboardVisible = visible }
    }

    /// Re-checks a believed-visible keyboard against the responder chain: nothing
    /// focused means no keyboard, whatever the notifications said.
    private func reconcileKeyboardVisibility() {
        guard keyboardVisible, !Self.hasActiveFirstResponder else { return }
        setKeyboardVisible(false)
    }

    private func scheduleKeyboardReconcile() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: reconcileKeyboardVisibility)
    }

    private static var hasActiveFirstResponder: Bool {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .contains { $0.containsFirstResponder }
    }

    private func syncCompleteProfileSheet() {
        guard authService.appUser?.needsProfileCompletion == true else {
            showCompleteProfileSheet = false
            return
        }
        showCompleteProfileSheet = true
    }

    /// After profile completion: optional push prompt (new accounts), then the
    /// currently-reading question, then Goodreads welcome — each once per account.
    private func schedulePostProfileOnboardingFlow() {
        guard authService.appUser?.needsProfileCompletion == false,
              let user = authService.appUser,
              authService.firebaseUser?.uid != nil else {
            scheduleCurrentlyReadingPromptIfNeeded()
            return
        }
        if !user.hasSeenPushNotificationPrompt {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                showPushNotificationPromptSheet = true
            }
            return
        }
        scheduleCurrentlyReadingPromptIfNeeded()
    }

    /// Between profile completion and the Goodreads welcome: ask what the user is
    /// reading right now (once per account). Its sheet dismissal chains into the
    /// Goodreads modal.
    private func scheduleCurrentlyReadingPromptIfNeeded() {
        guard authService.appUser?.needsProfileCompletion == false,
              let uid = authService.firebaseUser?.uid,
              !OnboardingCurrentlyReadingPromptStorage.hasShown(for: uid) else {
            scheduleWelcomeGoodreadsModalIfNeeded()
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            showCurrentlyReadingPrompt = true
        }
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
                scheduleCurrentlyReadingPromptIfNeeded()
            }
        }
    }

    /// True while any launch/onboarding sheet is up — new modals must not stack on top.
    private var isAnyLaunchModalUp: Bool {
        showCompleteProfileSheet || showPushNotificationPromptSheet || showWelcomeGoodreadsModal
            || showGoodreadsImportFromWelcome || showPushNudgeModal
            || showProfilePhotoNudgeModal || showPhoneNumberNudgeModal
            || showCurrentlyReadingPrompt || deepLinkProfile != nil
            || incomingBlendInvite != nil
    }

    /// Pending blend invite aimed at me that isn't snoozed/dismissed → surface the
    /// invite modal. Push-independent: this is how invites reach users without
    /// notification permission.
    private func considerShowingBlendInviteModal() {
        guard let uid = authService.firebaseUser?.uid else { return }
        guard authService.appUser?.needsProfileCompletion == false else { return }
        guard !isAnyLaunchModalUp, !isDeepLinkPending else { return }
        Task {
            let invites = await BookBlendService.shared.fetchIncomingPendingBlends(myUid: uid)
            guard let invite = invites.first(where: {
                BookBlendInviteModalStorage.isEligible(uid: uid, blend: $0)
            }) else { return }
            await MainActor.run {
                guard !isAnyLaunchModalUp, !isDeepLinkPending else { return }
                blendInviteDecided = false
                lastPresentedBlendInvite = invite
                incomingBlendInvite = invite
            }
        }
    }

    /// A push deep link is (about to be) presenting — launch nudges must stand down,
    /// or SwiftUI drops the deep-link sheet silently (only one sheet can present).
    private var isDeepLinkPending: Bool {
        deepLinkProfile != nil
            || appState.deepLinkFeedPostId != nil
            || appState.scrollToFeedPostId != nil
            // A fast feed load can consume the pending ids before the nudge timers
            // fire — the recent-tap window covers that gap.
            || PushNotificationService.recentlyHandledDeepLinkTap
    }

    /// New-follower push tapped: present the follower's profile. Any launch nudge that's
    /// already up is dismissed first — the user's explicit tap outranks a nudge — and the
    /// sheet presents after a beat so the dismissal has finished.
    private func presentDeepLinkProfile(userId: String) {
        showProfilePhotoNudgeModal = false
        showPhoneNumberNudgeModal = false
        showPushNudgeModal = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            deepLinkProfile = DeepLinkUserProfile(id: userId)
        }
    }

    /// Recurring prompt when push permission is missing and snooze window has passed.
    private func considerShowingPushNudgeModal() {
        guard let uid = authService.firebaseUser?.uid else { return }
        guard authService.appUser?.needsProfileCompletion == false else { return }
        guard authService.appUser?.hasSeenPushNotificationPrompt == true else { return }
        guard !isAnyLaunchModalUp, !isDeepLinkPending else { return }
        guard PushNotificationNudgeStorage.isEligibleForNudge(uid: uid) else { return }

        PushNotificationService.needsPushPermissionNudge { needs in
            guard needs else { return }
            guard !isAnyLaunchModalUp else { return }
            showPushNudgeModal = true
        }
    }

    /// Launch reminder for users without a profile photo: shows each cold launch
    /// until a photo is set or the user has dismissed it 4 times.
    private func considerShowingProfilePhotoNudge() {
        // The onboarding wizard just offered the photo step in this session;
        // nudging 1.2s after "Skip for now" would undercut it. Next cold launch
        // is fair game.
        guard !OnboardingWizardModel.justCompletedThisLaunch else { return }
        guard let uid = authService.firebaseUser?.uid,
              let user = authService.appUser,
              !user.needsProfileCompletion,
              (user.profileImageURL ?? "").isEmpty,
              ProfilePhotoNudgeStorage.isEligible(uid: uid) else { return }
        guard !isAnyLaunchModalUp, !isDeepLinkPending else { return }
        showProfilePhotoNudgeModal = true
    }

    /// Backfill reminder for accounts with no phone number on file (they
    /// predate the wizard's phone step, or skipped it): shows each cold launch
    /// until a number is saved or the user has dismissed it 4 times. Same
    /// deal as the photo nudge, and it never blocks anything.
    private func considerShowingPhoneNumberNudge() {
        // The wizard just asked for the number in this session; asking again
        // 1.6s after "Skip for now" would undercut it.
        guard !OnboardingWizardModel.justCompletedThisLaunch else { return }
        guard let uid = authService.firebaseUser?.uid,
              let user = authService.appUser,
              !user.needsProfileCompletion,
              (user.phoneNumber ?? "").isEmpty,
              PhoneNumberNudgeStorage.isEligible(uid: uid) else { return }
        guard !isAnyLaunchModalUp, !isDeepLinkPending else { return }
        showPhoneNumberNudgeModal = true
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
            tabButton(.search, icon: "magnifyingglass", label: "Search")
            tabButton(.profile, icon: "books.vertical.fill", label: "Profile")
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
            if selectedTab != tab {
                withAnimation(.snappy(duration: 0.3, extraBounce: 0.12)) {
                    selectedTab = tab
                }
            } else {
                // Already on this tab: its root view pops any pushed pages back to
                // the tab root (Feed additionally scrolls to top or refreshes).
                NotificationCenter.default.post(name: tab.tappedAgainNotification, object: nil)
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

private extension UIView {
    /// Depth-first search for a live first responder — the only public way to ask
    /// whether anything in the app is actually holding the keyboard up.
    var containsFirstResponder: Bool {
        if isFirstResponder { return true }
        return subviews.contains { $0.containsFirstResponder }
    }
}
