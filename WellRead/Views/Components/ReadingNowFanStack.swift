//
//  ReadingNowFanStack.swift
//  WellRead
//
//  Fanned mini-stack of the covers on the "Reading now" shelf, floated next to
//  a profile picture — a quick visual of what someone is reading right now.
//  Shows up to 3 covers (tilted like a loose hand of cards); extras become "+N".
//  Renders nothing when the shelf is empty.
//

import SwiftUI

struct ReadingNowFanStack: View {
    /// Reading-now books in shelf order (first = current top read, drawn front-most).
    let books: [Book]
    var coverWidth: CGFloat = 30
    var onTap: ((Book) -> Void)? = nil

    private static let maxCovers = 3

    private var visible: [Book] { Array(books.prefix(Self.maxCovers)) }
    private var overflow: Int { max(0, books.count - Self.maxCovers) }

    /// Alternating tilts sell the "floating" look; values shrink as the fan grows crowded.
    private func rotation(_ index: Int) -> Double {
        [-7, 5, -4][index % 3]
    }

    private func xOffset(_ index: Int) -> CGFloat {
        CGFloat(index) * coverWidth * 0.55
    }

    private func yOffset(_ index: Int) -> CGFloat {
        [0, 2, 4][index % 3]
    }

    private var fanWidth: CGFloat {
        coverWidth + CGFloat(max(0, visible.count - 1)) * coverWidth * 0.55 + 6
    }

    var body: some View {
        if !books.isEmpty {
            HStack(alignment: .center, spacing: 5) {
                ZStack(alignment: .topLeading) {
                    ForEach(Array(visible.enumerated()), id: \.element.id) { index, book in
                        BookCoverView(
                            book: book,
                            size: coverWidth,
                            onTap: onTap != nil ? { onTap?(book) } : nil
                        )
                        .rotationEffect(.degrees(rotation(index)))
                        .offset(x: xOffset(index), y: yOffset(index))
                        .zIndex(Double(visible.count - index))
                    }
                }
                .frame(width: fanWidth, height: coverWidth * 1.5 + 6, alignment: .topLeading)

                if overflow > 0 {
                    Text("+\(overflow)")
                        .font(.system(size: max(9, coverWidth * 0.3), weight: .bold, design: .monospaced))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 3)
                        .background(
                            Capsule().fill(Theme.surface)
                        )
                        .overlay(
                            Capsule().strokeBorder(Theme.chromeTeal.opacity(0.4), lineWidth: 0.75)
                        )
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Reading now: \(books.map(\.title).joined(separator: ", "))")
        }
    }
}
