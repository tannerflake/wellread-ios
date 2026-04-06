//
//  LibraryView.swift
//  WellRead
//
//  Library-only tab (labeled "Profile" in tab bar): "Your Library". Toolbar menu in top-right.
//

import SwiftUI

// MARK: - Library (Profile tab content)

struct ProfileLibraryView: View {
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
    @State private var readTabDropTargeted = false
    @State private var queueTabDropTargeted = false
    @State private var showEditProfile = false
    #if DEBUG
    @State private var showPushDiagnostics = false
    #endif

    private var readBooksFilteredByYear: [UserBook] {
        let read = appState.readBooks
        guard let year = selectedYear else { return read }
        return read.filter { ub in
            guard let d = ub.dateFinished else { return false }
            return Calendar.current.component(.year, from: d) == year
        }
    }

    private var availableYears: [Int] {
        let years = Set(appState.readBooks.compactMap { ub -> Int? in
            ub.dateFinished.map { Calendar.current.component(.year, from: $0) }
        })
        return years.sorted(by: >)
    }

    private var calendarYear: Int {
        Calendar.current.component(.year, from: Date())
    }

    /// Books marked read with `dateFinished` in the current calendar year.
    private var booksFinishedThisCalendarYear: Int {
        let y = calendarYear
        return appState.readBooks.filter { ub in
            guard let d = ub.dateFinished else { return false }
            return Calendar.current.component(.year, from: d) == y
        }.count
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
                    if let goal = activeReadingGoal {
                        LibraryReadingGoalProgressStrip(
                            calendarYear: calendarYear,
                            booksRead: booksFinishedThisCalendarYear,
                            goal: goal,
                            copy: .own
                        )
                    }

                    HStack(alignment: .center, spacing: 12) {
                        librarySegmentControl
                            .frame(maxWidth: .infinity)

                        if !availableYears.isEmpty {
                            yearFilterInline
                        }
                    }
                    .padding(.vertical, 10)

                    libraryContent
                }
                .padding(.horizontal, 4)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
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
                .padding(.horizontal)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Your Library")
                        .font(Theme.title())
                        .foregroundStyle(Theme.textPrimary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    toolbarProfilePhoto
                }
            }
            .sheet(isPresented: $showEditProfile) {
                ProfileCompletionView(
                    mode: .edit,
                    title: "Edit profile",
                    subtitle: "Update your name, handle, and how many books you want to read this year.",
                    onDismiss: {
                        showEditProfile = false
                    }
                )
                .environmentObject(authService)
                .environmentObject(appState)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showGoodreadsImport) {
                GoodreadsImportView(initialRows: goodreadsImportInitialRows)
                    .environmentObject(appState)
                    .onDisappear { goodreadsImportInitialRows = nil }
            }
            #if DEBUG
            .sheet(isPresented: $showPushDiagnostics) {
                NavigationStack {
                    PushDiagnosticsView()
                }
                .presentationDetents([.medium, .large])
            }
            #endif
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
            .sheet(item: $pendingMarkReadFromQueue) { userBook in
                MarkAsReadQueueSheet(
                    userBook: userBook,
                    onConfirm: { date, rating, postToFeed, caption in
                        guard let latest = appState.userBooks.first(where: { $0.id == userBook.id && $0.status == .wantToRead }) else {
                            pendingMarkReadFromQueue = nil
                            return
                        }
                        appState.promoteQueueEntryToRead(
                            userBook: latest,
                            dateFinished: date,
                            rating: rating,
                            postToFeed: postToFeed,
                            caption: caption
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

    /// True while a library drag is active — sliding selection pill is hidden; selected tab uses a static gray fill when that tab has no green/red chrome.
    private var isDraggingBooksForChrome: Bool {
        queueDragCoordinator.isDraggingQueueBook || queueDragCoordinator.isDraggingReadBook
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
                RoundedRectangle(cornerRadius: 10).fill(Color(white: 0.16))
                if !isDraggingBooksForChrome {
                    GeometryReader { geo in
                        let half = geo.size.width / 2
                        let pillW = max(0, half - 6)
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(white: 0.24))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(Theme.textTertiary.opacity(0.55), lineWidth: 1.25)
                            )
                            .shadow(color: Color.black.opacity(0.45), radius: 4, y: 1)
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
            if showReadRemoveChrome { return Color.red.opacity(emphasizeReadHover ? 0.58 : 0.5) }
            if readStaticSelectedWhileDragging { return Color(white: 0.24) }
            if isSelected && !isDraggingBooksForChrome { return .clear }
            return .clear
        }()
        let readStrokeColor: Color = {
            if showReadMarkReadChrome { return Theme.accent.opacity(emphasizeReadHover ? 1.0 : 0.95) }
            if showReadRemoveChrome { return Color.red.opacity(emphasizeReadHover ? 1.0 : 0.95) }
            if readStaticSelectedWhileDragging { return Theme.textTertiary.opacity(0.55) }
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
            if showReadRemoveChrome { return Color.red.opacity(emphasizeReadHover ? 0.55 : 0.45) }
            if readStaticSelectedWhileDragging { return Color.black.opacity(0.45) }
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
            .padding(.vertical, 11)
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
            if showQueueRemoveChrome { return Color.red.opacity(emphasizeQueueHover ? 0.58 : 0.5) }
            if queueStaticSelectedWhileDragging { return Color(white: 0.24) }
            if isSelected && !isDraggingBooksForChrome { return .clear }
            return .clear
        }()
        let queueStrokeColor: Color = {
            if showQueueRemoveChrome { return Color.red.opacity(emphasizeQueueHover ? 1.0 : 0.95) }
            if queueStaticSelectedWhileDragging { return Theme.textTertiary.opacity(0.55) }
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
            if showQueueRemoveChrome { return Color.red.opacity(emphasizeQueueHover ? 0.55 : 0.45) }
            if queueStaticSelectedWhileDragging { return Color.black.opacity(0.45) }
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
            .padding(.vertical, 11)
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

    @ViewBuilder
    private var toolbarProfilePhoto: some View {
        if let user = appState.currentUser, authService.firebaseUser?.uid != nil {
            Menu {
                Button {
                    showEditProfile = true
                } label: {
                    Label("Edit profile", systemImage: "person.crop.circle")
                }
                Button {
                    showGoodreadsImport = true
                } label: {
                    Label("Import from Goodreads", systemImage: "square.and.arrow.down")
                }
                #if DEBUG
                Button {
                    showPushDiagnostics = true
                } label: {
                    Label("Push diagnostics", systemImage: "bell.badge")
                }
                #endif
                Divider()
                Button("Sign out", role: .destructive) {
                    authService.signOut()
                }
            } label: {
                ZStack {
                    if let urlString = user.profileImageURL, let url = URL(string: urlString) {
                        CachedProfileImage(url: url, contentMode: .fill) {
                            avatarPlaceholder(initial: String(user.displayName.prefix(1)), compact: true)
                        }
                    } else {
                        avatarPlaceholder(initial: String(user.displayName.prefix(1)), compact: true)
                    }
                }
                .frame(width: 36, height: 36)
                .clipShape(Circle())
            }
            .buttonStyle(.plain)
        } else {
            Menu {
                Button {
                    showEditProfile = true
                } label: {
                    Label("Edit profile", systemImage: "person.crop.circle")
                }
                #if DEBUG
                Button {
                    showPushDiagnostics = true
                } label: {
                    Label("Push diagnostics", systemImage: "bell.badge")
                }
                #endif
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

    private func avatarPlaceholder(initial: String, compact: Bool = false) -> some View {
        Circle()
            .fill(Theme.surface)
            .overlay(
                Text(initial)
                    .font(compact ? Theme.headline() : Theme.largeTitle())
                    .foregroundStyle(Theme.textSecondary)
            )
    }

    /// Year filter to the right of the Read/Queue segment control (stays visible when switching segments; applies to Read list).
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
            TierListView(userBooks: readBooksFilteredByYear, onUpdateTierAndOrder: { id, tier, order in
                appState.setTierAndOrder(for: id, tier: tier, order: order)
            }, onBookTap: { selectedBookForProfile = $0 })
        } else {
            QueueLibraryView(
                upNext: appState.wantToReadUpNext,
                backlog: appState.wantToReadBacklog,
                onUpdateShelfAndOrder: { id, shelf, idx in
                    appState.setQueueShelfAndOrder(for: id, shelf: shelf, insertionIndex: idx)
                },
                onBookTap: { selectedBookForProfile = $0 }
            )
        }
    }
}

// MARK: - Mark as read (queue → Read tab drop)

private struct MarkAsReadQueueSheet: View {
    let userBook: UserBook
    let onConfirm: (Date, Double?, Bool, String?) -> Void
    let onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var isThoughtsFocused: Bool
    @State private var markAsReadDate = Date()
    /// Visual middle of 1…10; label shows "—" until the user moves the slider.
    @State private var markAsReadSliderValue: Double = 5.5
    @State private var hasExplicitMarkReadRating = false
    @State private var markAsReadPostToFeed = true
    @State private var markAsReadThoughts = ""

    private var markAsReadRatingSliderBinding: Binding<Double> {
        Binding(
            get: { markAsReadSliderValue },
            set: { newValue in
                markAsReadSliderValue = newValue
                hasExplicitMarkReadRating = true
            }
        )
    }

    private var markAsReadRatingLabel: String {
        hasExplicitMarkReadRating ? Theme.formatRatingOutOfTen(markAsReadSliderValue) : "—"
    }

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
                                Text("Rating: \(markAsReadRatingLabel) / 10")
                                    .font(Theme.caption())
                                    .foregroundStyle(Theme.textSecondary)
                                Slider(value: markAsReadRatingSliderBinding, in: 1...10, step: 0.1)
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

                            Toggle(isOn: $markAsReadPostToFeed) {
                                Text("Post to feed")
                                    .font(Theme.callout())
                                    .foregroundStyle(Theme.textPrimary)
                            }
                            .tint(Theme.accent)

                            Button {
                                let date = markAsReadDate
                                let rating: Double? = hasExplicitMarkReadRating
                                    ? Theme.normalizeRatingOutOfTen(markAsReadSliderValue)
                                    : nil
                                let post = markAsReadPostToFeed
                                let thoughts = markAsReadThoughts.trimmingCharacters(in: .whitespacesAndNewlines)
                                onConfirm(date, rating, post, thoughts.isEmpty ? nil : thoughts)
                                dismiss()
                            } label: {
                                Text("Mark as read")
                                    .font(Theme.headline())
                                    .foregroundStyle(Theme.background)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(Theme.accent)
                                    .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(20)
                    .padding(.bottom, 24)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: markAsReadThoughts) { _, _ in
                    guard isThoughtsFocused else { return }
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo("markReadThoughtsBlock", anchor: .bottom)
                    }
                }
                .onChange(of: isThoughtsFocused) { _, focused in
                    if focused {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                            withAnimation(.easeOut(duration: 0.2)) {
                                proxy.scrollTo("markReadThoughtsBlock", anchor: .bottom)
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
            markAsReadSliderValue = 5.5
            hasExplicitMarkReadRating = false
            markAsReadPostToFeed = true
            markAsReadThoughts = ""
        }
    }
}

