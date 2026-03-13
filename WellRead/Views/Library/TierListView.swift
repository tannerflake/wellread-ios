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

/// Invisible drop slot between or around books so the user can drop at a specific position (front, between, or back) in a tier. Generous hit area for easier drops.
private struct TierRowDropSlot: View {
    let tier: String?
    let insertionIndex: Int
    let onUpdateTierAndOrder: (UUID, String?, Int?) -> Void

    private let minWidth: CGFloat = 20

    var body: some View {
        Color.clear
            .frame(minWidth: minWidth, minHeight: 80)
            .contentShape(Rectangle())
            .dropDestination(for: TierDragItem.self) { items, _ in
                guard let payload = items.first else { return false }
                onUpdateTierAndOrder(payload.userBookId, tier, insertionIndex)
                return true
            } isTargeted: { _ in }
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
    /// When set, tapping a book cover opens the book profile.
    var onBookTap: ((Book) -> Void)? = nil

    /// Content area width for each row: list width minus horizontal padding (8×2) and tier label (44).
    private static let tierLabelWidth: CGFloat = 44
    private static let horizontalPadding: CGFloat = 8 * 2

    var body: some View {
        GeometryReader { geo in
            let listWidth = geo.size.width
            let contentAreaWidth = max(0, listWidth - Self.horizontalPadding - Self.tierLabelWidth)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(tierLabels, id: \.self) { tier in
                        TierRowView(
                            tier: tier,
                            books: sortedBooks(for: tier),
                            contentAreaWidth: contentAreaWidth,
                            onUpdateTierAndOrder: onUpdateTierAndOrder,
                            onBookTap: onBookTap
                        )
                    }
                    TierRowView(
                        tier: nil,
                        books: sortedBooks(for: nil),
                        contentAreaWidth: contentAreaWidth,
                        onUpdateTierAndOrder: onUpdateTierAndOrder,
                        onBookTap: onBookTap
                    )
                }
                .padding(.horizontal, 8)
                .padding(.top, 16)
                .padding(.bottom, 100)
            }
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

private let tierBookSize: CGFloat = 72
private let tierSlotWidth: CGFloat = 20
private let tierRowPadding: CGFloat = 2

struct TierRowView: View {
    let tier: String?
    let books: [UserBook]
    /// Passed from TierListView so books-per-row matches actual width and nothing clips.
    var contentAreaWidth: CGFloat = 0
    let onUpdateTierAndOrder: (UUID, String?, Int?) -> Void
    var onBookTap: ((Book) -> Void)? = nil

    var header: String {
        tier ?? "Unranked"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ZStack {
                tierColor(for: tier)
                Text(header)
                    .font(Theme.headline())
                    .foregroundStyle(header == "Unranked" ? Theme.textSecondary : Color.black.opacity(0.75))
            }
            .frame(minWidth: 44, maxWidth: 44, minHeight: 120)
            .frame(maxHeight: .infinity)

            tierContent(contentWidth: contentAreaWidth)
                .frame(minHeight: 120)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 0)
                        .fill(Theme.surface.opacity(0.6))
                )
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius))
    }

    @ViewBuilder
    private func tierContent(contentWidth: CGFloat) -> some View {
        let w = contentWidth > 0 ? contentWidth : 280
        let safety: CGFloat = 6
        let available = w - tierRowPadding * 2 - tierSlotWidth - safety
        let slotAndBook = tierBookSize + tierSlotWidth
        let booksPerRow = max(1, Int((available - tierSlotWidth) / slotAndBook))
        let rows: [[UserBook]] = books.isEmpty
            ? []
            : stride(from: 0, to: books.count, by: booksPerRow).map { start in
                Array(books[start..<min(start + booksPerRow, books.count)])
            }
        VStack(alignment: .leading, spacing: 4) {
            if rows.isEmpty {
                HStack(spacing: 0) {
                    TierRowDropSlot(tier: tier, insertionIndex: 0, onUpdateTierAndOrder: onUpdateTierAndOrder)
                }
                .padding(.horizontal, 1)
            } else {
                ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, rowBooks in
                    let startIndex = rowIndex * booksPerRow
                    HStack(spacing: 0) {
                        ForEach(Array(rowBooks.enumerated()), id: \.element.id) { i, ub in
                            TierRowDropSlot(tier: tier, insertionIndex: startIndex + i, onUpdateTierAndOrder: onUpdateTierAndOrder)
                            if ub.book != nil {
                                TierBookCell(userBook: ub, onBookTap: onBookTap)
                            }
                        }
                        TierRowDropSlot(tier: tier, insertionIndex: startIndex + rowBooks.count, onUpdateTierAndOrder: onUpdateTierAndOrder)
                    }
                    .padding(.horizontal, 1)
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: books.map(\.id))
        .padding(.vertical, 4)
    }
}

struct TierBookCell: View {
    let userBook: UserBook
    var onBookTap: ((Book) -> Void)? = nil

    var body: some View {
        Group {
            if let book = userBook.book {
                BookCoverView(book: book, size: 72, onTap: onBookTap != nil ? { onBookTap?(book) } : nil)
                    .draggable(TierDragItem(userBookId: userBook.id))
                    .modifier(ShorterDragPressModifier(minimumDuration: 0.15))
            }
        }
    }
}
