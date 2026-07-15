//
//  DiscoverCriteriaStrip.swift
//  Spine
//
//  Always-visible row under the Discover header showing exactly what's driving
//  the next suggestion: a "Suggesting based on" caption over default-taste chips,
//  or one removable chip per custom criterion, plus add/adjust affordances that
//  open the criteria editor.
//

import SwiftUI

struct DiscoverCriteriaStrip: View {
    let criteria: DiscoverCriteria
    /// Count of the user's onboarding interest tags (drives the default-mode chips).
    let interestTagsCount: Int
    /// Called with the mutated criteria when the user removes a chip.
    let onRemove: (DiscoverCriteria) -> Void
    let onEdit: () -> Void
    /// Resolves a seed's full Book (for cover art) — e.g. from the user's library.
    var bookForSeed: ((DiscoverSeedBook) -> Book?)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(SpinesGlyphs.caps("Suggesting based on"))
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.4)
                .foregroundStyle(Theme.textTertiary)
            HStack(spacing: 8) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        if criteria.isDefault {
                            defaultChips
                        } else {
                            customChips
                        }
                        addChip
                    }
                    .padding(.vertical, 2)
                }
                adjustButton
            }
        }
        .padding(.horizontal, Theme.horizontalPadding)
        .padding(.bottom, 8)
    }

    /// Inline "+ Add" chip at the end of the row — the obvious way to add criteria.
    private var addChip: some View {
        Button(action: onEdit) {
            HStack(spacing: 5) {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .bold))
                Text("Add")
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(Theme.accent)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Theme.accent.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Theme.accent.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            )
        }
        .buttonStyle(.plain)
    }

    /// Always-visible compact entry to the full criteria editor (never scrolls away).
    private var adjustButton: some View {
        Button(action: onEdit) {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 30, height: 30)
                .background(Theme.surface)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .strokeBorder(Theme.accent.opacity(0.35), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Adjust suggestion criteria")
    }

    // MARK: - Default mode

    @ViewBuilder
    private var defaultChips: some View {
        infoChip(label: "Your library", icon: "books.vertical")
        if interestTagsCount > 0 {
            infoChip(label: "Your interests", icon: "sparkles")
        }
    }

    private func infoChip(label: String, icon: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
            Text(label)
                .font(.system(size: 12, weight: .medium))
        }
        .foregroundStyle(Theme.textSecondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Theme.textTertiary.opacity(0.25), lineWidth: 1)
        )
    }

    // MARK: - Custom mode

    @ViewBuilder
    private var customChips: some View {
        if !criteria.seedBooks.isEmpty {
            seedBooksChip
        }
        ForEach(criteria.tiers, id: \.self) { tier in
            removableChip(label: "\(tier) tier", tint: spineTierColor(for: tier)) {
                var c = criteria
                c.tiers.removeAll { $0 == tier }
                onRemove(c)
            }
        }
        ForEach(criteria.tags, id: \.self) { tag in
            removableChip(label: tag, tint: nil) {
                var c = criteria
                c.tags.removeAll { $0 == tag }
                onRemove(c)
            }
        }
        if !criteria.trimmedFreeText.isEmpty {
            removableChip(label: "“\(truncated(criteria.trimmedFreeText))”", tint: nil) {
                var c = criteria
                c.freeText = ""
                onRemove(c)
            }
        }
    }

    /// Grouped seed-book tag: "Like these:" followed by tiny cover thumbnails.
    /// Tap opens the editor; ✕ clears all seed books.
    private var seedBooksChip: some View {
        HStack(spacing: 7) {
            Button(action: onEdit) {
                HStack(spacing: 7) {
                    Text("Like these:")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                    HStack(spacing: 3) {
                        ForEach(criteria.seedBooks, id: \.bookId) { seed in
                            BookCoverView(book: resolvedBook(seed), size: 18)
                        }
                    }
                }
            }
            .buttonStyle(.plain)
            Button {
                var c = criteria
                c.seedBooks = []
                onRemove(c)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Theme.chromeTeal.opacity(0.5), lineWidth: 1)
        )
    }

    /// Library book when available (real cover); otherwise a title-only placeholder from the snapshot.
    private func resolvedBook(_ seed: DiscoverSeedBook) -> Book {
        bookForSeed?(seed) ?? Book(
            id: seed.bookId,
            title: seed.title,
            author: seed.author,
            coverURL: "",
            pageCount: nil,
            publishedDate: nil,
            description: nil,
            genres: []
        )
    }

    private func truncated(_ text: String, limit: Int = 28) -> String {
        text.count <= limit ? text : String(text.prefix(limit)) + "…"
    }

    private func removableChip(label: String, tint: Color?, remove: @escaping () -> Void) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .frame(maxWidth: 140, alignment: .leading)
            Button(action: remove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(tint?.opacity(0.35) ?? Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Theme.chromeTeal.opacity(0.5), lineWidth: 1)
        )
    }
}
