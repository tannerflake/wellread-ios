//
//  MarkAsReadInlineOverlay.swift
//  WellRead
//
//  Inline “Mark as read” card with local state so typing does not re-render BookProfileView’s scroll content.
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
                            /// Scroll once on focus only — per-keystroke scroll caused lag and “variant selector cell index” errors.
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
        VStack(alignment: .leading, spacing: 16) {
            Text("Mark as read")
                .font(Theme.title2())
                .foregroundStyle(Theme.textPrimary)
            VStack(alignment: .leading, spacing: 6) {
                Text("When did you finish?")
                    .font(Theme.caption())
                    .foregroundStyle(Theme.textSecondary)
                DatePicker("", selection: $markAsReadDate, displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .labelsHidden()
                    .tint(Theme.accent)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Rating: \(markAsReadRatingLabel) / 10")
                    .font(Theme.caption())
                    .foregroundStyle(Theme.textSecondary)
                Slider(value: markAsReadRatingSliderBinding, in: 1...10, step: 0.1)
                    .tint(Theme.accent)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Thoughts")
                    .font(Theme.caption())
                    .foregroundStyle(Theme.textSecondary)
                ZStack(alignment: .topLeading) {
                    if markAsReadThoughts.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("Thoughts on this book…")
                            .font(Theme.body())
                            .foregroundStyle(Theme.textSecondary.opacity(0.7))
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
                .background(Theme.background.opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
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
                Text("Mark as read")
                    .font(Theme.headline())
                    .foregroundStyle(Theme.background)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Theme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius))
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius))
        .shadow(color: .black.opacity(0.25), radius: 20, y: 8)
    }
}
