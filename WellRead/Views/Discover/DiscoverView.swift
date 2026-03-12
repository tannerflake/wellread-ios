//
//  DiscoverView.swift
//  WellRead
//
//  Full-screen Hinge-style discovery: one book at a time with three actions.
//  Suggestions are prefetched when the tab bar appears so the first suggestion is ready when user taps Discover.
//

import SwiftUI

struct DiscoverView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedBookForProfile: Book?
    @State private var bookWeCameFrom: Book?

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                VStack(spacing: 0) {
                    Group {
                        if appState.isLoadingDiscoverSuggestions && appState.discoverCurrentSuggestion == nil {
                            loadingView
                        } else if let book = appState.discoverCurrentSuggestion {
                            suggestionCardFullScreen(book: book)
                        } else {
                            emptyStateView
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("Discover")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .navigationDestination(item: $selectedBookForProfile) { book in
                BookProfileView(
                    book: book,
                    readBooksForSimilar: appState.readBooks,
                    onNotInterested: { selectedBookForProfile = nil },
                    onWantToRead: { appState.addToWantToRead(book: book); selectedBookForProfile = nil },
                    onHaveRead: { appState.addAsRead(book: book); selectedBookForProfile = nil },
                    isOnReadList: appState.isBookOnReadList(bookId: book.id),
                    isInQueue: appState.isBookInQueue(bookId: book.id)
                )
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            if let prev = bookWeCameFrom {
                                appState.returnToDiscoverBook(prev)
                            }
                            bookWeCameFrom = nil
                            selectedBookForProfile = nil
                        } label: {
                            Image(systemName: "chevron.left")
                        }
                    }
                }
            }
            .onAppear {
                if appState.discoverCurrentSuggestion == nil, !appState.discoverSuggestionQueue.isEmpty {
                    appState.advanceDiscoverSuggestion()
                } else if appState.discoverCurrentSuggestion == nil, appState.discoverSuggestionQueue.isEmpty, !appState.isLoadingDiscoverSuggestions {
                    appState.loadDiscoverSuggestionsIfNeeded()
                }
            }
        }
    }

    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.2)
                .tint(Theme.accent)
            Text("Finding your next read…")
                .font(Theme.title2())
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 0)
            Image(systemName: "sparkles")
                .font(.system(size: 56))
                .foregroundStyle(Theme.accent)
            Text("Find my next read")
                .font(Theme.title())
                .foregroundStyle(Theme.textPrimary)
            Text("Get a personalized suggestion and swipe through your next favorite book.")
                .font(Theme.body())
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button {
                appState.loadDiscoverSuggestionsIfNeeded()
            } label: {
                Text("Start")
                    .font(Theme.headline())
                    .foregroundStyle(Theme.background)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Theme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 40)
            .padding(.top, 8)
            .disabled(appState.isLoadingDiscoverSuggestions)
            Spacer(minLength: 0)
        }
    }

    private func suggestionCardFullScreen(book: Book) -> some View {
        BookProfileView(
            book: book,
            readBooksForSimilar: appState.readBooks,
            onNotInterested: { performNotInterested(book) },
            onWantToRead: { performWantToRead(book) },
            onHaveRead: { performHaveRead(book) },
            onBookTap: { tappedBook in
                bookWeCameFrom = appState.discoverCurrentSuggestion
                selectedBookForProfile = tappedBook
            },
            isOnReadList: appState.isBookOnReadList(bookId: book.id),
            isInQueue: appState.isBookInQueue(bookId: book.id)
        )
        .padding(.horizontal)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .id(book.id)
    }

    private func performNotInterested(_ book: Book) {
        appState.addDismissedBookId(book.id)
        appState.advanceDiscoverSuggestion()
    }

    private func performWantToRead(_ book: Book) {
        appState.addToWantToRead(book: book)
        appState.advanceDiscoverSuggestion()
    }

    private func performHaveRead(_ book: Book) {
        appState.addAsRead(book: book)
        appState.advanceDiscoverSuggestion()
    }
}

struct DiscoverBookCard: View {
    let book: Book
    var onCoverTap: (() -> Void)? = nil
    let onAdd: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            BookCoverView(book: book, size: 100, onTap: onCoverTap)
            Text(book.title)
                .font(Theme.caption())
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(2)
                .frame(width: 100, alignment: .leading)
            Button("Queue") {
                onAdd()
            }
            .font(.caption2)
            .foregroundStyle(Theme.accent)
        }
        .frame(width: 100)
    }
}
