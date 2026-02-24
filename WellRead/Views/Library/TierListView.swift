//
//  TierListView.swift
//  WellRead
//
//  Drag-and-drop tiers: S, A, B, C, D. Unranked bucket for books without tier.
//

import SwiftUI

private let tierLabels = ["S", "A", "B", "C", "D"]

struct TierListView: View {
    let userBooks: [UserBook]
    let onUpdateTier: (UUID, String?) -> Void
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(tierLabels, id: \.self) { tier in
                    TierRowView(
                        tier: tier,
                        books: userBooks.filter { $0.tier == tier },
                        onUpdateTier: onUpdateTier
                    )
                }
                TierRowView(
                    tier: nil,
                    books: userBooks.filter { $0.tier == nil || $0.tier?.isEmpty == true },
                    onUpdateTier: onUpdateTier
                )
            }
            .padding()
        }
    }
}

struct TierRowView: View {
    let tier: String?
    let books: [UserBook]
    let onUpdateTier: (UUID, String?) -> Void
    
    var header: String {
        tier ?? "Unranked"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(header)
                .font(Theme.headline())
                .foregroundStyle(tier == "S" ? Theme.accent : Theme.textSecondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(books) { ub in
                        if let book = ub.book {
                            TierBookCell(userBook: ub, onMoveToTier: { newTier in
                                onUpdateTier(ub.id, newTier)
                            })
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }
}

struct TierBookCell: View {
    let userBook: UserBook
    let onMoveToTier: (String?) -> Void
    
    var body: some View {
        Group {
            if let book = userBook.book {
                BookCoverView(book: book, size: 72)
                    .contextMenu {
                        ForEach(tierLabels, id: \.self) { t in
                            Button("Move to \(t)") { onMoveToTier(t) }
                        }
                        Button("Unranked") { onMoveToTier(nil) }
                    }
            }
        }
    }
}
