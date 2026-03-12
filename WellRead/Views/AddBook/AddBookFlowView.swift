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
    @State private var rating: Double = 7
    @State private var reviewText = ""
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
            .navigationTitle(stepTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Theme.accent)
                }
            }
            .navigationDestination(item: $selectedBookForProfile) { book in
                BookProfileView(
                    book: book,
                    readBooksForSimilar: appState.readBooks,
                    onNotInterested: { selectedBookForProfile = nil },
                    onWantToRead: { appState.addToWantToRead(book: book); selectedBookForProfile = nil },
                    onHaveRead: { appState.addAsRead(book: book); selectedBookForProfile = nil }
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
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Theme.textSecondary)
                TextField("Search by title or author", text: $query)
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

            if !hasSearched && !isSearching && searchError == nil {
                Text("Tap Search or press Return to find books.")
                    .font(Theme.caption())
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
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
        .padding(.top, 8)
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
        VStack(alignment: .leading, spacing: 24) {
            Text("Rating: \(Int(rating))/10")
                .font(Theme.title2())
                .foregroundStyle(Theme.textPrimary)
            Slider(value: $rating, in: 1...10, step: 1)
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
            Button("Save") { saveAndDismiss() }
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
    
    private func saveAndDismiss() {
        guard let book = selectedBook, let uid = authService.firebaseUser?.uid else { dismiss(); return }
        let now = Date()
        let tempId = UUID()
        let ratingValue = status == .read ? Int(rating) : nil
        let review = reviewText.isEmpty ? nil : reviewText
        let dateFinished = status == .read ? now : nil
        let dateStarted = status == .currentlyReading ? now : nil

        var optimistic = UserBook(
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
            tier: nil
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
                        caption: review
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
