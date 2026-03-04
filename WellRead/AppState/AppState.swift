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

    private let userBookRepo = UserBookRepository()
    private let postRepo = PostRepository()
    private var userBooksListener: ListenerRegistration?
    private var feedListener: ListenerRegistration?
    private var currentUserId: String?

    init() {}

    /// Call when user signs in (with their Firebase uid). Loads cached library first for instant UI, then starts Firestore listener.
    func startFirestoreListeners(uid: String) {
        stopFirestoreListeners()
        currentUserId = uid

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
        for (i, ub) in inTarget.enumerated() {
            guard let idx = userBooks.firstIndex(where: { $0.id == ub.id }) else { continue }
            let changed = userBooks[idx].tier != ub.tier || userBooks[idx].tierOrder != i
            userBooks[idx].tier = ub.tier
            userBooks[idx].tierOrder = i
            if ub.id == userBookId { userBooks[idx].updatedAt = now }
            if changed { toPersist.append(userBooks[idx]) }
        }

        // Source tier (if different): renumber remaining books
        if !sameTier(sourceTier, tier) {
            var inSource = userBooks.filter { sameTier($0.tier, sourceTier) }
            inSource.sort { ($0.tierOrder ?? 999) < ($1.tierOrder ?? 999) }
            for (i, ub) in inSource.enumerated() {
                guard let idx = userBooks.firstIndex(where: { $0.id == ub.id }) else { continue }
                if userBooks[idx].tierOrder != i {
                    userBooks[idx].tierOrder = i
                    toPersist.append(userBooks[idx])
                }
            }
        }

        Task {
            for ub in toPersist {
                try? await userBookRepo.updateUserBook(ub)
            }
        }
    }

    /// Move a book from Want to Read (or any status) to Read. Sets dateFinished to now and persists.
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
}
