//
//  AppState.swift
//  WellRead
//
//  Global app state: auth, current user, userBooks and feed from Firestore. Library cached on disk for instant load.
//

import SwiftUI
import Combine
import FirebaseFirestore

final class AppState: ObservableObject {
    @Published var isAuthenticated: Bool = false
    @Published var currentUser: User?
    @Published var userBooks: [UserBook] = []
    @Published var feedPosts: [Post] = []
    @Published var dismissedBookIds: Set<String> = []
    @Published var discoverCurrentSuggestion: Book?
    @Published var discoverSuggestionQueue: [Book] = []
    @Published var isLoadingDiscoverSuggestions = false
    @Published var likedPostIds: Set<String> = []

    /// True only after we've loaded dismissed book IDs from Firestore, so discover suggestions exclude them from the first fetch.
    private var dismissedBookIdsLoaded = false

    private let userBookRepo = UserBookRepository()
    private let postRepo = PostRepository()
    private let dismissedRepo = DismissedSuggestionsRepository()
    private var userBooksListener: ListenerRegistration?
    private var feedListener: ListenerRegistration?
    private var currentUserId: String?

    /// Firebase Auth uid for the current user (use for Firestore writes).
    var authUserId: String? { currentUserId }

    init() {}

    /// Call when user signs in (with their Firebase uid). Loads cached library first for instant UI, then starts Firestore listener.
    func startFirestoreListeners(uid: String) {
        stopFirestoreListeners()
        currentUserId = uid
        dismissedBookIdsLoaded = false

        // Load from disk first so the user sees their library immediately.
        if let cached = LocalLibraryCache.shared.loadLibrary(userId: uid), !cached.isEmpty {
            userBooks = cached
            BookRepository.shared.prewarmCache(with: cached.compactMap(\.book))
        }

        userBooksListener = userBookRepo.listenUserBooks(userId: uid) { [weak self] list in
            guard let self = self else { return }
            self.userBooks = list
            if let uid = self.currentUserId {
                let copy = list
                DispatchQueue.global(qos: .utility).async {
                    LocalLibraryCache.shared.saveLibrary(copy, userId: uid)
                }
            }
        }
        feedListener = postRepo.listenFeed { [weak self] list in
            self?.feedPosts = list
        }

        Task { [weak self] in
            guard let self = self, let uid = self.currentUserId else { return }
            let ids = await self.dismissedRepo.fetchDismissedBookIds(userId: uid)
            await MainActor.run {
                self.dismissedBookIds = Set(ids)
                self.dismissedBookIdsLoaded = true
                self.loadDiscoverSuggestionsIfNeeded()
            }
        }
        Task { [weak self] in
            guard let self = self, let uid = self.currentUserId else { return }
            let liked = await self.postRepo.fetchLikedPostIds(userId: uid)
            await MainActor.run { self.likedPostIds = liked }
        }
    }

    /// Call when user signs out to stop listeners and clear state.
    func stopFirestoreListeners() {
        userBooksListener?.remove()
        userBooksListener = nil
        feedListener?.remove()
        feedListener = nil
    }

    func signOut() {
        stopFirestoreListeners()
        currentUserId = nil
        currentUser = nil
        isAuthenticated = false
        userBooks = []
        feedPosts = []
        dismissedBookIds = []
        dismissedBookIdsLoaded = false
        discoverCurrentSuggestion = nil
        discoverSuggestionQueue = []
        likedPostIds = []
        BookRepository.shared.clearCache()
    }

    func addUserBook(_ userBook: UserBook) {
        userBooks.append(userBook)
    }

    func updateUserBook(_ userBook: UserBook) {
        if let i = userBooks.firstIndex(where: { $0.id == userBook.id }) {
            userBooks[i] = userBook
        }
    }

    func setTier(for userBookId: UUID, tier: String?) {
        setTierAndOrder(for: userBookId, tier: tier, order: nil)
    }

    /// Set a book's tier and its order within that tier. Order is 0-based; nil = append at end. Renumbers others in source and target tier.
    func setTierAndOrder(for userBookId: UUID, tier: String?, order: Int?) {
        guard let moveIndex = userBooks.firstIndex(where: { $0.id == userBookId }) else { return }
        let now = Date()
        func sameTier(_ a: String?, _ b: String?) -> Bool {
            switch (a, b) {
            case (nil, nil): return true
            case let (x?, y?): return x == y
            default: return false
            }
        }

        var moved = userBooks[moveIndex]
        let sourceTier = moved.tier
        moved.tier = tier
        moved.updatedAt = now

        var toPersist: [UserBook] = []

        // Target tier: current members (excluding moved), insert moved at order, then assign tierOrder 0,1,2,...
        var inTarget = userBooks.filter { sameTier($0.tier, tier) && $0.id != userBookId }
        inTarget.sort { ($0.tierOrder ?? 999) < ($1.tierOrder ?? 999) }
        let insertAt = order.map { min($0, inTarget.count) } ?? inTarget.count
        inTarget.insert(moved, at: insertAt)
        var inSourceUpdates: [(Int, Int)] = []
        if !sameTier(sourceTier, tier) {
            var inSource = userBooks.filter { sameTier($0.tier, sourceTier) }
            inSource.sort { ($0.tierOrder ?? 999) < ($1.tierOrder ?? 999) }
            for (i, ub) in inSource.enumerated() {
                guard let idx = userBooks.firstIndex(where: { $0.id == ub.id }) else { continue }
                if userBooks[idx].tierOrder != i {
                    inSourceUpdates.append((idx, i))
                }
            }
        }

        withAnimation(.easeInOut(duration: 0.3)) {
            for (i, ub) in inTarget.enumerated() {
                guard let idx = userBooks.firstIndex(where: { $0.id == ub.id }) else { continue }
                let changed = userBooks[idx].tier != ub.tier || userBooks[idx].tierOrder != i
                userBooks[idx].tier = ub.tier
                userBooks[idx].tierOrder = i
                if ub.id == userBookId { userBooks[idx].updatedAt = now }
                if changed { toPersist.append(userBooks[idx]) }
            }
            for (idx, i) in inSourceUpdates {
                userBooks[idx].tierOrder = i
                toPersist.append(userBooks[idx])
            }
        }

        Task {
            for ub in toPersist {
                try? await userBookRepo.updateUserBook(ub)
            }
        }
    }

    /// Move a book from Queue (or any status) to Read. Sets dateFinished to now and persists.
    func moveToRead(_ userBook: UserBook) {
        var updated = userBook
        updated.status = .read
        updated.dateFinished = Date()
        updated.updatedAt = Date()
        updateUserBook(updated)
        Task {
            try? await userBookRepo.updateUserBook(updated)
        }
    }

    var readBooks: [UserBook] {
        userBooks.filter { $0.status == .read }
    }

    var currentlyReading: [UserBook] {
        userBooks.filter { $0.status == .currentlyReading }
    }

    var wantToRead: [UserBook] {
        userBooks.filter { $0.status == .wantToRead }
    }

    /// Mark a book as "not interested" so we never suggest it again.
    func addDismissedBookId(_ bookId: String) {
        dismissedBookIds.insert(bookId)
        guard let uid = currentUserId else { return }
        Task {
            try? await dismissedRepo.addDismissed(userId: uid, bookId: bookId)
        }
    }

    /// Remove a book from dismissed (undo Pass) and show it again as the current Discover suggestion.
    func returnToDiscoverBook(_ book: Book) {
        dismissedBookIds.remove(book.id)
        discoverCurrentSuggestion = book
        guard let uid = currentUserId else { return }
        Task {
            try? await dismissedRepo.removeDismissed(userId: uid, bookId: book.id)
        }
    }

    /// Add a book to Queue. Firestore listener will update userBooks.
    func addToWantToRead(book: Book) {
        guard let uid = currentUserId else { return }
        Task {
            _ = try? await userBookRepo.addUserBook(userId: uid, book: book, status: .wantToRead, rating: nil, reviewText: nil, dateStarted: nil, dateFinished: nil)
        }
    }

    /// Add a book as Read (dateFinished = now). Firestore listener will update userBooks.
    func addAsRead(book: Book) {
        guard let uid = currentUserId else { return }
        Task {
            _ = try? await userBookRepo.addUserBook(userId: uid, book: book, status: .read, rating: nil, reviewText: nil, dateStarted: nil, dateFinished: Date())
        }
    }

    // MARK: - Discover suggestions (prefetch so suggestions are ready when user taps Discover)

    /// Call when app/tab bar appears to load first suggestion in background. No-op if already have a suggestion or are loading. Waits for dismissed IDs to load from Firestore so we never suggest passed books.
    func loadDiscoverSuggestionsIfNeeded() {
        guard dismissedBookIdsLoaded else { return }
        guard discoverCurrentSuggestion == nil, discoverSuggestionQueue.isEmpty, !isLoadingDiscoverSuggestions else { return }
        isLoadingDiscoverSuggestions = true
        Task { [weak self] in
            guard let self = self else { return }
            let batch = await DiscoverSuggestionsService.fetchBatch(readBooks: self.readBooks, dismissedBookIds: self.dismissedBookIds)
            await MainActor.run {
                self.isLoadingDiscoverSuggestions = false
                self.discoverSuggestionQueue.append(contentsOf: batch)
                if !self.discoverSuggestionQueue.isEmpty {
                    self.discoverCurrentSuggestion = self.discoverSuggestionQueue.first
                    self.discoverSuggestionQueue = Array(self.discoverSuggestionQueue.dropFirst())
                    if self.discoverSuggestionQueue.isEmpty {
                        self.fetchMoreDiscoverSuggestionsInBackground()
                    }
                }
            }
        }
    }

    /// Advance to next suggestion (e.g. after Pass / Queue / Read). Fetches more in background if queue is empty.
    func advanceDiscoverSuggestion() {
        if discoverSuggestionQueue.isEmpty {
            discoverCurrentSuggestion = nil
            loadDiscoverSuggestionsIfNeeded()
            return
        }
        discoverCurrentSuggestion = discoverSuggestionQueue.first
        discoverSuggestionQueue = Array(discoverSuggestionQueue.dropFirst())
        if discoverSuggestionQueue.isEmpty {
            fetchMoreDiscoverSuggestionsInBackground()
        }
    }

    private func fetchMoreDiscoverSuggestionsInBackground() {
        Task { [weak self] in
            guard let self = self else { return }
            let batch = await DiscoverSuggestionsService.fetchBatch(readBooks: self.readBooks, dismissedBookIds: self.dismissedBookIds)
            await MainActor.run {
                self.discoverSuggestionQueue.append(contentsOf: batch)
            }
        }
    }

    /// Toggle like on a post. Updates Firestore and local state (likedPostIds and feedPosts likeCount).
    func togglePostLike(postId: String, liked: Bool) {
        guard let uid = currentUserId else { return }
        if liked {
            likedPostIds.insert(postId)
            if let idx = feedPosts.firstIndex(where: { $0.id.uuidString == postId }) {
                feedPosts[idx].likeCount += 1
            }
            Task {
                try? await postRepo.addLike(postId: postId, userId: uid)
            }
        } else {
            likedPostIds.remove(postId)
            if let idx = feedPosts.firstIndex(where: { $0.id.uuidString == postId }) {
                feedPosts[idx].likeCount = max(0, feedPosts[idx].likeCount - 1)
            }
            Task {
                try? await postRepo.removeLike(postId: postId, userId: uid)
            }
        }
    }
}
