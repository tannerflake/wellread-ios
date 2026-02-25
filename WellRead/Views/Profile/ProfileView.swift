//
//  ProfileView.swift
//  WellRead
//
//  Profile photo, username, bio, followers/following, stats, goal, recent reads.
//

import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var authService: AuthService
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                ScrollView {
                    if let user = appState.currentUser {
                        VStack(alignment: .leading, spacing: 24) {
                            header(user: user)
                            stats(user: user)
                            if let goal = user.readingGoal, goal > 0 {
                                goalProgress(current: user.totalBooksRead, goal: goal)
                            }
                            recentReadsSection
                        }
                        .padding(.bottom, 100)
                    }
                }
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
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
    
    private func header(user: User) -> some View {
        VStack(spacing: 12) {
            Circle()
                .fill(Theme.surface)
                .frame(width: 88, height: 88)
                .overlay(
                    Text(String(user.displayName.prefix(1)))
                        .font(Theme.largeTitle())
                        .foregroundStyle(Theme.textSecondary)
                )
            Text(user.displayName)
                .font(Theme.title())
                .foregroundStyle(Theme.textPrimary)
            Text("@\(user.username)")
                .font(Theme.callout())
                .foregroundStyle(Theme.textSecondary)
            if let bio = user.bio, !bio.isEmpty {
                Text(bio)
                    .font(Theme.body())
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            HStack(spacing: 24) {
                VStack {
                    Text("\(user.followers.count)")
                        .font(Theme.headline())
                        .foregroundStyle(Theme.textPrimary)
                    Text("Followers")
                        .font(Theme.caption())
                        .foregroundStyle(Theme.textSecondary)
                }
                VStack {
                    Text("\(user.following.count)")
                        .font(Theme.headline())
                        .foregroundStyle(Theme.textPrimary)
                    Text("Following")
                        .font(Theme.caption())
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .padding()
    }
    
    private func stats(user: User) -> some View {
        HStack(spacing: 20) {
            statBlock(value: "\(user.totalBooksRead)", label: "Books read")
            statBlock(value: "\(user.totalPagesRead)", label: "Pages read")
        }
        .padding()
        .wellReadCard()
        .padding(.horizontal)
    }
    
    private func statBlock(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(Theme.title2())
                .foregroundStyle(Theme.accent)
            Text(label)
                .font(Theme.caption())
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }
    
    private func goalProgress(current: Int, goal: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Reading goal")
                    .font(Theme.headline())
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text("\(current)/\(goal)")
                    .font(Theme.callout())
                    .foregroundStyle(Theme.textSecondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Theme.surface)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Theme.accent)
                        .frame(width: geo.size.width * min(1, CGFloat(current) / CGFloat(goal)))
                }
            }
            .frame(height: 8)
        }
        .padding()
        .wellReadCard()
        .padding(.horizontal)
    }
    
    private var recentReadsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent reads")
                .font(Theme.title2())
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(appState.readBooks.prefix(10)) { ub in
                        if let book = ub.book {
                            VStack(alignment: .leading, spacing: 4) {
                                BookCoverView(book: book, size: 80)
                                Text(book.title)
                                    .font(Theme.caption())
                                    .foregroundStyle(Theme.textPrimary)
                                    .lineLimit(2)
                                    .frame(width: 80, alignment: .leading)
                            }
                            .frame(width: 80)
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}
