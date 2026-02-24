//
//  FeedView.swift
//  WellRead
//
//  Instagram-style feed: finished book, review, recommendation, tier list update.
//

import SwiftUI

struct FeedView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(appState.feedPosts) { post in
                            FeedPostRow(post: post)
                        }
                    }
                    .padding(.bottom, 100)
                }
            }
            .navigationTitle("Feed")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }
}

struct FeedPostRow: View {
    let post: Post
    @State private var liked = false
    @State private var likeCount: Int = 0
    
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
                    BookCoverView(book: book, size: 80)
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
                    liked.toggle()
                    likeCount = post.likeCount + (liked ? 1 : -1)
                } label: {
                    Image(systemName: liked ? "heart.fill" : "heart")
                        .foregroundStyle(liked ? Theme.accent : Theme.textSecondary)
                }
                Text("\(likeCount)")
                    .font(Theme.caption())
                    .foregroundStyle(Theme.textSecondary)
                Image(systemName: "bubble.right")
                    .foregroundStyle(Theme.textSecondary)
                Text("\(post.commentCount)")
                    .font(Theme.caption())
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.bottom, 16)
        }
        .padding(.top, 12)
        .onAppear { likeCount = post.likeCount }
    }
}
