//
//  FeedView.swift
//  Spine
//
//  Vertical feed of posts. Friends row up top, then a feed of finished books,
//  reviews, and recommendations from people you follow. Themed for the new
//  cream/teal palette with mono type and receipt-style row separators.
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
    @State private var showFollowCommunityWelcome = false
    /// Post briefly tinted after a push-tap scroll so the review the user tapped is unmistakable.
    @State private var highlightedPostId: String? = nil

    private let userRepo = UserRepository()
    private let postRepo = PostRepository()

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                ScrollViewReader { scrollProxy in
                    ScrollView {
                        VStack(spacing: 0) {
                            spinesHeader
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
                                        },
                                        displayTier: effectiveTier(for: post)
                                    )
                                    .id(post.id.uuidString)
                                    .background(Theme.accent.opacity(highlightedPostId == post.id.uuidString ? 0.14 : 0))
                                }
                            }
                            .animation(.easeInOut(duration: 0.35), value: highlightedPostId)
                            .padding(.bottom, 100)
                        }
                    }
                    .refreshable {
                        await loadOtherReaders()
                    }
                    .onAppear {
                        scrollToPushedPostIfNeeded(proxy: scrollProxy)
                    }
                    .onChange(of: appState.scrollToFeedPostId) { _, _ in
                        scrollToPushedPostIfNeeded(proxy: scrollProxy)
                    }
                    .onChange(of: appState.feedPosts.count) { _, _ in
                        scrollToPushedPostIfNeeded(proxy: scrollProxy)
                    }
                }

                if showFollowCommunityWelcome {
                    Color.black.opacity(0.45)
                        .ignoresSafeArea()
                        .transition(.opacity)

                    FeedCommunityWelcomeModal {
                        Task {
                            await dismissFollowCommunityWelcome()
                        }
                    }
                    .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.22), value: showFollowCommunityWelcome)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbarColorScheme(.light, for: .navigationBar)
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
                    onConfirmRead: { date, rating, post, caption, tier in appState.addAsRead(book: book, dateFinished: date, rating: rating, postToFeed: post, caption: caption, tier: tier); selectedBookForProfile = nil },
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
            .task(id: authService.firebaseUser?.uid) {
                await scheduleFollowCommunityWelcomeIfNeeded()
            }
            .onAppear {
                openDeepLinkedPostIfNeeded()
            }
            .onChange(of: appState.deepLinkFeedPostId) { _, _ in
                openDeepLinkedPostIfNeeded()
            }
            .onChange(of: authService.firebaseUser?.uid) { _, _ in
                Task { await loadOtherReaders() }
            }
        }
    }

    /// Tier shown on a feed post — prefer the post's own `tier` field; fall back to the current user's local tier for legacy posts that haven't been backfilled yet.
    private func effectiveTier(for post: Post) -> String? {
        if let t = post.tier { return t }
        guard post.userId == authService.firebaseUser?.uid, let bid = post.bookId else { return nil }
        return appState.userReadBook(forBookId: bid)?.tier
    }

    /// A friend-review push was tapped: scroll the feed to that post and tint it briefly. Waits for the
    /// feed listener to deliver posts (cold start); gives up once the feed has loaded without the post.
    private func scrollToPushedPostIfNeeded(proxy: ScrollViewProxy) {
        guard let id = appState.scrollToFeedPostId else { return }
        guard appState.feedPosts.contains(where: { $0.id.uuidString == id }) else {
            if !appState.feedPosts.isEmpty {
                appState.scrollToFeedPostId = nil
            }
            return
        }
        appState.scrollToFeedPostId = nil
        // Small delay so the tab switch settles before animating the scroll.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.easeInOut(duration: 0.5)) {
                proxy.scrollTo(id, anchor: .center)
            }
            highlightedPostId = id
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                if highlightedPostId == id {
                    highlightedPostId = nil
                }
            }
        }
    }

    private func openDeepLinkedPostIfNeeded() {
        guard let id = appState.deepLinkFeedPostId else { return }
        appState.deepLinkFeedPostId = nil
        if let p = appState.feedPosts.first(where: { $0.id.uuidString == id }) {
            postForComments = p
            return
        }
        Task {
            if let p = await postRepo.fetchPost(postId: id) {
                await MainActor.run { postForComments = p }
            }
        }
    }

    /// After profile is available and the feed has had a moment to render, show the one-time community follow explainer.
    private func scheduleFollowCommunityWelcomeIfNeeded() async {
        guard authService.firebaseUser != nil else { return }
        var attempts = 0
        while authService.appUser == nil && attempts < 40 {
            try? await Task.sleep(nanoseconds: 100_000_000)
            attempts += 1
        }
        guard let u = authService.appUser, !u.hasSeenFollowCommunityModal else { return }
        try? await Task.sleep(nanoseconds: 450_000_000)
        await MainActor.run {
            withAnimation(.easeInOut(duration: 0.22)) {
                showFollowCommunityWelcome = true
            }
        }
    }

    private func dismissFollowCommunityWelcome() async {
        guard let uid = authService.firebaseUser?.uid else {
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.22)) { showFollowCommunityWelcome = false }
            }
            return
        }
        do {
            try await userRepo.markHasSeenFollowCommunityModal(uid: uid)
            await authService.refreshAppUser()
        } catch {
            #if DEBUG
            print("markHasSeenFollowCommunityModal: \(error)")
            #endif
        }
        await MainActor.run {
            withAnimation(.easeInOut(duration: 0.22)) { showFollowCommunityWelcome = false }
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

    /// Top brand banner — terminal-style "SPINES // FEED" with an ASCII rule below.
    private var spinesHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("SPINE // SOCIAL")
                .font(.system(size: 22, weight: .bold, design: .monospaced))
                .tracking(2)
                .foregroundStyle(Theme.textPrimary)
            Text(SpinesGlyphs.rule(width: 32))
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundStyle(Theme.chromeTeal)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.horizontalPadding)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    /// Hairline rule between "Friends" row and posts.
    private var feedFriendsDivider: some View {
        Rectangle()
            .fill(Theme.chromeTeal.opacity(0.35))
            .frame(height: Theme.chromeHairline)
            .padding(.horizontal, Theme.horizontalPadding)
            .padding(.vertical, 10)
    }

    private var feedSectionLabel: some View {
        HStack {
            Text("FEED")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .tracking(1)
                .foregroundStyle(Theme.chromeTeal)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.horizontalPadding)
        .padding(.bottom, 6)
    }

    @ViewBuilder
    private var friendsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("FRIENDS")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .tracking(1)
                .foregroundStyle(Theme.chromeTeal)
                .padding(.horizontal, Theme.horizontalPadding)

            if isLoadingOtherReaders {
                HStack(spacing: 8) {
                    Text(SpinesGlyphs.phosphorFade)
                        .font(.system(size: 14, weight: .regular, design: .monospaced))
                        .foregroundStyle(Theme.chromeTeal)
                    Text("loading readers")
                        .font(.system(size: 13, weight: .regular, design: .monospaced))
                        .foregroundStyle(Theme.textTertiary)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, Theme.horizontalPadding)
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
                                    otherReaderCircleAvatar(user: item.user, size: 64)
                                    Text(item.user.displayName)
                                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
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

    private func otherReaderCircleAvatar(user: User, size: CGFloat) -> some View {
        let initial = String(user.displayName.prefix(1))
        return Group {
            if let urlStr = user.profileImageURL, let url = URL(string: urlStr) {
                CachedProfileImage(url: url, contentMode: .fill) {
                    otherReaderPlaceholder(initial: initial, size: size)
                }
            } else {
                otherReaderPlaceholder(initial: initial, size: size)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(
            Circle()
                .strokeBorder(Theme.chromeTeal.opacity(0.55), lineWidth: 1.5)
        )
    }

    private func otherReaderPlaceholder(initial: String, size: CGFloat) -> some View {
        Circle()
            .fill(Theme.chromeTeal)
            .overlay(
                Text(initial.uppercased())
                    .font(.system(size: size * 0.42, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.phosphorWhite)
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
    /// Tier to display on the post. Lets the feed pass a fallback (e.g. the current user's UserBook tier) for legacy posts where `post.tier` hasn't been backfilled yet.
    var displayTier: String? = nil

    /// Latest comments shown inline under the post (Instagram-style, max 2).
    @State private var previewComments: [Comment] = []

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
                            .lineLimit(2)
                        Text(book.author)
                            .font(Theme.callout())
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                        if let t = displayTier {
                            TierBadge(tier: t)
                        }
                    }
                    Spacer()
                }
                .padding(.horizontal)
            }

            if let caption = post.caption, !caption.isEmpty {
                ExpandableReviewText(text: caption)
                    .padding(.horizontal)
            }

            HStack(spacing: 12) {
                Button {
                    onLikeToggle?(!isLiked)
                } label: {
                    engagementPill(
                        icon: isLiked ? "heart.fill" : "heart",
                        count: post.likeCount,
                        tint: isLiked ? Theme.magentaPunch : Theme.textSecondary,
                        active: isLiked,
                        activeColor: Theme.magentaPunch
                    )
                }
                .buttonStyle(.plain)
                .sensoryFeedback(.impact(weight: .medium), trigger: isLiked)
                Button {
                    onCommentTap?()
                } label: {
                    engagementPill(
                        icon: "bubble.right.fill",
                        count: post.commentCount,
                        tint: Theme.chromeTeal,
                        active: false,
                        activeColor: Theme.chromeTeal
                    )
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.bottom, previewComments.isEmpty ? 14 : 4)

            commentPreviewSection

            // Receipt-style hairline between posts
            Rectangle()
                .fill(Theme.chromeTeal.opacity(0.25))
                .frame(height: Theme.chromeHairline)
                .padding(.horizontal, Theme.horizontalPadding)
        }
        .padding(.top, 14)
        .task(id: "\(post.id.uuidString)-\(post.commentCount)") {
            guard post.commentCount > 0 else {
                previewComments = []
                return
            }
            let all = await CommentRepository().fetchComments(postId: post.id.uuidString)
            previewComments = Array(all.suffix(2))
        }
    }

    /// Chunky tappable capsule for like/comment — icon bounces when toggled on.
    private func engagementPill(icon: String, count: Int, tint: Color, active: Bool, activeColor: Color) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(tint)
                .symbolEffect(.bounce, value: active)
            Text("\(count)")
                .font(.system(size: 15, weight: .bold, design: .monospaced))
                .foregroundStyle(active ? activeColor : Theme.textSecondary)
                .contentTransition(.numericText())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(
            Capsule().fill(active ? activeColor.opacity(0.14) : Theme.surface)
        )
        .overlay(
            Capsule().stroke(active ? activeColor.opacity(0.55) : Theme.chromeTeal.opacity(0.35), lineWidth: 1)
        )
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: active)
    }

    /// Up to two latest comments inline, then "View all N comments" (Instagram-style).
    @ViewBuilder
    private var commentPreviewSection: some View {
        if !previewComments.isEmpty {
            VStack(alignment: .leading, spacing: 5) {
                ForEach(previewComments) { c in
                    (
                        Text(c.displayName ?? "User")
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                        + Text("  \(c.text)")
                            .font(Theme.body())
                    )
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                }
                if post.commentCount > previewComments.count {
                    Text("View all \(post.commentCount) comments")
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { onCommentTap?() }
            .padding(.horizontal)
            .padding(.bottom, 14)
        }
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
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundStyle(Theme.textPrimary)
                        Text(Theme.feedRelativeTimestamp(post.createdAt))
                            .font(.system(size: 10, weight: .regular, design: .monospaced))
                            .tracking(0.5)
                            .foregroundStyle(Theme.chromeTeal)
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
            .overlay(
                Circle()
                    .strokeBorder(Theme.chromeTeal.opacity(0.55), lineWidth: 1)
            )
        } else {
            feedAvatarPlaceholder(initial: initial)
        }
    }

    private func feedAvatarPlaceholder(initial: String) -> some View {
        Circle()
            .fill(Theme.chromeTeal)
            .frame(width: 40, height: 40)
            .overlay(
                Text(initial.uppercased())
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.phosphorWhite)
            )
    }
}

/// Review/caption text that collapses past 9 lines. Tapping the text or the
/// "read more"/"show less" pill toggles expansion; short text renders plain.
struct ExpandableReviewText: View {
    let text: String
    private static let collapsedLineLimit = 9

    @State private var expanded = false
    /// True once measurement shows the full text is taller than 9 lines.
    @State private var truncatable = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(text)
                .font(Theme.body())
                .foregroundStyle(Theme.textPrimary)
                .lineSpacing(Theme.bodyLineSpacing)
                .lineLimit(expanded ? nil : Self.collapsedLineLimit)
            if truncatable {
                Text(expanded ? "show less" : "…read more")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.chromeTeal)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard truncatable else { return }
            withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
        }
        .background(measurer)
    }

    /// Invisible copies of the text — one clamped to 9 lines, one unclamped —
    /// measured to decide whether the toggle is needed at the current width.
    private var measurer: some View {
        ZStack(alignment: .topLeading) {
            Text(text)
                .font(Theme.body())
                .lineSpacing(Theme.bodyLineSpacing)
                .lineLimit(Self.collapsedLineLimit)
                .background(
                    GeometryReader { g in
                        Color.clear.preference(key: CollapsedHeightKey.self, value: g.size.height)
                    }
                )
            Text(text)
                .font(Theme.body())
                .lineSpacing(Theme.bodyLineSpacing)
                .fixedSize(horizontal: false, vertical: true)
                .background(
                    GeometryReader { g in
                        Color.clear.preference(key: FullHeightKey.self, value: g.size.height)
                    }
                )
        }
        .hidden()
        .onPreferenceChange(CollapsedHeightKey.self) { collapsed in
            collapsedHeight = collapsed
            updateTruncatable()
        }
        .onPreferenceChange(FullHeightKey.self) { full in
            fullHeight = full
            updateTruncatable()
        }
    }

    @State private var collapsedHeight: CGFloat = 0
    @State private var fullHeight: CGFloat = 0

    private func updateTruncatable() {
        truncatable = fullHeight > collapsedHeight + 1
    }

    private struct CollapsedHeightKey: PreferenceKey {
        static var defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
    }

    private struct FullHeightKey: PreferenceKey {
        static var defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
    }
}
