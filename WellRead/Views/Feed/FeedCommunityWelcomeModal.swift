//
//  FeedCommunityWelcomeModal.swift
//  WellRead
//
//  One-time overlay on the feed explaining default mutual follows (early community).
//

import SwiftUI

struct FeedCommunityWelcomeModal: View {
    let onGotIt: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Text("Welcome to Spines")
                .font(Theme.largeTitle())
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 16)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    paragraph("I'm excited to have you here early.")
                    paragraph("I'm focused on building a strong community of thoughtful, curious people.")
                    paragraph("To foster this, early users automatically follow all other Spines users.")
                    paragraph("Why? Because I think you'll like them and what they have to say.")
                    paragraph("You can unfollow anyone at any time from their profile, and they won't be notified.")
                    paragraph("There's nothing more I love in this life than the free sharing of new thoughts and ideas.")
                    paragraph("The app might be a bit ugly right now, but I hope it's functional enough. I promise it'll get smoother and prettier over time.")
                    paragraph("Please text me with any issues you encounter, as well as any feedback/thoughts/feature ideas. I want to hear what you think. Unfiltered.")
                    paragraph("Once again, I'm glad you're here.")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 400)

            Button(action: onGotIt) {
                Text("I'm glad to be here")
                    .font(Theme.headline())
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .foregroundStyle(Theme.background)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Theme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius))
            }
            .buttonStyle(.plain)
            .padding(.top, 20)
        }
        .padding(Theme.horizontalPadding)
        .padding(.vertical, 24)
        .background(Theme.background)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius)
                .strokeBorder(Theme.textTertiary.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 24, y: 12)
        .padding(.horizontal, Theme.horizontalPadding)
    }

    private func paragraph(_ text: String) -> some View {
        Text(text)
            .font(Theme.body())
            .foregroundStyle(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
