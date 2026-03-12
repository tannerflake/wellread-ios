//
//  MainTabView.swift
//  WellRead
//
//  Bottom tab bar: Feed, Discover, Add (center), Profile (library + profile merged).
//

import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTab: Tab = .profile
    @State private var showAddBook = false
    
    enum Tab: String, CaseIterable {
        case feed
        case discover
        case add
        case profile
    }
    
    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch selectedTab {
                case .feed: FeedView()
                case .discover: DiscoverView()
                case .add: Color.clear
                case .profile: ProfileLibraryView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            tabBar
        }
        .ignoresSafeArea(.keyboard)
        .sheet(isPresented: $showAddBook) { AddBookFlowView() }
        .onAppear {
            appState.loadDiscoverSuggestionsIfNeeded()
        }
    }
    
    private var tabBar: some View {
        HStack(spacing: 0) {
            tabButton(.feed, icon: "book.closed.fill", label: "Feed")
            tabButton(.discover, icon: "sparkles", label: "Discover")
            tabButton(.profile, icon: "books.vertical.fill", label: "Profile")
            addButton
        }
        .padding(.horizontal, 8)
        .padding(.top, 6)
        .padding(.bottom, 16)
        .background(Theme.background.opacity(0.95))
        .overlay(
            Rectangle()
                .fill(Theme.textTertiary.opacity(0.2))
                .frame(height: 1),
            alignment: .top
        )
    }
    
    private func tabButton(_ tab: Tab, icon: String, label: String) -> some View {
        Button {
            if tab == .add {
                showAddBook = true
            } else {
                selectedTab = tab
            }
        } label: {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))
                Text(label)
                    .font(Theme.caption())
            }
            .frame(maxWidth: .infinity)
            .foregroundStyle(selectedTab == tab ? Theme.accent : Theme.textSecondary)
        }
        .buttonStyle(.plain)
    }
    
    private var addButton: some View {
        Button {
            showAddBook = true
        } label: {
            VStack(spacing: 2) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 32))
                Text("Add")
                    .font(Theme.caption())
            }
            .frame(maxWidth: .infinity)
            .foregroundStyle(Theme.accent)
        }
        .buttonStyle(.plain)
    }
}
