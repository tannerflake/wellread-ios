//
//  FeedCommunityWelcomeModal.swift
//  Spine
//
//  One-time overlay on the feed explaining default mutual follows for early
//  community users. Themed to match Spine redesign — windowed card, mono
//  type, bracketed CTA.
//

import SwiftUI

struct FeedCommunityWelcomeModal: View {
    let onGotIt: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Welcome to Spine")
                    .font(Theme.largeTitle())
                    .tracking(Theme.displayTracking)
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(SpinesGlyphs.rule(width: 28))
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .foregroundStyle(Theme.chromeTeal)

                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        paragraph("I'm excited to have you here early.")
                        paragraph("I'm focused on building a strong community of thoughtful, curious people.")
                        paragraph("To foster this, early users automatically follow all other Spine users.")
                        paragraph("Why? Because I think you'll like them and what they have to say.")
                        paragraph("You can unfollow anyone at any time from their profile, and they won't be notified.")
                        paragraph("There's nothing more I love in this life than the free sharing of new thoughts and ideas.")
                        paragraph("The app might be a bit ugly right now, but I hope it's functional enough. I promise it'll get smoother and prettier over time.")
                        paragraph("Please text me with any issues you encounter, as well as any feedback/thoughts/feature ideas. I want to hear what you think. Unfiltered.")
                        paragraph("Once again, I'm glad you're here.")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 380)

                Button(action: onGotIt) {
                    Text("[ I'M GLAD TO BE HERE ]")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .tracking(1)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                        .foregroundStyle(Theme.phosphorWhite)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.cardCornerRadius)
                                .fill(Theme.accent)
                        )
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
            }
            .padding(20)
        }
        .windowedCard(title: "Welcome")
        .padding(.horizontal, Theme.horizontalPadding)
    }

    private func paragraph(_ text: String) -> some View {
        Text(text)
            .font(Theme.body())
            .foregroundStyle(Theme.textSecondary)
            .lineSpacing(Theme.bodyLineSpacing)
            .fixedSize(horizontal: false, vertical: true)
    }
}
