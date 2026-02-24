//
//  AppState.swift
//  WellRead
//
//  Global app state: auth, current user, and in-memory library for MVP.
//

import SwiftUI
import Combine

final class AppState: ObservableObject {
    @Published var isAuthenticated: Bool = false
    @Published var currentUser: User?
    @Published var userBooks: [UserBook] = []
    @Published var feedPosts: [Post] = []
    
    init() {
        // Demo: start logged in with mock user for MVP
        #if DEBUG
        loadDemoState()
        #endif
    }
    
    func loadDemoState() {
        currentUser = .demo
        isAuthenticated = true
        userBooks = UserBook.demoList
        feedPosts = Post.demoFeed
    }
    
    func signOut() {
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
