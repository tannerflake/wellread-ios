//
//  BookProfileView.swift
//  Spine
//
//  Hero book profile — cover front-and-center with a status badge, then airy
//  Hinge-style section cards (review, summary, similar, quote, recommend) with
//  small overline labels. Action bar below uses glossy CTA buttons.
//

import SwiftUI

struct BookProfileView: View {
    @Environment(\.mainTabBarOverlapExtraHeight) private var mainTabBarOverlapExtraHeight

    let book: Book
    /// When provided, we load and show "Similar to" with cute small covers from the user's read list.
    var readBooksForSimilar: [UserBook]? = nil
    var onNotInterested: (() -> Void)? = nil
    var onWantToRead: (() -> Void)? = nil
    /// Called when user confirms "Mark as Read" with (dateFinished, rating out of 10 e.g. 8.8, postToFeed, thoughtsCaption). When set, tapping Read shows the inline modal instead of firing immediately.
    /// (dateFinished, rating, postToFeed, thoughts, tier). Tier nil = Unranked → tier-list "Rank me" prompt.
    var onConfirmRead: ((Date, Double?, Bool, String?, String?) -> Void)? = nil
    /// When set, tapping a similar book opens that book (e.g. sets navigation selection). Used from Discover.
    var onBookTap: ((Book) -> Void)? = nil
    /// True when this book is already on the user's read list (affects Read button appearance).
    var isOnReadList: Bool = false
    /// True when this book is already in the user's queue (affects Queue button appearance).
    var isInQueue: Bool = false
    /// When set (e.g. from Library/Add/Feed), shows "Remove" when isInQueue; when nil (e.g. Discover), Queue button is disabled when isInQueue.
    var onRemoveFromQueue: (() -> Void)? = nil
    /// When set and the entry has review text and/or a rating, shows the first card section (e.g. current user's read row).
    var readEntryForReview: UserBook? = nil
    /// Section title for that card (`"My review"` vs `"Review"` on someone else's profile).
    var reviewSectionHeading: String = "My review"
    /// When `true`, shows a pencil on the review card to edit date, rating, thoughts, feed visibility, or delete.
    var canEditReadReview: Bool = false
    /// Shelf-scoped primary CTA (e.g. "+ READING NOW") shown above the Queue/Read row
    /// when the profile was opened from a shelf's "Add" tile. Hidden if already in queue.
    var shelfActionTitle: String? = nil
    var onAddToShelf: (() -> Void)? = nil
    /// When `false`, hides the "Recommend to a Friend" section. Discover suppresses it
    /// since those are books the user hasn't read yet.
    var showRecommend: Bool = true

    @EnvironmentObject private var appState: AppState

    @State private var summary: String?
    @State private var notableQuote: String?
    @State private var similarBooks: [Book] = []
    @State private var summaryLoading = false
    @State private var quoteLoading = false
    @State private var similarLoading = false
    @State private var showMarkAsReadModal = false
    @State private var profileTags: [String] = []
    @State private var tagsLoading = false
    @State private var userBookToEdit: UserBook? = nil
    // Re-read flow: tapping READ on an already-read book offers to log another read.
    @State private var showRereadPrompt = false
    @State private var showRereadEditPrompt = false
    @State private var showRefresher = false
    @State private var showSummaryMore = false
    @State private var matchScore: Int? = nil
    // "Why you might like it" — only for books scoring above 50% match.
    @State private var whyLikeText: String? = nil
    @State private var whyLikeLoading = false

    // Recommend-to-a-friend section
    private struct RecommendReader: Identifiable {
        var id: String { uid }
        let uid: String
        let user: User
    }
    // "Read by" section — followed readers who've finished this book.
    private struct ReadByReader: Identifiable {
        var id: String { uid }
        let uid: String
        let user: User
        let entry: UserBook
    }
    @State private var readByReaders: [ReadByReader] = []

    @State private var recommendReaders: [RecommendReader] = []
    @State private var recommendLoading = false
    @State private var recommendSendingTo: Set<String> = []
    @State private var recommendSentTo: Set<String> = []
    @State private var showInviteCompose = false
    @State private var cantSendTextAlert = false

    private var showActionBar: Bool {
        onNotInterested != nil || onWantToRead != nil || onConfirmRead != nil || onRemoveFromQueue != nil || onAddToShelf != nil
    }

    private var showShelfAction: Bool {
        shelfActionTitle != nil && onAddToShelf != nil && !isInQueue
    }

    /// Refresher is only offered for books the user has finished — that's the
    /// whole premise (full-spoiler recap), and it keeps the AI cost gated.
    private var hasReadBook: Bool {
        if isOnReadList { return true }
        if readEntryForReview?.status == .read { return true }
        return appState.userBooks.contains { $0.bookId == book.id && $0.status == .read }
    }

    /// Show review card when this read row has review text and/or a tier.
    private var showReviewSection: Bool {
        guard let ub = readEntryForReview else { return false }
        guard ub.status == .read else { return false }
        let trimmed = ub.reviewText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let hasText = !trimmed.isEmpty
        let hasTier = ub.tier != nil
        return hasText || hasTier
    }

    /// Hide the Notable Quote card entirely when no quote was found. Still shown while loading.
    private var shouldShowQuoteCard: Bool {
        if quoteLoading { return true }
        let trimmed = notableQuote?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !trimmed.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {

                    hero

                    if showReviewSection, let ub = readEntryForReview {
                        reviewWindow(ub: ub)
                            .padding(.horizontal)
                        recommendSection
                    }

                    if !readByReaders.isEmpty {
                        readByWindow
                            .padding(.horizontal)
                    }

                    if hasReadBook {
                        refresherWindow
                            .padding(.horizontal)
                    }

                    summaryWindow
                        .padding(.horizontal)

                    if !showReviewSection {
                        recommendSection
                    }

                    if !readBooksForSimilar.isEmptyOrNil && (similarLoading || !similarBooks.isEmpty) {
                        similarWindow
                            .padding(.horizontal)
                    }

                    if let match = matchScore, match > 50, whyLikeLoading || whyLikeText != nil {
                        whyLikeWindow(match)
                            .padding(.horizontal)
                    }

                    if shouldShowQuoteCard {
                        quoteWindow
                            .padding(.horizontal)
                    }
                }
                // Extra room when the floating action bar is up, so the last card
                // can scroll clear of the buttons.
                .padding(.bottom, showActionBar ? 108 : 32)
            }
            .background(Theme.background)
        }
        // Blackbird-style: the buttons float over the scrolling page — no panel,
        // no divider — so the content area runs the full height.
        .overlay(alignment: .bottom) {
            if showActionBar {
                actionBar
            }
        }
        .padding(.bottom, mainTabBarOverlapExtraHeight)
        .background(Theme.background)
        .overlay {
            MarkAsReadInlineOverlay(isPresented: $showMarkAsReadModal) { date, rating, post, thoughts, tier in
                onConfirmRead?(date, rating, post, thoughts, tier)
            }
        }
        .sheet(item: $userBookToEdit) { ub in
            EditReadReviewSheet(userBook: ub)
                .environmentObject(appState)
        }
        .sheet(isPresented: $showRefresher) {
            BookRefresherView(book: book)
        }
        .sheet(isPresented: $showSummaryMore) {
            BookSummaryMoreView(book: book)
        }
        .sheet(isPresented: $showInviteCompose) {
            MessageComposeView(recipients: [], body: AppLinks.inviteMessage(bookTitle: book.title))
                .ignoresSafeArea()
        }
        .alert("Did you read this book again?", isPresented: $showRereadPrompt) {
            Button("Yes") { logReread() }
            Button("No", role: .cancel) {}
        } message: {
            Text(rereadLogMessage)
        }
        .alert("Added. Would you like to edit your review?", isPresented: $showRereadEditPrompt) {
            Button("Yes") {
                if let ub = currentUserReadEntry { userBookToEdit = ub }
            }
            Button("No", role: .cancel) {}
        }
        .alert("Can't send texts", isPresented: $cantSendTextAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("This device can't send text messages. You can still share SPINE from the App Store: \(AppLinks.appStore)")
        }
        .navigationBarTitleDisplayMode(.inline)
        .task(id: book.id) {
            recommendSendingTo = []
            recommendSentTo = []
            readByReaders = []
            matchScore = nil
            whyLikeText = nil
            whyLikeLoading = false
            if let myUid = appState.authUserId {
                let following = Set(appState.currentUser?.following ?? [])
                if !following.isEmpty {
                    let bookId = book.id
                    Task {
                        let entries = await UserBookRepository().fetchReadEntries(bookId: bookId)
                        var seen = Set<String>()
                        let followed = entries.filter {
                            $0.userId != myUid && following.contains($0.userId) && seen.insert($0.userId).inserted
                        }
                        guard !followed.isEmpty else { return }
                        let repo = UserRepository()
                        var readers: [ReadByReader] = []
                        for entry in followed {
                            if let user = await repo.getUser(uid: entry.userId) {
                                readers.append(ReadByReader(uid: entry.userId, user: user, entry: entry))
                            }
                        }
                        let sorted = readers.sorted {
                            ($0.entry.dateFinished ?? .distantPast) > ($1.entry.dateFinished ?? .distantPast)
                        }
                        await MainActor.run {
                            guard bookId == book.id else { return }
                            readByReaders = sorted
                            refreshMatchScore()
                        }
                    }
                }
            }
            if showRecommend && appState.authUserId != nil && recommendReaders.isEmpty {
                recommendLoading = true
                Task {
                    let list = await UserRepository().fetchAllReaderProfiles(excludingUid: appState.authUserId, limit: 500)
                    recommendReaders = list.map { RecommendReader(uid: $0.uid, user: $0.user) }
                    recommendLoading = false
                }
            }

            profileTags = []
            tagsLoading = true
            summaryLoading = true
            quoteLoading = true

            async let tagsTask = BookProfileService.shared.profileTags(for: book)
            async let summaryTask = BookProfileService.shared.twoSentenceSummary(for: book)
            async let quoteTask = BookProfileService.shared.notableQuote(for: book)

            let (tags, sum, quote) = await (tagsTask, summaryTask, quoteTask)
            profileTags = tags
            tagsLoading = false
            refreshMatchScore()
            summary = sum
            summaryLoading = false
            notableQuote = quote
            quoteLoading = false

            if let read = readBooksForSimilar, !read.isEmpty {
                similarLoading = true
                similarBooks = await BookProfileService.shared.similarBooks(for: book, readBooks: read)
                similarLoading = false
            }
        }
    }

    // MARK: - Hero

    /// Badge label + color for the current user's status with this book.
    /// `nil` (no relationship) → no badge.
    private var statusBadge: (label: String, color: Color)? {
        guard let ub = appState.userBooks.first(where: { $0.bookId == book.id }) else { return nil }
        switch ub.status {
        case .read:
            return ("READ", Theme.chrome)
        case .currentlyReading:
            return ("READING NOW", Theme.punch)
        case .wantToRead:
            switch ub.queueShelf {
            case .readingNow: return ("READING NOW", Theme.punch)
            case .upNext: return ("UP NEXT", Theme.accent)
            case .backlog, nil: return ("BACKLOG", Theme.chromeStrong)
            }
        }
    }

    private var hero: some View {
        VStack(spacing: 14) {
            BookCoverView(book: book, size: 220)
                .shadow(color: Theme.shadowInk.opacity(0.18), radius: 14, x: 0, y: 6)
                .overlay(alignment: .topTrailing) {
                    if let badge = statusBadge {
                        Text(badge.label)
                            .font(.system(size: 11, weight: .bold))
                            .tracking(0.8)
                            .foregroundStyle(Theme.onChrome)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(badge.color))
                            .overlay(Capsule().stroke(Theme.onChrome.opacity(0.85), lineWidth: 1.5))
                            .rotationEffect(.degrees(6))
                            .shadow(color: Theme.shadowInk.opacity(0.25), radius: 4, x: 0, y: 2)
                            .offset(x: 14, y: -10)
                    }
                }
                .overlay(alignment: .bottomLeading) {
                    if !readByReaders.isEmpty {
                        readByAvatarFan
                            .offset(x: -14, y: 12)
                    }
                }

            VStack(spacing: 4) {
                Text(book.title)
                    .font(Theme.title())
                    .tracking(Theme.displayTracking)
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)

                Text(book.author)
                    .font(Theme.callout())
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)

                if let published = book.publishedDate {
                    Text(Self.publishedYearFormatter.string(from: published))
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(Theme.textTertiary)
                }

                if let match = matchScore {
                    matchBadge(match)
                        .padding(.top, 4)
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
            }
            .padding(.horizontal, 24)

            BrandRule(width: 44)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
    }

    // MARK: - Match score

    /// Monochrome match ramp — strong matches get full ink, weak ones fade toward the page.
    private func matchColor(_ score: Int) -> Color {
        if score >= 80 { return Theme.chrome }
        if score >= 60 { return Theme.textSecondary }
        return Theme.textTertiary
    }

    private func matchBadge(_ score: Int) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "sparkles")
                .font(.system(size: 10, weight: .bold))
            Text("\(score)% MATCH")
                .font(.system(size: 12, weight: .bold))
                .tracking(0.8)
        }
        .foregroundStyle(matchColor(score))
        .accessibilityLabel("\(score) percent match for you")
    }

    /// Recomputes the % match. Called once profile tags land and again when
    /// followed readers' entries arrive, so the score refines as data loads.
    private func refreshMatchScore() {
        let bookId = book.id
        let tags = profileTags
        let friendEntries = readByReaders.map(\.entry)
        let library = appState.userBooks
        let user = appState.currentUser
        Task {
            let score = await MatchScoreService.shared.matchScore(
                for: book,
                profileTags: tags,
                library: library,
                user: user,
                friendEntries: friendEntries
            )
            await MainActor.run {
                guard bookId == book.id else { return }
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    matchScore = score
                }
                if let score, score > 50 {
                    loadWhyLike()
                }
            }
        }
    }

    // MARK: - Why you might like it

    /// Generates the personalized blurb once the match clears 50%. Guarded so
    /// the second match refresh (when friend entries land) doesn't double-fire.
    private func loadWhyLike() {
        guard whyLikeText == nil, !whyLikeLoading else { return }
        whyLikeLoading = true
        let bookId = book.id
        let library = appState.userBooks
        let user = appState.currentUser
        Task {
            let text = await BookProfileService.shared.whyYouMightLikeIt(for: book, library: library, user: user)
            await MainActor.run {
                guard bookId == book.id else { return }
                whyLikeText = text
                whyLikeLoading = false
            }
        }
    }

    /// Match-branded card: same sparkles + ink-ramp imagery as the hero badge,
    /// with the % match echoed in the title row.
    private func whyLikeWindow(_ score: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if whyLikeLoading {
                phosphorLoader(label: "reading your taste")
            } else if let t = whyLikeText, !t.isEmpty {
                Text(t)
                    .font(Theme.body())
                    .foregroundStyle(Theme.textPrimary)
                    .lineSpacing(Theme.bodyLineSpacing)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .hingeSectionCard(title: "Why You Might Like It", accent: matchColor(score)) {
            matchBadge(score)
        }
    }

    // MARK: - Review window

    private func reviewWindow(ub: UserBook) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let text = ub.reviewText?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                Text(text)
                    .font(Theme.body())
                    .foregroundStyle(Theme.textPrimary)
                    .lineSpacing(Theme.bodyLineSpacing)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !ub.allReadDates.isEmpty {
                reviewFooter(ub: ub)
            }
        }
        .hingeSectionCard(title: reviewSectionHeading) {
            if canEditReadReview {
                Button {
                    userBookToEdit = ub
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(-6)
            }
        } titleAccessory: {
            if let t = ub.tier {
                TierBadge(tier: t, size: .mini)
            }
        }
    }

    /// Read date(s), every recorded read, so re-reads are visible.
    private func reviewFooter(ub: UserBook) -> some View {
        let dates = ub.allReadDates
        return (
            Text(dates.count > 1 ? "read \u{00D7}\(dates.count): " : "read: ")
                .foregroundColor(Theme.chrome)
            + Text(dates.map { Self.readDateFormatter.string(from: $0) }.joined(separator: " \u{00B7} "))
                .foregroundColor(Theme.textTertiary)
        )
        .font(.system(size: 12, weight: .medium))
        .fixedSize(horizontal: false, vertical: true)
    }

    private static let readDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy"
        return f
    }()

    // MARK: - Re-read flow

    /// The current user's read row for this book (nil when it's not on their shelf).
    private var currentUserReadEntry: UserBook? {
        appState.userBooks.first { $0.bookId == book.id && $0.status == .read }
    }

    /// Existing read logs shown in the "Did you read this book again?" prompt.
    private var rereadLogMessage: String {
        let dates = (currentUserReadEntry?.allReadDates ?? []).sorted(by: >)
        guard !dates.isEmpty else { return "It's already on your read shelf." }
        let list = dates.map { Self.readDateFormatter.string(from: $0) }.joined(separator: "\n")
        return "You've read it \(dates.count == 1 ? "once" : "\(dates.count) times"):\n\(list)"
    }

    /// Log today as another read of this book, then offer the review editor.
    private func logReread() {
        Task {
            await appState.mergeGoodreadsReReadDate(book: book, dateRead: Date())
            showRereadEditPrompt = true
        }
    }

    private static let publishedYearFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy"
        return f
    }()

    // MARK: - Refresher window

    /// Read-books-only card: one tap opens the AI refresher sheet (recap + Q&A).
    private var refresherWindow: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Read it a while ago? Get a recap of the plot, characters, and takeaways — then ask follow-up questions.")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(Theme.textSecondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                showRefresher = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 13, weight: .semibold))
                    Text("REFRESH MY MEMORY")
                        .font(.system(size: 13, weight: .bold))
                        .tracking(1)
                }
                .foregroundStyle(Theme.background)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: Theme.cardCornerRadius)
                        .fill(Theme.gloss(Theme.accent))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.cardCornerRadius)
                        .strokeBorder(
                            LinearGradient(
                                colors: [Theme.phosphorWhite.opacity(0.45), Theme.phosphorWhite.opacity(0.04)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(color: Theme.accent.opacity(0.32), radius: 8, x: 0, y: 3)
            }
            .buttonStyle(.springPress)
        }
        .hingeSectionCard(title: "Refresher", accent: Theme.accent)
    }

    // MARK: - Summary window

    private var summaryWindow: some View {
        VStack(alignment: .leading, spacing: 12) {
            if summaryLoading {
                phosphorLoader(label: "loading summary")
            } else if let s = summary, !s.isEmpty {
                Text(s)
                    .font(Theme.body())
                    .foregroundStyle(Theme.textPrimary)
                    .lineSpacing(Theme.bodyLineSpacing)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                emptyState(text: "summary unavailable")
            }

            if tagsLoading {
                phosphorLoader(label: "loading tags", compact: true)
                    .padding(.top, 4)
            } else if !profileTags.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(profileTags, id: \.self) { tag in
                        tagChip(tag)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
            }
        }
        .hingeSectionCard(title: "Summary") {
            Button {
                showSummaryMore = true
            } label: {
                HStack(spacing: 3) {
                    Text("MORE")
                        .font(.system(size: 11, weight: .bold))
                        .tracking(1.2)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                }
                .foregroundStyle(Theme.chrome)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("More about this book")
        }
    }

    private func tagChip(_ tag: String) -> some View {
        Text(tag.lowercased())
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.4)
            .foregroundStyle(Theme.chrome)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Theme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Theme.chrome.opacity(0.5), lineWidth: 1)
            )
    }

    // MARK: - Similar window

    private var similarWindow: some View {
        VStack(alignment: .leading, spacing: 12) {
            if similarLoading {
                HStack(spacing: 12) {
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Theme.surface)
                            .frame(width: 52, height: 52 * 1.5)
                            .overlay(
                                Image(systemName: "book.closed")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(Theme.chrome.opacity(0.5))
                            )
                    }
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 14) {
                        ForEach(similarBooks) { similar in
                            VStack(spacing: 6) {
                                BookCoverView(book: similar, size: 52, onTap: onBookTap != nil ? { onBookTap?(similar) } : nil)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                Text(similar.title)
                                    .font(.system(size: 10, weight: .regular))
                                    .foregroundStyle(Theme.textSecondary)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.center)
                                    .frame(width: 64)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .hingeSectionCard(title: "Similar Books")
    }

    // MARK: - Quote window

    private var quoteWindow: some View {
        VStack(alignment: .leading, spacing: 12) {
            if quoteLoading {
                phosphorLoader(label: "loading quote")
            } else if let q = notableQuote, !q.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Text("\u{201C}")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(Theme.chrome)
                        .offset(y: -2)
                        .accessibilityHidden(true)
                    Text(q)
                        .font(Theme.body())
                        .italic()
                        .foregroundStyle(Theme.textPrimary)
                        .lineSpacing(Theme.bodyLineSpacing)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                emptyState(text: "no notable quote available")
            }
        }
        .hingeSectionCard(title: "Notable Quote", accent: Theme.chromeStrong)
    }

    // MARK: - Read by window

    /// Fanned avatars hanging off the cover's bottom-left corner — the readers
    /// the user follows who've finished this book. Mirrors ReadingNowFanStack.
    private var readByAvatarFan: some View {
        let shown = readByReaders.prefix(3)
        let overflow = readByReaders.count - shown.count
        return HStack(spacing: -12) {
            ForEach(Array(shown.enumerated()), id: \.element.id) { index, reader in
                readerAvatar(user: reader.user, size: 34)
                    .overlay(Circle().stroke(Theme.background, lineWidth: 2))
                    .shadow(color: Theme.shadowInk.opacity(0.25), radius: 3, x: 0, y: 2)
                    .zIndex(Double(shown.count - index))
            }
            if overflow > 0 {
                Text("+\(overflow)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.onChrome)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Theme.chromeStrong))
                    .overlay(Circle().stroke(Theme.background, lineWidth: 2))
                    .shadow(color: Theme.shadowInk.opacity(0.25), radius: 3, x: 0, y: 2)
            }
        }
    }

    private var readByWindow: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(Array(readByReaders.enumerated()), id: \.element.id) { index, reader in
                readByRow(reader)
                if index < readByReaders.count - 1 {
                    Rectangle()
                        .fill(Theme.chrome.opacity(0.18))
                        .frame(height: Theme.chromeHairline)
                }
            }
        }
        .hingeSectionCard(title: "Read by")
    }

    private func readByRow(_ reader: ReadByReader) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                readerAvatar(user: reader.user, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(reader.user.displayName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    if let finished = reader.entry.dateFinished {
                        Text("read \(Self.readDateFormatter.string(from: finished))")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
                Spacer(minLength: 8)
                if let t = reader.entry.tier {
                    TierBadge(tier: t, size: .mini)
                }
            }
            if let text = reader.entry.reviewText?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                Text(text)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(Theme.textSecondary)
                    .lineSpacing(Theme.bodyLineSpacing)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Recommend window

    /// Windowed section (below My Review, or Summary when there's no review):
    /// tap a reader to send them this book, or the dashed tile to text an
    /// invite to someone who isn't on Spine yet.
    @ViewBuilder
    private var recommendSection: some View {
        if showRecommend, appState.authUserId != nil {
            recommendWindow
                .padding(.horizontal)
        }
    }

    private var recommendWindow: some View {
        VStack(alignment: .leading, spacing: 12) {
            if recommendLoading {
                phosphorLoader(label: "loading readers")
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 14) {
                        ForEach(recommendReaders) { reader in
                            recommendReaderTile(reader)
                        }
                        inviteTile
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .hingeSectionCard(title: "Recommend to a Friend")
    }

    private func recommendReaderTile(_ reader: RecommendReader) -> some View {
        let sent = recommendSentTo.contains(reader.uid)
        let sending = recommendSendingTo.contains(reader.uid)
        return Button {
            sendRecommendation(to: reader)
        } label: {
            VStack(spacing: 6) {
                readerAvatar(user: reader.user)
                    .opacity(sending || sent ? 0.55 : 1)
                    .overlay(alignment: .bottomTrailing) {
                        if sent {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(Theme.accent)
                                .background(Circle().fill(Theme.background))
                                .offset(x: 3, y: 3)
                        }
                    }
                    .overlay {
                        if sending {
                            ProgressView().tint(Theme.accent)
                        }
                    }
                Text(reader.user.displayName)
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(sent ? Theme.textTertiary : Theme.textSecondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(width: 64)
            }
        }
        .buttonStyle(.plain)
        .disabled(sent || sending)
    }

    private var inviteTile: some View {
        Button {
            if MessageComposeView.canSendText {
                showInviteCompose = true
            } else {
                cantSendTextAlert = true
            }
        } label: {
            VStack(spacing: 6) {
                Circle()
                    .fill(Theme.surface)
                    .frame(width: 52, height: 52)
                    .overlay(
                        Image(systemName: "plus.message")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Theme.chrome)
                    )
                    .overlay(
                        Circle()
                            .stroke(Theme.chrome.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    )
                Text("invite via text")
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(width: 64)
            }
        }
        .buttonStyle(.plain)
    }

    private func readerAvatar(user: User, size: CGFloat = 52) -> some View {
        ZStack {
            if let urlString = user.profileImageURL, let url = URL(string: urlString) {
                CachedProfileImage(url: url, contentMode: .fill) {
                    initialCircle(user.displayName, size: size)
                }
            } else {
                initialCircle(user.displayName, size: size)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private func initialCircle(_ name: String, size: CGFloat = 52) -> some View {
        Circle()
            .fill(Theme.chrome)
            .overlay(
                Text(String(name.prefix(1)).uppercased())
                    .font(.system(size: size * 0.38, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.onChrome)
            )
    }

    private func sendRecommendation(to reader: RecommendReader) {
        guard let fromUid = appState.authUserId else { return }
        recommendSendingTo.insert(reader.uid)
        Task {
            do {
                _ = try await RecommendationRepository().send(
                    fromUserId: fromUid,
                    toUserId: reader.uid,
                    book: book,
                    note: nil
                )
                await MainActor.run {
                    recommendSendingTo.remove(reader.uid)
                    recommendSentTo.insert(reader.uid)
                    ToastCenter.shared.show(.recommendationSent(to: reader.user.displayName))
                }
            } catch {
                await MainActor.run {
                    recommendSendingTo.remove(reader.uid)
                    ToastCenter.shared.show(
                        Toast(style: .error, status: "Failed", message: "Couldn't send to \(reader.user.displayName)")
                    )
                }
            }
        }
    }

    // MARK: - Loading / empty helpers

    private func phosphorLoader(label: String, compact: Bool = false) -> some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(compact ? .mini : .small)
                .tint(Theme.chrome)
            Text(label)
                .font(.system(size: compact ? 11 : 13, weight: .regular))
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, compact ? 0 : 8)
    }

    private func emptyState(text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .regular))
            .tracking(0.5)
            .foregroundStyle(Theme.textTertiary)
    }

    // MARK: - Action bar

    private var actionBar: some View {
        VStack(spacing: 10) {
            if showShelfAction, let title = shelfActionTitle {
                Button(action: { onAddToShelf?() }) {
                    actionLabel(title, foreground: Theme.background, background: Theme.accent, border: .clear)
                }
                .buttonStyle(.springPress)
            }
            actionButtonRow
        }
        .padding(.horizontal)
        .padding(.top, 10)
        // No panel or divider behind the buttons (Blackbird-style): they float
        // over the page, which reads as more usable screen. The buttons' own
        // fills and shadows carry the separation.
        .padding(.bottom, 14)
    }

    private var actionButtonRow: some View {
        HStack(spacing: 10) {
            if onNotInterested != nil {
                Button(action: { onNotInterested?() }) {
                    actionLabel("PASS", foreground: Theme.textSecondary, background: Theme.surface, border: Theme.chrome.opacity(0.5))
                }
                .buttonStyle(.springPress)
            }
            if onConfirmRead != nil {
                Button(action: {
                    if isOnReadList {
                        showRereadPrompt = true
                        return
                    }
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { showMarkAsReadModal = true }
                }) {
                    actionLabel(
                        isOnReadList ? "READ \u{2714}" : "READ",
                        foreground: isOnReadList ? Theme.background : Theme.queueTintLabel,
                        background: isOnReadList ? Theme.textTertiary : Theme.queueTint,
                        border: .clear
                    )
                }
                .buttonStyle(.springPress)
            }
            if onWantToRead != nil || onRemoveFromQueue != nil {
                Group {
                    if isInQueue && onRemoveFromQueue != nil {
                        Button(action: { onRemoveFromQueue?() }) {
                            actionLabel("REMOVE", foreground: Theme.phosphorWhite, background: Theme.danger, border: .clear)
                        }
                        .buttonStyle(.springPress)
                    } else if isInQueue {
                        Button {} label: {
                            actionLabel("IN QUEUE", foreground: Theme.textTertiary, background: Theme.surface, border: Theme.chrome.opacity(0.3))
                        }
                        .buttonStyle(.springPress)
                        .disabled(true)
                    } else {
                        Button(action: { onWantToRead?() }) {
                            // When a shelf CTA is the primary action, QUEUE steps down to an
                            // outline style so there's a single clear main button.
                            actionLabel(
                                "QUEUE",
                                foreground: showShelfAction ? Theme.textSecondary : Theme.background,
                                background: showShelfAction ? Theme.surface : Theme.accent,
                                border: showShelfAction ? Theme.chrome.opacity(0.5) : .clear
                            )
                        }
                        .buttonStyle(.springPress)
                    }
                }
            }
        }
    }

    private func actionLabel(_ text: String, foreground: Color, background: Color, border: Color) -> some View {
        Text(text)
            .font(.system(size: 14, weight: .bold))
            .tracking(1)
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius)
                    .fill(Theme.gloss(background))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Theme.phosphorWhite.opacity(0.45), Theme.phosphorWhite.opacity(0.04)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius)
                    .stroke(border, lineWidth: 1)
            )
            .shadow(color: background.opacity(0.32), radius: 8, x: 0, y: 3)
    }
}

private extension Optional where Wrapped == [UserBook] {
    var isEmptyOrNil: Bool {
        self == nil || self?.isEmpty == true
    }
}
