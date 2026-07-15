//
//  AddBookFlowView.swift
//  WellRead
//
//  Fast add flow: search → select → status → (if finished) review.
//

import SwiftUI

/// Local-only recent activity for the search drawer (per signed-in uid, capped,
/// never synced): submitted queries and book profiles the user opened.
enum SearchRecents {
    private static let queryCap = 8
    private static let bookCap = 12
    private static func queriesKey(_ uid: String) -> String { "searchRecentQueries.\(uid)" }
    private static func booksKey(_ uid: String) -> String { "searchRecentBooks.\(uid)" }

    static func queries(uid: String) -> [String] {
        UserDefaults.standard.stringArray(forKey: queriesKey(uid)) ?? []
    }

    static func addQuery(_ q: String, uid: String) {
        let t = q.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        var list = queries(uid: uid).filter { $0.caseInsensitiveCompare(t) != .orderedSame }
        list.insert(t, at: 0)
        UserDefaults.standard.set(Array(list.prefix(queryCap)), forKey: queriesKey(uid))
    }

    static func books(uid: String) -> [Book] {
        guard let data = UserDefaults.standard.data(forKey: booksKey(uid)),
              let list = try? JSONDecoder().decode([Book].self, from: data) else { return [] }
        return list
    }

    static func addBook(_ b: Book, uid: String) {
        var list = books(uid: uid).filter { $0.id != b.id }
        list.insert(b, at: 0)
        if let data = try? JSONEncoder().encode(Array(list.prefix(bookCap))) {
            UserDefaults.standard.set(data, forKey: booksKey(uid))
        }
    }
}

struct AddBookFlowView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var authService: AuthService
    @EnvironmentObject var appState: AppState
    @State private var isSearchFocused = false
    @State private var query = ""
    @State private var results: [Book] = []
    @State private var isSearching = false
    @State private var hasSearched = false
    /// True after the user taps "show every edition" — search re-runs without the junk filter and edition dedup.
    @State private var showingAllEditions = false
    @State private var searchError: String?
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var selectedBook: Book?
    @State private var selectedBookForProfile: Book?
    @State private var status: ReadingStatus = .read
    @State private var step: Step = .search
    @State private var searchTask: Task<Void, Never>?
    /// Recent search activity shown while the field is empty.
    @State private var recentQueries: [String] = []
    @State private var recentBooks: [Book] = []
    /// When set (opened from a queue shelf's "Add" tile), book profiles show a primary
    /// CTA that adds the book straight onto this shelf.
    var targetShelf: QueueShelf? = nil
    /// Set when presented as a custom overlay (not a system sheet) — called instead of
    /// `dismiss()` so the parent can drop the drawer from its view tree.
    var onDismiss: (() -> Void)? = nil

    /// Closes the drawer regardless of how it was presented.
    private func close() {
        if let onDismiss {
            onDismiss()
        } else {
            dismiss()
        }
    }

    /// Fraction of the screen left as a see-through tap-out strip above the drawer.
    /// The drawer is a custom overlay (not a system sheet) because sheet detents
    /// re-resolve when the keyboard appears, jumping the drawer to full height —
    /// and iOS 26 ignores `presentationBackground(.clear)`.
    private static let tapOutStripFraction: CGFloat = 0.12

    /// UIKit equivalent of `Theme.body()` (SF Pro, size 17) for the search field.
    private static var searchFieldUIFont: UIFont {
        UIFont.systemFont(ofSize: 17, weight: .regular)
    }

    enum Step {
        case search
        case status
        case rating
    }
    
    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                // Transparent strip above the drawer — tapping it dismisses the sheet.
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { close() }
                    .frame(height: max(60, geo.size.height * Self.tapOutStripFraction))
                drawerContent
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24))
                    .overlay(alignment: .top) {
                        // Grab handle — swiping it down dismisses (replaces the system
                        // sheet's interactive dismissal).
                        Capsule()
                            .fill(Theme.textTertiary.opacity(0.5))
                            .frame(width: 40, height: 5)
                            .padding(.top, 9)
                            .frame(maxWidth: .infinity)
                            .frame(height: 34, alignment: .top)
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 12)
                                    .onEnded { value in
                                        if value.translation.height > 60 { close() }
                                    }
                            )
                    }
                    .shadow(color: .black.opacity(0.18), radius: 18, y: -4)
            }
        }
        // Pin the drawer: without this, keyboard avoidance shrinks the geometry and
        // the drawer rides up under the keyboard.
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }

    private var drawerContent: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                VStack(spacing: 0) {
                    if step == .search {
                        searchStep
                    } else if step == .status {
                        statusStep
                    } else {
                        ratingStep
                    }
                }
            }
            .navigationTitle(step == .search ? "" : stepTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbar {
                if step != .search {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { close() }
                            .foregroundStyle(Theme.accent)
                    }
                }
            }
            .navigationDestination(item: $selectedBookForProfile) { book in
                BookProfileView(
                    book: book,
                    readBooksForSimilar: appState.readBooks,
                    onNotInterested: nil,
                    // Adding to the queue should land the user on their queue (with the success
                    // toast), not drop them back on the search bar. Dismiss the whole search sheet.
                    onWantToRead: { appState.addToWantToRead(book: book); appState.openQueue(); close() },
                    // Marking read fires the tier-highlight flow (switches to Profile → Read and
                    // scrolls to the book). Dismiss the whole search sheet so that lands in view,
                    // rather than popping back to the search bar.
                    onConfirmRead: { date, rating, post, caption, tier in appState.addAsRead(book: book, dateFinished: date, rating: rating, postToFeed: post, caption: caption, tier: tier); close() },
                    isOnReadList: appState.isBookOnReadList(bookId: book.id),
                    isInQueue: appState.isBookInQueue(bookId: book.id),
                    onRemoveFromQueue: { appState.removeFromQueue(book: book); selectedBookForProfile = nil },
                    readEntryForReview: appState.userReadBook(forBookId: book.id),
                    canEditReadReview: true,
                    shelfActionTitle: targetShelf.map(Self.shelfCTATitle),
                    onAddToShelf: targetShelf.map { shelf in
                        // Same landing behavior as Queue: dismiss the search sheet onto the queue.
                        { appState.addToQueue(book: book, shelf: shelf); appState.openQueue(); close() }
                    }
                )
            }
        }
    }

    private static func shelfCTATitle(_ shelf: QueueShelf) -> String {
        switch shelf {
        case .readingNow: return "+ READING NOW"
        case .upNext: return "+ UP NEXT"
        case .backlog: return "+ BACKLOG"
        }
    }
    
    private var stepTitle: String {
        switch step {
        case .search: return "Add Book"
        case .status: return "Status"
        case .rating: return "Review"
        }
    }
    
    private var searchStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(Theme.textSecondary)
                    NoSuggestionsTextField(
                        text: $query,
                        isFocused: $isSearchFocused,
                        placeholder: "Search by title or author",
                        font: Self.searchFieldUIFont,
                        textColor: UIColor(Theme.textPrimary),
                        placeholderColor: UIColor(Theme.textTertiary),
                        onSubmit: { runSearch() }
                    )
                        .frame(height: 24)
                        .onChange(of: query) { _, newValue in
                            scheduleSearch(for: newValue)
                        }
                    if !query.isEmpty {
                        Button {
                            query = ""
                            isSearchFocused = true
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 17))
                                .foregroundStyle(Theme.textTertiary)
                        }
                        .buttonStyle(.plain)
                        .transition(.opacity.combined(with: .scale(scale: 0.8)))
                        .accessibilityLabel("Clear search")
                    }
                }
                .animation(.easeInOut(duration: 0.15), value: query.isEmpty)
                .padding()
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius))
            }
            .padding(.horizontal)

            if isSearching {
                HStack {
                    ProgressView().tint(Theme.accent)
                    Text("Searching…").font(Theme.callout()).foregroundStyle(Theme.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding()
            }
            
            if let err = searchError {
                VStack(spacing: 12) {
                    Text(err)
                        .font(Theme.callout())
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                    Button("Try Again") { runSearch() }
                        .font(Theme.callout())
                        .foregroundStyle(Theme.accent)
                }
                .frame(maxWidth: .infinity)
                .padding()
            } else if hasSearched && !isSearching && results.isEmpty {
                VStack(spacing: 12) {
                    Text("No results. Try different keywords.")
                        .font(Theme.callout())
                        .foregroundStyle(Theme.textSecondary)
                    if !showingAllEditions {
                        Button("Show every edition") { showAllEditions() }
                            .font(Theme.callout())
                            .foregroundStyle(Theme.accent)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
            }

            ScrollView {
                if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    recentsSection
                        .padding()
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(results) { book in
                            BookSearchRow(book: book) {
                                openBookProfile(book)
                            }
                        }
                        if hasSearched && !isSearching && !results.isEmpty && !showingAllEditions {
                            VStack(spacing: 4) {
                                Text("Can't find what you're looking for?")
                                    .font(Theme.caption())
                                    .foregroundStyle(Theme.textSecondary)
                                Button("Show every edition") { showAllEditions() }
                                    .font(Theme.callout())
                                    .foregroundStyle(Theme.accent)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 8)
                        }
                    }
                    .padding()
                }
            }
        }
        .padding(.top, 28)
        .onAppear { refreshRecents() }
        .task {
            // Sheet presentation animations interfere with focus assignment if it
            // happens too early; a small delay reliably brings up the keyboard.
            try? await Task.sleep(nanoseconds: 350_000_000)
            isSearchFocused = true
        }
    }
    
    // MARK: - Recents

    private var recentsUid: String {
        authService.firebaseUser?.uid ?? "anon"
    }

    private func refreshRecents() {
        recentQueries = SearchRecents.queries(uid: recentsUid)
        recentBooks = SearchRecents.books(uid: recentsUid)
    }

    /// Opens a book profile from search results or recents, recording both the book
    /// and the query that surfaced it.
    private func openBookProfile(_ book: Book) {
        SearchRecents.addBook(book, uid: recentsUid)
        SearchRecents.addQuery(query, uid: recentsUid)
        refreshRecents()
        selectedBookForProfile = book
    }

    /// Shown while the search field is empty: past queries and recently opened books.
    @ViewBuilder
    private var recentsSection: some View {
        VStack(alignment: .leading, spacing: 22) {
            if !recentQueries.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Recent searches")
                        .font(Theme.headline())
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.bottom, 4)
                    ForEach(recentQueries, id: \.self) { q in
                        Button {
                            query = q
                            runSearch()
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "clock.arrow.circlepath")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(Theme.textTertiary)
                                Text(q)
                                    .font(Theme.callout())
                                    .foregroundStyle(Theme.textPrimary)
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                                Image(systemName: "arrow.up.left")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(Theme.textTertiary)
                            }
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if !recentBooks.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Recent books")
                        .font(Theme.headline())
                        .foregroundStyle(Theme.textSecondary)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(recentBooks) { b in
                                BookCoverView(book: b, size: 84, onTap: { openBookProfile(b) })
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Debounces keystrokes so results populate automatically as the user types,
    /// without firing a request on every character.
    private func scheduleSearch(for value: String) {
        searchTask?.cancel()
        // A new query goes back to curated results; "every edition" is per-search.
        showingAllEditions = false
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            // Clear stale results when the field is emptied.
            results = []
            hasSearched = false
            searchError = nil
            isSearching = false
            return
        }
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            await performSearch(trimmed)
        }
    }

    private func runSearch() {
        isSearchFocused = false
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        SearchRecents.addQuery(trimmed, uid: recentsUid)
        refreshRecents()
        searchTask = Task { await performSearch(trimmed) }
    }

    /// Re-runs the current search with the junk filter and edition dedup off.
    private func showAllEditions() {
        showingAllEditions = true
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        searchTask = Task { await performSearch(trimmed) }
    }

    private func performSearch(_ trimmed: String) async {
        // Authors already in the library get a small ranking boost.
        let libraryAuthors = Set(appState.userBooks.compactMap { $0.book?.author })
        let includeAll = showingAllEditions
        await MainActor.run {
            isSearching = true
            searchError = nil
        }
        do {
            let books = try await GoogleBooksService.shared.search(
                query: trimmed,
                includeAllEditions: includeAll,
                libraryAuthors: libraryAuthors
            )
            guard !Task.isCancelled else { return }
            await MainActor.run {
                results = books
                hasSearched = true
                isSearching = false
            }
        } catch {
            guard !Task.isCancelled else { return }
            await MainActor.run {
                hasSearched = true
                isSearching = false
                searchError = error.localizedDescription.isEmpty ? "Search failed. Check your connection and try again." : error.localizedDescription
            }
        }
    }
    
    private var statusStep: some View {
        VStack(alignment: .leading, spacing: 24) {
            if let book = selectedBook {
                HStack(spacing: 16) {
                    BookCoverView(book: book, size: 80)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(book.title).font(Theme.headline()).foregroundStyle(Theme.textPrimary)
                        Text(book.author).font(Theme.callout()).foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                }
                .padding()
                .wellReadCard()
                .padding(.horizontal)
            }
            Text("Status").font(Theme.headline()).foregroundStyle(Theme.textSecondary).padding(.horizontal)
            ForEach(ReadingStatus.allCases.filter { $0 != .currentlyReading }, id: \.self) { s in
                Button {
                    status = s
                    if s == .read {
                        step = .rating
                    } else {
                        saveAndDismiss()
                    }
                } label: {
                    HStack {
                        Text(s.rawValue).font(Theme.body()).foregroundStyle(Theme.textPrimary)
                        Spacer()
                        if status == s { Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent) }
                    }
                    .padding()
                    .wellReadCard()
                }
                .buttonStyle(.plain)
                .padding(.horizontal)
            }
            if selectedBook != nil {
                Button("Continue") {
                    if status == .read {
                        step = .rating
                    } else {
                        saveAndDismiss()
                    }
                }
                .font(Theme.headline())
                .foregroundStyle(Theme.background)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Theme.accentGloss)
                .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius))
                .padding(.horizontal)
            }
        }
        .padding(.top, 24)
    }
    
    private var ratingStep: some View {
        AddBookRatingStepView(
            isSaving: isSaving,
            saveError: saveError,
            onSave: { review in saveAndDismiss(ratingStepReview: review) }
        )
    }

    private func saveAndDismiss(ratingStepReview: String? = nil) {
        guard let book = selectedBook, let uid = authService.firebaseUser?.uid else { close(); return }
        let now = Date()
        let tempId = UUID()
        let ratingValue: Double? = nil
        let review: String?
        if status == .read {
            let trimmed = ratingStepReview?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            review = trimmed.isEmpty ? nil : trimmed
        } else {
            review = nil
        }
        let dateFinished = status == .read ? now : nil
        let dateStarted = status == .currentlyReading ? now : nil

        let optimistic = UserBook(
            id: tempId,
            userId: uid,
            bookId: book.id,
            book: book,
            status: status,
            rating: ratingValue,
            reviewText: review,
            dateStarted: dateStarted,
            dateFinished: dateFinished,
            createdAt: now,
            updatedAt: now,
            recommendedTo: [],
            tier: nil,
            tierOrder: nil,
            queueShelf: status == .wantToRead ? .backlog : nil,
            queueOrder: status == .wantToRead ? 0 : nil
        )
        appState.addUserBook(optimistic)
        if status == .read {
            appState.startTierHighlight(forBookId: book.id)
        }
        isSaving = true
        saveError = nil
        Task {
            do {
                let userBookRepo = UserBookRepository()
                _ = try await userBookRepo.addUserBook(
                    userId: uid,
                    book: book,
                    status: status,
                    rating: ratingValue,
                    reviewText: review,
                    dateStarted: dateStarted,
                    dateFinished: dateFinished
                )
                if status == .read {
                    let postRepo = PostRepository()
                    _ = try await postRepo.createPost(
                        userId: uid,
                        type: .finishedBook,
                        bookId: book.id,
                        caption: review,
                        rating: ratingValue,
                        dateFinished: dateFinished
                    )
                }
                await MainActor.run {
                    switch status {
                    case .read:
                        ToastCenter.shared.show(.markedAsRead(bookTitle: book.title, sharedToFeed: true))
                    case .wantToRead:
                        ToastCenter.shared.show(.addedToQueue(bookTitle: book.title))
                    case .currentlyReading:
                        ToastCenter.shared.show(.startedReading(bookTitle: book.title))
                    }
                    close()
                }
            } catch {
                await MainActor.run {
                    appState.userBooks.removeAll { $0.id == tempId }
                    saveError = error.localizedDescription
                    isSaving = false
                }
            }
        }
    }
}

private struct AddBookRatingStepView: View {
    let isSaving: Bool
    let saveError: String?
    let onSave: (String?) -> Void

    @State private var reviewText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("You'll rank this book in your tier list after saving.")
                .font(Theme.callout())
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal)
            Text("Review (optional)")
                .font(Theme.headline())
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal)
            TextEditor(text: $reviewText)
                .font(Theme.body())
                .foregroundStyle(Theme.textPrimary)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 100)
                .padding()
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius))
                .padding(.horizontal)
            Button("Save") {
                let t = reviewText.trimmingCharacters(in: .whitespacesAndNewlines)
                onSave(t.isEmpty ? nil : t)
            }
            .font(Theme.headline())
            .foregroundStyle(Theme.background)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Theme.accentGloss)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius))
            .padding(.horizontal)
            .disabled(isSaving)
            if let err = saveError {
                Text(err).font(Theme.caption()).foregroundStyle(.red).padding(.horizontal)
            }
        }
        .padding(.top, 24)
    }
}
