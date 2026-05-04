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
    let onConfirm: (Date, Double?, Bool, String?) -> Void

    @FocusState private var isThoughtsFocused: Bool
    @State private var markAsReadDate = Date()
    @State private var markAsReadSliderValue: Double = 5.5
    @State private var hasExplicitMarkReadRating = false
    @State private var markAsReadPostToFeed = true
    @State private var markAsReadThoughts = ""

    private var markAsReadRatingSliderBinding: Binding<Double> {
        Binding(
            get: { markAsReadSliderValue },
            set: { newValue in
                markAsReadSliderValue = newValue
                hasExplicitMarkReadRating = true
            }
        )
    }

    private var markAsReadRatingLabel: String {
        hasExplicitMarkReadRating ? Theme.formatRatingOutOfTen(markAsReadSliderValue) : "—"
    }

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
            markAsReadSliderValue = 5.5
            hasExplicitMarkReadRating = false
            markAsReadPostToFeed = true
            markAsReadThoughts = ""
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionLabel("Date Finished")
            DatePicker("", selection: $markAsReadDate, displayedComponents: .date)
                .datePickerStyle(.compact)
                .labelsHidden()
                .tint(Theme.accent)

            sectionLabel("Rating  \(markAsReadRatingLabel) / 10")
            Slider(value: markAsReadRatingSliderBinding, in: 1...10, step: 0.1)
                .tint(Theme.accent)

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
                    .stroke(Theme.chromeTeal.opacity(0.4), lineWidth: 1)
            )
            .id("inlineThoughts")

            Toggle(isOn: $markAsReadPostToFeed) {
                Text("Post to feed")
                    .font(Theme.callout())
                    .foregroundStyle(Theme.textPrimary)
            }
            .tint(Theme.accent)

            Button {
                let date = markAsReadDate
                let rating: Double? = hasExplicitMarkReadRating
                    ? Theme.normalizeRatingOutOfTen(markAsReadSliderValue)
                    : nil
                let post = markAsReadPostToFeed
                let thoughts = markAsReadThoughts.trimmingCharacters(in: .whitespacesAndNewlines)
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { isPresented = false }
                onConfirm(date, rating, post, thoughts.isEmpty ? nil : thoughts)
            } label: {
                Text("[ MARK AS READ ]")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .tracking(1)
                    .foregroundStyle(Theme.phosphorWhite)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.cardCornerRadius)
                            .fill(Theme.accent)
                    )
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .padding(20)
        .windowedCard(title: "Mark As Read")
    }

    /// Bracketed mono section label, e.g. "[ DATE FINISHED ]".
    private func sectionLabel(_ text: String) -> some View {
        Text("[ \(text.uppercased()) ]")
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .tracking(1)
            .foregroundStyle(Theme.chromeTeal)
    }
}
