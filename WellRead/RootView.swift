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

    /// Latched while the onboarding wizard runs. `completeProfileSetup` refreshes
    /// `appUser` mid-wizard (flipping `needsProfileCompletion` to false), so the
    /// gate below cannot be purely reactive or the wizard would be swapped out
    /// after the taste step. The wizard clears the latch from `finish()`.
    @State private var onboardingWizardActive = false

    #if DEBUG
    /// Launch with `-uiPreviewOnboardingWizard` to walk the wizard with no
    /// signed-in session (no Firestore writes; canned roster and handle checks).
    private var isWizardPreviewRun: Bool {
        ProcessInfo.processInfo.arguments.contains("-uiPreviewOnboardingWizard")
    }
    #endif

    #if DEBUG
    /// Launch with `-uiPreview` (simulator UI verification) to render the main UI
    /// without a signed-in session. Firestore listeners never start; local demo
    /// data is seeded so headers, shelves, and fans render populated.
    private var isUIPreviewRun: Bool {
        ProcessInfo.processInfo.arguments.contains("-uiPreview")
    }

    /// Launch with `-uiPreviewWelcome` to render the signed-out welcome screen
    /// regardless of any existing simulator session.
    private var isWelcomePreviewRun: Bool {
        ProcessInfo.processInfo.arguments.contains("-uiPreviewWelcome")
    }

    /// Local-only demo state for `-uiPreview` runs — never written to Firestore.
    private func seedUIPreviewData() {
        guard appState.currentUser == nil else { return }
        appState.currentUser = .demo
        appState.isAuthenticated = true
        let now = Date()
        let uid = "ui-preview"
        appState.seedPreviewAuth(uid: uid)
        func book(_ id: String, _ title: String, _ author: String) -> Book {
            Book(id: id, title: title, author: author, coverURL: "", pageCount: nil, publishedDate: nil, description: nil, genres: [])
        }
        func entry(_ b: Book, status: ReadingStatus, tier: String? = nil, finishedDaysAgo: Double? = nil, shelf: QueueShelf? = nil, order: Int? = nil) -> UserBook {
            UserBook(id: UUID(), userId: uid, bookId: b.id, book: b, status: status, rating: nil, reviewText: nil, dateStarted: nil, dateFinished: finishedDaysAgo.map { now.addingTimeInterval(-86400 * $0) }, createdAt: now, updatedAt: now, recommendedTo: [], tier: tier, tierOrder: nil, queueShelf: shelf, queueOrder: order)
        }
        appState.userBooks = [
            entry(book("rn1", "Endurance", "Alfred Lansing"), status: .wantToRead, shelf: .readingNow, order: 0),
            entry(book("rn2", "The Founders", "Jimmy Soni"), status: .wantToRead, shelf: .readingNow, order: 1),
            entry(book("rn3", "Choke", "Chuck Palahniuk"), status: .wantToRead, shelf: .readingNow, order: 2),
            entry(book("un1", "Chip War", "Chris Miller"), status: .wantToRead, shelf: .upNext, order: 0),
            entry(book("bl1", "The Nvidia Way", "Tae Kim"), status: .wantToRead, shelf: .backlog, order: 0),
            entry(book("bl2", "Titan", "Ron Chernow"), status: .wantToRead, shelf: .backlog, order: 1),
            entry(book("r1", "Build", "Tony Fadell"), status: .read, tier: "S", finishedDaysAgo: 10),
            entry(book("r6", "Shoe Dog", "Phil Knight"), status: .read, tier: "S", finishedDaysAgo: 15),
            entry(book("r7", "The Hard Thing About Hard Things", "Ben Horowitz"), status: .read, tier: "S", finishedDaysAgo: 20),
            entry(book("r8", "Zero to One", "Peter Thiel"), status: .read, tier: "S", finishedDaysAgo: 25),
            entry(book("r9", "Creativity, Inc.", "Ed Catmull"), status: .read, tier: "S", finishedDaysAgo: 28),
            entry(book("r10", "The Everything Store", "Brad Stone"), status: .read, tier: "S", finishedDaysAgo: 29),
            entry(book("r2", "Basic Economics", "Thomas Sowell"), status: .read, tier: "A", finishedDaysAgo: 30),
            entry(book("r3", "Brain Energy", "Christopher Palmer"), status: .read, tier: "A", finishedDaysAgo: 55),
            entry(book("r4", "Misbelief", "Dan Ariely"), status: .read, tier: "B", finishedDaysAgo: 80),
            entry(book("r5", "Outrage Machine", "Tobias Rose-Stockwell"), status: .read, tier: "B", finishedDaysAgo: 100)
        ]
        // A same-day posting burst from a second demo reader (6 posts today) so
        // the day-group carousel renders in preview, plus a normal standalone post.
        var burstAuthor = User.demo
        burstAuthor.id = UUID()
        burstAuthor.username = "june"
        burstAuthor.displayName = "June"
        let burstBooks: [(String, String, String, String)] = [
            ("g1", "Project Hail Mary", "Andy Weir", "S"),
            ("g2", "Tomorrow, and Tomorrow, and Tomorrow", "Gabrielle Zevin", "A"),
            ("g3", "The Midnight Library", "Matt Haig", "B"),
            ("g4", "Circe", "Madeline Miller", "S"),
            ("g5", "Lessons in Chemistry", "Bonnie Garmus", "A"),
            ("g6", "The Song of Achilles", "Madeline Miller", "A")
        ]
        let longCaption = Array(repeating: "A sentence long enough to wrap across the card and prove the read-more toggle still fires on genuinely long reviews.", count: 6).joined(separator: " ")
        let burstPosts = burstBooks.enumerated().map { i, item in
            Post(id: UUID(), userId: "ui-preview-burst", type: .finishedBook, bookId: item.0, book: book(item.0, item.1, item.2), caption: i == 0 ? "Backfilling my library. Loved this one." : (i == 1 ? longCaption : nil), createdAt: now.addingTimeInterval(Double(-60 * (i + 1))), likeCount: i == 0 ? 3 : 0, commentCount: 0, user: burstAuthor, rating: nil, dateFinished: now, tier: item.3)
        }
        appState.feedPosts = burstPosts + [
            Post(id: UUID(), userId: uid, type: .finishedBook, bookId: "r1", book: book("r1", "Build", "Tony Fadell"), caption: "An unorthodox guide to making things worth making.", createdAt: now.addingTimeInterval(-86400 * 2), likeCount: 4, commentCount: 0, user: .demo, rating: nil, dateFinished: now, tier: "A")
        ]
        appState.isFeedLoading = false
        if SearchRecents.queries(uid: "anon").isEmpty {
            SearchRecents.addQuery("tony fadell", uid: "anon")
            SearchRecents.addQuery("sapiens", uid: "anon")
            SearchRecents.addBook(book("rb1", "Sapiens", "Yuval Noah Harari"), uid: "anon")
            SearchRecents.addBook(book("rb2", "Endurance", "Alfred Lansing"), uid: "anon")
        }
    }
    #endif

    var body: some View {
        Group {
            #if DEBUG
            if isWizardPreviewRun {
                OnboardingWizardView(previewMode: true, onFinished: {})
            } else if isWelcomePreviewRun {
                OnboardingFlowView()
            } else if isUIPreviewRun {
                MainTabView()
                    .onAppear { seedUIPreviewData() }
            } else {
                authGatedRoot
            }
            #else
            authGatedRoot
            #endif
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
            #if DEBUG
            // A leftover simulator keychain session must not hijack `-uiPreview`
            // or `-uiPreviewOnboardingWizard` runs: it would overwrite the demo
            // user and start real listeners.
            if isUIPreviewRun || isWizardPreviewRun { return }
            #endif
            if let user = newUser {
                appState.currentUser = user
                appState.isAuthenticated = true
                if let uid = authService.firebaseUser?.uid {
                    appState.startFirestoreListeners(uid: uid, following: user.following)
                }
            } else if authService.firebaseUser == nil {
                appState.signOut()
            }
        }
        .onChange(of: authService.firebaseUser?.uid) { _, newValue in
            #if DEBUG
            if isUIPreviewRun || isWizardPreviewRun { return }
            #endif
            if newValue == nil {
                onboardingWizardActive = false
                appState.signOut()
            }
        }
    }

    @ViewBuilder
    private var authGatedRoot: some View {
        if authService.isLoading {
            loadingView
        } else if authService.firebaseUser == nil {
            OnboardingFlowView()
                .onAppear { onboardingWizardActive = false }
        } else if authService.appUser == nil {
            loadingView
        } else if let user = authService.appUser, user.needsProfileCompletion || onboardingWizardActive {
            OnboardingWizardView(onFinished: { onboardingWizardActive = false })
                .onAppear { onboardingWizardActive = true }
        } else {
            MainTabView()
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
