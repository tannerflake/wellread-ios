//
//  BookProfileView.swift
//  WellRead
//
//  Default book profile (Hinge-style): hero cover, title, author, summary + tags, notable quote,
//  optional "Similar to" row, and three actions (Pass, Read, Queue).
//

import SwiftUI

struct BookProfileView: View {
    let book: Book
    /// When provided, we load and show "Similar to" with cute small covers from the user's read list.
    var readBooksForSimilar: [UserBook]? = nil
    var onNotInterested: (() -> Void)? = nil
    var onWantToRead: (() -> Void)? = nil
    /// Called when user confirms "Mark as Read" with (dateFinished, rating out of 10 e.g. 8.8, postToFeed, thoughtsCaption). When set, tapping Read shows the inline modal instead of firing immediately.
    var onConfirmRead: ((Date, Double?, Bool, String?) -> Void)? = nil
    /// When set, tapping a similar book opens that book (e.g. sets navigation selection). Used from Discover.
    var onBookTap: ((Book) -> Void)? = nil
    /// True when this book is already on the user's read list (affects Read button appearance).
    var isOnReadList: Bool = false
    /// True when this book is already in the user's queue (affects Queue button appearance).
    var isInQueue: Bool = false
    /// When set (e.g. from Library/Add/Feed), shows "Remove" when isInQueue; when nil (e.g. Discover), Queue button is disabled when isInQueue.
    var onRemoveFromQueue: (() -> Void)? = nil
    /// When set and the entry has review text and/or a rating, shows the first card section (e.g. current user's read row).
    var readEntryForReview: UserBook? = nil
    /// Section title for that card (`"Your review"` vs `"Review"` on someone else's profile).
    var reviewSectionHeading: String = "Your review"
    /// When `true`, shows a pencil on the review card to edit date, rating, thoughts, feed visibility, or delete.
    var canEditReadReview: Bool = false

    @EnvironmentObject private var appState: AppState

    @State private var summary: String?
    @State private var notableQuote: String?
    @State private var similarBooks: [Book] = []
    @State private var summaryLoading = false
    @State private var quoteLoading = false
    @State private var similarLoading = false
    @State private var showMarkAsReadModal = false
    @State private var markAsReadDate = Date()
    /// Visual middle of 1…10; label shows "—" until the user moves the slider.
    @State private var markAsReadSliderValue: Double = 5.5
    @State private var hasExplicitMarkReadRating = false
    @State private var markAsReadPostToFeed = true
    @State private var markAsReadThoughts = ""
    @State private var profileTags: [String] = []
    @State private var tagsLoading = false
    @State private var userBookToEdit: UserBook? = nil

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

    private var showActionBar: Bool {
        onNotInterested != nil || onWantToRead != nil || onConfirmRead != nil || onRemoveFromQueue != nil
    }

    /// Show review card when this read row has review text and/or a rating.
    private var showReviewSection: Bool {
        guard let ub = readEntryForReview else { return false }
        guard ub.status == .read else { return false }
        let trimmed = ub.reviewText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let hasText = !trimmed.isEmpty
        let hasRating = ub.rating != nil
        return hasText || hasRating
    }

    private let actionBarHeight: CGFloat = 76
    /// Extra scroll space below the last section so content clears the fixed action bar.
    private let actionBarScrollGap: CGFloat = 28

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Hero cover — front and center
                    VStack(spacing: 16) {
                        BookCoverView(book: book, size: 220)
                            .shadow(color: .black.opacity(0.2), radius: 12, x: 0, y: 6)
                        VStack(spacing: 6) {
                            Text(book.title)
                                .font(Theme.title())
                                .foregroundStyle(Theme.textPrimary)
                                .multilineTextAlignment(.center)
                            Text(book.author)
                                .font(Theme.headline())
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 16)

                    // Your review (first card section when present)
                    if showReviewSection, let ub = readEntryForReview {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .center, spacing: 12) {
                                Text(reviewSectionHeading)
                                    .font(Theme.profileSectionHeader())
                                    .foregroundStyle(Theme.textSecondary)
                                    .multilineTextAlignment(.leading)
                                Spacer(minLength: 8)
                                if canEditReadReview {
                                    Button {
                                        userBookToEdit = ub
                                    } label: {
                                        Image(systemName: "pencil")
                                            .font(.body.weight(.semibold))
                                            .foregroundStyle(Theme.textSecondary)
                                    }
                                    .buttonStyle(.plain)
                                }
                                if let r = ub.rating {
                                    Text("\(Theme.formatRatingOutOfTen(r))/10")
                                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                                        .foregroundStyle(Theme.background)
                                        .padding(.horizontal, 11)
                                        .padding(.vertical, 6)
                                        .background(Theme.accent)
                                        .clipShape(Capsule())
                                }
                            }
                            if let text = ub.reviewText?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                                Text(text)
                                    .font(Theme.body())
                                    .foregroundStyle(Theme.textPrimary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius))
                        .padding(.horizontal)
                    }

                    // Summary
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Summary")
                            .font(Theme.profileSectionHeader())
                            .foregroundStyle(Theme.textSecondary)
                        if summaryLoading {
                            ProgressView()
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 12)
                        } else if let s = summary, !s.isEmpty {
                            Text(s)
                                .font(Theme.body())
                                .foregroundStyle(Theme.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            Text("Summary unavailable.")
                                .font(Theme.callout())
                                .foregroundStyle(Theme.textTertiary)
                        }

                        if tagsLoading {
                            ProgressView()
                                .controlSize(.small)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 4)
                        } else if !profileTags.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 5) {
                                    ForEach(profileTags, id: \.self) { tag in
                                        Text(tag)
                                            .font(.caption2)
                                            .fontWeight(.medium)
                                            .foregroundStyle(Theme.textSecondary)
                                            .padding(.horizontal, 7)
                                            .padding(.vertical, 3)
                                            .background(Theme.textTertiary.opacity(0.12))
                                            .clipShape(Capsule())
                                    }
                                }
                            }
                            .padding(.top, 8)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius))
                    .padding(.horizontal)

                    // Similar to — cute little icons (only when we have similar books)
                    if !readBooksForSimilar.isEmptyOrNil && (similarLoading || !similarBooks.isEmpty) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Similar to books you've read")
                                .font(Theme.profileSectionHeader())
                                .foregroundStyle(Theme.textSecondary)
                            if similarLoading {
                                HStack(spacing: 12) {
                                    ForEach(0..<3, id: \.self) { _ in
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(Theme.surface)
                                            .frame(width: 52, height: 52 * 1.5)
                                            .overlay(ProgressView().tint(Theme.accent))
                                    }
                                }
                            } else {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 14) {
                                        ForEach(similarBooks) { similar in
                                            VStack(spacing: 6) {
                                                BookCoverView(book: similar, size: 52, onTap: onBookTap != nil ? { onBookTap?(similar) } : nil)
                                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                                Text(similar.title)
                                                    .font(.caption2)
                                                    .foregroundStyle(Theme.textSecondary)
                                                    .lineLimit(2)
                                                    .multilineTextAlignment(.center)
                                                    .frame(width: 64)
                                            }
                                        }
                                    }
                                    .padding(.vertical, 4)
                                }
                            }
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius))
                        .padding(.horizontal)
                    }

                    // Notable quote
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Notable quote")
                            .font(Theme.profileSectionHeader())
                            .foregroundStyle(Theme.textSecondary)
                        if quoteLoading {
                            ProgressView()
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 12)
                        } else if let q = notableQuote, !q.isEmpty {
                            Text(q)
                                .font(Theme.body())
                                .italic()
                                .foregroundStyle(Theme.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            Text("No notable quote available.")
                                .font(Theme.callout())
                                .foregroundStyle(Theme.textTertiary)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius))
                    .padding(.horizontal)
                }
                .padding(.bottom, showActionBar ? actionBarHeight + actionBarScrollGap : 40)
            }
            .background(Theme.background)

            if showActionBar {
                actionBar
            }
        }
        .overlay { markAsReadOverlay }
        .sheet(item: $userBookToEdit) { ub in
            EditReadReviewSheet(userBook: ub)
                .environmentObject(appState)
        }
        .navigationBarTitleDisplayMode(.inline)
        .task(id: book.id) {
            profileTags = []
            tagsLoading = true
            summaryLoading = true
            quoteLoading = true

            async let tagsTask = BookProfileService.shared.profileTags(for: book)
            async let summaryTask = BookProfileService.shared.twoSentenceSummary(for: book)
            async let quoteTask = BookProfileService.shared.notableQuote(for: book)

            let (tags, sum, quote) = await (tagsTask, summaryTask, quoteTask)
            profileTags = tags
            tagsLoading = false
            summary = sum
            summaryLoading = false
            notableQuote = quote
            quoteLoading = false

            if let read = readBooksForSimilar, !read.isEmpty {
                similarLoading = true
                similarBooks = await BookProfileService.shared.similarBooks(for: book, readBooks: read)
                similarLoading = false
            }
        }
    }

    @ViewBuilder
    private var markAsReadOverlay: some View {
        if showMarkAsReadModal {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture { withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { showMarkAsReadModal = false } }
                .overlay(alignment: .bottom) {
                    markAsReadCard
                        .padding(.horizontal, 20)
                        .padding(.bottom, 100)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .bottom)).combined(with: .scale(scale: 0.92)),
                            removal: .opacity.combined(with: .move(edge: .bottom))
                        ))
                }
                .animation(.spring(response: 0.35, dampingFraction: 0.82), value: showMarkAsReadModal)
        }
    }

    private var markAsReadCard: some View {
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
            TextField("Thoughts on this book...", text: $markAsReadThoughts, axis: .vertical)
                .font(Theme.body())
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(3...6)
                .padding(12)
                .background(Theme.background.opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 10))
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
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { showMarkAsReadModal = false }
                onConfirmRead?(date, rating, post, thoughts.isEmpty ? nil : thoughts)
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
        .padding(20)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius))
        .shadow(color: .black.opacity(0.25), radius: 20, y: 8)
    }

    private var actionBar: some View {
        HStack(spacing: 12) {
            if onNotInterested != nil {
                Button(action: { onNotInterested?() }) {
                    Label("Pass", systemImage: "xmark.circle.fill")
                        .font(Theme.headline())
                        .foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Theme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius))
                }
                .buttonStyle(.plain)
            }
            if onConfirmRead != nil {
                Button(action: {
                    if isOnReadList { return }
                    markAsReadDate = Date()
                    markAsReadSliderValue = 5.5
                    hasExplicitMarkReadRating = false
                    markAsReadPostToFeed = true
                    markAsReadThoughts = ""
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { showMarkAsReadModal = true }
                }) {
                    Label(isOnReadList ? "On read list" : "Read", systemImage: "checkmark.circle.fill")
                        .font(Theme.headline())
                        .foregroundStyle(isOnReadList ? Theme.background : Theme.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(isOnReadList ? Theme.accent : Theme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius))
                }
                .buttonStyle(.plain)
                .disabled(isOnReadList)
            }
            if onWantToRead != nil || onRemoveFromQueue != nil {
                Group {
                    if isInQueue && onRemoveFromQueue != nil {
                        Button(action: { onRemoveFromQueue?() }) {
                            Label("Remove", systemImage: "book.circle.fill")
                                .font(Theme.headline())
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color(red: 0.95, green: 0.4, blue: 0.4))
                                .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius))
                        }
                        .buttonStyle(.plain)
                    } else if isInQueue {
                        Button {} label: {
                            Label("In queue", systemImage: "book.circle.fill")
                                .font(Theme.headline())
                                .foregroundStyle(Theme.textTertiary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Theme.surface)
                                .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius))
                        }
                        .buttonStyle(.plain)
                        .disabled(true)
                    } else {
                        Button(action: { onWantToRead?() }) {
                            Label("Queue", systemImage: "book.circle.fill")
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
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .padding(.bottom, 8)
    }
}

private extension Optional where Wrapped == [UserBook] {
    var isEmptyOrNil: Bool {
        self == nil || self?.isEmpty == true
    }
}
