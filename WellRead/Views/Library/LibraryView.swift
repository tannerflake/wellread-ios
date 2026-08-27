//
//  LibraryView.swift
//  WellRead
//
//  Library-only tab (labeled "Profile" in tab bar): "Your Library". Toolbar menu in top-right.
//

import SwiftUI

// MARK: - Library (Profile tab content)

struct ProfileLibraryView: View {
    @Environment(\.mainTabBarOverlapExtraHeight) private var mainTabBarOverlapExtraHeight
    @EnvironmentObject var authService: AuthService
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var queueDragCoordinator: QueueBookDragCoordinator
    @State private var segment: LibraryReadQueueTab = .read
    @State private var selectedYear: Int? = nil
    @State private var selectedBookForProfile: Book? = nil
    @State private var showGoodreadsImport = false
    @State private var goodreadsImportInitialRows: [GoodreadsRow]? = nil
    @State private var showGoodreadsImportErrorAlert = false
    /// Dropped a queue book onto the Read tab — show mark-as-read flow before updating Firestore.
    @State private var pendingMarkReadFromQueue: UserBook?
    /// Shelf whose "Add" tile was tapped — presents the search sheet scoped to that shelf.
    @State private var addToShelfTarget: ShelfAddTarget? = nil
    /// Floating + button in the bottom-right corner — opens the full search page.
    @State private var showAddBookSearch = false
    @State private var readTabDropTargeted = false
    @State private var queueTabDropTargeted = false
    @State private var showEditProfile = false
    /// Set when the edit-profile sheet was opened by tapping the goal strip —
    /// the sheet scrolls to the book-goal field and focuses it.
    @State private var editProfileFocusesBookGoal = false
    /// Tapping your avatar opens your own profile card page: card, rosters,
    /// and the settings gear (which took over the old avatar menu's actions).
    @State private var showMyCard = false
    /// Feature flag: the notifications bell is built but not launched yet —
    /// flip to true to unhide it. `-uiPreviewNotifications` overrides in DEBUG.
    private static let notificationsBellEnabled = true
    /// Bell beside the avatar: pushes the notifications feed.
    @State private var showNotifications = false
    /// List button in the header row: pushes the by-year list with multi-select year moves.
    @State private var showYearList = false
    /// Feed button beside the list button: pushes your own post history.
    @State private var showUserFeed = false
    /// Unread rows exist — the bell shows a badge dot until the feed is opened.
    @State private var hasUnreadNotifications = false
    private let notificationsRepo = NotificationsRepository()
    @AppStorage(AppearancePreference.storageKey) private var appearanceRaw = AppearancePreference.defaultValue.rawValue
    #if DEBUG
    #endif

    private var readBooksFilteredByYear: [UserBook] {
        let read = appState.readBooks
        guard let year = selectedYear else { return read }
        return read.filter { $0.wasRead(inYear: year) }
    }

    private var availableYears: [Int] {
        let years = Set(appState.readBooks.flatMap { ub in
            ub.allReadDates.map { Calendar.current.component(.year, from: $0) }
        })
        return years.sorted(by: >)
    }

    private var calendarYear: Int {
        Calendar.current.component(.year, from: Date())
    }

    /// Books with any read date in the current calendar year (re-reads count toward each year's goal).
    private var booksFinishedThisCalendarYear: Int {
        appState.readBooks.filter { $0.wasRead(inYear: calendarYear) }.count
    }

    private var activeReadingGoal: Int? {
        let g = appState.currentUser?.readingGoal ?? authService.appUser?.readingGoal
        guard let g, g > 0 else { return nil }
        return g
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                VStack(spacing: 0) {
                    spineProfileHeader

                    if activeReadingGoal != nil || !appState.readBooks.isEmpty {
                        HStack(alignment: .center, spacing: 8) {
                            if let goal = activeReadingGoal {
                                Button {
                                    editProfileFocusesBookGoal = true
                                    showEditProfile = true
                                } label: {
                                    LibraryReadingGoalProgressStrip(
                                        calendarYear: calendarYear,
                                        booksRead: booksFinishedThisCalendarYear,
                                        goal: goal,
                                        copy: .own
                                    )
                                }
                                .buttonStyle(.plain)
                                .accessibilityHint("Edit your yearly book goal.")
                            } else {
                                Spacer(minLength: 0)
                            }

                            if !appState.readBooks.isEmpty {
                                yearListButton
                            }
                            userFeedButton
                        }
                        .padding(.horizontal, Theme.horizontalPadding)
                        .padding(.vertical, 2)
                    }

                    if segment == .read && appState.goodreadsWizardRemainingCount > 0 {
                        goodreadsResumeCallout
                    }

                    libraryContent
                }
                .padding(.horizontal, 4)
            }
            .overlay(alignment: .bottomTrailing) {
                floatingAddBookButton
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.background, for: .navigationBar)
            .onAppear { appState.refreshGoodreadsWizardResumeState() }
            .navigationDestination(isPresented: $showNotifications) {
                NotificationsView()
                    .environmentObject(authService)
                    .environmentObject(appState)
            }
            .navigationDestination(isPresented: $showYearList) {
                ReadingYearListView(readBooks: appState.readBooks)
                    .environmentObject(authService)
                    .environmentObject(appState)
            }
            .navigationDestination(isPresented: $showUserFeed) {
                if let uid = authService.firebaseUser?.uid {
                    UserFeedView(userId: uid, onBookTap: { selectedBookForProfile = $0 })
                        .environmentObject(appState)
                        .environmentObject(authService)
                }
            }
            .navigationDestination(item: $selectedBookForProfile) { book in
                BookProfileView(
                    book: book,
                    readBooksForSimilar: appState.readBooks,
                    onNotInterested: nil,
                    onWantToRead: { appState.addToWantToRead(book: book); selectedBookForProfile = nil },
                    onStartReading: { appState.addToQueue(book: book, shelf: .readingNow); selectedBookForProfile = nil },
                    onConfirmRead: { date, rating, post, caption, tier in appState.addAsRead(book: book, dateFinished: date, rating: rating, postToFeed: post, caption: caption, tier: tier); selectedBookForProfile = nil },
                    isOnReadList: appState.isBookOnReadList(bookId: book.id),
                    isInQueue: appState.isBookInQueue(bookId: book.id),
                    onRemoveFromQueue: { appState.removeFromQueue(book: book); selectedBookForProfile = nil },
                    readEntryForReview: appState.userReadBook(forBookId: book.id),
                    canEditReadReview: true
                )
            }
            .onReceive(NotificationCenter.default.publisher(for: .spineProfileTabTappedAgain)) { _ in
                // Re-tap on the Profile tab item: pop any pushed page (notifications,
                // year list, user feed, book profile) back to the library root.
                showNotifications = false
                showYearList = false
                showUserFeed = false
                selectedBookForProfile = nil
            }
            .sheet(isPresented: $showEditProfile, onDismiss: {
                editProfileFocusesBookGoal = false
            }) {
                ProfileCompletionView(
                    mode: .edit,
                    title: "Edit profile",
                    subtitle: "Update your name, handle, yearly reading goal, and reading tastes.",
                    focusBookGoalOnAppear: editProfileFocusesBookGoal,
                    onDismiss: {
                        showEditProfile = false
                    }
                )
                .environmentObject(authService)
                .environmentObject(appState)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showMyCard) {
                if let me = authService.firebaseUser?.uid, let user = appState.currentUser {
                    UserProfileCardSheet(userId: me, user: user)
                        .environmentObject(authService)
                        .environmentObject(appState)
                }
            }
            // Same full page as the Search tab, presented over the library and scoped
            // to the shelf whose "Add" tile was tapped (hence the Cancel button).
            .fullScreenCover(item: $addToShelfTarget) { target in
                SearchView(targetShelf: target.shelf, onClose: { addToShelfTarget = nil })
                    .environmentObject(authService)
                    .environmentObject(appState)
                    // No tab bar over a full-screen cover, so nothing to clear.
                    .environment(\.mainTabBarOverlapExtraHeight, 0)
            }
            // Same full search page, unscoped — opened by the floating + button.
            .fullScreenCover(isPresented: $showAddBookSearch) {
                SearchView(onClose: { showAddBookSearch = false })
                    .environmentObject(authService)
                    .environmentObject(appState)
                    .environment(\.mainTabBarOverlapExtraHeight, 0)
            }
            .sheet(isPresented: $showGoodreadsImport, onDismiss: {
                appState.refreshGoodreadsWizardResumeState()
            }) {
                GoodreadsImportView(initialRows: goodreadsImportInitialRows)
                    .environmentObject(appState)
                    .onDisappear { goodreadsImportInitialRows = nil }
            }
            .overlay {
                if appState.isFetchingGoodreadsFromURL {
                    Theme.background.ignoresSafeArea()
                    VStack(spacing: 16) {
                        ProgressView()
                            .tint(Theme.accent)
                            .scaleEffect(1.2)
                        Text("Loading Goodreads import…")
                            .font(Theme.callout())
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .onAppear {
                if let rows = appState.pendingGoodreadsImportRows, !rows.isEmpty {
                    goodreadsImportInitialRows = rows
                    showGoodreadsImport = true
                    appState.pendingGoodreadsImportRows = nil
                }
                if appState.pendingGoodreadsImportError != nil {
                    showGoodreadsImportErrorAlert = true
                }
            }
            .onChange(of: appState.pendingGoodreadsImportRows) { _, rows in
                if let r = rows, !r.isEmpty {
                    goodreadsImportInitialRows = r
                    showGoodreadsImport = true
                    appState.pendingGoodreadsImportRows = nil
                }
            }
            .onChange(of: appState.pendingGoodreadsImportError) { _, message in
                showGoodreadsImportErrorAlert = (message != nil)
            }
            .alert("Import from Goodreads", isPresented: $showGoodreadsImportErrorAlert) {
                Button("OK") {
                    appState.pendingGoodreadsImportError = nil
                }
            } message: {
                if let msg = appState.pendingGoodreadsImportError {
                    Text(msg)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .spineHighlightTierBook)) { _ in
                segment = .read
            }
            .onReceive(NotificationCenter.default.publisher(for: .spineOpenQueue)) { _ in
                segment = .wantToRead
            }
            .sheet(item: $pendingMarkReadFromQueue) { userBook in
                MarkAsReadQueueSheet(
                    userBook: userBook,
                    onConfirm: { date, rating, postToFeed, caption, tier in
                        guard let latest = appState.userBooks.first(where: { $0.id == userBook.id && $0.status == .wantToRead }) else {
                            pendingMarkReadFromQueue = nil
                            return
                        }
                        appState.promoteQueueEntryToRead(
                            userBook: latest,
                            dateFinished: date,
                            rating: rating,
                            postToFeed: postToFeed,
                            caption: caption,
                            tier: tier
                        )
                        pendingMarkReadFromQueue = nil
                    },
                    onCancel: {
                        pendingMarkReadFromQueue = nil
                    }
                )
            }
        }
    }

    /// Fixed floating + in the bottom-right corner of the Profile page — pulls up
    /// the same full search page as the Search tab (with a Cancel button).
    private var floatingAddBookButton: some View {
        Button {
            showAddBookSearch = true
        } label: {
            Circle()
                .fill(Theme.accentGloss)
                .frame(width: 56, height: 56)
                .overlay(
                    Image(systemName: "plus")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Theme.onChrome.opacity(0.5))
                )
                .shadow(color: Theme.shadowInk.opacity(0.25), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
        .padding(.trailing, 20)
        // Clear the floating tab bar pill, same as BookProfileView's action bar.
        .padding(.bottom, mainTabBarOverlapExtraHeight + 12)
        .accessibilityLabel("Add a book")
    }

    /// True while a library drag is active — sliding selection pill is hidden; selected tab uses a static gray fill when that tab has no green/red chrome.
    private var isDraggingBooksForChrome: Bool {
        queueDragCoordinator.isDraggingQueueBook || queueDragCoordinator.isDraggingReadBook
    }

    /// Profile header — no wordmark: the Read/Queue control lives on the left,
    /// with the floating reading-now fan tucked right up against the avatar menu.
    private var spineProfileHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            librarySegmentControl
                .frame(maxWidth: .infinity)
            Spacer(minLength: 8)
            // What you're reading right now, floating beside your avatar. Tapping a
            // cover jumps to the Queue shelf it lives on, not the book's profile.
            HStack(alignment: .center, spacing: 2) {
                ReadingNowFanStack(
                    books: appState.wantToReadReadingNow.compactMap(\.book),
                    coverWidth: 30,
                    onTap: { _ in
                        withAnimation(LibrarySegmentControlAnimation.selection) {
                            segment = .wantToRead
                        }
                    },
                    floats: true
                )
                if Self.isNotificationsBellVisible {
                    notificationsBell
                        .padding(.trailing, 4)
                }
                toolbarProfilePhoto
            }
        }
        .padding(.horizontal, Theme.horizontalPadding)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    /// Custom Read / Queue control: **Read** = mark read from queue (green +) or remove from read shelf (red −); **Queue** = remove from queue (red −). Chrome follows UIKit drag sessions.
    private var librarySegmentControl: some View {
        HStack(spacing: 0) {
            readSegmentButton
            queueSegmentButton
        }
        .padding(3)
        .background {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 10).fill(Theme.surface)
                if !isDraggingBooksForChrome {
                    GeometryReader { geo in
                        let half = geo.size.width / 2
                        let pillW = max(0, half - 6)
                        LibrarySegmentGlassLens()
                            .frame(width: pillW)
                            .offset(x: 3 + (segment == .read ? 0 : half))
                            .animation(LibrarySegmentControlAnimation.selection, value: segment)
                    }
                    .allowsHitTesting(false)
                }
            }
        }
        .animation(LibrarySegmentControlAnimation.selection, value: segment)
        .sensoryFeedback(.selection, trigger: segment)
        .onChange(of: readTabDropTargeted) { _, isTargeted in
            if isTargeted { LibraryDragHaptics.dropTargetHoverEntered() }
        }
        .onChange(of: queueTabDropTargeted) { _, isTargeted in
            if isTargeted { LibraryDragHaptics.dropTargetHoverEntered() }
        }
    }

    private var readSegmentButton: some View {
        let isSelected = segment == .read
        // Green “mark read” while on Queue tab + dragging a queue book; red “remove from Read” while on Read tab + dragging a read book.
        let showReadMarkReadChrome = segment == .wantToRead && queueDragCoordinator.isDraggingQueueBook
        let showReadRemoveChrome = segment == .read && queueDragCoordinator.isDraggingReadBook
        let showReadDropChrome = showReadMarkReadChrome || showReadRemoveChrome
        /// Sliding pill covers gray when not dragging; during drag, keep gray on selected Read only when this tab has no drop chrome.
        let readStaticSelectedWhileDragging = isDraggingBooksForChrome && isSelected && !showReadMarkReadChrome && !showReadRemoveChrome
        let emphasizeReadHover = readTabDropTargeted
        let readLabelColor: Color = {
            if showReadDropChrome { return .white }
            if isSelected { return Theme.textPrimary }
            return Theme.textSecondary
        }()
        let readFill: Color = {
            if showReadMarkReadChrome { return Theme.accent.opacity(emphasizeReadHover ? 0.58 : 0.5) }
            if showReadRemoveChrome { return Theme.danger.opacity(emphasizeReadHover ? 0.58 : 0.5) }
            if readStaticSelectedWhileDragging { return Theme.surfaceElevated }
            if isSelected && !isDraggingBooksForChrome { return .clear }
            return .clear
        }()
        let readStrokeColor: Color = {
            if showReadMarkReadChrome { return Theme.accent.opacity(emphasizeReadHover ? 1.0 : 0.95) }
            if showReadRemoveChrome { return Theme.danger.opacity(emphasizeReadHover ? 1.0 : 0.95) }
            if readStaticSelectedWhileDragging { return Theme.chrome.opacity(0.55) }
            if isSelected && !isDraggingBooksForChrome { return .clear }
            return .clear
        }()
        let readStrokeWidth: CGFloat = {
            if showReadDropChrome { return emphasizeReadHover ? 3 : 2.5 }
            if readStaticSelectedWhileDragging { return 1.25 }
            if isSelected && !isDraggingBooksForChrome { return 0 }
            return 0
        }()
        let readShadowColor: Color = {
            if showReadMarkReadChrome { return Theme.accent.opacity(emphasizeReadHover ? 0.55 : 0.45) }
            if showReadRemoveChrome { return Theme.danger.opacity(emphasizeReadHover ? 0.55 : 0.45) }
            if readStaticSelectedWhileDragging { return Theme.shadowInk.opacity(0.12) }
            if isSelected && !isDraggingBooksForChrome { return .clear }
            return .clear
        }()
        let readShadowRadius: CGFloat = {
            if showReadDropChrome { return emphasizeReadHover ? 10 : 8 }
            if readStaticSelectedWhileDragging { return 4 }
            if isSelected && !isDraggingBooksForChrome { return 0 }
            return 0
        }()
        return Button {
            segment = .read
        } label: {
            HStack(spacing: 6) {
                if showReadMarkReadChrome {
                    Image(systemName: "plus.circle.fill")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.white)
                } else if showReadRemoveChrome {
                    Image(systemName: "minus.circle.fill")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.white)
                }
                Text("Read")
                    .font(Theme.callout().weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(readLabelColor)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(readFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(readStrokeColor, lineWidth: readStrokeWidth)
            )
            .shadow(color: readShadowColor, radius: readShadowRadius, y: showReadDropChrome ? 0 : 1)
            .animation(LibrarySegmentControlAnimation.dragChrome, value: readTabDropTargeted)
            .animation(LibrarySegmentControlAnimation.dragChrome, value: queueDragCoordinator.isDraggingQueueBook)
            .animation(LibrarySegmentControlAnimation.dragChrome, value: queueDragCoordinator.isDraggingReadBook)
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .padding(.vertical, 4)
        .padding(.leading, 2)
        .padding(.trailing, 2)
        .dropDestination(for: TierDragItem.self) { items, _ in
            guard let payload = items.first else { return false }
            return handleReadTabDrop(payload: payload)
        } isTargeted: { readTabDropTargeted = $0 }
    }

    private var queueSegmentButton: some View {
        let isSelected = segment == .wantToRead
        let showQueueRemoveChrome = segment == .wantToRead && queueDragCoordinator.isDraggingQueueBook
        let queueStaticSelectedWhileDragging = isDraggingBooksForChrome && isSelected && !showQueueRemoveChrome
        let emphasizeQueueHover = queueTabDropTargeted
        let queueLabelColor: Color = {
            if showQueueRemoveChrome { return .white }
            if isSelected { return Theme.textPrimary }
            return Theme.textSecondary
        }()
        let queueFill: Color = {
            if showQueueRemoveChrome { return Theme.danger.opacity(emphasizeQueueHover ? 0.58 : 0.5) }
            if queueStaticSelectedWhileDragging { return Theme.surfaceElevated }
            if isSelected && !isDraggingBooksForChrome { return .clear }
            return .clear
        }()
        let queueStrokeColor: Color = {
            if showQueueRemoveChrome { return Theme.danger.opacity(emphasizeQueueHover ? 1.0 : 0.95) }
            if queueStaticSelectedWhileDragging { return Theme.chrome.opacity(0.55) }
            if isSelected && !isDraggingBooksForChrome { return .clear }
            return .clear
        }()
        let queueStrokeWidth: CGFloat = {
            if showQueueRemoveChrome { return emphasizeQueueHover ? 3 : 2.5 }
            if queueStaticSelectedWhileDragging { return 1.25 }
            if isSelected && !isDraggingBooksForChrome { return 0 }
            return 0
        }()
        let queueShadowColor: Color = {
            if showQueueRemoveChrome { return Theme.danger.opacity(emphasizeQueueHover ? 0.55 : 0.45) }
            if queueStaticSelectedWhileDragging { return Theme.shadowInk.opacity(0.12) }
            if isSelected && !isDraggingBooksForChrome { return .clear }
            return .clear
        }()
        let queueShadowRadius: CGFloat = {
            if showQueueRemoveChrome { return emphasizeQueueHover ? 10 : 8 }
            if queueStaticSelectedWhileDragging { return 4 }
            if isSelected && !isDraggingBooksForChrome { return 0 }
            return 0
        }()
        return Button {
            segment = .wantToRead
        } label: {
            HStack(spacing: 6) {
                if showQueueRemoveChrome {
                    Image(systemName: "minus.circle.fill")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.white)
                }
                Text("Queue")
                    .font(Theme.callout().weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(queueLabelColor)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(queueFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(queueStrokeColor, lineWidth: queueStrokeWidth)
            )
            .shadow(color: queueShadowColor, radius: queueShadowRadius, y: showQueueRemoveChrome ? 0 : 1)
            .animation(LibrarySegmentControlAnimation.dragChrome, value: readTabDropTargeted)
            .animation(LibrarySegmentControlAnimation.dragChrome, value: queueTabDropTargeted)
            .animation(LibrarySegmentControlAnimation.dragChrome, value: queueDragCoordinator.isDraggingQueueBook)
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .padding(.vertical, 4)
        .padding(.trailing, 2)
        .dropDestination(for: TierDragItem.self) { items, _ in
            guard let payload = items.first else { return false }
            return handleQueueTabRemoveDrop(payload: payload)
        } isTargeted: { queueTabDropTargeted = $0 }
    }

    private func handleReadTabDrop(payload: TierDragItem) -> Bool {
        if segment == .wantToRead {
            guard let ub = appState.userBooks.first(where: { $0.id == payload.userBookId && $0.status == .wantToRead }),
                  ub.book != nil else { return false }
            pendingMarkReadFromQueue = ub
            return true
        }
        if segment == .read {
            guard let ub = appState.userBooks.first(where: { $0.id == payload.userBookId && $0.status == .read }),
                  let book = ub.book else { return false }
            appState.removeFromReadList(book: book)
            return true
        }
        return false
    }

    private func handleQueueTabRemoveDrop(payload: TierDragItem) -> Bool {
        guard segment == .wantToRead,
              let ub = appState.userBooks.first(where: { $0.id == payload.userBookId && $0.status == .wantToRead }),
              let book = ub.book else { return false }
        appState.removeFromQueue(book: book)
        return true
    }

    /// Flag plus the DEBUG preview override — keeps the bell verifiable in the
    /// simulator while it stays hidden from users.
    private static var isNotificationsBellVisible: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-uiPreviewNotifications") { return true }
        #endif
        return notificationsBellEnabled
    }

    /// Bell to the left of your avatar: opens the notifications feed. Shows a
    /// badge dot while unread rows exist; opening the feed marks them read.
    private var notificationsBell: some View {
        Button {
            showNotifications = true
            hasUnreadNotifications = false
        } label: {
            Image(systemName: "bell")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                // Badge anchors to the glyph, not the tap frame, so it hugs the
                // bell's top-right shoulder.
                .overlay(alignment: .topTrailing) {
                    if hasUnreadNotifications {
                        Circle()
                            .fill(Theme.danger)
                            .frame(width: 10, height: 10)
                            .overlay(Circle().strokeBorder(Theme.background, lineWidth: 1.5))
                            .offset(x: -2, y: 3)
                    }
                }
                .frame(width: 34, height: 34)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(hasUnreadNotifications ? "Notifications, new activity" : "Notifications")
        .task(id: authService.firebaseUser?.uid) {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-uiPreviewNotifications") {
                hasUnreadNotifications = true
                return
            }
            #endif
            guard let uid = authService.firebaseUser?.uid else {
                hasUnreadNotifications = false
                return
            }
            hasUnreadNotifications = await notificationsRepo.hasUnread(uid: uid)
        }
    }

    /// Your avatar in the header: opens your own profile card page (card front
    /// and back, followers, following, and the settings gear). The old action
    /// menu that lived here moved to that page's settings screen.
    @ViewBuilder
    private var toolbarProfilePhoto: some View {
        if let user = appState.currentUser, authService.firebaseUser?.uid != nil {
            Button {
                showMyCard = true
            } label: {
                UserAvatarView(
                    urlString: user.profileImageURL,
                    displayName: user.displayName,
                    firstName: user.firstName,
                    lastName: user.lastName,
                    size: 40
                )
                .overlay(
                    Circle()
                        .strokeBorder(Theme.chrome.opacity(0.55), lineWidth: 1.5)
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Your profile")
        } else {
            // User doc not loaded yet: the card page has nothing to show, so
            // keep the bare essentials reachable.
            Menu {
                appearanceMenu
                Divider()
                Button("Sign out", role: .destructive) {
                    authService.signOut()
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    /// Light / Dark / System picker in the fallback menu — persisted app-wide
    /// via `AppearancePreference` and applied at the root `preferredColorScheme`.
    private var appearanceMenu: some View {
        Menu {
            Picker("Appearance", selection: $appearanceRaw) {
                ForEach(AppearancePreference.allCases) { option in
                    Label(option.label, systemImage: option.iconName)
                        .tag(option.rawValue)
                }
            }
        } label: {
            let current = AppearancePreference(rawValue: appearanceRaw) ?? .defaultValue
            Label("Appearance: \(current.label)", systemImage: current.iconName)
        }
    }

    /// Book count for the S-tier year dropdown rows; nil year = all read books.
    private func readBookCount(forYear year: Int?) -> Int {
        guard let year else { return appState.readBooks.count }
        return appState.readBooks.filter { $0.wasRead(inYear: year) }.count
    }

    /// List icon beside the reading goal strip: opens "Reading by year", where books can
    /// be multi-selected and moved into another year.
    private var yearListButton: some View {
        Button {
            showYearList = true
        } label: {
            goalStripIconLabel("list.bullet")
        }
        .buttonStyle(.plain)
        .accessibilityLabel("List view")
    }

    /// Shared chrome for the square icon buttons beside the reading goal strip:
    /// identical footprint and identical glyph box, so `list.bullet` and
    /// `newspaper` can't render at different sizes.
    private func goalStripIconLabel(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Theme.textPrimary)
            .frame(width: 34, height: 34)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    /// Feed icon beside the list button: opens your post history, every feed
    /// post you've made, newest first.
    private var userFeedButton: some View {
        Button {
            showUserFeed = true
        } label: {
            goalStripIconLabel("newspaper")
        }
        .buttonStyle(.plain)
        .accessibilityLabel("My feed")
    }

    /// "Finish importing" callout above the tier list when a Goodreads wizard
    /// session is paused. Tapping resumes exactly where the user left off.
    private var goodreadsResumeCallout: some View {
        Button {
            goodreadsImportInitialRows = nil
            showGoodreadsImport = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.onChrome)
                    .frame(width: 30, height: 30)
                    .background(Theme.accentGloss)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                VStack(alignment: .leading, spacing: 2) {
                    Text(SpinesGlyphs.caps("Finish importing!"))
                        .font(.system(size: 12, weight: .bold))
                        .tracking(0.5)
                        .foregroundStyle(Theme.accent)
                    Text(goodreadsResumeMessage)
                        .font(Theme.caption())
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(2)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(10)
            .background(Theme.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius)
                    .strokeBorder(Theme.accent.opacity(0.45), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, Theme.horizontalPadding - 4)
        .padding(.bottom, 8)
    }

    /// Drop-slot indices are positions in the (possibly year-filtered) rows the user sees.
    /// With a year filter active the full tier also contains hidden books, so translate
    /// "insert at visible slot N" into "insert before that same book in the full tier".
    private func fullTierInsertionIndex(tier: String?, visibleIndex: Int?) -> Int? {
        guard let visibleIndex, selectedYear != nil else { return visibleIndex }
        let t = tier.flatMap { $0.isEmpty ? nil : $0 }
        let visible = spineTierSorted(readBooksFilteredByYear.filter { $0.normalizedTier == t })
        // Dropped past the last visible book → append to the end of the full tier.
        guard visibleIndex < visible.count else { return nil }
        let insertBefore = visible[visibleIndex]
        let full = spineTierSorted(appState.readBooks.filter { $0.normalizedTier == t })
        return full.firstIndex(where: { $0.id == insertBefore.id })
    }

    private var goodreadsResumeMessage: String {
        let n = appState.goodreadsWizardRemainingCount
        let noun = n == 1 ? "book" : "books"
        return "\(n) \(noun) remaining"
    }

    @ViewBuilder
    private var libraryContent: some View {
        if segment == .read {
            TierListView(
                userBooks: readBooksFilteredByYear,
                onUpdateTierAndOrder: { id, tier, order in
                    appState.setTierAndOrder(for: id, tier: tier, order: fullTierInsertionIndex(tier: tier, visibleIndex: order))
                },
                onBookTap: { selectedBookForProfile = $0 },
                highlightedBookId: appState.pendingTierHighlightBookId,
                yearFilter: availableYears.isEmpty ? nil : TierYearFilter(
                    availableYears: availableYears,
                    selectedYear: selectedYear,
                    countForYear: { readBookCount(forYear: $0) },
                    onSelect: { selectedYear = $0 }
                )
            )
        } else {
            QueueLibraryView(
                readingNow: appState.wantToReadReadingNow,
                upNext: appState.wantToReadUpNext,
                backlog: appState.wantToReadBacklog,
                onUpdateShelfAndOrder: { id, shelf, idx in
                    appState.setQueueShelfAndOrder(for: id, shelf: shelf, insertionIndex: idx)
                },
                onBookTap: { selectedBookForProfile = $0 },
                onAddToShelf: { addToShelfTarget = ShelfAddTarget(shelf: $0) },
                recommendations: appState.incomingRecommendations,
                recommenderNames: appState.recommenderProfiles.mapValues(\.displayName),
                onAcceptRecommendation: { appState.acceptRecommendation($0) },
                onDismissRecommendation: { appState.dismissRecommendation($0) }
            )
        }
    }
}

/// Identifiable wrapper so `.sheet(item:)` can present the add-book search for a specific shelf.
private struct ShelfAddTarget: Identifiable {
    let shelf: QueueShelf
    var id: String { shelf.rawValue }
}

// MARK: - Mark as read (queue → Read tab drop)

private struct MarkAsReadQueueSheet: View {
    let userBook: UserBook
    /// (dateFinished, rating, postToFeed, thoughts, tier). Tier nil = Unranked → tier-list "Rank me" prompt.
    let onConfirm: (Date, Double?, Bool, String?, String?) -> Void
    let onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var isThoughtsFocused: Bool
    @State private var markAsReadDate = Date()
    @State private var markAsReadPostToFeed = true
    @State private var markAsReadThoughts = ""
    @State private var selectedTier: String? = nil

    private var bookTitle: String {
        userBook.book?.title ?? "Book"
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(bookTitle)
                            .font(Theme.title())
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(4)
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Mark as read")
                                .font(Theme.title2())
                                .foregroundStyle(Theme.textPrimary)
                            VStack(alignment: .leading, spacing: 6) {
                                Text("When did you finish?")
                                    .font(Theme.caption())
                                    .foregroundStyle(Theme.textSecondary)
                                DatePicker("", selection: $markAsReadDate, displayedComponents: .date)
                                    .datePickerStyle(.compact)
                                    .labelsHidden()
                                    .tint(Theme.accent)
                            }
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Thoughts")
                                    .font(Theme.caption())
                                    .foregroundStyle(Theme.textSecondary)
                                ZStack(alignment: .topLeading) {
                                    if markAsReadThoughts.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                        Text("Thoughts on this book…")
                                            .font(Theme.body())
                                            .foregroundStyle(Theme.textSecondary.opacity(0.7))
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 10)
                                    }
                                    TextEditor(text: $markAsReadThoughts)
                                        .font(Theme.body())
                                        .foregroundStyle(Theme.textPrimary)
                                        .scrollContentBackground(.hidden)
                                        .frame(minHeight: 160, maxHeight: 320)
                                        .focused($isThoughtsFocused)
                                }
                                .padding(12)
                                .background(Theme.background.opacity(0.6))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                            .id("markReadThoughtsBlock")

                            InlineTierPicker(selection: $selectedTier)

                            Toggle(isOn: $markAsReadPostToFeed) {
                                Text("Post to feed")
                                    .font(Theme.callout())
                                    .foregroundStyle(Theme.textPrimary)
                            }
                            .tint(Theme.toggleOn)

                            Button {
                                let date = markAsReadDate
                                let post = markAsReadPostToFeed
                                let thoughts = markAsReadThoughts.trimmingCharacters(in: .whitespacesAndNewlines)
                                onConfirm(date, nil, post, thoughts.isEmpty ? nil : thoughts, selectedTier)
                                dismiss()
                            } label: {
                                Text("Mark as read")
                                    .font(Theme.headline())
                                    .foregroundStyle(Theme.background)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(Theme.accentGloss)
                                    .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(20)
                    .padding(.bottom, 24)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: isThoughtsFocused) { _, focused in
                    if focused {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            withAnimation(.easeOut(duration: 0.2)) {
                                proxy.scrollTo("markReadThoughtsBlock", anchor: .center)
                            }
                        }
                    }
                }
            }
            .background(Theme.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.large])
        .onAppear {
            markAsReadDate = Date()
            markAsReadPostToFeed = true
            markAsReadThoughts = ""
            selectedTier = nil
        }
    }
}

