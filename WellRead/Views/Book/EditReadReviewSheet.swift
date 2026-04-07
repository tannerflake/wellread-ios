//
//  EditReadReviewSheet.swift
//  WellRead
//
//  Edit date finished, rating, thoughts, feed visibility, or delete the read entry.
//

import SwiftUI

/// Identifies an edit session. `feedCaption` pre-fills Thoughts when `userBook.reviewText` is empty (e.g. legacy feed-only text).
struct EditReadReviewSheetPayload: Identifiable {
    var id: UUID { userBook.id }
    let userBook: UserBook
    /// Feed post caption when opening from the feed; use `nil` from book profile.
    var feedCaption: String?

    init(userBook: UserBook, feedCaption: String? = nil) {
        self.userBook = userBook
        self.feedCaption = feedCaption
    }
}

struct EditReadReviewSheet: View {
    let userBook: UserBook
    /// Optional caption from the feed post when `userBook.reviewText` is empty.
    private let feedCaption: String?

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState

    @State private var dateFinished: Date
    @State private var hasRating: Bool
    @State private var sliderValue: Double
    @State private var thoughts: String
    @State private var postToFeed: Bool
    @State private var loadedFeedToggle: Bool = false
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var showDeleteConfirm = false
    @State private var isDeleting = false
    @FocusState private var isThoughtsFocused: Bool

    init(userBook: UserBook, feedCaption: String? = nil) {
        self.userBook = userBook
        self.feedCaption = feedCaption
        _dateFinished = State(initialValue: userBook.dateFinished ?? Date())
        let r = userBook.rating
        _hasRating = State(initialValue: r != nil)
        _sliderValue = State(initialValue: r ?? 5.5)
        _thoughts = State(initialValue: Self.initialThoughts(userBook: userBook, feedCaption: feedCaption))
        _postToFeed = State(initialValue: true)
    }

    private static func initialThoughts(userBook: UserBook, feedCaption: String?) -> String {
        let fromBook = userBook.reviewText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !fromBook.isEmpty { return fromBook }
        let fromFeed = feedCaption?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return fromFeed
    }

    private var ratingLabel: String {
        guard hasRating else { return "—" }
        return Theme.formatRatingOutOfTen(sliderValue)
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                    if let b = userBook.book {
                        HStack(spacing: 12) {
                            BookCoverView(book: b, size: 56)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(b.title)
                                    .font(Theme.headline())
                                    .foregroundStyle(Theme.textPrimary)
                                    .lineLimit(2)
                                Text(b.author)
                                    .font(Theme.callout())
                                    .foregroundStyle(Theme.textSecondary)
                                    .lineLimit(1)
                            }
                        }
                    } else {
                        Text("Book")
                            .font(Theme.headline())
                            .foregroundStyle(Theme.textPrimary)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Date finished")
                            .font(Theme.caption())
                            .foregroundStyle(Theme.textSecondary)
                        DatePicker("", selection: $dateFinished, displayedComponents: .date)
                            .datePickerStyle(.compact)
                            .labelsHidden()
                            .tint(Theme.accent)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Toggle("Include rating", isOn: $hasRating)
                            .font(Theme.callout())
                            .foregroundStyle(Theme.textPrimary)
                            .tint(Theme.accent)
                        if hasRating {
                            Text("Rating: \(ratingLabel) / 10")
                                .font(Theme.caption())
                                .foregroundStyle(Theme.textSecondary)
                            Slider(value: $sliderValue, in: 1...10, step: 0.1)
                                .tint(Theme.accent)
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Thoughts")
                            .font(Theme.caption())
                            .foregroundStyle(Theme.textSecondary)
                        ZStack(alignment: .topLeading) {
                            if thoughts.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text("Thoughts on this book…")
                                    .font(Theme.body())
                                    .foregroundStyle(Theme.textSecondary.opacity(0.7))
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 10)
                            }
                            TextEditor(text: $thoughts)
                                .font(Theme.body())
                                .foregroundStyle(Theme.textPrimary)
                                .scrollContentBackground(.hidden)
                                .frame(minHeight: 120, maxHeight: 280)
                                .focused($isThoughtsFocused)
                        }
                        .padding(12)
                        .background(Theme.background.opacity(0.6))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .id("editReviewThoughts")

                    Toggle(isOn: $postToFeed) {
                        Text("Show on feed")
                            .font(Theme.callout())
                            .foregroundStyle(Theme.textPrimary)
                    }
                    .tint(Theme.accent)
                    .disabled(!loadedFeedToggle)
                    .opacity(loadedFeedToggle ? 1 : 0.6)

                    if let saveError {
                        Text(saveError)
                            .font(Theme.caption())
                            .foregroundStyle(.red)
                    }

                    Button {
                        Task { await save() }
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
                    .disabled(isSaving || isDeleting)

                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Text("Delete review")
                            .font(Theme.headline())
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.plain)
                    .disabled(isSaving || isDeleting)
                    }
                    .padding(20)
                }
                .scrollDismissesKeyboard(.interactively)
                /// Scroll once when the field is focused — not on every keystroke (`onChange(thoughts)` caused lag and ScrollView index errors).
                .onChange(of: isThoughtsFocused) { _, focused in
                    if focused {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            withAnimation(.easeOut(duration: 0.2)) {
                                proxy.scrollTo("editReviewThoughts", anchor: .center)
                            }
                        }
                    }
                }
            }
            .background(Theme.background)
            .navigationTitle("Edit review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Theme.accent)
                }
            }
        }
        .task {
            let has = await appState.hasFinishedBookPost(forBookId: userBook.bookId)
            await MainActor.run {
                postToFeed = has
                loadedFeedToggle = true
            }
            let trimmed = await MainActor.run { thoughts.trimmingCharacters(in: .whitespacesAndNewlines) }
            if trimmed.isEmpty, let caption = await appState.finishedBookPostCaption(forBookId: userBook.bookId) {
                await MainActor.run { thoughts = caption }
            }
        }
        .confirmationDialog("Delete this review? This removes the book from your finished list and deletes your feed post if any.", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                Task { await deleteReview() }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func save() async {
        saveError = nil
        isSaving = true
        defer { isSaving = false }
        let rating: Double? = hasRating ? Theme.normalizeRatingOutOfTen(sliderValue) : nil
        let err = await appState.updateReadReview(
            userBook: userBook,
            dateFinished: dateFinished,
            rating: rating,
            thoughts: thoughts,
            postToFeed: postToFeed
        )
        await MainActor.run {
            if let err {
                saveError = err
            } else {
                dismiss()
            }
        }
    }

    private func deleteReview() async {
        isDeleting = true
        defer { isDeleting = false }
        let err = await appState.deleteReadReview(userBook: userBook)
        await MainActor.run {
            if let err {
                saveError = err
            } else {
                dismiss()
            }
        }
    }
}
