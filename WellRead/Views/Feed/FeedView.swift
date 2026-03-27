//
//  FeedView.swift
//  WellRead
//
//  Instagram-style feed: finished book, review, recommendation, tier list update.
//

import SwiftUI

struct FeedView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var authService: AuthService
    @State private var selectedBookForProfile: Book? = nil
    @State private var postForComments: Post? = nil
    @State private var editReviewFromFeed: EditReadReviewSheetPayload? = nil
    @State private var otherReaders: [(uid: String, user: User)] = []
    @State private var isLoadingOtherReaders = true

    private let userRepo = UserRepository()

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 0) {
                        friendsSection
                        feedFriendsDivider
                        feedSectionLabel
                        LazyVStack(spacing: 0) {
                            ForEach(appState.feedPosts) { post in
                                FeedPostRow(
                                    post: post,
                                    currentUserFirebaseUid: authService.firebaseUser?.uid,
                                    isLiked: appState.likedPostIds.contains(post.id.uuidString),
                                    onBookTap: { selectedBookForProfile = $0 },
                                    onCommentTap: { postForComments = post },
                                    onLikeToggle: { appState.togglePostLike(postId: post.id.uuidString, liked: $0) },
                                    onEditReviewTap: {
                                        guard post.type == .finishedBook,
                                              let bid = post.bookId,
                                              post.userId == authService.firebaseUser?.uid,
                                              let ub = appState.userReadBook(forBookId: bid) else { return }
                                        editReviewFromFeed = EditReadReviewSheetPayload(userBook: ub, feedCaption: post.caption)
                                    }
                                )
                            }
                        }
                        .padding(.bottom, 100)
                    }
                }
                .refreshable {
                    await loadOtherReaders()
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .navigationDestination(for: String.self) { userId in
                UserLibraryDetailView(userId: userId)
                    .environmentObject(authService)
                    .environmentObject(appState)
            }
            .navigationDestination(item: $selectedBookForProfile) { book in
                BookProfileView(
                    book: book,
                    readBooksForSimilar: appState.readBooks,
                    onNotInterested: nil,
                    onWantToRead: { appState.addToWantToRead(book: book); selectedBookForProfile = nil },
                    onConfirmRead: { date, rating, post, caption in appState.addAsRead(book: book, dateFinished: date, rating: rating, postToFeed: post, caption: caption); selectedBookForProfile = nil },
                    isOnReadList: appState.isBookOnReadList(bookId: book.id),
                    isInQueue: appState.isBookInQueue(bookId: book.id),
                    onRemoveFromQueue: { appState.removeFromQueue(book: book); selectedBookForProfile = nil },
                    readEntryForReview: appState.userReadBook(forBookId: book.id),
                    canEditReadReview: true
                )
            }
            .sheet(item: $editReviewFromFeed) { payload in
                EditReadReviewSheet(userBook: payload.userBook, feedCaption: payload.feedCaption)
                    .environmentObject(appState)
            }
            .sheet(item: $postForComments) { post in
                CommentsView(post: post)
                    .environmentObject(appState)
                    .environmentObject(authService)
            }
            .task {
                await loadOtherReaders()
            }
            .onChange(of: authService.firebaseUser?.uid) { _, _ in
                Task { await loadOtherReaders() }
            }
        }
    }

    private func loadOtherReaders() async {
        let uid = authService.firebaseUser?.uid
        let list = await userRepo.fetchAllReaderProfiles(excludingUid: uid, limit: 400)
        await MainActor.run {
            otherReaders = list
            isLoadingOtherReaders = false
        }
    }

    /// Subtle rule between “Your friends” and the “Feed” posts block.
    private var feedFriendsDivider: some View {
        Rectangle()
            .fill(Theme.textTertiary.opacity(0.22))
            .frame(height: 0.5)
            .padding(.horizontal, Theme.horizontalPadding)
            .padding(.vertical, 10)
    }

    private var feedSectionLabel: some View {
        HStack {
            Text("Feed")
                .font(Theme.feedBlockTitle())
                .foregroundStyle(Theme.textPrimary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.horizontalPadding)
        .padding(.bottom, 6)
    }

    @ViewBuilder
    private var friendsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your friends")
                .font(Theme.feedSectionHeader())
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, Theme.horizontalPadding)

            if isLoadingOtherReaders {
                HStack {
                    Spacer(minLength: 0)
                    ProgressView()
                        .tint(Theme.accent)
                    Spacer(minLength: 0)
                }
                .frame(height: 88)
                .padding(.bottom, 8)
            } else if otherReaders.isEmpty {
                EmptyView()
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 14) {
                        ForEach(Array(otherReaders.enumerated()), id: \.element.uid) { _, item in
                            NavigationLink(value: item.uid) {
                                VStack(spacing: 8) {
                                    otherReaderSquareAvatar(user: item.user, size: 64)
                                    Text(item.user.displayName)
                                        .font(Theme.caption())
                                        .foregroundStyle(Theme.textSecondary)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.center)
                                        .frame(width: 72)
                                }
                                .accessibilityElement(children: .combine)
                                .accessibilityLabel("\(item.user.displayName), open library")
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, Theme.horizontalPadding)
                    .padding(.bottom, 12)
                }
            }
        }
        .padding(.top, 4)
    }

    private func otherReaderSquareAvatar(user: User, size: CGFloat) -> some View {
        let corner: CGFloat = 12
        let initial = String(user.displayName.prefix(1))
        return Group {
            if let urlStr = user.profileImageURL, let url = URL(string: urlStr) {
                CachedProfileImage(url: url, contentMode: .fill) {
                    otherReaderPlaceholder(initial: initial, size: size, corner: corner)
                }
            } else {
                otherReaderPlaceholder(initial: initial, size: size, corner: corner)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: corner))
        .overlay(
            RoundedRectangle(cornerRadius: corner)
                .strokeBorder(Theme.textTertiary.opacity(0.25), lineWidth: 1)
        )
    }

    private func otherReaderPlaceholder(initial: String, size: CGFloat, corner: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: corner)
            .fill(Theme.surface)
            .overlay(
                Text(initial)
                    .font(.system(size: size * 0.38, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
            )
    }
}

struct FeedPostRow: View {
    let post: Post
    /// Signed-in user's Firebase uid (for edit pencil / like state).
    var currentUserFirebaseUid: String? = nil
    var isLiked: Bool = false
    var onBookTap: ((Book) -> Void)? = nil
    var onCommentTap: (() -> Void)? = nil
    var onLikeToggle: ((Bool) -> Void)? = nil
    var onEditReviewTap: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            feedAuthorHeader
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
                        if post.rating != nil || post.dateFinished != nil {
                            HStack(spacing: 8) {
                                if let r = post.rating {
                                    Text(Theme.formatRatingOutOfTen(r))
                                        .font(Theme.callout())
                                        .foregroundStyle(Theme.textSecondary)
                                }
                                if let date = post.dateFinished {
                                    Text(date, style: .date)
                                        .font(.caption2)
                                        .foregroundStyle(Theme.textTertiary)
                                }
                            }
                        }
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
                HStack(spacing: 4) {
                    Button {
                        onLikeToggle?(!isLiked)
                    } label: {
                        Image(systemName: isLiked ? "heart.fill" : "heart")
                            .foregroundStyle(isLiked ? Theme.accent : Theme.textSecondary)
                    }
                    .buttonStyle(.plain)
                    Text("\(post.likeCount)")
                        .font(Theme.caption())
                        .foregroundStyle(Theme.textSecondary)
                }
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

    private var showEditReviewButton: Bool {
        guard let uid = currentUserFirebaseUid else { return false }
        guard post.userId == uid else { return false }
        guard post.type == .finishedBook, post.bookId != nil else { return false }
        return onEditReviewTap != nil
    }

    private var feedAuthorHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            NavigationLink(value: post.userId) {
                HStack(spacing: 10) {
                    feedAvatar
                    VStack(alignment: .leading, spacing: 2) {
                        Text(post.user?.displayName ?? "User")
                            .font(Theme.headline())
                            .foregroundStyle(Theme.textPrimary)
                        Text(post.createdAt, style: .relative)
                            .font(Theme.caption())
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
            }
            .buttonStyle(.plain)
            Spacer(minLength: 8)
            if showEditReviewButton {
                Button {
                    onEditReviewTap?()
                } label: {
                    Image(systemName: "pencil")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var feedAvatar: some View {
        let initial = String((post.user?.displayName ?? "?").prefix(1))
        if let urlStr = post.user?.profileImageURL, let url = URL(string: urlStr) {
            CachedProfileImage(url: url, contentMode: .fill) {
                feedAvatarPlaceholder(initial: initial)
            }
            .frame(width: 40, height: 40)
            .clipShape(Circle())
        } else {
            feedAvatarPlaceholder(initial: initial)
        }
    }

    private func feedAvatarPlaceholder(initial: String) -> some View {
        Circle()
            .fill(Theme.surface)
            .frame(width: 40, height: 40)
            .overlay(
                Text(initial)
                    .font(Theme.headline())
                    .foregroundStyle(Theme.textSecondary)
            )
    }
}
