//
//  WizardSocialSteps.swift
//  WellRead
//
//  Social steps of the onboarding wizard: the phone number used for contact
//  matching, the roster of readers already on SPINE (follow anyone), contact
//  invites (explainer before the contacts permission, Messages-composer texts
//  after), and the push notification pitch. Every permission/follow/push side effect runs through
//  OnboardingWizardModel; these views own only display state plus the
//  Messages composer presentation. Copy rule: no em-dashes in user-facing text.
//

import SwiftUI

// MARK: - Phone step

/// Optional, skippable, and never gated: SPINE stores the number only so
/// friends who already have the user in their address book can find them
/// (ContactSyncService matches on the last 10 digits, on device). App Store
/// guideline 5.1.1(v) is the reason "Skip for now" is always right there and
/// nothing downstream depends on the answer.
struct WizardPhoneStep: View {
    @ObservedObject var model: OnboardingWizardModel

    @FocusState private var phoneFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TypewriterText(
                text: "What's your number?",
                font: .system(size: 28, weight: .bold),
                centered: false
            )

            VStack(alignment: .leading, spacing: 12) {
                Text("It helps us find your friends.")
                Text("We won't show it on your profile, and we won't text you.")
            }
            .font(.system(size: 16))
            .foregroundStyle(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .wizardReveal(delay: 0.2)
            .padding(.top, 14)

            phoneField
                .padding(.top, 26)
                .wizardReveal(delay: 0.3)

            Spacer(minLength: 12)

            VStack(spacing: 10) {
                WizardCTAButton(title: "That's me", enabled: model.canSubmitPhone) {
                    model.finishPhoneStep()
                }
                WizardGhostButton(title: "Skip for now") {
                    model.advance()
                }
            }
            .wizardReveal(delay: 0.3)
        }
        .padding(.horizontal, 28)
        .padding(.top, 10)
        .padding(.bottom, 24)
        .onAppear {
            model.prefillPhoneIfNeeded()
            // Deferred so the keyboard doesn't race the step transition, and
            // never stolen back if the user already tapped somewhere.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                guard !phoneFocused else { return }
                phoneFocused = true
            }
        }
        .onChange(of: model.phoneNumber) { old, new in
            model.phoneInputChanged(old: old, new: new)
        }
    }

    private var phoneField: some View {
        HStack(spacing: 10) {
            Image(systemName: "phone.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)
            TextField("(555) 555-0199", text: $model.phoneNumber)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                // textContentType is what puts the user's own number in the
                // QuickType bar: one tap and the field is filled.
                .textContentType(.telephoneNumber)
                .keyboardType(.phonePad)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .focused($phoneFocused)
        }
        .wizardFieldChrome(focused: phoneFocused) {
            phoneFocused = true
        }
    }
}

// MARK: - Contacts sync step

/// Asks to sync contacts on its own screen, so the roster step that follows can
/// lead with people the user actually knows. Its own step because asking inside
/// the roster ("know someone here?") landed before any sync had happened, which
/// read as a question the app should already have known the answer to.
///
/// Skippable, and the OS dialog fires only from the primary button (App Store
/// guideline 5.1.1(v)). Nothing downstream depends on the answer.
struct WizardContactsSyncStep: View {
    @ObservedObject var model: OnboardingWizardModel

    /// Covers the whole tap, permission dialog included. `isMatchingContacts`
    /// only goes true after permission is granted, so on its own it leaves the
    /// button looking idle while the OS dialog is up.
    @State private var isSyncing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TypewriterText(
                text: "Sync your contacts.",
                font: .system(size: 28, weight: .bold),
                centered: false
            )

            Text("It helps us find your friends on SPINE.")
                .font(.system(size: 16))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .wizardReveal(delay: 0.2)
                .padding(.top, 10)

            Spacer(minLength: 12)

            Image(systemName: "person.2.fill")
                .font(.system(size: 128, weight: .light))
                .foregroundStyle(Theme.textPrimary.opacity(0.25))
                .frame(maxWidth: .infinity)
                .wizardReveal(delay: 0.3)

            Spacer(minLength: 12)

            VStack(spacing: 10) {
                WizardCTAButton(
                    title: "Sync contacts",
                    showsProgress: isSyncing || model.isMatchingContacts
                ) {
                    isSyncing = true
                    Task {
                        await model.matchContactsForRoster(requestingPermission: true)
                        isSyncing = false
                        // Granted or refused, the wizard moves on either way.
                        // advanceIfCurrent, not advance: a second tap landing
                        // while the dialog was up must not skip the roster.
                        model.advanceIfCurrent(.contacts)
                    }
                }
                // Never gated on the sync: if the permission request stalls,
                // this is the way out.
                WizardGhostButton(title: "Skip") {
                    model.advanceIfCurrent(.contacts)
                }
            }
            .wizardReveal(delay: 0.3)
        }
        .padding(.horizontal, 28)
        .padding(.top, 10)
        .padding(.bottom, 24)
    }
}

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
        .task {
            await model.loadRosterIfNeeded()
            // Access already granted (or granted on a previous run): match
            // straight away, no dialog and nothing for the user to tap.
            if model.canMatchContactsSilently, !model.didAttemptContactMatch {
                await model.matchContactsForRoster(requestingPermission: false)
            }
        }
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
        } else if model.roster.isEmpty, model.contactMatches.isEmpty {
            Text("It's early. More readers arrive every week.")
                .font(.system(size: 15))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            // Order of the list, top down: people you actually know, then
            // strangers who read like you, then everyone else. `similarReaders`
            // already drops contact matches, so only `rest` needs filtering.
            let similar = model.similarReaders
            let similarUids = Set(similar.map(\.entry.uid))
            let contactUids = Set(model.contactMatches.map(\.uid))
            let rest = model.roster
                .filter { !similarUids.contains($0.uid) && !contactUids.contains($0.uid) }
                .sorted { $0.user.displayName.localizedCaseInsensitiveCompare($1.user.displayName) == .orderedAscending }
            ScrollView {
                LazyVStack(spacing: 9) {
                    if !model.contactMatches.isEmpty {
                        contactsSection
                    } else {
                        contactsPrompt
                    }
                    if !similar.isEmpty {
                        similarSection(similar)
                    }
                    ForEach(rest) { entry in
                        rosterRow(entry, sharedTags: nil, contactName: nil)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    /// People from the address book who are already here. First in the list:
    /// a name the user recognizes beats any taste score.
    private var contactsSection: some View {
        boxedSection(title: "YOUR CONTACTS ON SPINE") {
            ForEach(model.contactMatches) { match in
                rosterRow(
                    OnboardingWizardModel.RosterEntry(uid: match.uid, user: match.user),
                    sharedTags: nil,
                    // Only when the address book calls them something else:
                    // that mismatch is the whole "oh, that's Katie" moment.
                    contactName: match.contact.displayName == match.user.displayName
                        ? nil
                        : match.contact.displayName
                )
            }
        }
    }

    /// Stands in for the contacts section when the sync step was skipped or
    /// refused: one line and an icon, tappable to sync. The long privacy
    /// explainer lives in the OS dialog, not here.
    @ViewBuilder
    private var contactsPrompt: some View {
        if model.isMatchingContacts {
            HStack(spacing: 10) {
                ProgressView()
                Text("Checking your contacts…")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
            .padding(.bottom, 6)
        } else if model.didAttemptContactMatch, model.contactsGranted {
            // Synced, nobody matched. Saying so beats a dead "sync" prompt that
            // would just come back empty again.
            contactsNote(
                icon: "person.2.slash.fill",
                text: "No one in your contacts is on SPINE yet.",
                onTap: nil
            )
        } else {
            // Includes the refused case: a denied request can still be granted
            // in Settings, and re-tapping is how the user gets there.
            contactsNote(
                icon: "person.2.fill",
                text: "Sync your contacts to find your friends on SPINE.",
                onTap: {
                    Task { await model.matchContactsForRoster(requestingPermission: true) }
                }
            )
        }
    }

    private func contactsNote(icon: String, text: String, onTap: (() -> Void)?) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 26)
            Text(text)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if onTap != nil {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Theme.textPrimary.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Theme.textPrimary.opacity(0.14), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onTapGesture {
            guard let onTap else { return }
            WizardHaptics.selection()
            onTap()
        }
        .padding(.bottom, 6)
    }

    /// The boxed "start here" treatment shared by the contacts and taste
    /// sections, so neither reads as more of the plain list.
    private func boxedSection(
        title: String,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .tracking(1.6)
                .foregroundStyle(Theme.textSecondary)
                .padding(.leading, 2)
            content()
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
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

    /// Readers with the most taste overlap, boxed off so they read as "start
    /// here" rather than more of the same list.
    private func similarSection(_ similar: [(entry: OnboardingWizardModel.RosterEntry, sharedTags: [String])]) -> some View {
        boxedSection(title: "MOST LIKE YOU") {
            ForEach(similar, id: \.entry.uid) { item in
                rosterRow(item.entry, sharedTags: item.sharedTags, contactName: nil)
            }
        }
    }

    private func rosterRow(
        _ entry: OnboardingWizardModel.RosterEntry,
        sharedTags: [String]?,
        contactName: String?
    ) -> some View {
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
                        if let contactName {
                            Text("In your contacts as \(contactName)")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.textSecondary)
                                .lineLimit(2)
                        }
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
