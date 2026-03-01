//
//  AppState.swift
//  WellRead
//
//  Global app state: auth, current user, userBooks and feed from Firestore.
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

    init() {}

    /// Call when user signs in (with their Firebase uid) to start Firestore listeners.
    func startFirestoreListeners(uid: String) {
        stopFirestoreListeners()
        userBooksListener = userBookRepo.listenUserBooks(userId: uid) { [weak self] list in
            self?.userBooks = list
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
        currentUser = nil
        isAuthenticated = false
        userBooks = []
        feedPosts = []
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
        if let i = userBooks.firstIndex(where: { $0.id == userBookId }) {
            userBooks[i].tier = tier
            userBooks[i].updatedAt = Date()
        }
        Task {
            try? await userBookRepo.setTier(userBookId: userBookId, tier: tier)
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
