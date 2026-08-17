//
//  WizardSocialSteps.swift
//  WellRead
//
//  Social steps of the onboarding wizard: the roster of readers already on
//  SPINE (follow anyone), contact invites (explainer before the contacts
//  permission, Messages-composer texts after), and the push notification
//  pitch. Every permission/follow/push side effect runs through
//  OnboardingWizardModel; these views own only display state plus the
//  Messages composer presentation. Copy rule: no em-dashes in user-facing text.
//

import SwiftUI

// MARK: - Roster step

struct WizardRosterStep: View {
    @ObservedObject var model: OnboardingWizardModel

    /// Reader whose tier list is being peeked at in a sheet; dismissing the
    /// sheet lands right back on this step.
    @State private var peekEntry: OnboardingWizardModel.RosterEntry?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TypewriterText(
                text: "Find a buddy",
                font: .system(size: 28, weight: .bold),
                centered: false
            )

            Text("Don't be shy! You're in good company.")
                .font(.system(size: 16))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .wizardReveal(delay: 0.2)
                .padding(.top, 10)

            rosterContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .wizardReveal(delay: 0.3)
                .padding(.top, 16)

            VStack(spacing: 10) {
                WizardCTAButton(title: "Continue") {
                    model.finishRosterStep()
                }
            }
            .wizardReveal(delay: 0.3)
            .padding(.top, 12)
        }
        .padding(.horizontal, 28)
        .padding(.top, 10)
        .padding(.bottom, 24)
        .task { await model.loadRosterIfNeeded() }
        .sheet(item: $peekEntry) { entry in
            NavigationStack {
                ZStack {
                    Theme.background.ignoresSafeArea()
                    UserLibraryDetailView(userId: entry.uid)
                }
                .toolbarBackground(Theme.background, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { peekEntry = nil }
                            .foregroundStyle(Theme.accent)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var rosterContent: some View {
        if model.isLoadingRoster {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.roster.isEmpty {
            Text("It's early. More readers arrive every week.")
                .font(.system(size: 15))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            let similar = model.similarReaders
            let similarUids = Set(similar.map(\.entry.uid))
            let rest = model.roster
                .filter { !similarUids.contains($0.uid) }
                .sorted { $0.user.displayName.localizedCaseInsensitiveCompare($1.user.displayName) == .orderedAscending }
            ScrollView {
                LazyVStack(spacing: 9) {
                    if !similar.isEmpty {
                        similarSection(similar)
                    }
                    ForEach(rest) { entry in
                        rosterRow(entry, sharedTags: nil)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    /// Readers with the most taste overlap, boxed off so they read as "start
    /// here" rather than more of the same list.
    private func similarSection(_ similar: [(entry: OnboardingWizardModel.RosterEntry, sharedTags: [String])]) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("MOST LIKE YOU")
                .font(.system(size: 11, weight: .bold))
                .tracking(1.6)
                .foregroundStyle(Theme.textSecondary)
                .padding(.leading, 2)
            ForEach(similar, id: \.entry.uid) { item in
                rosterRow(item.entry, sharedTags: item.sharedTags)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Theme.textPrimary.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Theme.textPrimary.opacity(0.14), lineWidth: 1)
        )
        .padding(.bottom, 6)
    }

    private func rosterRow(_ entry: OnboardingWizardModel.RosterEntry, sharedTags: [String]?) -> some View {
        HStack(spacing: 11) {
            // Name/avatar open a read-only peek at their tier list; the
            // follow button stays its own tap target.
            Button {
                WizardHaptics.selection()
                peekEntry = entry
            } label: {
                HStack(spacing: 11) {
                    rosterAvatar(for: entry.user)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.user.displayName)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                        Text("@\(entry.user.username)")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.textTertiary)
                            .lineLimit(1)
                        if let sharedTags, !sharedTags.isEmpty {
                            Text(sharesText(sharedTags))
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.textSecondary)
                                .lineLimit(3)
                        }
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Shows their tier list")

            Spacer(minLength: 8)

            followButton(for: entry)
        }
        .padding(11)
        .background(Theme.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Theme.textPrimary.opacity(0.12), lineWidth: 1)
        )
    }

    private func sharesText(_ tags: [String]) -> String {
        let shown = tags.prefix(4)
        let extra = tags.count - shown.count
        let list = shown.joined(separator: ", ")
        return extra > 0 ? "Shares: \(list) +\(extra)" : "Shares: \(list)"
    }

    private func rosterAvatar(for user: User) -> some View {
        UserAvatarView(
            urlString: user.profileImageURL,
            displayName: user.displayName,
            firstName: user.firstName,
            lastName: user.lastName,
            size: 42
        )
    }

    private func followButton(for entry: OnboardingWizardModel.RosterEntry) -> some View {
        let isFollowing = model.followedUids.contains(entry.uid)
        return Button {
            WizardHaptics.selection()
            Task { await model.toggleFollow(targetUid: entry.uid) }
        } label: {
            Text(isFollowing ? "Following" : "Follow")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(isFollowing ? Theme.textSecondary : Theme.onChrome)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Capsule().fill(isFollowing ? Color.clear : Theme.textPrimary))
                .overlay(
                    Capsule().stroke(Theme.textPrimary.opacity(isFollowing ? 0.2 : 0), lineWidth: 1.5)
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(model.followInFlight.contains(entry.uid))
        .accessibilityLabel(isFollowing ? "Unfollow \(entry.user.displayName)" : "Follow \(entry.user.displayName)")
    }
}

// MARK: - Invite step

struct WizardInviteStep: View {
    @ObservedObject var model: OnboardingWizardModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var contactToInvite: SyncedContact?
    @State private var cantSendTextAlert = false
    @State private var contactSearch = ""
    @State private var leafPulsing = false

    private var filteredInviteCandidates: [SyncedContact] {
        let query = contactSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return model.inviteCandidates }
        return model.inviteCandidates.filter { contact in
            contact.displayName.localizedCaseInsensitiveContains(query)
                || contact.phoneNumbers.contains { $0.contains(query) }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TypewriterText(
                text: "Help SPINE grow!",
                font: .system(size: 28, weight: .bold),
                centered: false
            )

            Text(model.contactsGranted
                 ? "Invite 3 friends whose reading you'd love to see."
                 : "Share the app with your most well-read friends.")
                .font(.system(size: 16))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .wizardReveal(delay: 0.2)
                .padding(.top, 10)

            if model.contactsGranted {
                inviteMeter
                    .padding(.top, 14)
                contactSearchField
                    .padding(.top, 12)
                inviteList
                    .padding(.top, 10)
            } else {
                Spacer()

                Image(systemName: "leaf")
                    .font(.system(size: 192, weight: .light))
                    .foregroundStyle(Theme.textPrimary.opacity(0.25))
                    .scaleEffect(leafPulsing && !reduceMotion ? 1.08 : 0.94)
                    .animation(
                        reduceMotion ? nil : .easeInOut(duration: 1.8).repeatForever(autoreverses: true),
                        value: leafPulsing
                    )
                    .frame(maxWidth: .infinity)
                    .wizardReveal(delay: 0.3)
                    .onAppear { leafPulsing = true }

                Spacer()
            }

            VStack(spacing: 10) {
                if model.contactsGranted {
                    WizardCTAButton(title: "Done inviting") {
                        model.advance()
                    }
                } else {
                    WizardCTAButton(title: "Invite") {
                        Task {
                            let granted = await model.requestContactsAndLoadInvites()
                            if !granted { model.advance() }
                        }
                    }
                    WizardSecondaryButton(title: "Maybe later") {
                        model.advance()
                    }
                }
            }
            .wizardReveal(delay: 0.3)
            .padding(.top, 12)
        }
        .padding(.horizontal, 28)
        .padding(.top, 10)
        .padding(.bottom, 24)
        .sheet(item: $contactToInvite) { contact in
            MessageComposeView(
                recipients: Array(contact.phoneNumbers.prefix(1)),
                body: AppLinks.onboardingInviteMessage(),
                onFinish: { model.invitedContactIds.insert(contact.id) }
            )
            .ignoresSafeArea()
        }
        .alert("Can't send texts", isPresented: $cantSendTextAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("This device can't send text messages. You can still share SPINE from the App Store: \(AppLinks.appStore)")
        }
    }

    /// Three slots that ink in as invites go out; a concrete "get to 3" ask
    /// converts better than an open-ended list.
    private var inviteMeter: some View {
        let count = min(3, model.invitedContactIds.count)
        return HStack(spacing: 10) {
            ForEach(0..<3, id: \.self) { index in
                Capsule()
                    .fill(index < count ? Theme.textPrimary : Theme.textPrimary.opacity(0.12))
                    .frame(height: 6)
            }
            Text(count >= 3 ? "3 of 3. Well done." : "\(count) of 3")
                .font(.system(size: 12, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(count >= 3 ? Theme.textPrimary : Theme.textTertiary)
                .lineLimit(1)
                .fixedSize()
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: count)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(count) of 3 friends invited")
    }

    private var contactSearchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
            TextField("Search your contacts", text: $contactSearch)
                .font(.system(size: 15))
                .foregroundStyle(Theme.textPrimary)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
            if !contactSearch.isEmpty {
                Button {
                    contactSearch = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.textTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear contact search")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private var inviteList: some View {
        ScrollView {
            LazyVStack(spacing: 9) {
                if model.isLoadingContacts {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .padding(.vertical, 24)
                } else if model.inviteCandidates.isEmpty {
                    Text("Everyone you know is already here.")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                } else if filteredInviteCandidates.isEmpty {
                    Text("No contacts match \u{201C}\(contactSearch)\u{201D}.")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                } else {
                    ForEach(filteredInviteCandidates) { contact in
                        inviteRow(contact)
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func inviteRow(_ contact: SyncedContact) -> some View {
        let invited = model.invitedContactIds.contains(contact.id)
        return HStack(spacing: 11) {
            ZStack {
                Circle().fill(Theme.surfaceElevated)
                Circle().stroke(Theme.textPrimary.opacity(0.12), lineWidth: 1)
                Text(initials(for: contact.displayName))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 2) {
                Text(contact.displayName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text(contact.phoneNumbers.first ?? "")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Button {
                WizardHaptics.selection()
                if model.previewMode {
                    // Preview runs never open a real Messages composer at the
                    // canned fixture numbers; just show the state change.
                    model.invitedContactIds.insert(contact.id)
                } else if MessageComposeView.canSendText {
                    contactToInvite = contact
                } else {
                    cantSendTextAlert = true
                }
            } label: {
                Text(invited ? "Sent" : "Invite")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(invited ? Theme.textSecondary : Theme.onChrome)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(invited ? Color.clear : Theme.textPrimary))
                    .overlay(
                        Capsule().stroke(Theme.textPrimary.opacity(invited ? 0.2 : 0), lineWidth: 1.5)
                    )
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(invited)
            .accessibilityLabel(invited ? "Invited \(contact.displayName)" : "Invite \(contact.displayName)")
        }
        .padding(11)
        .background(Theme.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Theme.textPrimary.opacity(0.12), lineWidth: 1)
        )
    }

    private func initials(for name: String) -> String {
        let parts = name.split(separator: " ", omittingEmptySubsequences: true)
        let letters = parts.prefix(2).compactMap { $0.first }
        return String(letters).uppercased()
    }
}

// MARK: - Notifications step

struct WizardNotificationsStep: View {
    @ObservedObject var model: OnboardingWizardModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TypewriterText(
                text: "SPINE is no fun without notifications!",
                font: .system(size: 28, weight: .bold),
                centered: false
            )

            Text("Only the good stuff. We promise not to blow your phone up.")
                .font(.system(size: 16))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .wizardReveal(delay: 0.2)
                .padding(.top, 10)

            Text("ex.")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)
                .wizardReveal(delay: 0.25)
                .padding(.top, 24)

            VStack(spacing: 10) {
                mockCard(
                    symbol: "star.fill",
                    title: "Maya finished The Secret History",
                    message: "\u{201C}okay I get the hype now\u{201D} · 8.5",
                    time: "2m"
                )
                .wizardReveal(delay: 0.3)
                mockCard(
                    symbol: "arrow.right",
                    title: "Sam recommended you a book",
                    message: "Project Hail Mary. \u{201C}trust me on this one\u{201D}",
                    time: "1h"
                )
                .wizardReveal(delay: 0.3)
                mockCard(
                    symbol: "at",
                    title: "Priya replied to your review",
                    message: "\u{201C}completely agree about the ending\u{201D}",
                    time: "3h"
                )
                .wizardReveal(delay: 0.3)
            }
            .padding(.top, 8)

            Spacer()

            VStack(spacing: 10) {
                WizardCTAButton(title: "Turn on notifications") {
                    model.finishNotificationsStep(enable: true)
                }
                WizardGhostButton(title: "Not now") {
                    model.finishNotificationsStep(enable: false)
                }
            }
            .wizardReveal(delay: 0.3)
        }
        .padding(.horizontal, 28)
        .padding(.top, 10)
        .padding(.bottom, 24)
    }

    private func mockCard(symbol: String, title: String, message: String, time: String) -> some View {
        HStack(spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Theme.textPrimary)
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.onChrome)
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(message)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            Text(time)
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(12)
        .background(Theme.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Theme.textPrimary.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: Theme.shadowInk.opacity(0.10), radius: 10, x: 0, y: 4)
        .accessibilityElement(children: .combine)
    }
}
