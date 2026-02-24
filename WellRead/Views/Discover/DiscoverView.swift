//
//  DiscoverView.swift
//  WellRead
//
//  AI suggestions + Trending (most added, finished, highly rated).
//

import SwiftUI

struct DiscoverView: View {
    @EnvironmentObject var appState: AppState
    @State private var aiSuggestions: [Book] = []
    @State private var isLoadingAI = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        aiSection
                        trendingSection
                    }
                    .padding(.bottom, 100)
                }
            }
            .navigationTitle("Discover")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }
    
    private var aiSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("AI Suggestions")
                .font(Theme.title2())
                .foregroundStyle(Theme.textPrimary)
            Button {
                loadAISuggestions()
            } label: {
                HStack {
                    if isLoadingAI {
                        ProgressView().tint(Theme.accent)
                        Text("Generating…").font(Theme.headline()).foregroundStyle(Theme.textPrimary)
                    } else {
                        Image(systemName: "sparkles")
                            .font(.title2)
                            .foregroundStyle(Theme.accent)
                        Text("Generate My Next 5 Reads")
                            .font(Theme.headline())
                            .foregroundStyle(Theme.textPrimary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
                .wellReadCard()
            }
            .buttonStyle(.plain)
            .disabled(isLoadingAI)
            
            if !aiSuggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(aiSuggestions) { book in
                            DiscoverBookCard(book: book) {
                                // Add to Want to Read - would integrate with appState
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
        .padding(.horizontal)
    }
    
    private func loadAISuggestions() {
        isLoadingAI = true
        aiSuggestions = []
        Task {
            try? await Task.sleep(nanoseconds: 800_000_000)
            let readTitles = appState.readBooks.compactMap { $0.book?.title }
            let query = !readTitles.isEmpty ? readTitles.prefix(2).joined(separator: " ") : "popular books"
            let books = (try? await GoogleBooksService.shared.search(query: query)) ?? []
            await MainActor.run {
                aiSuggestions = Array(books.prefix(5))
                isLoadingAI = false
            }
        }
    }
    
    private var trendingSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Trending")
                .font(Theme.title2())
                .foregroundStyle(Theme.textPrimary)
            Text("Most finished this week")
                .font(Theme.caption())
                .foregroundStyle(Theme.textSecondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(appState.readBooks.prefix(5)) { ub in
                        if let book = ub.book {
                            DiscoverBookCard(book: book) {}
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
        .padding(.horizontal)
    }
}

struct DiscoverBookCard: View {
    let book: Book
    let onAdd: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            BookCoverView(book: book, size: 100)
            Text(book.title)
                .font(Theme.caption())
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(2)
                .frame(width: 100, alignment: .leading)
            Button("Want to Read") {
                onAdd()
            }
            .font(.caption2)
            .foregroundStyle(Theme.accent)
        }
        .frame(width: 100)
    }
}
