//
//  FeedCommunityWelcomeModal.swift
//  Spine
//
//  One-time overlay on the feed: the founder's welcome note to early users.
//  Themed to match Spine redesign — windowed card, mono type, mono CTA.
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
                        paragraph("Thanks for being here early!")
                        paragraph("I'm adding new features and polishing the app on a weekly basis. Please send feedback my way via text/DM.")
                        paragraph("Reading and learning exist at the core of my passion for life. I hope this app helps you share what inspires you. I'm glad you're here.")
                        paragraph("-Tanner")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 380)

                Button(action: onGotIt) {
                    Text("I'm glad to be here!")
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
