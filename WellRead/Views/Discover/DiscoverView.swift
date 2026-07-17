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
                    // Keep the tune-callout bubble (which hangs below the strip) above the content underneath.
                    .zIndex(1)

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
            SpinningSpineLogo()
            Text("Finding your next read…")
                .font(Theme.title2())
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyStateView: some View {
        let cameUpEmpty = appState.discoverLoadCameUpEmpty
        return VStack(spacing: 24) {
            Spacer(minLength: 0)
            SparklingSpineLogo()
            Text(cameUpEmpty ? "Nothing new that time" : "Find my next read")
                .font(Theme.title())
                .foregroundStyle(Theme.textPrimary)
            Text(cameUpEmpty
                 ? "Every pick came back as a book you've already read, queued, or passed on. Try again, or steer with different tiers, tags, or books."
                 : "Every pick is tailored to the books in your library and your interests — steer it with tiers, tags, or books you loved.")
                .font(Theme.body())
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button {
                appState.loadDiscoverSuggestionsIfNeeded()
            } label: {
                Text(cameUpEmpty ? "Try Again" : "Start")
                    .font(Theme.headline())
                    .foregroundStyle(Theme.onChrome)
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

/// Loading indicator for Discover: the SPINE mark spinning with a 4-second
/// cycle — it launches fast, bleeds off speed, and just as it's about to
/// stop it whips back up to full speed. Each cycle covers whole turns so the
/// repeat is seamless.
private struct SpinningSpineLogo: View {
    @State private var spinning = false

    var body: some View {
        Image("SpineLogo")
            .resizable()
            .renderingMode(.template)
            .scaledToFit()
            .frame(width: 72, height: 72)
            .foregroundStyle(Theme.accent)
            .rotationEffect(.degrees(spinning ? 1080 : 0))
            .animation(
                .timingCurve(0.1, 0.8, 0.2, 1.0, duration: 4).repeatForever(autoreverses: false),
                value: spinning
            )
            .onAppear { spinning = true }
            .accessibilityHidden(true)
    }
}

/// SPINE brand mark for the Discover empty state: the transparent logo tinted
/// with the accent color, with a cluster of gently twinkling sparkles in the
/// same tint superimposed above the reader's head.
private struct SparklingSpineLogo: View {
    @State private var twinkle = false

    var body: some View {
        ZStack {
            Image("SpineLogo")
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .frame(width: 120, height: 120)
            sparkle(size: 22, offset: CGSize(width: 34, height: -36), delay: 0)
            sparkle(size: 13, offset: CGSize(width: 50, height: -16), delay: 0.5)
            sparkle(size: 10, offset: CGSize(width: 18, height: -50), delay: 1.0)
        }
        .foregroundStyle(Theme.accent)
        .onAppear { twinkle = true }
        .accessibilityHidden(true)
    }

    private func sparkle(size: CGFloat, offset: CGSize, delay: Double) -> some View {
        Image(systemName: "sparkle")
            .font(.system(size: size, weight: .medium))
            .scaleEffect(twinkle ? 1.0 : 0.55)
            .opacity(twinkle ? 1.0 : 0.35)
            .offset(offset)
            .animation(
                .easeInOut(duration: 1.1).repeatForever(autoreverses: true).delay(delay),
                value: twinkle
            )
    }
}
