//
//  LibraryView.swift
//  WellRead
//
//  Library-only tab (labeled "Profile" in tab bar): "Your Library" with Read | Want to Read. View toggle: Grid | Tier List. Optional filter by year read (Read segment).
//

import SwiftUI

// MARK: - Library (Profile tab content)

struct ProfileLibraryView: View {
    @EnvironmentObject var authService: AuthService
    @EnvironmentObject var appState: AppState
    @State private var segment: LibrarySegment = .read
    @State private var viewMode: LibraryViewMode = .tierList
    @State private var selectedYear: Int? = nil

    enum LibrarySegment: String, CaseIterable {
        case read = "Read"
        case wantToRead = "Want to Read"
    }

    var filteredBooks: [UserBook] {
        switch segment {
        case .read: return readBooksFilteredByYear
        case .wantToRead: return appState.wantToRead
        }
    }

    private var readBooksFilteredByYear: [UserBook] {
        let read = appState.readBooks
        guard let year = selectedYear else { return read }
        return read.filter { ub in
            guard let d = ub.dateFinished else { return false }
            return Calendar.current.component(.year, from: d) == year
        }
    }

    private var availableYears: [Int] {
        let years = Set(appState.readBooks.compactMap { ub -> Int? in
            ub.dateFinished.map { Calendar.current.component(.year, from: $0) }
        })
        return years.sorted(by: >)
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

                    if segment == .read && !availableYears.isEmpty {
                        yearFilterBar
                    }

                    libraryContent
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Your Library")
                        .font(Theme.title())
                        .foregroundStyle(Theme.textPrimary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        ForEach(LibraryViewMode.allCases, id: \.self) { mode in
                            Button {
                                viewMode = mode
                            } label: {
                                Label(mode.label, systemImage: mode.icon)
                            }
                        }
                        Divider()
                        Button("Sign out", role: .destructive) {
                            authService.signOut()
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
        }
    }

    private var yearFilterBar: some View {
        HStack(spacing: 8) {
            Text("Year:")
                .font(Theme.caption())
                .foregroundStyle(Theme.textSecondary)
            Menu {
                Button("All") { selectedYear = nil }
                ForEach(availableYears, id: \.self) { year in
                    Button(String(year)) { selectedYear = year }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(selectedYear.map { String($0) } ?? "All")
                        .font(Theme.callout())
                        .foregroundStyle(Theme.textPrimary)
                    Image(systemName: "chevron.down.circle.fill")
                        .font(.caption)
                        .foregroundStyle(Theme.textTertiary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            Spacer()
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var libraryContent: some View {
        if viewMode == .tierList && segment == .read {
            TierListView(userBooks: readBooksFilteredByYear, onUpdateTierAndOrder: { id, tier, order in
                appState.setTierAndOrder(for: id, tier: tier, order: order)
            })
        } else {
            GridLibraryView(
                userBooks: filteredBooks,
                onMoveToRead: segment == .wantToRead ? { appState.moveToRead($0) } : nil
            )
        }
    }
}

// MARK: - Library view mode (shared)

enum LibraryViewMode: String, CaseIterable {
    case tierList
    case grid
    var icon: String {
        switch self {
        case .tierList: return "list.number"
        case .grid: return "square.grid.2x2"
        }
    }
    var label: String {
        switch self {
        case .tierList: return "Tier List"
        case .grid: return "Grid"
        }
    }
}
