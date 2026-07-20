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
            entry(book("r1", "Build", "Tony Fadell"), status: .read, tier: "S", finishedDaysAgo: 10),
            entry(book("r2", "Basic Economics", "Thomas Sowell"), status: .read, tier: "A", finishedDaysAgo: 30),
            entry(book("r3", "Brain Energy", "Christopher Palmer"), status: .read, tier: "A", finishedDaysAgo: 55),
            entry(book("r4", "Misbelief", "Dan Ariely"), status: .read, tier: "B", finishedDaysAgo: 80),
            entry(book("r5", "Outrage Machine", "Tobias Rose-Stockwell"), status: .read, tier: "B", finishedDaysAgo: 100)
        ]
        appState.feedPosts = [
            Post(id: UUID(), userId: uid, type: .finishedBook, bookId: "r1", book: book("r1", "Build", "Tony Fadell"), caption: "An unorthodox guide to making things worth making.", createdAt: now.addingTimeInterval(-86400 * 2), likeCount: 4, commentCount: 0, user: .demo, rating: nil, dateFinished: now, tier: "A")
        ]
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
            if isWelcomePreviewRun {
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
            if newValue == nil {
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
        } else if authService.appUser == nil {
            loadingView
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
