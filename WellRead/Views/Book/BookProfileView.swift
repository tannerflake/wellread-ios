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

    // Recommend-to-a-friend section
    private struct RecommendReader: Identifiable {
        var id: String { uid }
        let uid: String
        let user: User
    }
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

                    summaryWindow
                        .padding(.horizontal)

                    if !showReviewSection {
                        recommendSection
                    }

                    if !readBooksForSimilar.isEmptyOrNil && (similarLoading || !similarBooks.isEmpty) {
                        similarWindow
                            .padding(.horizontal)
                    }

                    if shouldShowQuoteCard {
                        quoteWindow
                            .padding(.horizontal)
                    }
                }
                .padding(.bottom, 32)
            }
            .background(Theme.background)

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
        .sheet(isPresented: $showInviteCompose) {
            MessageComposeView(recipients: [], body: AppLinks.inviteMessage(bookTitle: book.title))
                .ignoresSafeArea()
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
            return ("READ", Theme.chromeTeal)
        case .currentlyReading:
            return ("READING NOW", Theme.magentaPunch)
        case .wantToRead:
            switch ub.queueShelf {
            case .readingNow: return ("READING NOW", Theme.magentaPunch)
            case .upNext: return ("UP NEXT", Theme.accent)
            case .backlog, nil: return ("BACKLOG", Theme.chromeNavy)
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
                            .foregroundStyle(Theme.phosphorWhite)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(badge.color))
                            .overlay(Capsule().stroke(Theme.phosphorWhite.opacity(0.85), lineWidth: 1.5))
                            .rotationEffect(.degrees(6))
                            .shadow(color: Theme.shadowInk.opacity(0.25), radius: 4, x: 0, y: 2)
                            .offset(x: 14, y: -10)
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
            }
            .padding(.horizontal, 24)

            BrandRule(width: 44)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
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
                .foregroundColor(Theme.chromeTeal)
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

    private static let publishedYearFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy"
        return f
    }()

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
        .hingeSectionCard(title: "Summary")
    }

    private func tagChip(_ tag: String) -> some View {
        Text(tag.lowercased())
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.4)
            .foregroundStyle(Theme.chromeTeal)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Theme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Theme.chromeTeal.opacity(0.5), lineWidth: 1)
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
                                    .foregroundStyle(Theme.chromeTeal.opacity(0.5))
                            )
                    }
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
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
                        .foregroundStyle(Theme.chromeTeal)
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
        .hingeSectionCard(title: "Notable Quote", accent: Theme.chromeNavy)
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
                            .foregroundStyle(Theme.chromeTeal)
                    )
                    .overlay(
                        Circle()
                            .stroke(Theme.chromeTeal.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
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

    private func readerAvatar(user: User) -> some View {
        ZStack {
            if let urlString = user.profileImageURL, let url = URL(string: urlString) {
                CachedProfileImage(url: url, contentMode: .fill) {
                    initialCircle(user.displayName)
                }
            } else {
                initialCircle(user.displayName)
            }
        }
        .frame(width: 52, height: 52)
        .clipShape(Circle())
    }

    private func initialCircle(_ name: String) -> some View {
        Circle()
            .fill(Theme.chromeTeal)
            .overlay(
                Text(String(name.prefix(1)).uppercased())
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.phosphorWhite)
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
                .tint(Theme.chromeTeal)
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
        .padding(.top, 18)
        .padding(.bottom, 18)
        .background(
            VStack(spacing: 0) {
                Rectangle()
                    .fill(Theme.chromeTeal.opacity(0.45))
                    .frame(height: Theme.chromeHairline)
                Theme.background
            }
        )
        .padding(.bottom, 12)
    }

    private var actionButtonRow: some View {
        HStack(spacing: 10) {
            if onNotInterested != nil {
                Button(action: { onNotInterested?() }) {
                    actionLabel("PASS", foreground: Theme.textSecondary, background: Theme.surface, border: Theme.chromeTeal.opacity(0.5))
                }
                .buttonStyle(.springPress)
            }
            if onWantToRead != nil || onRemoveFromQueue != nil {
                Group {
                    if isInQueue && onRemoveFromQueue != nil {
                        Button(action: { onRemoveFromQueue?() }) {
                            actionLabel("REMOVE", foreground: Theme.phosphorWhite, background: Color(red: 0.86, green: 0.32, blue: 0.30), border: .clear)
                        }
                        .buttonStyle(.springPress)
                    } else if isInQueue {
                        Button {} label: {
                            actionLabel("IN QUEUE", foreground: Theme.textTertiary, background: Theme.surface, border: Theme.chromeTeal.opacity(0.3))
                        }
                        .buttonStyle(.springPress)
                        .disabled(true)
                    } else {
                        Button(action: { onWantToRead?() }) {
                            actionLabel("QUEUE", foreground: Theme.queuePowderBlueLabel, background: Theme.queuePowderBlue, border: .clear)
                        }
                        .buttonStyle(.springPress)
                    }
                }
            }
            if onConfirmRead != nil {
                Button(action: {
                    if isOnReadList { return }
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { showMarkAsReadModal = true }
                }) {
                    // When a shelf CTA is the primary action, READ steps down to an outline
                    // style so there's a single clear main button.
                    actionLabel(
                        isOnReadList ? "READ \u{2714}" : "READ",
                        foreground: isOnReadList
                            ? Theme.background
                            : (showShelfAction ? Theme.textSecondary : Theme.background),
                        background: isOnReadList
                            ? Theme.textTertiary
                            : (showShelfAction ? Theme.surface : Theme.accent),
                        border: showShelfAction && !isOnReadList ? Theme.chromeTeal.opacity(0.5) : .clear
                    )
                }
                .buttonStyle(.springPress)
                .disabled(isOnReadList)
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
