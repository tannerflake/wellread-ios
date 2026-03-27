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
    /// Set when app is opened from Share Extension with a Goodreads CSV; LibraryView shows import sheet and clears this.
    @Published var pendingGoodreadsImportRows: [GoodreadsRow]? = nil
    /// Set when Share Extension opened the app but couldn't get CSV (e.g. user shared page URL); show alert and clear.
    @Published var pendingGoodreadsImportError: String? = nil
    /// Set when Share Extension passed a URL; app downloads in foreground then sets rows or error and clears this.
    @Published var pendingGoodreadsImportURL: URL? = nil
    @Published var isFetchingGoodreadsFromURL = false

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
            Task { @MainActor in
                self.dropExcludedFromDiscoverQueue()
            }
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
        // Drop zones pass `order` = "insert before this slot" in the **full** tier list (including the moved book).
        // `inTarget` excludes the moved book, so indices are off by one for slots after the moved book — fix below.
        let fullTierBefore = userBooks.filter { sameTier($0.tier, tier) }
            .sorted { ($0.tierOrder ?? 999) < ($1.tierOrder ?? 999) }
        let movedIndexInFullTier = fullTierBefore.firstIndex(where: { $0.id == userBookId })

        var inTarget = userBooks.filter { sameTier($0.tier, tier) && $0.id != userBookId }
        inTarget.sort { ($0.tierOrder ?? 999) < ($1.tierOrder ?? 999) }

        let insertAt: Int
        if let raw = order {
            let cap = fullTierBefore.count
            let insertBeforeSlot = min(max(0, raw), cap)
            if let m = movedIndexInFullTier, sameTier(sourceTier, tier) {
                let converted = insertBeforeSlot <= m ? insertBeforeSlot : insertBeforeSlot - 1
                insertAt = min(max(0, converted), inTarget.count)
            } else {
                insertAt = min(max(0, insertBeforeSlot), inTarget.count)
            }
        } else {
            insertAt = inTarget.count
        }
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

    /// Updates the **existing** queue `userBook` document to Read with rating, optional thoughts as `reviewText`, and optional feed post. Does not create a duplicate row.
    func promoteQueueEntryToRead(
        userBook: UserBook,
        dateFinished: Date,
        rating: Double?,
        postToFeed: Bool,
        caption: String?
    ) {
        guard let uid = currentUserId, userBook.status == .wantToRead else { return }
        let stored = rating.map { Theme.normalizeRatingOutOfTen($0) }
        let thoughts = caption?.trimmingCharacters(in: .whitespacesAndNewlines)
        let review = thoughts.flatMap { $0.isEmpty ? nil : $0 }
        var updated = userBook
        updated.status = .read
        updated.dateFinished = dateFinished
        updated.rating = stored
        updated.reviewText = review
        updated.queueShelf = nil
        updated.queueOrder = nil
        updated.updatedAt = Date()
        updateUserBook(updated)
        Task {
            try? await userBookRepo.updateUserBook(updated)
            if postToFeed {
                _ = try? await postRepo.createPost(
                    userId: uid,
                    type: .finishedBook,
                    bookId: userBook.bookId,
                    caption: review,
                    rating: stored,
                    dateFinished: dateFinished
                )
            }
        }
    }

    /// Drag-and-drop between **Up next** and **Backlog**, or reorder within a shelf. `insertionIndex` 0 = first cell (top-left).
    func setQueueShelfAndOrder(for userBookId: UUID, shelf: QueueShelf, insertionIndex: Int?) {
        guard let moveIndex = userBooks.firstIndex(where: { $0.id == userBookId }) else { return }
        guard userBooks[moveIndex].status == .wantToRead else { return }
        let now = Date()

        func belongsToShelf(_ ub: UserBook, _ s: QueueShelf) -> Bool {
            switch s {
            case .upNext: return ub.queueShelf == .upNext
            case .backlog: return ub.queueShelf == nil || ub.queueShelf == .backlog
            }
        }

        var moved = userBooks[moveIndex]
        let sourceShelf: QueueShelf = (moved.queueShelf == .upNext) ? .upNext : .backlog
        moved.queueShelf = shelf
        moved.updatedAt = now

        // Same as tier list: UI passes insertion slot in the **full** shelf list (including the moved book).
        let fullShelfBefore = Self.sortQueueMembers(
            userBooks.filter { belongsToShelf($0, shelf) },
            shelf: shelf
        )
        let movedIndexInFullShelf = fullShelfBefore.firstIndex(where: { $0.id == userBookId })

        var inTarget = userBooks.filter { $0.id != userBookId && belongsToShelf($0, shelf) }
        inTarget = Self.sortQueueMembers(inTarget, shelf: shelf)

        let insertAt: Int
        if let raw = insertionIndex {
            let cap = fullShelfBefore.count
            let insertBeforeSlot = min(max(0, raw), cap)
            if let m = movedIndexInFullShelf, sourceShelf == shelf {
                let converted = insertBeforeSlot <= m ? insertBeforeSlot : insertBeforeSlot - 1
                insertAt = min(max(0, converted), inTarget.count)
            } else {
                insertAt = min(max(0, insertBeforeSlot), inTarget.count)
            }
        } else {
            insertAt = inTarget.count
        }
        inTarget.insert(moved, at: insertAt)

        var toPersist: [UserBook] = []

        withAnimation(.easeInOut(duration: 0.3)) {
            for (i, ub) in inTarget.enumerated() {
                guard let idx = userBooks.firstIndex(where: { $0.id == ub.id }) else { continue }
                let prev = userBooks[idx]
                userBooks[idx].queueShelf = shelf
                userBooks[idx].queueOrder = i
                if ub.id == userBookId { userBooks[idx].updatedAt = now }
                if prev.queueShelf != userBooks[idx].queueShelf || prev.queueOrder != userBooks[idx].queueOrder {
                    toPersist.append(userBooks[idx])
                }
            }

            if sourceShelf != shelf {
                var inSource = userBooks.filter { $0.id != userBookId && belongsToShelf($0, sourceShelf) }
                inSource = Self.sortQueueMembers(inSource, shelf: sourceShelf)
                for (i, ub) in inSource.enumerated() {
                    guard let idx = userBooks.firstIndex(where: { $0.id == ub.id }) else { continue }
                    let prev = userBooks[idx]
                    userBooks[idx].queueOrder = i
                    userBooks[idx].queueShelf = sourceShelf
                    userBooks[idx].updatedAt = now
                    if prev.queueOrder != userBooks[idx].queueOrder || prev.queueShelf != userBooks[idx].queueShelf {
                        toPersist.append(userBooks[idx])
                    }
                }
            }
        }

        Task {
            for ub in toPersist {
                try? await userBookRepo.updateUserBook(ub)
            }
        }
    }

    private static func sortQueueMembers(_ books: [UserBook], shelf: QueueShelf) -> [UserBook] {
        switch shelf {
        case .upNext:
            return books.sorted { ($0.queueOrder ?? 999) < ($1.queueOrder ?? 999) }
        case .backlog:
            return sortedBacklog(books)
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

    /// Queue → **Up next** (explicit shelf only).
    var wantToReadUpNext: [UserBook] {
        userBooks
            .filter { $0.status == .wantToRead && $0.queueShelf == .upNext }
            .sorted { ($0.queueOrder ?? 999) < ($1.queueOrder ?? 999) }
    }

    /// Queue → **Backlog** (default; includes legacy `queueShelf == nil`).
    var wantToReadBacklog: [UserBook] {
        let backlog = userBooks.filter { $0.status == .wantToRead && ($0.queueShelf == nil || $0.queueShelf == .backlog) }
        return Self.sortedBacklog(backlog)
    }

    /// Explicit `queueOrder` first (0 = top), then legacy nil rows by `updatedAt` descending (newer near top).
    private static func sortedBacklog(_ books: [UserBook]) -> [UserBook] {
        let explicit = books.filter { $0.queueOrder != nil }.sorted { $0.queueOrder! < $1.queueOrder! }
        let implicit = books.filter { $0.queueOrder == nil }.sorted { $0.updatedAt > $1.updatedAt }
        return explicit + implicit
    }

    /// True if the given book id is on the user's read list.
    func isBookOnReadList(bookId: String) -> Bool {
        userBooks.contains { $0.bookId == bookId && $0.status == .read }
    }

    /// The signed-in user's read `UserBook` for this book id, if any (e.g. book profile "Your review").
    func userReadBook(forBookId bookId: String) -> UserBook? {
        userBooks.first { $0.bookId == bookId && $0.status == .read }
    }

    /// True if the given book id is in the user's queue (want to read).
    func isBookInQueue(bookId: String) -> Bool {
        userBooks.contains { $0.bookId == bookId && $0.status == .wantToRead }
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

    /// Add a book to Queue. No-op if already in queue. Firestore listener will update userBooks.
    func addToWantToRead(book: Book) {
        guard !isBookInQueue(bookId: book.id), let uid = currentUserId else { return }
        Task {
            _ = try? await userBookRepo.addUserBook(userId: uid, book: book, status: .wantToRead, rating: nil, reviewText: nil, dateStarted: nil, dateFinished: nil)
        }
    }

    /// Remove a book from the queue. No-op if not in queue.
    func removeFromQueue(book: Book) {
        guard let uid = currentUserId else { return }
        guard let userBook = userBooks.first(where: { $0.bookId == book.id && $0.status == .wantToRead }) else { return }
        Task {
            try? await userBookRepo.deleteUserBook(userId: uid, userBookId: userBook.id)
        }
    }

    /// Remove a book from the read shelf (tier list). No-op if not on read list.
    func removeFromReadList(book: Book) {
        guard let uid = currentUserId else { return }
        guard let userBook = userBooks.first(where: { $0.bookId == book.id && $0.status == .read }) else { return }
        Task {
            try? await userBookRepo.deleteUserBook(userId: uid, userBookId: userBook.id)
        }
    }

    /// Add a book as Read. `rating` is out of 10 with one decimal (e.g. 8.8). `caption` is saved on the user’s `UserBook` as review text (book profile “Your review”) and, if `postToFeed`, on the finished-book feed post.
    func addAsRead(book: Book, dateFinished: Date, rating: Double?, postToFeed: Bool, caption: String? = nil) {
        guard let uid = currentUserId else { return }
        let stored: Double? = rating.map { Theme.normalizeRatingOutOfTen($0) }
        let thoughts = (caption?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
        Task {
            _ = try? await userBookRepo.addUserBook(userId: uid, book: book, status: .read, rating: stored, reviewText: thoughts, dateStarted: nil, dateFinished: dateFinished)
            if postToFeed {
                _ = try? await postRepo.createPost(userId: uid, type: .finishedBook, bookId: book.id, caption: thoughts, rating: stored, dateFinished: dateFinished)
            }
        }
    }

    /// Whether the current user has a `finishedBook` feed post for this book (for edit sheet “Show on feed”).
    func hasFinishedBookPost(forBookId bookId: String) async -> Bool {
        guard let uid = currentUserId else { return false }
        let posts = await postRepo.fetchPostsForUserAndBook(userId: uid, bookId: bookId)
        return posts.contains { $0.type == .finishedBook }
    }

    /// Text from the most recent finished-book post for this book (when `userBook.reviewText` is empty).
    func finishedBookPostCaption(forBookId bookId: String) async -> String? {
        guard let uid = currentUserId else { return nil }
        let posts = await postRepo.fetchPostsForUserAndBook(userId: uid, bookId: bookId)
        let finished = posts.filter { $0.type == .finishedBook }.sorted { $0.createdAt > $1.createdAt }
        guard let raw = finished.first?.caption?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        return raw
    }

    /// Updates read `UserBook` and syncs or creates/removes the matching feed post. Returns an error message on failure.
    func updateReadReview(
        userBook: UserBook,
        dateFinished: Date,
        rating: Double?,
        thoughts: String,
        postToFeed: Bool
    ) async -> String? {
        guard let uid = currentUserId, userBook.userId == uid else { return "You’re not signed in." }
        guard userBook.status == .read else { return "This isn’t a finished book entry." }
        let trimmed = thoughts.trimmingCharacters(in: .whitespacesAndNewlines)
        let reviewText = trimmed.isEmpty ? nil : trimmed
        let storedRating = rating.map { Theme.normalizeRatingOutOfTen($0) }
        var updated = userBook
        updated.dateFinished = dateFinished
        updated.rating = storedRating
        updated.reviewText = reviewText
        updated.updatedAt = Date()
        do {
            try await userBookRepo.updateUserBook(updated)
            await MainActor.run { self.updateUserBook(updated) }
            let posts = await postRepo.fetchPostsForUserAndBook(userId: uid, bookId: userBook.bookId)
            let finished = posts.filter { $0.type == .finishedBook }.sorted { $0.createdAt > $1.createdAt }
            if postToFeed {
                if finished.isEmpty {
                    _ = try await postRepo.createPost(
                        userId: uid,
                        type: .finishedBook,
                        bookId: userBook.bookId,
                        caption: reviewText,
                        rating: storedRating,
                        dateFinished: dateFinished
                    )
                } else {
                    for p in finished {
                        try await postRepo.updatePost(
                            postId: p.id.uuidString,
                            caption: reviewText,
                            rating: storedRating,
                            dateFinished: dateFinished
                        )
                    }
                }
            } else {
                for p in finished {
                    try await postRepo.deletePostCascade(postId: p.id.uuidString)
                    await MainActor.run {
                        likedPostIds.remove(p.id.uuidString)
                        feedPosts.removeAll { $0.id == p.id }
                    }
                }
            }
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    /// Removes the read entry and any matching finished-book feed posts for this book.
    func deleteReadReview(userBook: UserBook) async -> String? {
        guard let uid = currentUserId, userBook.userId == uid else { return "You’re not signed in." }
        do {
            let posts = await postRepo.fetchPostsForUserAndBook(userId: uid, bookId: userBook.bookId)
            let finished = posts.filter { $0.type == .finishedBook }
            for p in finished {
                try await postRepo.deletePostCascade(postId: p.id.uuidString)
                await MainActor.run {
                    likedPostIds.remove(p.id.uuidString)
                    feedPosts.removeAll { $0.id == p.id }
                }
            }
            try await userBookRepo.deleteUserBook(userId: uid, userBookId: userBook.id)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    // MARK: - Goodreads import

    /// Import Goodreads-matched items. Skips duplicates when skipDuplicates is true. Calls progress?(importedCount, totalCount) on the main actor after each book.
    func importFromGoodreads(items: [GoodreadsMatchedItem], skipDuplicates: Bool, importRatings: Bool, importReviews: Bool, progress: (@Sendable (Int, Int) -> Void)? = nil) async {
        guard let uid = currentUserId else { return }
        var existingIds = Set(userBooks.map(\.bookId))
        let total = items.count
        var imported = 0
        for item in items {
            guard let book = item.book else { continue }
            if skipDuplicates && existingIds.contains(book.id) { continue }
            let status = GoodreadsImportService.status(for: item.row.exclusiveShelf)
            let rating = importRatings ? GoodreadsImportService.ratingOutOfTen(from: item.row.myRating) : nil
            let review = importReviews ? item.row.myReview : nil
            let dateFinished = status == .read ? item.row.dateRead : nil
            do {
                _ = try await userBookRepo.addUserBook(userId: uid, book: book, status: status, rating: rating, reviewText: review, dateStarted: nil, dateFinished: dateFinished)
                existingIds.insert(book.id)
                imported += 1
                progress?(imported, total)
            } catch { }
        }
    }

    /// Download shared URL (from Share Extension), parse as CSV if possible, and set pendingGoodreadsImportRows or pendingGoodreadsImportError. Call from main app when pendingGoodreadsImportURL is set.
    func fetchGoodreadsImportFromURL(_ url: URL) async {
        await MainActor.run { isFetchingGoodreadsFromURL = true }
        defer { Task { @MainActor in isFetchingGoodreadsFromURL = false; pendingGoodreadsImportURL = nil } }
        guard let (data, _) = try? await URLSession.shared.data(from: url), !data.isEmpty else {
            await MainActor.run {
                pendingGoodreadsImportError = GoodreadsImportCopy.couldNotFetchExportMessage
            }
            return
        }
        let head = String(data: data.prefix(500), encoding: .utf8) ?? ""
        let isCSV = head.contains("Book Id") || head.contains("Title,")
        await MainActor.run {
            if isCSV {
                let parsed = GoodreadsCSVParser.parse(data: data)
                pendingGoodreadsImportRows = parsed.isEmpty ? nil : parsed
                if parsed.isEmpty {
                    pendingGoodreadsImportError = "No book data was found at that link."
                }
            } else {
                pendingGoodreadsImportError = GoodreadsImportCopy.couldNotFetchExportMessage
            }
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
            let batch = await DiscoverSuggestionsService.fetchBatch(readBooks: self.readBooks, queueBookIds: self.queueBookIds, dismissedBookIds: self.dismissedBookIds)
            await MainActor.run {
                self.isLoadingDiscoverSuggestions = false
                let filtered = batch.filter { !self.shouldExcludeFromDiscover(bookId: $0.id) }
                self.discoverSuggestionQueue.append(contentsOf: filtered)
                self.popNextDiscoverSuggestion()
            }
        }
    }

    /// Advance to next suggestion (e.g. after Pass / Queue / Read). Fetches more in background if queue is empty.
    func advanceDiscoverSuggestion() {
        dropExcludedFromDiscoverQueue()
        if discoverSuggestionQueue.isEmpty {
            discoverCurrentSuggestion = nil
            loadDiscoverSuggestionsIfNeeded()
            return
        }
        popNextDiscoverSuggestion()
    }

    /// Book IDs in the user's queue (want to read).
    private var queueBookIds: Set<String> {
        Set(userBooks.filter { $0.status == .wantToRead }.map(\.bookId))
    }

    /// True if this book should never be shown in Discover (read, queue, or passed).
    private func shouldExcludeFromDiscover(bookId: String) -> Bool {
        isBookOnReadList(bookId: bookId) || isBookInQueue(bookId: bookId) || dismissedBookIds.contains(bookId)
    }

    /// Remove any books from current suggestion and queue that are now read, queued, or dismissed.
    private func dropExcludedFromDiscoverQueue() {
        if let current = discoverCurrentSuggestion, shouldExcludeFromDiscover(bookId: current.id) {
            discoverCurrentSuggestion = nil
        }
        discoverSuggestionQueue.removeAll { shouldExcludeFromDiscover(bookId: $0.id) }
    }

    /// Set current suggestion to first in queue and remove it; trigger background fetch if queue empty.
    private func popNextDiscoverSuggestion() {
        while let first = discoverSuggestionQueue.first, shouldExcludeFromDiscover(bookId: first.id) {
            discoverSuggestionQueue.removeFirst()
        }
        if discoverSuggestionQueue.isEmpty {
            discoverCurrentSuggestion = nil
            fetchMoreDiscoverSuggestionsInBackground()
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
            let batch = await DiscoverSuggestionsService.fetchBatch(readBooks: self.readBooks, queueBookIds: self.queueBookIds, dismissedBookIds: self.dismissedBookIds)
            await MainActor.run {
                let filtered = batch.filter { !self.shouldExcludeFromDiscover(bookId: $0.id) }
                self.discoverSuggestionQueue.append(contentsOf: filtered)
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
