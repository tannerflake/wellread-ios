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
    @EnvironmentObject private var queueDragCoordinator: QueueBookDragCoordinator
    @State private var selectedBookForProfile: Book?
    @State private var bookWeCameFrom: Book?
    @State private var showCriteriaEditor = false

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                VStack(spacing: 0) {
                    spineDiscoverHeader

                    DiscoverCriteriaStrip(
                        criteria: appState.discoverCriteria,
                        interestTagsCount: appState.currentUser?.readingInterestTags.count ?? 0,
                        onRemove: { appState.setDiscoverCriteria($0) },
                        onEdit: { showCriteriaEditor = true },
                        bookForSeed: { seed in
                            appState.userBooks.first(where: { $0.bookId == seed.bookId })?.book
                        }
                    )

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
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.background, for: .navigationBar)
            .navigationDestination(item: $selectedBookForProfile) { book in
                BookProfileView(
                    book: book,
                    readBooksForSimilar: appState.readBooks,
                    onNotInterested: { selectedBookForProfile = nil },
                    onWantToRead: { appState.addToWantToRead(book: book); selectedBookForProfile = nil },
                    onConfirmRead: { date, rating, post, caption, tier in appState.addAsRead(book: book, dateFinished: date, rating: rating, postToFeed: post, caption: caption, tier: tier); selectedBookForProfile = nil },
                    isOnReadList: appState.isBookOnReadList(bookId: book.id),
                    isInQueue: appState.isBookInQueue(bookId: book.id),
                    readEntryForReview: appState.userReadBook(forBookId: book.id),
                    canEditReadReview: true,
                    showRecommend: false
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
            .sheet(isPresented: $showCriteriaEditor) {
                DiscoverCriteriaEditorSheet(initial: appState.discoverCriteria)
                    .environmentObject(appState)
                    .environmentObject(queueDragCoordinator)
                    .presentationDetents([.large])
            }
        }
    }

    /// Banner at the top of the Discover tab.
    private var spineDiscoverHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("DISCOVER")
                .font(.system(size: 22, weight: .bold))
                .tracking(2)
                .foregroundStyle(Theme.textPrimary)
            BrandRule(width: 48)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.horizontalPadding)
        .padding(.top, 8)
        .padding(.bottom, 12)
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
                    .foregroundStyle(Theme.phosphorWhite)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .glossyProminent()
            }
            .buttonStyle(.springPress)
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
            onConfirmRead: { date, rating, post, caption, tier in performHaveRead(book, dateFinished: date, rating: rating, postToFeed: post, caption: caption, tier: tier) },
            onBookTap: { tappedBook in
                bookWeCameFrom = appState.discoverCurrentSuggestion
                selectedBookForProfile = tappedBook
            },
            isOnReadList: appState.isBookOnReadList(bookId: book.id),
            isInQueue: appState.isBookInQueue(bookId: book.id),
            readEntryForReview: appState.userReadBook(forBookId: book.id),
            canEditReadReview: true,
            showRecommend: false
        )
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

    private func performHaveRead(_ book: Book, dateFinished: Date, rating: Double?, postToFeed: Bool, caption: String?, tier: String?) {
        appState.addAsRead(book: book, dateFinished: dateFinished, rating: rating, postToFeed: postToFeed, caption: caption, tier: tier)
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
