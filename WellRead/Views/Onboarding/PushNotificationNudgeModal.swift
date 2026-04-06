//
//  PushNotificationNudgeModal.swift
//  WellRead
//
//  Recurring prompt for users who have not granted notification permission.
//

import SwiftUI

struct PushNotificationNudgeModal: View {
    let onEnable: () -> Void
    let onNoThanks: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Text("Spines is best with push notifications!")
                .font(Theme.title2())
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 12) {
                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 44))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(Theme.accent, Theme.textSecondary)
                Text("Turn on alerts so you never miss when friends post reviews, like yours, or reply in threads.")
                    .font(Theme.body())
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 12) {
                Button(action: onEnable) {
                    Text("Enable")
                        .font(Theme.headline())
                        .foregroundStyle(Theme.background)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Theme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius))
                }
                .buttonStyle(.plain)

                Button(action: onNoThanks) {
                    Text("No thanks")
                        .font(Theme.headline())
                        .foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(24)
    }
}
