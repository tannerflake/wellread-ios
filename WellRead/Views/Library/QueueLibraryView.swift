//
//  QueueLibraryView.swift
//  WellRead
//
//  **Up next** (explicit moves only) and **Backlog** (default). Drag covers to reorder, move sections, or drop on Read/Queue in the segment control.
//

import SwiftUI

// MARK: - Drop slots & book cell (reuse TierDragItem payload)

/// Wider than the old 8pt slots so drops register reliably between covers (especially backlog → Up next).
private let queueDropSlotWidth: CGFloat = 16

private struct QueueShelfDropSlot: View {
    let shelf: QueueShelf
    let insertionIndex: Int
    let onUpdate: (UUID, QueueShelf, Int?) -> Void
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
                    .frame(minWidth: queueDropSlotWidth, maxWidth: fillsRow ? .infinity : queueDropSlotWidth)
                    .frame(minHeight: minHeight)
                    .contentShape(Rectangle())
                    .dropDestination(for: TierDragItem.self) { items, _ in
                        guard let payload = items.first else { return false }
                        onUpdate(payload.userBookId, shelf, insertionIndex)
                        return true
                    } isTargeted: { targeted in
                        if targeted { LibraryDragHaptics.dropTargetHoverEntered() }
                    }
            }
        }
    }
}

private let queueBookDropZoneFraction: CGFloat = 0.3

private struct QueueBookCell: View {
    @EnvironmentObject private var queueDragCoordinator: QueueBookDragCoordinator

    let userBook: UserBook
    let shelf: QueueShelf
    let insertionIndex: Int
    var bookSize: CGFloat = 100
    let onUpdate: (UUID, QueueShelf, Int?) -> Void
    var onBookTap: ((Book) -> Void)?
    var readOnly: Bool = false

    var body: some View {
        Group {
            if let book = userBook.book {
                if readOnly {
                    BookCoverView(book: book, size: bookSize, onTap: onBookTap != nil ? { onBookTap?(book) } : nil)
                        .frame(width: bookSize, height: bookSize * 1.5)
                } else {
                    ZStack {
                        QueueBookDragCover(
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
                                    .frame(width: bookSize * queueBookDropZoneFraction)
                                Color.clear
                                    .frame(maxWidth: .infinity)
                                    .allowsHitTesting(false)
                                dropZone(insertAt: insertionIndex + 1)
                                    .frame(width: bookSize * queueBookDropZoneFraction)
                            }
                            .frame(width: bookSize, height: bookSize * 1.5)
                        }
                    }
                }
            }
        }
        // Fixed width prevents HStack flex from shrinking covers (often visible on the 2nd item).
        .frame(width: bookSize, alignment: .topLeading)
        .layoutPriority(1)
        .fixedSize(horizontal: true, vertical: false)
    }

    private func dropZone(insertAt index: Int) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .dropDestination(for: TierDragItem.self) { items, _ in
                guard let payload = items.first else { return false }
                onUpdate(payload.userBookId, shelf, index)
                return true
            } isTargeted: { targeted in
                if targeted { LibraryDragHaptics.dropTargetHoverEntered() }
            }
    }
}

// MARK: - Section grid (tier-list style rows of 4)

private let queueBooksPerRow = 4
private let queueRowPadding: CGFloat = 1

private enum QueueSectionEmptyKind {
    case none
    /// Dashed drop zone + “Drag the book(s) you’re currently reading here.”
    case readingNow
    /// Dashed drop zone + “Drag your next reads here!”
    case upNext
    /// Dashed area + backlog explainer (drops still accepted on overlay slot).
    case backlog

    var emptyPlaceholderMessage: String? {
        switch self {
        case .none: return nil
        case .readingNow: return "Drag the books you're currently reading here."
        case .upNext: return "Drag your next reads here!"
        case .backlog: return "When you add a book to your queue, it'll land here."
        }
    }
}

private struct QueueSectionGrid: View {
    let title: String
    let shelf: QueueShelf
    let books: [UserBook]
    var emptyKind: QueueSectionEmptyKind = .none
    let contentWidth: CGFloat
    let onUpdateShelfAndOrder: (UUID, QueueShelf, Int?) -> Void
    var onBookTap: ((Book) -> Void)?
    var readOnly: Bool = false

    var body: some View {
        let w = contentWidth > 0 ? contentWidth : 280
        let available = w - queueRowPadding * 2
        // Slots: one before each book + one after the last book (narrow min width). Trailing slot can flex; reserve all narrow mins so book width math matches layout.
        let narrowSlotCount = queueBooksPerRow + 1
        let slotSpace = CGFloat(narrowSlotCount) * queueDropSlotWidth
        let bookSize = min(CGFloat(100), max(CGFloat(56), (available - slotSpace) / CGFloat(queueBooksPerRow)))
        let slotHeight = max(64, bookSize * 1.15)

        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(Theme.headline())
                .foregroundStyle(Theme.textSecondary)

            if books.isEmpty, let message = emptyKind.emptyPlaceholderMessage {
                if readOnly {
                    Text("No books here yet.")
                        .font(Theme.callout())
                        .foregroundStyle(Theme.textTertiary)
                        .frame(maxWidth: .infinity, minHeight: 100)
                        .multilineTextAlignment(.center)
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: Theme.cardCornerRadius)
                            .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                            .foregroundStyle(Theme.textTertiary.opacity(0.5))
                            .background(
                                RoundedRectangle(cornerRadius: Theme.cardCornerRadius)
                                    .fill(Color.white.opacity(0.08))
                            )
                        Text(message)
                            .font(Theme.callout())
                            .foregroundStyle(Theme.textTertiary)
                            .multilineTextAlignment(.center)
                            .padding(20)
                            .allowsHitTesting(false)
                        QueueShelfDropSlot(shelf: shelf, insertionIndex: 0, onUpdate: onUpdateShelfAndOrder, fillsRow: true, minHeight: 140, readOnly: false)
                    }
                    .frame(minHeight: 140)
                }
            } else {
                queueRows(bookSize: bookSize, slotHeight: slotHeight)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: books.map(\.id))
    }

    @ViewBuilder
    private func queueRows(bookSize: CGFloat, slotHeight: CGFloat) -> some View {
        let rows: [[UserBook]] = books.isEmpty
            ? []
            : stride(from: 0, to: books.count, by: queueBooksPerRow).map { start in
                Array(books[start..<min(start + queueBooksPerRow, books.count)])
            }

        LazyVStack(alignment: .leading, spacing: 14) {
            if rows.isEmpty {
                HStack(spacing: 0) {
                    QueueShelfDropSlot(shelf: shelf, insertionIndex: 0, onUpdate: onUpdateShelfAndOrder, fillsRow: true, minHeight: slotHeight, readOnly: readOnly)
                }
                .padding(.horizontal, 1)
            } else {
                ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, rowBooks in
                    let startIndex = rowIndex * queueBooksPerRow
                    HStack(alignment: .top, spacing: 0) {
                        ForEach(Array(rowBooks.enumerated()), id: \.element.id) { i, ub in
                            QueueShelfDropSlot(shelf: shelf, insertionIndex: startIndex + i, onUpdate: onUpdateShelfAndOrder, minHeight: slotHeight, readOnly: readOnly)
                            if ub.book != nil {
                                QueueBookCell(
                                    userBook: ub,
                                    shelf: shelf,
                                    insertionIndex: startIndex + i,
                                    bookSize: bookSize,
                                    onUpdate: onUpdateShelfAndOrder,
                                    onBookTap: onBookTap,
                                    readOnly: readOnly
                                )
                                .frame(width: bookSize, alignment: .leading)
                            }
                        }
                        QueueShelfDropSlot(shelf: shelf, insertionIndex: startIndex + rowBooks.count, onUpdate: onUpdateShelfAndOrder, fillsRow: true, minHeight: slotHeight, readOnly: readOnly)
                    }
                    .padding(.horizontal, 1)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Public

struct QueueLibraryView: View {
    let readingNow: [UserBook]
    let upNext: [UserBook]
    let backlog: [UserBook]
    let onUpdateShelfAndOrder: (UUID, QueueShelf, Int?) -> Void
    var onBookTap: ((Book) -> Void)? = nil
    var readOnly: Bool = false

    @EnvironmentObject private var queueDragCoordinator: QueueBookDragCoordinator

    private static let horizontalPadding: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            let contentWidth = max(0, geo.size.width - Self.horizontalPadding)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    QueueSectionGrid(
                        title: "Reading now",
                        shelf: .readingNow,
                        books: readingNow,
                        emptyKind: .readingNow,
                        contentWidth: contentWidth,
                        onUpdateShelfAndOrder: onUpdateShelfAndOrder,
                        onBookTap: onBookTap,
                        readOnly: readOnly
                    )

                    QueueSectionGrid(
                        title: "Up next",
                        shelf: .upNext,
                        books: upNext,
                        emptyKind: .upNext,
                        contentWidth: contentWidth,
                        onUpdateShelfAndOrder: onUpdateShelfAndOrder,
                        onBookTap: onBookTap,
                        readOnly: readOnly
                    )

                    QueueSectionGrid(
                        title: "Backlog",
                        shelf: .backlog,
                        books: backlog,
                        emptyKind: .backlog,
                        contentWidth: contentWidth,
                        onUpdateShelfAndOrder: onUpdateShelfAndOrder,
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
}
