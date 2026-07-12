//
//  DiscoverCriteriaEditorSheet.swift
//  Spine
//
//  Edit the criteria driving Discover suggestions: seed books (picked from the
//  tier list), tiers, tags, and a free-text instruction. Saving applies once —
//  one Firestore write, one queue flush + refetch.
//

import SwiftUI

struct DiscoverCriteriaEditorSheet: View {
    private static let freeTextLimit = 300

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState

    @State private var draft: DiscoverCriteria
    @State private var selectedTags: Set<String>
    @FocusState private var isFreeTextFocused: Bool

    init(initial: DiscoverCriteria) {
        _draft = State(initialValue: initial)
        _selectedTags = State(initialValue: Set(initial.tags))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("Your next suggestions come only from what you set here. Leave everything empty to go back to picks from your whole library and interests.")
                        .font(Theme.caption())
                        .foregroundStyle(Theme.textSecondary)

                    seedBooksSection
                    tiersSection
                    tagsSection
                    freeTextSection

                    Button {
                        save()
                    } label: {
                        Text("Save")
                            .font(Theme.headline())
                            .foregroundStyle(Theme.background)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Theme.accent)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius))
                    }
                    .buttonStyle(.plain)

                    if !isDraftDefault {
                        Button {
                            draft = .default
                            selectedTags = []
                        } label: {
                            VStack(spacing: 4) {
                                Text("Reset to default")
                                    .font(Theme.headline())
                                    .foregroundStyle(.red)
                                Text("Back to recommendations from your whole library and interests.")
                                    .font(Theme.caption())
                                    .foregroundStyle(Theme.textTertiary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.background)
            .navigationTitle("Tune Discover")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbarColorScheme(.light, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Theme.accent)
                }
            }
        }
    }

    private var isDraftDefault: Bool {
        var d = draft
        d.tags = Array(selectedTags)
        return d.isDefault
    }

    private func save() {
        var final = draft
        // Keep catalog order + canonical strings; whitelist also dedupes.
        final.tags = WellReadTagCatalog.shared.whitelist(
            WellReadTagCatalog.shared.allTags.filter { selectedTags.contains($0) }
        )
        final.freeText = String(final.trimmedFreeText.prefix(Self.freeTextLimit))
        appState.setDiscoverCriteria(final)
        dismiss()
    }

    // MARK: - Books

    private var seedBooksSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Specific books", detail: "Get suggestions similar to books you pick.")
            if draft.seedBooks.isEmpty {
                if appState.readBooks.isEmpty {
                    Text("Finish and rank some books first to use them as seeds.")
                        .font(Theme.caption())
                        .foregroundStyle(Theme.textTertiary)
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(draft.seedBooks, id: \.bookId) { seed in
                            seedTile(seed)
                        }
                    }
                }
            }
            if !appState.readBooks.isEmpty {
                NavigationLink {
                    DiscoverBookPickerView(readBooks: appState.readBooks, selectedSeeds: $draft.seedBooks)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 14, weight: .semibold))
                        Text(draft.seedBooks.isEmpty ? "Choose from your tier list" : "Add or remove books")
                            .font(Theme.caption())
                            .fontWeight(.medium)
                    }
                    .foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func seedTile(_ seed: DiscoverSeedBook) -> some View {
        VStack(spacing: 6) {
            if let book = appState.readBooks.first(where: { $0.bookId == seed.bookId })?.book {
                BookCoverView(book: book, size: 56)
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Theme.surface)
                    .frame(width: 56, height: 84)
                    .overlay(
                        Text(seed.title)
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(Theme.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(4)
                    )
            }
            Button {
                draft.seedBooks.removeAll { $0.bookId == seed.bookId }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .frame(width: 68)
    }

    // MARK: - Tiers

    private var tiersSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Tiers", detail: "Seed suggestions from every book in the tiers you pick.")
            HStack(spacing: 8) {
                ForEach(spineTierLabels, id: \.self) { tier in
                    tierToggle(tier)
                }
            }
        }
    }

    private func tierToggle(_ tier: String) -> some View {
        let count = appState.readBooks.filter { $0.tier == tier }.count
        let selected = draft.tiers.contains(tier)
        return Button {
            if selected {
                draft.tiers.removeAll { $0 == tier }
            } else {
                draft.tiers = spineTierLabels.filter { draft.tiers.contains($0) || $0 == tier }
            }
        } label: {
            VStack(spacing: 2) {
                Text(tier)
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.black.opacity(0.75))
                Text("\(count)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.black.opacity(0.55))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(spineTierColor(for: tier).opacity(selected ? 1.0 : 0.35))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(selected ? Theme.textPrimary : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .disabled(count == 0)
        .opacity(count == 0 ? 0.35 : 1)
    }

    // MARK: - Tags

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("Tags & genres", detail: "Focus suggestions on topics, genres, or vibes.")
            TagCatalogPicker(selected: $selectedTags)
        }
    }

    // MARK: - Free text

    private var freeTextSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("In your own words", detail: "Describe what you're in the mood for.")
            ZStack(alignment: .topLeading) {
                if draft.freeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("e.g. something like Dune but funnier")
                        .font(Theme.body())
                        .foregroundStyle(Theme.textSecondary.opacity(0.7))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 10)
                }
                TextEditor(text: $draft.freeText)
                    .font(Theme.body())
                    .foregroundStyle(Theme.textPrimary)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 80, maxHeight: 160)
                    .focused($isFreeTextFocused)
                    .onChange(of: draft.freeText) { _, newValue in
                        if newValue.count > Self.freeTextLimit {
                            draft.freeText = String(newValue.prefix(Self.freeTextLimit))
                        }
                    }
            }
            .padding(12)
            .background(Theme.background.opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Theme.textTertiary.opacity(0.3), lineWidth: 1)
            )
        }
    }

    private func sectionHeader(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(Theme.caption())
                .foregroundStyle(Theme.textSecondary)
            Text(detail)
                .font(Theme.caption())
                .foregroundStyle(Theme.textTertiary)
        }
    }
}
