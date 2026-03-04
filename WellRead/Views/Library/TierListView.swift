//
//  TierListView.swift
//  WellRead
//
//  Drag-and-drop tiers: S, A, B, C, D, Unranked. Brief press and drag a book onto a tier row.
//

import SwiftUI
import UniformTypeIdentifiers

// Shortens the system long-press before drag starts (used on tier book cells).
private struct ShorterDragPressModifier: ViewModifier {
    let minimumDuration: TimeInterval

    func body(content: Content) -> some View {
        content.background(ShorterDragPressFinder(minimumDuration: minimumDuration))
    }
}

private struct ShorterDragPressFinder: UIViewRepresentable {
    let minimumDuration: TimeInterval

    func makeUIView(context: Context) -> UIView {
        let v = UIView()
        v.backgroundColor = .clear
        v.isUserInteractionEnabled = false
        return v
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async {
            guard let container = uiView.superview else { return }
            var toCheck: [UIView] = [container]
            toCheck.append(contentsOf: container.subviews)
            for view in toCheck {
                for rec in view.gestureRecognizers ?? [] {
                    guard let long = rec as? UILongPressGestureRecognizer else { continue }
                    let name = String(describing: type(of: long))
                    if name.contains("Lift") || name.contains("Drag") {
                        long.minimumPressDuration = minimumDuration
                        return
                    }
                }
            }
        }
    }
}

private let tierLabels = ["S", "A", "B", "C", "D"]

/// Traditional tier list colors (S → D).
private func tierColor(for tier: String?) -> Color {
    guard let tier else { return Theme.surface }
    switch tier {
    case "S": return Color(red: 0.95, green: 0.55, blue: 0.50)   // salmon / light red
    case "A": return Color(red: 0.98, green: 0.72, blue: 0.55)   // light orange / peach
    case "B": return Color(red: 0.98, green: 0.78, blue: 0.45)   // yellow-orange
    case "C": return Color(red: 0.98, green: 0.92, blue: 0.55)   // light yellow
    case "D": return Color(red: 0.65, green: 0.85, blue: 0.60)   // light green
    default: return Theme.surface
    }
}

/// Payload for tier-list drag-and-drop. Uses plain-text UUID for reliable in-app transfer.
struct TierDragItem: Transferable, Hashable {
    let userBookId: UUID

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .plainText) { item in
            Data(item.userBookId.uuidString.utf8)
        }
        DataRepresentation(importedContentType: .plainText) { data in
            let s = String(decoding: data, as: UTF8.self)
            guard let id = UUID(uuidString: s) else {
                struct DecodeError: Error {}
                throw DecodeError()
            }
            return TierDragItem(userBookId: id)
        }
    }
}

struct TierListView: View {
    let userBooks: [UserBook]
    /// (userBookId, tier, insertionIndex). Index 0 = first in row; nil = append at end.
    let onUpdateTierAndOrder: (UUID, String?, Int?) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(tierLabels, id: \.self) { tier in
                    TierRowView(
                        tier: tier,
                        books: sortedBooks(for: tier),
                        onUpdateTierAndOrder: onUpdateTierAndOrder
                    )
                }
                TierRowView(
                    tier: nil,
                    books: sortedBooks(for: nil),
                    onUpdateTierAndOrder: onUpdateTierAndOrder
                )
            }
            .padding()
            .padding(.bottom, 100)
        }
    }

    private func sortedBooks(for tier: String?) -> [UserBook] {
        let filtered: [UserBook]
        if let tier {
            filtered = userBooks.filter { $0.tier == tier }
        } else {
            filtered = userBooks.filter { $0.tier == nil || $0.tier?.isEmpty == true }
        }
        return filtered.sorted { ($0.tierOrder ?? 999) < ($1.tierOrder ?? 999) }
    }
}

struct TierRowView: View {
    let tier: String?
    let books: [UserBook]
    let onUpdateTierAndOrder: (UUID, String?, Int?) -> Void
    @State private var isTargeted = false

    var header: String {
        tier ?? "Unranked"
    }

    var body: some View {
        HStack(spacing: 0) {
            ZStack {
                tierColor(for: tier)
                Text(header)
                    .font(Theme.headline())
                    .foregroundStyle(header == "Unranked" ? Theme.textSecondary : Color.black.opacity(0.75))
            }
            .frame(width: 44)
            .frame(minHeight: 120)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(books, id: \.id) { ub in
                        if ub.book != nil {
                            TierBookCell(userBook: ub)
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
            .frame(minHeight: 120)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 0)
                    .fill(isTargeted ? Theme.accent.opacity(0.2) : Theme.surface.opacity(0.6))
            )
            .contentShape(Rectangle())
            .dropDestination(for: TierDragItem.self) { items, _ in
                guard let payload = items.first else { return false }
                onUpdateTierAndOrder(payload.userBookId, tier, nil)
                isTargeted = false
                return true
            } isTargeted: { targeted in
                isTargeted = targeted
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius))
    }
}

struct TierBookCell: View {
    let userBook: UserBook

    var body: some View {
        Group {
            if let book = userBook.book {
                BookCoverView(book: book, size: 72)
                    .draggable(TierDragItem(userBookId: userBook.id))
                    .modifier(ShorterDragPressModifier(minimumDuration: 0.25))
            }
        }
    }
}
