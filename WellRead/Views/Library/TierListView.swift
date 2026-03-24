//
//  TierListView.swift
//  WellRead
//
//  Drag-and-drop tiers: S, A, B, C, D, Unranked. Brief press and drag a book onto a tier row.
//

import SwiftUI
import UniformTypeIdentifiers

/// Match queue grid: wider slots so drops register between covers.
private let tierDropSlotWidth: CGFloat = 16

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

/// Invisible drop slot between or around books so the user can drop at a specific position (front, between, or back) in a tier. Fixed width so rows stay left-aligned; use fillsRow: true for empty tiers so the whole row accepts drops.
private struct TierRowDropSlot: View {
    let tier: String?
    let insertionIndex: Int
    let onUpdateTierAndOrder: (UUID, String?, Int?) -> Void
    /// When true (e.g. empty tier), slot expands to fill the row so drops are easy to register.
    var fillsRow: Bool = false
    var minHeight: CGFloat = 80
    var readOnly: Bool = false

    var body: some View {
        Group {
            if readOnly {
                Color.clear
                    .frame(minWidth: 6, maxWidth: fillsRow ? .infinity : 6)
                    .frame(minHeight: minHeight)
            } else {
                Color.clear
                    .frame(minWidth: tierDropSlotWidth, maxWidth: fillsRow ? .infinity : tierDropSlotWidth)
                    .frame(minHeight: minHeight)
                    .contentShape(Rectangle())
                    .dropDestination(for: TierDragItem.self) { items, _ in
                        guard let payload = items.first else { return false }
                        onUpdateTierAndOrder(payload.userBookId, tier, insertionIndex)
                        return true
                    } isTargeted: { targeted in
                        if targeted { LibraryDragHaptics.dropTargetHoverEntered() }
                    }
            }
        }
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
    /// When true (viewing someone else's library), hide drag-and-drop.
    var readOnly: Bool = false

    @EnvironmentObject private var queueDragCoordinator: QueueBookDragCoordinator

    /// Content area width for each row: list width minus horizontal padding and tier label.
    private static let tierLabelWidth: CGFloat = 38
    private static let horizontalPadding: CGFloat = 6 * 2

    var body: some View {
        GeometryReader { geo in
            let listWidth = geo.size.width
            let contentAreaWidth = max(0, listWidth - Self.horizontalPadding - Self.tierLabelWidth)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(tierLabels, id: \.self) { tier in
                        TierRowView(
                            tier: tier,
                            books: sortedBooks(for: tier),
                            contentAreaWidth: contentAreaWidth,
                            onUpdateTierAndOrder: onUpdateTierAndOrder,
                            onBookTap: onBookTap,
                            readOnly: readOnly
                        )
                    }
                    TierRowView(
                        tier: nil,
                        books: sortedBooks(for: nil),
                        contentAreaWidth: contentAreaWidth,
                        onUpdateTierAndOrder: onUpdateTierAndOrder,
                        onBookTap: onBookTap,
                        readOnly: readOnly
                    )
                }
                .background(alignment: .topLeading) {
                    LibraryScrollViewAnchor(dragCoordinator: queueDragCoordinator)
                        .frame(width: 1, height: 1)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, 4)
                .padding(.top, 10)
                .padding(.bottom, 88)
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

/// Min/max book size so 4-per-row stays readable and doesn't clip.
private let tierBookSizeMin: CGFloat = 48
private let tierBookSizeMax: CGFloat = 80
private let tierRowPadding: CGFloat = 1

struct TierRowView: View {
    let tier: String?
    let books: [UserBook]
    /// Passed from TierListView so books-per-row matches actual width and nothing clips.
    var contentAreaWidth: CGFloat = 0
    let onUpdateTierAndOrder: (UUID, String?, Int?) -> Void
    var onBookTap: ((Book) -> Void)? = nil
    var readOnly: Bool = false

    var header: String {
        tier ?? "Unranked"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ZStack {
                tierColor(for: tier)
                Text(header)
                    .font(Theme.headline())
                    .lineLimit(1)
                    .fixedSize(horizontal: header == "Unranked", vertical: false)
                    .foregroundStyle(header == "Unranked" ? Theme.textSecondary : Color.black.opacity(0.75))
                    .rotationEffect(header == "Unranked" ? .degrees(-90) : .zero)
            }
            .frame(minWidth: 38, maxWidth: 38, minHeight: 96)
            .frame(maxHeight: .infinity)

            tierContent(contentWidth: contentAreaWidth, readOnly: readOnly)
                .frame(minHeight: 96)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 0)
                        .fill(Theme.surface.opacity(0.6))
                )
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius))
    }

    @ViewBuilder
    private func tierContent(contentWidth: CGFloat, readOnly: Bool) -> some View {
        let w = contentWidth > 0 ? contentWidth : 280
        let available = w - tierRowPadding * 2
        let booksPerRow = 4
        // One narrow slot before each cover; trailing slot is flexible — don’t reserve an extra slot width from book size.
        let slotSpace = CGFloat(booksPerRow) * tierDropSlotWidth
        let bookSize = min(tierBookSizeMax, max(tierBookSizeMin, (available - slotSpace) / CGFloat(booksPerRow)))
        let slotHeight = max(64, bookSize * 1.15)
        let rows: [[UserBook]] = books.isEmpty
            ? []
            : stride(from: 0, to: books.count, by: booksPerRow).map { start in
                Array(books[start..<min(start + booksPerRow, books.count)])
            }
        LazyVStack(alignment: .leading, spacing: 2) {
            if rows.isEmpty {
                HStack(spacing: 0) {
                    TierRowDropSlot(tier: tier, insertionIndex: 0, onUpdateTierAndOrder: onUpdateTierAndOrder, fillsRow: true, minHeight: slotHeight, readOnly: readOnly)
                }
                .padding(.horizontal, 1)
            } else {
                ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, rowBooks in
                    let startIndex = rowIndex * booksPerRow
                    HStack(spacing: 0) {
                        ForEach(Array(rowBooks.enumerated()), id: \.element.id) { i, ub in
                            TierRowDropSlot(tier: tier, insertionIndex: startIndex + i, onUpdateTierAndOrder: onUpdateTierAndOrder, minHeight: slotHeight, readOnly: readOnly)
                            if ub.book != nil {
                                TierBookCell(userBook: ub, tier: tier, insertionIndex: startIndex + i, bookSize: bookSize, onUpdateTierAndOrder: onUpdateTierAndOrder, onBookTap: onBookTap, readOnly: readOnly)
                            }
                        }
                        TierRowDropSlot(tier: tier, insertionIndex: startIndex + rowBooks.count, onUpdateTierAndOrder: onUpdateTierAndOrder, fillsRow: true, minHeight: slotHeight, readOnly: readOnly)
                    }
                    .padding(.horizontal, 1)
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: books.map(\.id))
        .padding(.vertical, 2)
    }
}

/// Fraction of book width that acts as "insert before" (left) or "insert after" (right) drop zone when dragging between books.
private let tierBookDropZoneFraction: CGFloat = 0.3

struct TierBookCell: View {
    @EnvironmentObject private var queueDragCoordinator: QueueBookDragCoordinator

    let userBook: UserBook
    let tier: String?
    let insertionIndex: Int
    var bookSize: CGFloat = 72
    let onUpdateTierAndOrder: (UUID, String?, Int?) -> Void
    var onBookTap: ((Book) -> Void)? = nil
    var readOnly: Bool = false

    var body: some View {
        Group {
            if let book = userBook.book {
                if readOnly {
                    BookCoverView(book: book, size: bookSize, onTap: onBookTap != nil ? { onBookTap?(book) } : nil)
                } else {
                    ZStack {
                        ReadListBookDragCover(
                            book: book,
                            userBookId: userBook.id,
                            bookSize: bookSize,
                            onTap: onBookTap != nil ? { onBookTap?(book) } : nil,
                            dragCoordinator: queueDragCoordinator
                        )
                        .frame(width: bookSize, height: bookSize * 1.5)
                        .overlay(alignment: .leading) {
                            HStack(spacing: 0) {
                                dropZone(insertAt: insertionIndex)
                                    .frame(width: bookSize * tierBookDropZoneFraction)
                                Color.clear
                                    .frame(maxWidth: .infinity)
                                    .allowsHitTesting(false)
                                dropZone(insertAt: insertionIndex + 1)
                                    .frame(width: bookSize * tierBookDropZoneFraction)
                            }
                            .frame(width: bookSize, height: bookSize * 1.5)
                        }
                    }
                }
            }
        }
    }

    private func dropZone(insertAt index: Int) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .dropDestination(for: TierDragItem.self) { items, _ in
                guard let payload = items.first else { return false }
                onUpdateTierAndOrder(payload.userBookId, tier, index)
                return true
            } isTargeted: { targeted in
                if targeted { LibraryDragHaptics.dropTargetHoverEntered() }
            }
    }
}
