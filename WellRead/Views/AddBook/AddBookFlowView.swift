//
//  AddBookFlowView.swift
//  WellRead
//
//  Fast add flow: search → select → status → (if finished) rating + review.
//

import SwiftUI

struct AddBookFlowView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState
    @State private var query = ""
    @State private var results: [Book] = []
    @State private var isSearching = false
    @State private var selectedBook: Book?
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
                    .onSubmit { runSearch() }
            }
            .padding()
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius))
            .padding(.horizontal)
            
            Button("Search") { runSearch() }
                .font(Theme.headline())
                .foregroundStyle(Theme.background)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Theme.accent)
                .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius))
                .padding(.horizontal)
            
            if isSearching {
                HStack {
                    ProgressView().tint(Theme.accent)
                    Text("Searching…").font(Theme.callout()).foregroundStyle(Theme.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding()
            }
            
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(results) { book in
                        BookSearchRow(book: book) {
                            selectedBook = book
                            step = .status
                        }
                    }
                }
                .padding()
            }
        }
        .padding(.top, 8)
    }
    
    private func runSearch() {
        guard !query.isEmpty else { return }
        isSearching = true
        results = []
        Task {
            do {
                let books = try await GoogleBooksService.shared.search(query: query)
                await MainActor.run {
                    results = books
                    isSearching = false
                }
            } catch {
                await MainActor.run { isSearching = false }
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
            ForEach(ReadingStatus.allCases, id: \.self) { s in
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
        }
        .padding(.top, 24)
    }
    
    private func saveAndDismiss() {
        guard let book = selectedBook, let user = appState.currentUser else { dismiss(); return }
        let now = Date()
        var ub = UserBook(
            id: UUID(),
            userId: user.id,
            bookId: book.id,
            book: book,
            status: status,
            rating: status == .read ? Int(rating) : nil,
            reviewText: reviewText.isEmpty ? nil : reviewText,
            dateStarted: nil,
            dateFinished: status == .read ? now : nil,
            createdAt: now,
            updatedAt: now,
            recommendedTo: [],
            tier: nil
        )
        if status == .currentlyReading { ub.dateStarted = now }
        appState.addUserBook(ub)
        dismiss()
    }
}
