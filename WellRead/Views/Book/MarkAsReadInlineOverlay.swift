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
    @State private var markAsReadDate = Date()
    @State private var markAsReadPostToFeed = true
    @State private var markAsReadThoughts = ""
    @State private var selectedTier: String? = nil
    @State private var showDatePopover = false

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
            markAsReadDate = Date()
            markAsReadPostToFeed = true
            markAsReadThoughts = ""
            selectedTier = nil
            showDatePopover = false
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionLabel("Date Finished")
            Button {
                isThoughtsFocused = false
                showDatePopover = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "calendar")
                        .font(.system(size: 13, weight: .semibold))
                    Text(markAsReadDate.formatted(date: .abbreviated, time: .omitted))
                        .font(Theme.callout())
                }
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
            .popover(isPresented: $showDatePopover) {
                DatePicker("", selection: $markAsReadDate, displayedComponents: .date)
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
                    }
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

            InlineTierPicker(selection: $selectedTier)

            Toggle(isOn: $markAsReadPostToFeed) {
                Text("Post to feed")
                    .font(Theme.callout())
                    .foregroundStyle(Theme.textPrimary)
            }
            .tint(Theme.accent)

            Button {
                let date = markAsReadDate
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
