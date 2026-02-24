//
//  RatingLibraryView.swift
//  WellRead
//
//  Sorted descending by rating.
//

import SwiftUI

struct RatingLibraryView: View {
    let userBooks: [UserBook]
    
    private var sorted: [UserBook] {
        userBooks
            .filter { $0.rating != nil }
            .sorted { ($0.rating ?? 0) > ($1.rating ?? 0) }
    }
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(sorted) { ub in
                    if let book = ub.book, let r = ub.rating {
                        HStack(spacing: 14) {
                            Text("\(r)")
                                .font(Theme.title2())
                                .foregroundStyle(Theme.accent)
                                .frame(width: 28, alignment: .leading)
                            BookCoverView(book: book, size: 56)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(book.title).font(Theme.headline()).foregroundStyle(Theme.textPrimary)
                                Text(book.author).font(Theme.caption()).foregroundStyle(Theme.textSecondary)
                            }
                            Spacer()
                        }
                        .padding()
                        .wellReadCard()
                    }
                }
            }
            .padding()
        }
    }
}
