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

/// Coordinate space of the tier-list ScrollView, used to pin each tier's letter
/// to the top of the viewport while its (possibly very tall) row scrolls by.
private let tierListScrollSpace = "tierListScroll"
/// Height of the pinned letter block inside the colored label column.
private let tierStickyLetterHeight: CGFloat = 96

/// Tier rows rendered top-to-bottom, plus an Unranked row appended after.
private let tierLabels: [String] = spineTierLabels

private func tierColor(for tier: String?) -> Color {
    spineTierColor(for: tier)
}

// MARK: - Post-review tier prompt (scroll anchor + callout)

/// ScrollViewReader anchor attached to the just-reviewed book so we can bring it
/// fully into view (not just the tall Unranked row).
private let tierHighlightScrollID = "tier-highlight-book"

/// Publishes the highlighted book's on-screen bounds so the callout can point at
/// it from an overlay above the (clipped) tier rows.
private struct TierHighlightAnchorKey: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

/// Measured height of the callout bubble, so we can seat its tail just above the book.
private struct TierCalloutHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 58
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Downward-pointing tail for the callout bubble.
private struct CalloutTail: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

/// "Rank me!" bubble shown above a freshly-reviewed, still-unranked book.
/// `tailOffset` shifts the tail horizontally so it keeps pointing at the book
/// even when the bubble is nudged inward to stay on screen.
private struct TierHighlightCallout: View {
    var tailOffset: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 2) {
                Text(SpinesGlyphs.caps("Rank me"))
                    .font(.system(size: 13, weight: .bold))
                    .tracking(0.5)
                Text("Drag me onto a tier")
                    .font(Theme.caption())
                    .opacity(0.9)
            }
            .foregroundStyle(Theme.onChrome)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Theme.accentGloss)
            )

            CalloutTail()
                .fill(Theme.accentGloss)
                .frame(width: 18, height: 9)
                .offset(x: tailOffset)
        }
        .shadow(color: Theme.shadowInk.opacity(0.22), radius: 8, x: 0, y: 3)
        .allowsHitTesting(false)
    }
}

private extension View {
    /// Applies a ScrollViewReader `.id` only when `active`, so the anchor exists
    /// solely on the currently-highlighted book.
    @ViewBuilder
    func scrollAnchorID(_ id: String, active: Bool) -> some View {
        if active { self.id(id) } else { self }
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
    /// `Book.id` of a book to pulse-glow + scroll into view (e.g. just-reviewed book sitting in Unranked).
    var highlightedBookId: String? = nil
    /// `Book.id`s to render with a selection check (Discover seed-book picker). Only used with `readOnly`.
    var selectedBookIds: Set<String> = []

    @EnvironmentObject private var queueDragCoordinator: QueueBookDragCoordinator

    /// Measured callout height (updated via preference) so the tail seats just above the book.
    @State private var calloutHeight: CGFloat = 58
    /// Gated on after the scroll settles so the callout fades in over the centered book.
    @State private var showCallout = false

    /// Content area width for each row: list width minus horizontal padding and tier label.
    private static let tierLabelWidth: CGFloat = 38
    private static let horizontalPadding: CGFloat = 6 * 2

    var body: some View {
        GeometryReader { geo in
            let listWidth = geo.size.width
            let contentAreaWidth = max(0, listWidth - Self.horizontalPadding - Self.tierLabelWidth)

            ScrollViewReader { proxy in
                ScrollView {
                    // Plain VStack (6 rows) so every row — especially "unranked" at the
                    // bottom — is registered with the ScrollViewReader immediately;
                    // scrollTo on an unbuilt LazyVStack child silently does nothing.
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(tierLabels, id: \.self) { tier in
                            TierRowView(
                                tier: tier,
                                books: sortedBooks(for: tier),
                                contentAreaWidth: contentAreaWidth,
                                onUpdateTierAndOrder: onUpdateTierAndOrder,
                                onBookTap: onBookTap,
                                readOnly: readOnly,
                                highlightedBookId: highlightedBookId,
                                selectedBookIds: selectedBookIds
                            )
                        }
                        TierRowView(
                            tier: nil,
                            books: sortedBooks(for: nil),
                            contentAreaWidth: contentAreaWidth,
                            onUpdateTierAndOrder: onUpdateTierAndOrder,
                            onBookTap: onBookTap,
                            readOnly: readOnly,
                            highlightedBookId: highlightedBookId,
                            selectedBookIds: selectedBookIds
                        )
                        .id("unranked")
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
                .coordinateSpace(name: tierListScrollSpace)
                // Draw the "Rank me!" callout above the tier rows so it isn't clipped
                // by each row's rounded-rect mask, and point it at the exact book.
                .overlayPreferenceValue(TierHighlightAnchorKey.self) { anchor in
                    GeometryReader { overlayProxy in
                        if let anchor, showCallout {
                            let rect = overlayProxy[anchor]
                            let W = overlayProxy.size.width
                            let bubbleW: CGFloat = 200
                            let edgePad: CGFloat = 16
                            let gap: CGFloat = 8
                            // Keep the bubble on screen, but let its tail slide to stay on the book.
                            let centerX = min(max(rect.midX, edgePad + bubbleW / 2), W - edgePad - bubbleW / 2)
                            let maxTail = bubbleW / 2 - 18
                            let tailOffset = min(max(rect.midX - centerX, -maxTail), maxTail)
                            let centerY = rect.minY - gap - calloutHeight / 2

                            TierHighlightCallout(tailOffset: tailOffset)
                                .frame(width: bubbleW)
                                .background(
                                    GeometryReader { g in
                                        Color.clear.preference(key: TierCalloutHeightKey.self, value: g.size.height)
                                    }
                                )
                                .position(x: centerX, y: max(calloutHeight / 2 + 4, centerY))
                                .transition(.scale(scale: 0.85, anchor: .bottom).combined(with: .opacity))
                        }
                    }
                    .onPreferenceChange(TierCalloutHeightKey.self) { calloutHeight = $0 }
                    .allowsHitTesting(false)
                }
                .onChange(of: highlightedBookId) { _, newValue in
                    scrollToHighlight(proxy: proxy, isSet: newValue != nil, delay: 0.25)
                }
                // A freshly marked-read book reaches `userBooks` only after the Firestore
                // listener echoes it back — often after onAppear's scroll already ran and
                // found nothing. Re-scroll the moment the highlighted book actually exists.
                .onChange(of: highlightedBookIsPresent) { _, present in
                    if present {
                        scrollToHighlight(proxy: proxy, isSet: true, delay: 0.15)
                    }
                }
                .onAppear {
                    scrollToHighlight(proxy: proxy, isSet: highlightedBookId != nil, delay: 0.35)
                }
            }
        }
    }

    /// Whether the highlighted book has actually arrived in `userBooks` (Firestore echo).
    private var highlightedBookIsPresent: Bool {
        guard let highlightedBookId else { return false }
        return userBooks.contains { $0.book?.id == highlightedBookId }
    }

    /// Brings the freshly-reviewed book into view and fades the callout in once it settles.
    /// Two-stage: scroll to the Unranked row first (its anchor always exists, and getting
    /// it on screen builds the lazy book cells inside it), then center the exact book.
    private func scrollToHighlight(proxy: ScrollViewProxy, isSet: Bool, delay: TimeInterval) {
        guard isSet else {
            withAnimation(.easeOut(duration: 0.2)) { showCallout = false }
            return
        }
        showCallout = false
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard highlightedBookId != nil else { return }
            withAnimation(.easeInOut(duration: 0.3)) {
                proxy.scrollTo("unranked", anchor: .top)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                guard highlightedBookId != nil else { return }
                withAnimation(.easeInOut(duration: 0.3)) {
                    proxy.scrollTo(tierHighlightScrollID, anchor: .center)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    guard highlightedBookId != nil else { return }
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                        showCallout = true
                    }
                }
            }
        }
    }

    private func sortedBooks(for tier: String?) -> [UserBook] {
        // Must stay in lockstep with AppState.setTierAndOrder — drop-slot indices are
        // positions in this exact ordering.
        spineTierSorted(userBooks.filter { $0.normalizedTier == tier })
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
    var highlightedBookId: String? = nil
    var selectedBookIds: Set<String> = []

    var header: String {
        tier ?? "Unranked"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ZStack {
                tierColor(for: tier)
                if header == "Unranked" {
                    Text(header)
                        .font(Theme.headline())
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .foregroundStyle(Theme.textSecondary)
                        .rotationEffect(.degrees(-90))
                } else {
                    // Pin the letter to the top of the viewport while scrolling through
                    // a tall tier, stopping at the bottom of the row.
                    GeometryReader { geo in
                        let frame = geo.frame(in: .named(tierListScrollSpace))
                        let overflow = max(0, -frame.minY)
                        let pinned = min(overflow, max(0, frame.height - tierStickyLetterHeight))
                        Text(header)
                            .font(Theme.headline())
                            .lineLimit(1)
                            .foregroundStyle(Color.black.opacity(0.75))
                            .frame(width: 38, height: tierStickyLetterHeight)
                            .offset(y: pinned)
                    }
                }
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
                                TierBookCell(userBook: ub, tier: tier, insertionIndex: startIndex + i, bookSize: bookSize, onUpdateTierAndOrder: onUpdateTierAndOrder, onBookTap: onBookTap, readOnly: readOnly, isHighlighted: highlightedBookId != nil && ub.book?.id == highlightedBookId, isSelected: selectedBookIds.contains(ub.bookId))
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
    /// True when this is the just-reviewed book sitting in Unranked — pulses a tier-color glow until tiered.
    var isHighlighted: Bool = false
    /// True when picked as a Discover seed book (readOnly picker mode) — shows a check overlay.
    var isSelected: Bool = false

    @State private var pulseOn = false

    var body: some View {
        Group {
            if let book = userBook.book {
                if readOnly {
                    BookCoverView(book: book, size: bookSize, onTap: onBookTap != nil ? { onBookTap?(book) } : nil)
                        .overlay(selectionOverlay)
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
                    .overlay(highlightOverlay)
                    .scaleEffect(isHighlighted && pulseOn ? 1.04 : 1.0)
                    .animation(.easeInOut(duration: 0.95).repeatForever(autoreverses: true), value: pulseOn)
                    .onAppear {
                        if isHighlighted { pulseOn = true }
                    }
                    .onChange(of: isHighlighted) { _, newValue in
                        pulseOn = newValue
                    }
                }
            }
        }
        // Scroll target + callout anchor for the just-reviewed book.
        .scrollAnchorID(tierHighlightScrollID, active: isHighlighted)
        .anchorPreference(key: TierHighlightAnchorKey.self, value: .bounds) { isHighlighted ? $0 : nil }
    }

    @ViewBuilder
    private var selectionOverlay: some View {
        if isSelected {
            RoundedRectangle(cornerRadius: 6)
                .stroke(Theme.accent, lineWidth: 2.5)
                .frame(width: bookSize, height: bookSize * 1.5)
                .overlay(alignment: .topTrailing) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(Theme.accent)
                        .background(Circle().fill(Theme.background))
                        .offset(x: 6, y: -6)
                }
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var highlightOverlay: some View {
        if isHighlighted {
            RoundedRectangle(cornerRadius: 6)
                .stroke(Theme.accent, lineWidth: 2.5)
                .shadow(color: Theme.accent.opacity(pulseOn ? 0.95 : 0.3), radius: pulseOn ? 14 : 4)
                .shadow(color: Theme.accent.opacity(pulseOn ? 0.7 : 0.2), radius: pulseOn ? 22 : 8)
                .frame(width: bookSize, height: bookSize * 1.5)
                .allowsHitTesting(false)
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
