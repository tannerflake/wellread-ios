//
//  LibraryView.swift
//  WellRead
//
//  Segmented: Read | Currently Reading | Want to Read.
//  View toggle: Grid | Timeline | Tier List | Rating.
//

import SwiftUI

struct LibraryView: View {
    @EnvironmentObject var appState: AppState
    @State private var segment: LibrarySegment = .read
    @State private var viewMode: LibraryViewMode = .grid

    enum LibrarySegment: String, CaseIterable {
        case read = "Read"
        case currentlyReading = "Reading"
        case wantToRead = "Want to Read"
    }
    
    enum LibraryViewMode: String, CaseIterable {
        case grid
        case timeline
        case tierList
        case rating
        var icon: String {
            switch self {
            case .grid: return "square.grid.2x2"
            case .timeline: return "list.bullet"
            case .tierList: return "list.number"
            case .rating: return "star.fill"
            }
        }
        var label: String {
            switch self {
            case .grid: return "Grid"
            case .timeline: return "Timeline"
            case .tierList: return "Tier List"
            case .rating: return "Rating"
            }
        }
    }
    
    var filteredBooks: [UserBook] {
        switch segment {
        case .read: return appState.readBooks
        case .currentlyReading: return appState.currentlyReading
        case .wantToRead: return appState.wantToRead
        }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                VStack(spacing: 0) {
                    Picker("", selection: $segment) {
                        ForEach(LibrarySegment.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .padding()
                    
                    if viewMode == .tierList && segment == .read {
                        TierListView(userBooks: appState.readBooks, onUpdateTier: { id, tier in
                            appState.setTier(for: id, tier: tier)
                        })
                    } else if viewMode == .timeline && segment == .read {
                        TimelineLibraryView(userBooks: filteredBooks)
                    } else if viewMode == .rating && segment == .read {
                        RatingLibraryView(userBooks: filteredBooks)
                    } else {
                        GridLibraryView(userBooks: filteredBooks)
                    }
                }
            }
            .navigationTitle("Library")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        ForEach(LibraryViewMode.allCases, id: \.self) { mode in
                            Button {
                                viewMode = mode
                            } label: {
                                Label(mode.label, systemImage: mode.icon)
                            }
                        }
                    } label: {
                        Image(systemName: viewMode.icon)
                            .foregroundStyle(Theme.accent)
                    }
                }
            }
        }
    }
}
