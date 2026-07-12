//
//  AddBookFlowView.swift
//  WellRead
//
//  Fast add flow: search → select → status → (if finished) review.
//

import SwiftUI

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
    /// Height the drawer is showing at. Starts compact and grows to `.large` once a search runs.
    @Binding var detent: PresentationDetent
    /// When set (opened from a queue shelf's "Add" tile), book profiles show a primary
    /// CTA that adds the book straight onto this shelf.
    var targetShelf: QueueShelf? = nil

    /// Compact height the search drawer opens at before any books are loaded.
    static let smallDetent: PresentationDetent = .fraction(0.5)

    /// Height the drawer grows to once a search runs — stops short of the top so
    /// there's room to tap out and dismiss.
    static let expandedDetent: PresentationDetent = .fraction(0.8)

    /// UIKit equivalent of `Theme.body()` (serif, size 17) for the search field.
    private static var searchFieldUIFont: UIFont {
        let size: CGFloat = 17
        let base = UIFont.systemFont(ofSize: size, weight: .regular)
        return base.fontDescriptor.withDesign(.serif).map { UIFont(descriptor: $0, size: size) } ?? base
    }

    enum Step {
        case search
        case status
        case rating
    }
    
    var body: some View {
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
            .toolbarColorScheme(.light, for: .navigationBar)
            .toolbar {
                if step != .search {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
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
                    onWantToRead: { appState.addToWantToRead(book: book); appState.openQueue(); dismiss() },
                    // Marking read fires the tier-highlight flow (switches to Profile → Read and
                    // scrolls to the book). Dismiss the whole search sheet so that lands in view,
                    // rather than popping back to the search bar.
                    onConfirmRead: { date, rating, post, caption, tier in appState.addAsRead(book: book, dateFinished: date, rating: rating, postToFeed: post, caption: caption, tier: tier); dismiss() },
                    isOnReadList: appState.isBookOnReadList(bookId: book.id),
                    isInQueue: appState.isBookInQueue(bookId: book.id),
                    onRemoveFromQueue: { appState.removeFromQueue(book: book); selectedBookForProfile = nil },
                    readEntryForReview: appState.userReadBook(forBookId: book.id),
                    canEditReadReview: true,
                    shelfActionTitle: targetShelf.map(Self.shelfCTATitle),
                    onAddToShelf: targetShelf.map { shelf in
                        // Same landing behavior as Queue: dismiss the search sheet onto the queue.
                        { appState.addToQueue(book: book, shelf: shelf); appState.openQueue(); dismiss() }
                    }
                )
            }
        }
    }

    private static func shelfCTATitle(_ shelf: QueueShelf) -> String {
        switch shelf {
        case .readingNow: return "[ + READING NOW ]"
        case .upNext: return "[ + UP NEXT ]"
        case .backlog: return "[ + BACKLOG ]"
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
                }
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
                LazyVStack(spacing: 12) {
                    ForEach(results) { book in
                        BookSearchRow(book: book) {
                            selectedBookForProfile = book
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
        .padding(.top, 28)
        // Grow the drawer once books start loading; stay compact until then.
        .onChange(of: isSearching) { _, searching in
            if searching { withAnimation(.easeInOut(duration: 0.25)) { detent = Self.expandedDetent } }
        }
        .onChange(of: results.isEmpty) { _, empty in
            if !empty { withAnimation(.easeInOut(duration: 0.25)) { detent = Self.expandedDetent } }
        }
        .task {
            // Sheet presentation animations interfere with focus assignment if it
            // happens too early; a small delay reliably brings up the keyboard.
            try? await Task.sleep(nanoseconds: 350_000_000)
            isSearchFocused = true
        }
    }
    
    /// Debounces keystrokes so results populate automatically as the user types,
    /// without firing a request on every character.
    private func scheduleSearch(for value: String) {
        searchTask?.cancel()
        // A new query goes back to curated results; "every edition" is per-search.
        showingAllEditions = false
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            // Clear stale results when the field is emptied, and shrink back to compact.
            results = []
            hasSearched = false
            searchError = nil
            isSearching = false
            withAnimation(.easeInOut(duration: 0.25)) { detent = Self.smallDetent }
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
                .background(Theme.accent)
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
        guard let book = selectedBook, let uid = authService.firebaseUser?.uid else { dismiss(); return }
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
                    dismiss()
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
            .background(Theme.accent)
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
