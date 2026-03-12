//
//  BookProfileView.swift
//  WellRead
//
//  Default book profile (Hinge-style): hero cover, title, author, summary, notable quote,
//  optional "Similar to" row, and three actions (Pass, Read, Queue).
//

import SwiftUI

struct BookProfileView: View {
    let book: Book
    /// When provided, we load and show "Similar to" with cute small covers from the user's read list.
    var readBooksForSimilar: [UserBook]? = nil
    var onNotInterested: (() -> Void)? = nil
    var onWantToRead: (() -> Void)? = nil
    var onHaveRead: (() -> Void)? = nil
    /// When set, tapping a similar book opens that book (e.g. sets navigation selection). Used from Discover.
    var onBookTap: ((Book) -> Void)? = nil
    /// True when this book is already on the user's read list (affects Read button appearance).
    var isOnReadList: Bool = false
    /// True when this book is already in the user's queue (affects Queue button appearance).
    var isInQueue: Bool = false

    @State private var summary: String?
    @State private var notableQuote: String?
    @State private var similarBooks: [Book] = []
    @State private var summaryLoading = false
    @State private var quoteLoading = false
    @State private var similarLoading = false

    private var showActionBar: Bool {
        onNotInterested != nil || onWantToRead != nil || onHaveRead != nil
    }

    private let actionBarHeight: CGFloat = 76
    /// Space so the action bar sits above the tab bar (tab bar + small gap).
    private let tabBarInset: CGFloat = 52

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

                    // Summary
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Summary")
                            .font(Theme.headline())
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
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius))
                    .padding(.horizontal)

                    // Similar to — cute little icons (only when we have similar books)
                    if !readBooksForSimilar.isEmptyOrNil && (similarLoading || !similarBooks.isEmpty) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Similar to books you've read")
                                .font(Theme.headline())
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
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Notable quote")
                            .font(Theme.headline())
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
                .padding(.bottom, showActionBar ? actionBarHeight + tabBarInset + 24 : 40)
            }
            .background(Theme.background)

            if showActionBar {
                actionBar
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task(id: book.id) {
            summaryLoading = true
            summary = await BookProfileService.shared.twoSentenceSummary(for: book)
            summaryLoading = false

            quoteLoading = true
            notableQuote = await BookProfileService.shared.notableQuote(for: book)
            quoteLoading = false

            if let read = readBooksForSimilar, !read.isEmpty {
                similarLoading = true
                similarBooks = await BookProfileService.shared.similarBooks(for: book, readBooks: read)
                similarLoading = false
            }
        }
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
            if onHaveRead != nil {
                Button(action: { onHaveRead?() }) {
                    Label(isOnReadList ? "On read list" : "Read", systemImage: "checkmark.circle.fill")
                        .font(Theme.headline())
                        .foregroundStyle(isOnReadList ? Theme.background : Theme.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(isOnReadList ? Theme.accent : Theme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius))
                }
                .buttonStyle(.plain)
            }
            if onWantToRead != nil {
                Button(action: { onWantToRead?() }) {
                    Label(isInQueue ? "In queue" : "Queue", systemImage: "book.circle.fill")
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
        .padding(.horizontal)
        .padding(.vertical, 10)
        .padding(.bottom, tabBarInset)
    }
}

private extension Optional where Wrapped == [UserBook] {
    var isEmptyOrNil: Bool {
        self == nil || self?.isEmpty == true
    }
}
