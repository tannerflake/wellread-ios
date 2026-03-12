//
//  FeedView.swift
//  WellRead
//
//  Instagram-style feed: finished book, review, recommendation, tier list update.
//

import SwiftUI

struct FeedView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedBookForProfile: Book? = nil
    @State private var postForComments: Post? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(appState.feedPosts) { post in
                            FeedPostRow(
                                post: post,
                                isLiked: appState.likedPostIds.contains(post.id.uuidString),
                                onBookTap: { selectedBookForProfile = $0 },
                                onCommentTap: { postForComments = post },
                                onLikeToggle: { appState.togglePostLike(postId: post.id.uuidString, liked: $0) }
                            )
                        }
                    }
                    .padding(.bottom, 100)
                }
            }
            .navigationTitle("Feed")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .navigationDestination(item: $selectedBookForProfile) { book in
                BookProfileView(
                    book: book,
                    readBooksForSimilar: appState.readBooks,
                    onNotInterested: { selectedBookForProfile = nil },
                    onWantToRead: { appState.addToWantToRead(book: book); selectedBookForProfile = nil },
                    onHaveRead: { appState.addAsRead(book: book); selectedBookForProfile = nil }
                )
            }
            .sheet(item: $postForComments) { post in
                CommentsView(post: post)
                    .environmentObject(appState)
            }
        }
    }
}

struct FeedPostRow: View {
    let post: Post
    var isLiked: Bool = false
    var onBookTap: ((Book) -> Void)? = nil
    var onCommentTap: (() -> Void)? = nil
    var onLikeToggle: ((Bool) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Circle()
                    .fill(Theme.surface)
                    .frame(width: 40, height: 40)
                    .overlay(
                        Text(String((post.user?.displayName ?? "?").prefix(1)))
                            .font(Theme.headline())
                            .foregroundStyle(Theme.textSecondary)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(post.user?.displayName ?? "User")
                        .font(Theme.headline())
                        .foregroundStyle(Theme.textPrimary)
                    Text(post.createdAt, style: .relative)
                        .font(Theme.caption())
                        .foregroundStyle(Theme.textTertiary)
                }
                Spacer()
            }
            .padding(.horizontal)
            
            if let book = post.book {
                HStack(alignment: .top, spacing: 14) {
                    BookCoverView(book: book, size: 80, onTap: onBookTap != nil ? { onBookTap?(book) } : nil)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(book.title)
                            .font(Theme.headline())
                            .foregroundStyle(Theme.textPrimary)
                        Text(book.author)
                            .font(Theme.callout())
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                }
                .padding(.horizontal)
            }
            
            if let caption = post.caption, !caption.isEmpty {
                Text(caption)
                    .font(Theme.body())
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal)
            }
            
            HStack(spacing: 20) {
                Button {
                    onLikeToggle?(!isLiked)
                } label: {
                    Image(systemName: isLiked ? "heart.fill" : "heart")
                        .foregroundStyle(isLiked ? Theme.accent : Theme.textSecondary)
                }
                Text("\(post.likeCount)")
                    .font(Theme.caption())
                    .foregroundStyle(Theme.textSecondary)
                Button {
                    onCommentTap?()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "bubble.right")
                            .foregroundStyle(Theme.textSecondary)
                        Text("\(post.commentCount)")
                            .font(Theme.caption())
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.bottom, 16)
        }
        .padding(.top, 12)
    }
}
