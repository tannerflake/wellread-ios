//
//  AddBookFlowView.swift
//  WellRead
//
//  Fast add flow: search → select → status → (if finished) rating + review.
//

import SwiftUI

struct AddBookFlowView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var authService: AuthService
    @EnvironmentObject var appState: AppState
    @FocusState private var isSearchFocused: Bool
    @State private var query = ""
    @State private var results: [Book] = []
    @State private var isSearching = false
    @State private var hasSearched = false
    @State private var searchError: String?
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var selectedBook: Book?
    @State private var selectedBookForProfile: Book?
    @State private var status: ReadingStatus = .read
    @State private var rating: Double = 7.0
    @State private var step: Step = .search
    
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
                    onWantToRead: { appState.addToWantToRead(book: book); selectedBookForProfile = nil },
                    onConfirmRead: { date, rating, post, caption in appState.addAsRead(book: book, dateFinished: date, rating: rating, postToFeed: post, caption: caption); selectedBookForProfile = nil },
                    isOnReadList: appState.isBookOnReadList(bookId: book.id),
                    isInQueue: appState.isBookInQueue(bookId: book.id),
                    onRemoveFromQueue: { appState.removeFromQueue(book: book); selectedBookForProfile = nil },
                    readEntryForReview: appState.userReadBook(forBookId: book.id),
                    canEditReadReview: true
                )
            }
        }
    }
    
    private var stepTitle: String {
        switch step {
        case .search: return "Add Book"
        case .status: return "Status"
        case .rating: return "Rating"
        }
    }
    
    private var searchStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(Theme.textSecondary)
                    TextField(
                        "",
                        text: $query,
                        prompt: Text("Search by title or author")
                            .foregroundColor(Theme.textTertiary)
                    )
                        .font(Theme.body())
                        .foregroundStyle(Theme.textPrimary)
                        .textContentType(.none)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .focused($isSearchFocused)
                        .onSubmit { runSearch() }
                }
                .padding()
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius))

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 36, height: 36)
                        .background(
                            Circle()
                                .fill(Theme.surface)
                        )
                        .overlay(
                            Circle()
                                .strokeBorder(Theme.chromeTeal.opacity(0.4), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }
            .padding(.horizontal)

            ZStack {
                Theme.accent
                Text("Search")
                    .font(Theme.headline())
                    .foregroundStyle(Theme.background)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .contentShape(Rectangle())
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius))
            .padding(.horizontal)
            .onTapGesture {
                isSearchFocused = false
                runSearch()
            }

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
                Text("No results. Try different keywords.")
                    .font(Theme.callout())
                    .foregroundStyle(Theme.textSecondary)
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
                }
                .padding()
            }
        }
        .padding(.top, 28)
        .task {
            // Sheet presentation animations interfere with focus assignment if it
            // happens too early; a small delay reliably brings up the keyboard.
            try? await Task.sleep(nanoseconds: 350_000_000)
            isSearchFocused = true
        }
    }
    
    private func runSearch() {
        isSearchFocused = false
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isSearching = true
        searchError = nil
        results = []
        Task {
            do {
                let books = try await GoogleBooksService.shared.search(query: trimmed)
                await MainActor.run {
                    results = books
                    hasSearched = true
                    isSearching = false
                }
            } catch {
                await MainActor.run {
                    hasSearched = true
                    isSearching = false
                    searchError = error.localizedDescription.isEmpty ? "Search failed. Check your connection and try again." : error.localizedDescription
                }
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
            rating: $rating,
            isSaving: isSaving,
            saveError: saveError,
            onSave: { _, review in saveAndDismiss(ratingStepReview: review) }
        )
    }

    private func saveAndDismiss(ratingStepReview: String? = nil) {
        guard let book = selectedBook, let uid = authService.firebaseUser?.uid else { dismiss(); return }
        let now = Date()
        let tempId = UUID()
        let ratingValue = status == .read ? Theme.normalizeRatingOutOfTen(rating) : nil
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
                await MainActor.run { dismiss() }
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
    @Binding var rating: Double
    let isSaving: Bool
    let saveError: String?
    let onSave: (Double, String?) -> Void

    @State private var reviewText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Rating: \(Theme.formatRatingOutOfTen(rating)) / 10")
                .font(Theme.title2())
                .foregroundStyle(Theme.textPrimary)
            Slider(value: $rating, in: 1...10, step: 0.1)
                .tint(Theme.accent)
                .padding(.horizontal)
            Text("Review (optional)")
                .font(Theme.headline())
                .foregroundStyle(Theme.textSecondary)
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
                onSave(rating, t.isEmpty ? nil : t)
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
