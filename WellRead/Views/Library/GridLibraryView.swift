//
//  GridLibraryView.swift
//  WellRead
//
//  When onMoveToRead is set (e.g. Queue segment), long-press a cover to mark as Read.
//

import SwiftUI

struct GridLibraryView: View {
    let userBooks: [UserBook]
    /// When non-nil (e.g. on Queue), long-press a book to move it to Read.
    var onMoveToRead: ((UserBook) -> Void)? = nil
    /// When set, tapping a book cover opens the book profile.
    var onBookTap: ((Book) -> Void)? = nil

    private let columns = [
        GridItem(.adaptive(minimum: 100), spacing: Theme.gridSpacing)
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: Theme.gridSpacing) {
                ForEach(userBooks) { ub in
                    if let book = ub.book {
                        VStack(alignment: .leading, spacing: 6) {
                            BookCoverView(book: book, size: 100, onTap: onBookTap != nil ? { onBookTap?(book) } : nil)
                                .onLongPressGesture(minimumDuration: 0.5) {
                                    onMoveToRead?(ub)
                                }
                                .contextMenu {
                                    if let onMoveToRead {
                                        Button {
                                            onMoveToRead(ub)
                                        } label: {
                                            Label("Mark as Read", systemImage: "checkmark.circle")
                                        }
                                    }
                                }
                            Text(book.title)
                                .font(Theme.caption())
                                .foregroundStyle(Theme.textPrimary)
                                .lineLimit(2)
                            if let r = ub.rating {
                                HStack(spacing: 2) {
                                    Image(systemName: "star.fill")
                                        .font(.caption2)
                                        .foregroundStyle(Theme.accent)
                                    Text("\(r)").font(Theme.caption()).foregroundStyle(Theme.textSecondary)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding()
        }
    }
}
