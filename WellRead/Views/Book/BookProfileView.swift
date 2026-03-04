//
//  BookProfileView.swift
//  WellRead
//
//  Book profile page: cover, title, author, short description. Optional "Add to Library" for search flow.
//

import SwiftUI

struct BookProfileView: View {
    let book: Book
    /// When non-nil, shows "Add to Library" button and calls this on tap (e.g. to continue add flow).
    var onAddToLibrary: (() -> Void)? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Cover + title + author block
                VStack(spacing: 16) {
                    BookCoverView(book: book, size: 140)
                    VStack(spacing: 4) {
                        Text(book.title)
                            .font(Theme.title())
                            .foregroundStyle(Theme.textPrimary)
                            .multilineTextAlignment(.center)
                        Text(book.author)
                            .font(Theme.headline())
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 8)

                // Description
                if let desc = book.description, !desc.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("About")
                            .font(Theme.headline())
                            .foregroundStyle(Theme.textSecondary)
                        Text(desc)
                            .font(Theme.body())
                            .foregroundStyle(Theme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius))
                    .padding(.horizontal)
                } else {
                    Text("No description available.")
                        .font(Theme.callout())
                        .foregroundStyle(Theme.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                }

                if onAddToLibrary != nil {
                    Button(action: { onAddToLibrary?() }) {
                        Text("Add to Library")
                            .font(Theme.headline())
                            .foregroundStyle(Theme.background)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Theme.accent)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal)
                    .padding(.top, 8)
                }
            }
            .padding(.bottom, 40)
        }
        .background(Theme.background)
        .navigationBarTitleDisplayMode(.inline)
    }
}
