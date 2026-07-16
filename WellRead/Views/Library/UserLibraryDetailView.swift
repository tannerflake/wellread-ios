//
//  UserLibraryDetailView.swift
//  WellRead
//
//  Another member's library (read-only): same layout as Profile tab, opened from Feed.
//

import SwiftUI
import FirebaseFirestore

struct UserLibraryDetailView: View {
    let userId: String

    @EnvironmentObject var authService: AuthService
    @EnvironmentObject var appState: AppState

    private let userBookRepo = UserBookRepository()
    private let userRepo = UserRepository()

    @State private var profileUser: User?
    @State private var books: [UserBook] = []
    @State private var booksListener: ListenerRegistration?
    @State private var segment: LibraryReadQueueTab = .read
    @State private var selectedYear: Int? = nil
    @State private var selectedBookForProfile: Book? = nil
    @State private var iFollowThem: Bool = false
    @State private var followActionInFlight = false

    // Book Blend: live pair-doc state drives the entry button; the landing
    // screen handles invite / waiting / story routing.
    @State private var blend: BookBlend?
    @State private var blendListener: ListenerRegistration?
    @State private var blendRequestInFlight = false
    @State private var showBlendLanding = false

    private var readBooks: [UserBook] {
        books.filter { $0.status == .read }
    }

    private var wantToReadList: [UserBook] {
        books.filter { $0.status == .wantToRead }
    }

    private var wantToReadReadingNow: [UserBook] {
        wantToReadList
            .filter { $0.queueShelf == .readingNow }
            .sorted { ($0.queueOrder ?? 999) < ($1.queueOrder ?? 999) }
    }

    private var wantToReadUpNext: [UserBook] {
        wantToReadList
            .filter { $0.queueShelf == .upNext }
            .sorted { ($0.queueOrder ?? 999) < ($1.queueOrder ?? 999) }
    }

    private var wantToReadBacklog: [UserBook] {
        let backlog = wantToReadList.filter { $0.queueShelf == nil || $0.queueShelf == .backlog }
        return Self.sortedBacklog(backlog)
    }

    private static func sortedBacklog(_ books: [UserBook]) -> [UserBook] {
        let explicit = books.filter { $0.queueOrder != nil }.sorted { $0.queueOrder! < $1.queueOrder! }
        let implicit = books.filter { $0.queueOrder == nil }.sorted { $0.updatedAt > $1.updatedAt }
        return explicit + implicit
    }

    private var readBooksFilteredByYear: [UserBook] {
        guard let year = selectedYear else { return readBooks }
        return readBooks.filter { $0.wasRead(inYear: year) }
    }

    private var availableYears: [Int] {
        let years = Set(readBooks.flatMap { ub in
            ub.allReadDates.map { Calendar.current.component(.year, from: $0) }
        })
        return years.sorted(by: >)
    }

    private var libraryTitle: String {
        guard let u = profileUser else { return "Library" }
        return Theme.possessiveLibraryTitleFirstNameOnly(user: u)
    }

    private var calendarYear: Int {
        Calendar.current.component(.year, from: Date())
    }

    /// Books with any read date in the current calendar year (re-reads count toward each year's goal).
    private var booksFinishedThisCalendarYear: Int {
        readBooks.filter { $0.wasRead(inYear: calendarYear) }.count
    }

    private var activeReadingGoal: Int? {
        guard let g = profileUser?.readingGoal, g > 0 else { return nil }
        return g
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack(alignment: .center, spacing: 12) {
                    followToggleButton

                    otherUserSegmentControl
                        .frame(maxWidth: .infinity)

                    if !availableYears.isEmpty {
                        yearFilterInline
                    }
                }
                .padding(.vertical, 10)

                if let me = authService.firebaseUser?.uid, me != userId {
                    BookBlendEntryButton(
                        state: blendEntryState(myUid: me),
                        otherFirstName: profileUser?.firstName ?? "They",
                        action: { handleBlendButtonTap(myUid: me) }
                    )
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                }

                if let goal = activeReadingGoal {
                    LibraryReadingGoalProgressStrip(
                        calendarYear: calendarYear,
                        booksRead: booksFinishedThisCalendarYear,
                        goal: goal,
                        copy: .other(displayFirstName: profileUser?.firstName)
                    )
                    .padding(.bottom, 4)
                }

                libraryContent
            }
            .padding(.horizontal, 4)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.background, for: .navigationBar)
        .toolbar { libraryToolbar }
        .navigationDestination(item: $selectedBookForProfile) { book in
            BookProfileView(
                book: book,
                readBooksForSimilar: appState.readBooks,
                onNotInterested: nil,
                onWantToRead: { appState.addToWantToRead(book: book); selectedBookForProfile = nil },
                onConfirmRead: { date, rating, post, caption, tier in
                    appState.addAsRead(book: book, dateFinished: date, rating: rating, postToFeed: post, caption: caption, tier: tier)
                    selectedBookForProfile = nil
                },
                isOnReadList: appState.isBookOnReadList(bookId: book.id),
                isInQueue: appState.isBookInQueue(bookId: book.id),
                onRemoveFromQueue: { appState.removeFromQueue(book: book); selectedBookForProfile = nil },
                readEntryForReview: books.first(where: { $0.bookId == book.id && $0.status == .read }),
                reviewSectionHeading: "Review"
            )
        }
        .onAppear {
            Task {
                profileUser = await userRepo.getUser(uid: userId)
                await refreshIFollowState()
            }
            booksListener = userBookRepo.listenUserBooks(userId: userId) { list in
                books = list
            }
            startBlendListener()
        }
        .onChange(of: authService.firebaseUser?.uid) { _, _ in
            Task { await refreshIFollowState() }
            blendListener?.remove()
            blendListener = nil
            startBlendListener()
        }
        .onDisappear {
            booksListener?.remove()
            booksListener = nil
            blendListener?.remove()
            blendListener = nil
        }
        .fullScreenCover(isPresented: $showBlendLanding) {
            if let me = authService.firebaseUser?.uid {
                BookBlendLandingView(blendId: BookBlend.pairId(me, userId))
                    .environmentObject(authService)
            }
        }
    }

    // MARK: - Book Blend

    private func startBlendListener() {
        guard let me = authService.firebaseUser?.uid, me != userId, blendListener == nil else { return }
        blendListener = BookBlendService.shared.listenBlend(pairId: BookBlend.pairId(me, userId)) { updated in
            blend = updated
        }
    }

    private func blendEntryState(myUid: String) -> BookBlendEntryState {
        guard let blend else { return .none }
        switch blend.status {
        case .ready: return .ready
        case .declined: return .none
        case .pending: return blend.requesterId == myUid ? .requestedByMe : .invitedMe
        }
    }

    private func handleBlendButtonTap(myUid: String) {
        switch blendEntryState(myUid: myUid) {
        case .none:
            guard !blendRequestInFlight else { return }
            blendRequestInFlight = true
            Task {
                let me = appState.currentUser
                if let requested = try? await BookBlendService.shared.requestBlend(
                    myUid: myUid, me: me, otherUid: userId, other: profileUser
                ) {
                    await MainActor.run { blend = requested }
                }
                await MainActor.run { blendRequestInFlight = false }
            }
        case .requestedByMe:
            break
        case .invitedMe, .ready:
            showBlendLanding = true
        }
    }

    @ToolbarContentBuilder
    private var libraryToolbar: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Text(libraryTitle)
                .font(Theme.title())
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
        }
        // Bare covers + avatar like the own-library header — no glass capsule behind
        // them on iOS 26+ (`sharedBackgroundVisibility` doesn't exist pre-26).
        if #available(iOS 26.0, *) {
            ToolbarItem(placement: .topBarTrailing) {
                fanAndAvatarToolbarContent
            }
            .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .topBarTrailing) {
                fanAndAvatarToolbarContent
            }
        }
    }

    private var fanAndAvatarToolbarContent: some View {
        HStack(spacing: 8) {
            ReadingNowFanStack(
                books: wantToReadReadingNow.compactMap(\.book),
                coverWidth: 20,
                onTap: { selectedBookForProfile = $0 },
                floats: true
            )
            otherUserAvatar
        }
    }

    private var otherUserAvatar: some View {
        Group {
            if let u = profileUser {
                ZStack {
                    if let urlString = u.profileImageURL, let url = URL(string: urlString) {
                        CachedProfileImage(url: url, contentMode: .fill) {
                            avatarPlaceholder(initial: avatarInitial(for: u))
                        }
                    } else {
                        avatarPlaceholder(initial: avatarInitial(for: u))
                    }
                }
                .frame(width: 36, height: 36)
                .clipShape(Circle())
                .allowsHitTesting(false)
            }
        }
    }

    private func avatarInitial(for user: User) -> String {
        if let fn = user.firstName?.trimmingCharacters(in: .whitespacesAndNewlines), let c = fn.first {
            return String(c).uppercased()
        }
        let parts = user.displayName.split(separator: " ")
        if let first = parts.first?.first {
            return String(first).uppercased()
        }
        return String(user.displayName.prefix(1)).uppercased()
    }

    private func avatarPlaceholder(initial: String) -> some View {
        Circle()
            .fill(Theme.surface)
            .overlay(
                Text(initial)
                    .font(Theme.headline())
                    .foregroundStyle(Theme.textSecondary)
            )
    }

    @ViewBuilder
    private var followToggleButton: some View {
        if let me = authService.firebaseUser?.uid, me != userId {
            Button {
                Task { await toggleFollow() }
            } label: {
                Text(iFollowThem ? "Following" : "Follow")
                    .font(Theme.caption())
                    .fontWeight(.semibold)
                    .foregroundStyle(iFollowThem ? Theme.textPrimary : Theme.background)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(iFollowThem ? Theme.surface : Theme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(Theme.textTertiary.opacity(iFollowThem ? 0.35 : 0), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .disabled(followActionInFlight)
        }
    }

    private func refreshIFollowState() async {
        guard let me = authService.firebaseUser?.uid, me != userId else {
            iFollowThem = false
            return
        }
        if let u = await userRepo.getUser(uid: me) {
            iFollowThem = u.following.contains(userId)
        }
    }

    private func toggleFollow() async {
        guard let me = authService.firebaseUser?.uid, me != userId else { return }
        followActionInFlight = true
        defer { followActionInFlight = false }
        let next = !iFollowThem
        do {
            try await userRepo.setFollowing(currentUid: me, targetUid: userId, follow: next)
            iFollowThem = next
            await authService.refreshAppUser()
            WidgetDataService.shared.scheduleRefresh(appState: appState, delay: 1.0, forceFriendRefresh: true)
        } catch {
            await refreshIFollowState()
        }
    }

    private var otherUserSegmentControl: some View {
        LibraryReadQueueSegmentControlReadOnly(segment: $segment)
    }

    private var yearFilterInline: some View {
        Menu {
            Button("All") { selectedYear = nil }
            ForEach(availableYears, id: \.self) { year in
                Button(String(year)) { selectedYear = year }
            }
        } label: {
            HStack(spacing: 4) {
                Text(selectedYear.map { String($0) } ?? "All")
                    .font(Theme.callout())
                    .foregroundStyle(Theme.textPrimary)
                Image(systemName: "chevron.down.circle.fill")
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    @ViewBuilder
    private var libraryContent: some View {
        if segment == .read {
            TierListView(
                userBooks: readBooksFilteredByYear,
                onUpdateTierAndOrder: { _, _, _ in },
                onBookTap: { selectedBookForProfile = $0 },
                readOnly: true
            )
        } else {
            QueueLibraryView(
                readingNow: wantToReadReadingNow,
                upNext: wantToReadUpNext,
                backlog: wantToReadBacklog,
                onUpdateShelfAndOrder: { _, _, _ in },
                onBookTap: { selectedBookForProfile = $0 },
                readOnly: true
            )
        }
    }
}
