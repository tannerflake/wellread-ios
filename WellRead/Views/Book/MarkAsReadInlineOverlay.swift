//
//  MarkAsReadInlineOverlay.swift
//  Spine
//
//  Inline "Mark as read" card. Local state so typing does not re-render
//  BookProfileView's scroll content. Themed to match the new Spine palette
//  (cream foundation, mono typography, windowed card with teal title bar).
//

import SwiftUI

struct MarkAsReadInlineOverlay: View {
    @Binding var isPresented: Bool
    /// (dateFinished, rating, postToFeed, thoughts, tier). Tier nil = Unranked → tier-list "Rank me" prompt.
    let onConfirm: (Date, Double?, Bool, String?, String?) -> Void

    @FocusState private var isThoughtsFocused: Bool
    /// Roster for @mention autocomplete in Thoughts.
    @ObservedObject private var mentionCatalog = MentionCatalog.shared
    /// Starts empty on purpose: defaulting to today let users save without ever
    /// noticing the date, so finished-on dates silently became "whenever I tapped".
    @State private var markAsReadDate: Date? = nil
    @State private var markAsReadPostToFeed = true
    @State private var markAsReadThoughts = ""
    @State private var selectedTier: String? = nil
    @State private var showDatePopover = false
    @State private var showDateError = false

    var body: some View {
        Group {
            if isPresented {
                Color.black.opacity(0.45)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { isPresented = false }
                    }
                    .overlay(alignment: .bottom) {
                        ScrollViewReader { proxy in
                            ScrollView {
                                card
                                    .padding(.bottom, 8)
                            }
                            .scrollDismissesKeyboard(.interactively)
                            .frame(maxHeight: min(UIScreen.main.bounds.height * 0.78, 640))
                            /// Scroll once on focus only — per-keystroke scroll caused lag and "variant selector cell index" errors.
                            .onChange(of: isThoughtsFocused) { _, focused in
                                if focused {
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                        withAnimation(.easeOut(duration: 0.2)) {
                                            proxy.scrollTo("inlineThoughts", anchor: .center)
                                        }
                                    }
                                }
                            }
                            // The confirm button sits at the bottom of the card; the date
                            // field it complains about is at the top. Bring the error into view.
                            .onChange(of: showDateError) { _, showing in
                                if showing {
                                    withAnimation(.easeOut(duration: 0.2)) {
                                        proxy.scrollTo("dateFinished", anchor: .top)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 12)
                        .transition(
                            .asymmetric(
                                insertion: .opacity.combined(with: .move(edge: .bottom)).combined(with: .scale(scale: 0.92)),
                                removal: .opacity.combined(with: .move(edge: .bottom))
                            )
                        )
                    }
                    .animation(.spring(response: 0.35, dampingFraction: 0.82), value: isPresented)
            }
        }
        .onChange(of: isPresented) { _, new in
            guard new else { return }
            markAsReadDate = nil
            markAsReadPostToFeed = true
            markAsReadThoughts = ""
            selectedTier = nil
            showDatePopover = false
            showDateError = false
            MentionCatalog.shared.ensureLoadedForCurrentUser()
        }
        // Half-typed thoughts survive a deep-link tap: if this card is inside a
        // presented sheet, the tap would otherwise take the sheet (and the
        // typing) with it.
        .composerDraftGuard(isPresented ? markAsReadThoughts : "")
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionLabel("Date Finished")
                .id("dateFinished")
            HStack(spacing: 10) {
                Button {
                    isThoughtsFocused = false
                    showDatePopover = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "calendar")
                            .font(.system(size: 13, weight: .semibold))
                        Text(markAsReadDate.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "Select date")
                            .font(Theme.callout())
                    }
                    .foregroundStyle(markAsReadDate == nil ? Theme.textTertiary : Theme.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Theme.background)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(showDateError ? Theme.danger : Theme.chrome.opacity(0.4), lineWidth: showDateError ? 1.5 : 1)
                    )
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showDatePopover) {
                    DatePicker(
                        "",
                        selection: Binding(
                            get: { markAsReadDate ?? Date() },
                            set: { markAsReadDate = $0 }
                        ),
                        displayedComponents: .date
                    )
                        .datePickerStyle(.graphical)
                        .labelsHidden()
                        .tint(Theme.accent)
                        .padding(12)
                        // The graphical calendar has no usable intrinsic width inside a
                        // popover — without an explicit frame it collapses to a narrow
                        // clipped column. Size it to the calendar's natural dimensions.
                        .frame(width: 320, height: 360)
                        .presentationCompactAdaptation(.popover)
                        // Tapping a specific day changes the selection — close the calendar
                        // immediately instead of waiting for the user to tap outside it.
                        .onChange(of: markAsReadDate) { _, _ in
                            showDatePopover = false
                            showDateError = false
                        }
                }

                Button {
                    isThoughtsFocused = false
                    withAnimation(.easeOut(duration: 0.15)) {
                        markAsReadDate = Date()
                        showDateError = false
                    }
                } label: {
                    Text("Today")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Theme.background)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Theme.chrome.opacity(0.4), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
            if showDateError {
                Text("Add the date you finished this book.")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.danger)
                    .padding(.top, -10)
                    .transition(.opacity)
            }

            sectionLabel("Thoughts")
            ZStack(alignment: .topLeading) {
                if markAsReadThoughts.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("> Thoughts on this book…")
                        .font(Theme.body())
                        .foregroundStyle(Theme.textTertiary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 10)
                }
                TextEditor(text: $markAsReadThoughts)
                    .font(Theme.body())
                    .foregroundStyle(Theme.textPrimary)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 140, maxHeight: 280)
                    .focused($isThoughtsFocused)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Theme.background)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Theme.chrome.opacity(0.4), lineWidth: 1)
            )
            .id("inlineThoughts")

            // Tag readers with "@" — suggestions appear one letter in.
            if let query = MentionScanner.activeQuery(in: markAsReadThoughts) {
                let matches = mentionCatalog.suggestions(matching: query)
                if !matches.isEmpty {
                    MentionSuggestionBar(suggestions: matches) { user in
                        markAsReadThoughts = MentionScanner.insertMention(
                            handle: user.username.lowercased(),
                            into: markAsReadThoughts
                        )
                    }
                    .padding(.top, -8)
                }
            }

            InlineTierPicker(selection: $selectedTier)

            Toggle(isOn: $markAsReadPostToFeed) {
                Text("Post to feed")
                    .font(Theme.callout())
                    .foregroundStyle(Theme.textPrimary)
            }
            .tint(Theme.toggleOn)

            Button {
                guard let date = markAsReadDate else {
                    isThoughtsFocused = false
                    withAnimation(.easeOut(duration: 0.2)) { showDateError = true }
                    return
                }
                let post = markAsReadPostToFeed
                let thoughts = markAsReadThoughts.trimmingCharacters(in: .whitespacesAndNewlines)
                let tier = selectedTier
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { isPresented = false }
                onConfirm(date, nil, post, thoughts.isEmpty ? nil : thoughts, tier)
            } label: {
                Text("MARK AS READ")
                    .font(.system(size: 14, weight: .bold))
                    .tracking(1)
                    .foregroundStyle(Theme.onChrome)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.cardCornerRadius)
                            .fill(Theme.accentGloss)
                    )
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .padding(20)
        .windowedCard(title: "Mark As Read", onClose: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { isPresented = false }
        })
    }

    /// Mono section label, e.g. "DATE FINISHED".
    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .bold))
            .tracking(1)
            .foregroundStyle(Theme.chrome)
    }
}
