//
//  MainTabView.swift
//  WellRead
//
//  Bottom tab bar: Feed, Discover, Add (center), Library, Profile.
//

import SwiftUI

struct MainTabView: View {
    @State private var selectedTab: Tab = .library
    @State private var showAddBook = false
    
    enum Tab: String, CaseIterable {
        case feed
        case discover
        case add
        case library
        case profile
    }
    
    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch selectedTab {
                case .feed: FeedView()
                case .discover: DiscoverView()
                case .add: Color.clear
                case .library: LibraryView()
                case .profile: ProfileView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            tabBar
        }
        .ignoresSafeArea(.keyboard)
        .sheet(isPresented: $showAddBook) { AddBookFlowView() }
    }
    
    private var tabBar: some View {
        HStack(spacing: 0) {
            tabButton(.feed, icon: "book.closed.fill", label: "Feed")
            tabButton(.discover, icon: "sparkles", label: "Discover")
            addButton
            tabButton(.library, icon: "books.vertical.fill", label: "Library")
            tabButton(.profile, icon: "person.fill", label: "Profile")
        }
        .padding(.horizontal, 8)
        .padding(.top, 12)
        .padding(.bottom, 28)
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
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .medium))
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
            VStack(spacing: 4) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 36))
                Text("Add")
                    .font(Theme.caption())
            }
            .frame(maxWidth: .infinity)
            .foregroundStyle(Theme.accent)
        }
        .buttonStyle(.plain)
    }
}
