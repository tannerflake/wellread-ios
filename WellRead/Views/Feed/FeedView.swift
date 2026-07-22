//
//  FeedView.swift
//  Spine
//
//  Vertical feed of posts. "Following" row up top (people you follow first —
//  current readers leading — then a divider and everyone else on Spine with a
//  quick-follow button), then a feed of finished books, reviews, and
//  recommendations from people you follow. Themed for the cream/teal palette
//  with receipt-style row separators.
//

import SwiftUI

struct FeedView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var authService: AuthService
    @State private var selectedBookForProfile: Book? = nil
    @State private var postForComments: Post? = nil
    @State private var editReviewFromFeed: EditReadReviewSheetPayload? = nil
    @State private var otherReaders: [(uid: String, user: User)] = []
    /// Reading-now covers per member uid (floating book fans on the avatars).
    @State private var readingNowByUid: [String: [Book]] = [:]
    /// Uids with a follow write in flight (debounces the quick-follow plus button).
    @State private var followInFlight: Set<String> = []
    @State private var isLoadingOtherReaders = true
    @State private var showFounderWelcome = false
    /// Post briefly tinted after a push-tap scroll so the review the user tapped is unmistakable.
    @State private var highlightedPostId: String? = nil
    /// Own post awaiting delete confirmation (from the post's ellipsis menu).
    @State private var postPendingDelete: Post? = nil

    private let userRepo = UserRepository()
    private let userBookRepo = UserBookRepository()
    private let postRepo = PostRepository()

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                ScrollViewReader { scrollProxy in
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
                                        },
                                        canEditReview: post.bookId.map { appState.userReadBook(forBookId: $0) != nil } ?? false,
                                        onDeleteTap: { postPendingDelete = post },
                                        displayTier: effectiveTier(for: post),
                                        readingNowBooks: readingNowFanBooks(for: post)
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

                if showFounderWelcome {
                    Color.black.opacity(0.45)
                        .ignoresSafeArea()
                        .transition(.opacity)

                    FeedCommunityWelcomeModal {
                        Task {
                            await dismissFounderWelcome()
                        }
                    }
                    .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.22), value: showFounderWelcome)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.background, for: .navigationBar)
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
            .confirmationDialog(
                "Delete this post?",
                isPresented: Binding(
                    get: { postPendingDelete != nil },
                    set: { if !$0 { postPendingDelete = nil } }
                ),
                titleVisibility: .visible,
                presenting: postPendingDelete
            ) { post in
                Button("Delete Post", role: .destructive) {
                    postPendingDelete = nil
                    Task { _ = await appState.deleteFeedPost(post: post) }
                }
                Button("Cancel", role: .cancel) { postPendingDelete = nil }
            } message: { _ in
                Text("Its likes and comments will be deleted too. Books on your shelf aren’t affected.")
            }
            .task {
                await loadOtherReaders()
            }
            .task(id: authService.firebaseUser?.uid) {
                await scheduleFounderWelcomeIfNeeded()
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

    /// Reading-now covers fanned beside the post author's avatar. Own posts use live
    /// local shelf state (fresher than the feed-load snapshot); others use the snapshot.
    private func readingNowFanBooks(for post: Post) -> [Book] {
        let isOwn = post.userId == authService.firebaseUser?.uid
            || (post.user != nil && post.user?.id == appState.currentUser?.id)
        if isOwn {
            return appState.wantToReadReadingNow.compactMap(\.book)
        }
        return readingNowByUid[post.userId] ?? []
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

    /// After profile is available and the feed has had a moment to render, show the one-time founder welcome note.
    private func scheduleFounderWelcomeIfNeeded() async {
        guard authService.firebaseUser != nil else { return }
        var attempts = 0
        while authService.appUser == nil && attempts < 40 {
            try? await Task.sleep(nanoseconds: 100_000_000)
            attempts += 1
        }
        guard let u = authService.appUser, !u.hasSeenFounderWelcomeModal else { return }
        try? await Task.sleep(nanoseconds: 450_000_000)
        await MainActor.run {
            withAnimation(.easeInOut(duration: 0.22)) {
                showFounderWelcome = true
            }
        }
    }

    private func dismissFounderWelcome() async {
        guard let uid = authService.firebaseUser?.uid else {
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.22)) { showFounderWelcome = false }
            }
            return
        }
        do {
            try await userRepo.markHasSeenFounderWelcomeModal(uid: uid)
            await authService.refreshAppUser()
        } catch {
            #if DEBUG
            print("markHasSeenFounderWelcomeModal: \(error)")
            #endif
        }
        await MainActor.run {
            withAnimation(.easeInOut(duration: 0.22)) { showFounderWelcome = false }
        }
    }

    private func loadOtherReaders() async {
        let uid = authService.firebaseUser?.uid
        async let profilesTask = userRepo.fetchAllReaderProfiles(excludingUid: uid, limit: 400)
        async let readingNowTask = userBookRepo.fetchAllReadingNowBooks()
        let (list, readingNow) = await (profilesTask, readingNowTask)
        await MainActor.run {
            otherReaders = list
            readingNowByUid = readingNow
            isLoadingOtherReaders = false
        }
    }

    /// Hairline rule between the "Following" row and posts.
    private var feedFriendsDivider: some View {
        Rectangle()
            .fill(Theme.chrome.opacity(0.35))
            .frame(height: Theme.chromeHairline)
            .padding(.horizontal, Theme.horizontalPadding)
            .padding(.vertical, 10)
    }

    private var feedSectionLabel: some View {
        HStack {
            Text("FEED")
                .font(.system(size: 12, weight: .bold))
                .tracking(1)
                .foregroundStyle(Theme.chrome)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.horizontalPadding)
        .padding(.bottom, 6)
    }

    /// Uids the signed-in user follows.
    private var myFollowingSet: Set<String> {
        Set(authService.appUser?.following ?? [])
    }

    /// People you follow — anyone reading a book right now first, then alphabetical.
    private var followedReaders: [(uid: String, user: User)] {
        otherReaders
            .filter { myFollowingSet.contains($0.uid) }
            .sorted { a, b in
                let aReading = !(readingNowByUid[a.uid] ?? []).isEmpty
                let bReading = !(readingNowByUid[b.uid] ?? []).isEmpty
                if aReading != bReading { return aReading }
                return a.user.displayName.localizedCaseInsensitiveCompare(b.user.displayName) == .orderedAscending
            }
    }

    /// Everyone on Spine you don't follow yet — most mutual connections first, then alphabetical.
    private var discoverableReaders: [(uid: String, user: User)] {
        let candidates = otherReaders.filter { !myFollowingSet.contains($0.uid) }
        var scores: [String: Int] = [:]
        for c in candidates {
            scores[c.uid] = mutualConnectionCount(candidateUid: c.uid, candidateFollowing: c.user.following)
        }
        return candidates.sorted { a, b in
            let sa = scores[a.uid] ?? 0
            let sb = scores[b.uid] ?? 0
            if sa != sb { return sa > sb }
            return a.user.displayName.localizedCaseInsensitiveCompare(b.user.displayName) == .orderedAscending
        }
    }

    /// Mutual-connection score for the "everyone" ranking: people we both follow,
    /// plus people I follow who follow the candidate.
    private func mutualConnectionCount(candidateUid: String, candidateFollowing: [String]) -> Int {
        let mine = myFollowingSet
        guard !mine.isEmpty else { return 0 }
        var count = mine.intersection(candidateFollowing).count
        for (uid, user) in otherReaders where mine.contains(uid) && user.following.contains(candidateUid) {
            count += 1
        }
        return count
    }

    @ViewBuilder
    private var friendsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("PEOPLE")
                .font(.system(size: 12, weight: .bold))
                .tracking(1)
                .foregroundStyle(Theme.chrome)
                .padding(.horizontal, Theme.horizontalPadding)

            if isLoadingOtherReaders {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Theme.chrome)
                    Text("loading readers")
                        .font(.system(size: 13, weight: .regular))
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
                        ForEach(followedReaders, id: \.uid) { item in
                            readerCell(item: item, isFollowed: true)
                        }
                        if !followedReaders.isEmpty && !discoverableReaders.isEmpty {
                            allReadersDivider
                        }
                        ForEach(discoverableReaders, id: \.uid) { item in
                            readerCell(item: item, isFollowed: false)
                        }
                    }
                    .padding(.horizontal, Theme.horizontalPadding)
                    // Headroom for the quick-follow plus, which overhangs the avatar's
                    // top edge — without it the ScrollView clips the button.
                    .padding(.top, 7)
                    .padding(.bottom, 12)
                    .animation(.easeInOut(duration: 0.25), value: myFollowingSet)
                }
            }
        }
        .padding(.top, 4)
    }

    /// Little rule between the people you follow and the rest of Spine.
    private var allReadersDivider: some View {
        VStack(spacing: 6) {
            Rectangle()
                .fill(Theme.chrome.opacity(0.45))
                .frame(width: 1.5, height: 56)
            Text("ALL")
                .font(.system(size: 9, weight: .bold))
                .tracking(1)
                .foregroundStyle(Theme.chrome)
        }
        .padding(.top, 4)
        .padding(.horizontal, 2)
        .accessibilityHidden(true)
    }

    /// Avatar + name cell. Reading-now covers float on the bottom-left edge of the
    /// avatar; the quick-follow plus sits top-right so the two never collide.
    private func readerCell(item: (uid: String, user: User), isFollowed: Bool) -> some View {
        let readingNow = readingNowByUid[item.uid] ?? []
        return NavigationLink(value: item.uid) {
            VStack(spacing: 8) {
                otherReaderCircleAvatar(user: item.user, size: 64)
                    .overlay(alignment: .bottomLeading) {
                        if !readingNow.isEmpty {
                            ReadingNowFanStack(books: readingNow, coverWidth: 19)
                                .offset(x: -9, y: 8)
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        if !isFollowed {
                            followPlusButton(targetUid: item.uid)
                                .offset(x: 5, y: -5)
                        }
                    }
                Text(item.user.displayName)
                    .font(.system(size: 11, weight: .semibold))
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

    private func followPlusButton(targetUid: String) -> some View {
        Button {
            followReader(targetUid: targetUid)
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Theme.onChrome)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Theme.accentGloss))
                .overlay(Circle().strokeBorder(Theme.background, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .disabled(followInFlight.contains(targetUid))
        .accessibilityLabel("Follow")
    }

    private func followReader(targetUid: String) {
        guard let uid = authService.firebaseUser?.uid, uid != targetUid else { return }
        guard !followInFlight.contains(targetUid) else { return }
        followInFlight.insert(targetUid)
        Task {
            do {
                try await userRepo.setFollowing(currentUid: uid, targetUid: targetUid, follow: true)
                await authService.refreshAppUser()
                await MainActor.run {
                    WidgetDataService.shared.scheduleRefresh(appState: appState, delay: 1.0, forceFriendRefresh: true)
                }
            } catch {
                #if DEBUG
                print("followReader: \(error)")
                #endif
            }
            await MainActor.run { _ = followInFlight.remove(targetUid) }
        }
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
                .strokeBorder(Theme.chrome.opacity(0.55), lineWidth: 1.5)
        )
    }

    private func otherReaderPlaceholder(initial: String, size: CGFloat) -> some View {
        Circle()
            .fill(Theme.chrome)
            .overlay(
                Text(initial.uppercased())
                    .font(.system(size: size * 0.42, weight: .bold))
                    .foregroundStyle(Theme.onChrome)
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
    /// Whether the author's read entry still exists — editing goes through the `UserBook`,
    /// so an orphaned post (book removed from the read shelf) can only be deleted.
    var canEditReview: Bool = false
    var onDeleteTap: (() -> Void)? = nil
    /// Tier to display on the post. Lets the feed pass a fallback (e.g. the current user's UserBook tier) for legacy posts where `post.tier` hasn't been backfilled yet.
    var displayTier: String? = nil
    /// The author's reading-now covers, fanned beside their avatar (same treatment
    /// as the Following row and the profile header).
    var readingNowBooks: [Book] = []

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
                        tint: isLiked ? Theme.punch : Theme.textSecondary,
                        active: isLiked,
                        activeColor: Theme.punch
                    )
                }
                .buttonStyle(.plain)
                .sensoryFeedback(.impact(weight: .medium), trigger: isLiked)
                Button {
                    onCommentTap?()
                } label: {
                    engagementPill(
                        icon: "bubble.right",
                        count: post.commentCount,
                        tint: Theme.textSecondary,
                        active: false,
                        activeColor: Theme.chrome
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
                .fill(Theme.chrome.opacity(0.25))
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
    /// Zero counts are hidden (the mono slashed 0 reads badly), leaving just the icon.
    private func engagementPill(icon: String, count: Int, tint: Color, active: Bool, activeColor: Color) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(tint)
                .symbolEffect(.bounce, value: active)
            if count > 0 {
                Text("\(count)")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(active ? activeColor : Theme.textSecondary)
                    .contentTransition(.numericText())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(
            Capsule().fill(active ? activeColor.opacity(0.14) : Theme.surface)
        )
        .overlay(
            Capsule().stroke(active ? activeColor.opacity(0.55) : Theme.chrome.opacity(0.35), lineWidth: 1)
        )
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: active)
    }

    /// Up to two latest comments inline (Instagram-style) on an inset card:
    /// tiny avatar + name badge above each comment, then "View all N comments".
    @ViewBuilder
    private var commentPreviewSection: some View {
        if !previewComments.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(previewComments) { c in
                    HStack(alignment: .top, spacing: 8) {
                        previewCommentAvatar(c)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(c.displayName ?? "User")
                                .font(.system(size: 10, weight: .bold))
                                .tracking(0.5)
                                .foregroundStyle(Theme.chrome)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Theme.chrome.opacity(0.12)))
                            Text(c.text)
                                .font(.system(size: 14))
                                .foregroundStyle(Theme.textPrimary)
                                .lineLimit(2)
                        }
                        Spacer(minLength: 0)
                    }
                }
                if post.commentCount > previewComments.count {
                    Text("View all \(post.commentCount) comments")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Theme.surface.opacity(0.6))
            )
            .contentShape(Rectangle())
            .onTapGesture { onCommentTap?() }
            .padding(.horizontal)
            .padding(.bottom, 14)
        }
    }

    private func previewCommentAvatar(_ c: Comment) -> some View {
        let initial = String((c.displayName ?? "?").prefix(1))
        let placeholder = Circle()
            .fill(Theme.chrome)
            .overlay(
                Text(initial.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.onChrome)
            )
        return Group {
            if let urlStr = c.profileImageURL, let url = URL(string: urlStr) {
                CachedProfileImage(url: url, contentMode: .fill) {
                    placeholder
                }
            } else {
                placeholder
            }
        }
        .frame(width: 22, height: 22)
        .clipShape(Circle())
    }

    private var isOwnPost: Bool {
        guard let uid = currentUserFirebaseUid else { return false }
        return post.userId == uid
    }

    private var showEditReviewButton: Bool {
        guard isOwnPost, canEditReview else { return false }
        guard post.type == .finishedBook, post.bookId != nil else { return false }
        return onEditReviewTap != nil
    }

    /// Delete is offered on every own post so orphaned posts stay deletable.
    private var showPostMenu: Bool {
        showEditReviewButton || (isOwnPost && onDeleteTap != nil)
    }

    private var feedAuthorHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            NavigationLink(value: post.userId) {
                HStack(spacing: 10) {
                    HStack(spacing: 2) {
                        feedAvatar
                        ReadingNowFanStack(books: readingNowBooks, coverWidth: 17)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(post.user?.displayName ?? "User")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Theme.textPrimary)
                        Text(Theme.feedRelativeTimestamp(post.createdAt))
                            .font(.system(size: 10, weight: .regular))
                            .tracking(0.5)
                            .foregroundStyle(Theme.chrome)
                    }
                }
            }
            .buttonStyle(.plain)
            Spacer(minLength: 8)
            if showPostMenu {
                Menu {
                    if showEditReviewButton {
                        Button {
                            onEditReviewTap?()
                        } label: {
                            Label("Edit review", systemImage: "pencil")
                        }
                    }
                    if isOwnPost, onDeleteTap != nil {
                        Button(role: .destructive) {
                            onDeleteTap?()
                        } label: {
                            Label("Delete post", systemImage: "trash")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Post options")
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
                    .strokeBorder(Theme.chrome.opacity(0.55), lineWidth: 1)
            )
        } else {
            feedAvatarPlaceholder(initial: initial)
        }
    }

    private func feedAvatarPlaceholder(initial: String) -> some View {
        Circle()
            .fill(Theme.chrome)
            .frame(width: 40, height: 40)
            .overlay(
                Text(initial.uppercased())
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Theme.onChrome)
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
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.chrome)
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
