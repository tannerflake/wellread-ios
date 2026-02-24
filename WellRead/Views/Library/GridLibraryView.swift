//
//  GridLibraryView.swift
//  WellRead
//

import SwiftUI

struct GridLibraryView: View {
    let userBooks: [UserBook]
    
    private let columns = [
        GridItem(.adaptive(minimum: 100), spacing: Theme.gridSpacing)
    ]
    
    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: Theme.gridSpacing) {
                ForEach(userBooks) { ub in
                    if let book = ub.book {
                        VStack(alignment: .leading, spacing: 6) {
                            BookCoverView(book: book, size: 100)
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
