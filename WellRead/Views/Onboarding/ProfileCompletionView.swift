//
//  ProfileCompletionView.swift
//  WellRead
//
//  First name, last name, and handle. Shown as a sheet over the main app until complete;
//  dismissible, but reappears on each launch until saved.
//

import PhotosUI
import SwiftUI
import UIKit

// MARK: - Handle validation (shared with User.needsProfileCompletion)

enum ProfileHandleRules {
    static let reservedHandles: Set<String> = [
        "admin", "support", "help", "spines", "wellread", "root", "system", "api", "staff", "moderator"
    ]

    /// Lowercase ASCII handle only (a–z, 0–9, _).
    static func sanitizeHandleInput(_ raw: String) -> String {
        String(raw.lowercased().filter { c in
            ("a"..."z").contains(c) || ("0"..."9").contains(c) || c == "_"
        })
    }

    static func isValidHandle(_ s: String) -> Bool {
        guard (3...24).contains(s.count) else { return false }
        for ch in s {
            guard ch.isASCII, ch.isLetter || ch.isNumber || ch == "_" else { return false }
        }
        return true
    }
}

extension User {
    /// True until first & last name, a valid non-reserved handle, and onboarding flag are set in Firestore.
    var needsProfileCompletion: Bool {
        let f = firstName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let l = lastName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let h = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if f.isEmpty || l.isEmpty { return true }
        guard ProfileHandleRules.isValidHandle(h) else { return true }
        guard !ProfileHandleRules.reservedHandles.contains(h) else { return true }
        if !profileSetupCompleted { return true }
        return false
    }
}

// MARK: - View

enum ProfileEditorMode {
    /// First-time name, handle, and yearly book goal after sign-in.
    case onboarding
    /// Opened from Library → Edit profile.
    case edit
}

struct ProfileCompletionView: View {
    @EnvironmentObject var authService: AuthService
    @EnvironmentObject private var appState: AppState
    @FocusState private var focusedField: Field?

    let mode: ProfileEditorMode
    let title: String
    let subtitle: String?
    /// Called after successful save (e.g. to dismiss the sheet). Swipe-down still dismisses the sheet.
    var onDismiss: (() -> Void)?

    @State private var firstName = ""
    @State private var lastName = ""
    @State private var handle = ""
    /// Plain digits; validated as 1…1000 for the calendar year goal.
    @State private var readingGoalText = "24"
    @State private var errorMessage: String?
    @State private var isSubmitting = false
    @State private var handleAvailable: Bool?
    /// When set, we couldn’t verify (e.g. Firestore rules) — don’t show “taken”.
    @State private var handleCheckError: String?
    @State private var handleCheckTask: Task<Void, Never>?
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var showPhotoPicker = false
    @State private var isUploadingPhoto = false
    @State private var photoUploadError: String?

    private enum Field: Hashable {
        case first, last, handle, goal
    }

    private var calendarYear: Int {
        Calendar.current.component(.year, from: Date())
    }

    private var bookGoalFieldTitle: String {
        "\(calendarYear) book goal:"
    }

    init(
        mode: ProfileEditorMode = .onboarding,
        title: String,
        subtitle: String? = nil,
        onDismiss: (() -> Void)? = nil
    ) {
        self.mode = mode
        self.title = title
        self.subtitle = subtitle
        self.onDismiss = onDismiss
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                        .font(Theme.largeTitle())
                        .foregroundStyle(Theme.textPrimary)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(Theme.body())
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .padding(.top, 8)

                profilePhotoSection

                VStack(alignment: .leading, spacing: 16) {
                    labeledField(title: "First name") {
                        TextField("First name", text: $firstName)
                            .textContentType(.givenName)
                            .textFieldStyle(.plain)
                            .focused($focusedField, equals: .first)
                            .submitLabel(.next)
                            .onSubmit { focusedField = .last }
                    }
                    labeledField(title: "Last name") {
                        TextField("Last name", text: $lastName)
                            .textContentType(.familyName)
                            .textFieldStyle(.plain)
                            .focused($focusedField, equals: .last)
                            .submitLabel(.next)
                            .onSubmit { focusedField = .handle }
                    }
                    labeledField(title: "Handle") {
                        HStack(spacing: 4) {
                            Text("@")
                                .font(Theme.body())
                                .foregroundStyle(Theme.textTertiary)
                            TextField("your_handle", text: $handle)
                                .textFieldStyle(.plain)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .focused($focusedField, equals: .handle)
                                .submitLabel(.next)
                                .onSubmit { focusedField = .goal }
                                .onChange(of: handle) { _, new in
                                    let sanitized = ProfileHandleRules.sanitizeHandleInput(new)
                                    if sanitized != new { handle = sanitized }
                                    scheduleHandleAvailabilityCheck()
                                }
                        }
                        .padding()
                        .background(Theme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius))

                        handleHintRow
                    }
                    labeledField(title: bookGoalFieldTitle) {
                        TextField("e.g. 24", text: $readingGoalText)
                            .keyboardType(.numberPad)
                            .textFieldStyle(.plain)
                            .focused($focusedField, equals: .goal)
                            .submitLabel(.done)
                    }
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(Theme.caption())
                        .foregroundStyle(.red.opacity(0.95))
                }

                Button(action: submit) {
                    HStack {
                        if isSubmitting {
                            ProgressView()
                                .tint(Theme.background)
                        } else {
                            Text("Save")
                                .font(Theme.headline())
                        }
                    }
                    .foregroundStyle(Theme.background)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(canSubmit && !isSubmitting ? Theme.accent : Theme.accent.opacity(0.45))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius))
                }
                .disabled(!canSubmit || isSubmitting)
                .padding(.top, 8)
            }
            .padding(Theme.horizontalPadding)
            .padding(.bottom, 40)
        }
        // Interactive scroll-dismiss fights the sheet + TextField focus; dismiss as soon as scrolling begins.
        .scrollDismissesKeyboard(.immediately)
        .background(Theme.background.ignoresSafeArea())
        .onAppear {
            prefillFromExistingUser()
            prefillNameFromProviderIfNeeded()
        }
        .onDisappear { handleCheckTask?.cancel() }
        .onChange(of: selectedPhotoItem) { _, newItem in
            showPhotoPicker = false
            guard let item = newItem else { return }
            Task {
                let image = await Self.loadUIImage(from: item)
                await MainActor.run {
                    selectedPhotoItem = nil
                }
                guard let image else {
                    await MainActor.run { photoUploadError = "Could not load image. Try another photo." }
                    return
                }
                await uploadProfileImage(image)
            }
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $selectedPhotoItem, matching: .images, photoLibrary: .shared())
        .alert("Photo", isPresented: Binding(
            get: { photoUploadError != nil },
            set: { if !$0 { photoUploadError = nil } }
        )) {
            Button("OK", role: .cancel) { photoUploadError = nil }
        } message: {
            Text(photoUploadError ?? "")
        }
    }

    private var profileUserForAvatar: User? {
        appState.currentUser ?? authService.appUser
    }

    private var profilePhotoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Profile photo")
                .font(Theme.caption())
                .foregroundStyle(Theme.textSecondary)
            HStack(alignment: .center, spacing: 16) {
                ZStack {
                    if let user = profileUserForAvatar,
                       let urlString = user.profileImageURL,
                       let url = URL(string: urlString) {
                        CachedProfileImage(url: url, contentMode: .fill) {
                            avatarPlaceholder(initial: String(user.displayName.prefix(1)), size: 80)
                        }
                    } else if let user = profileUserForAvatar {
                        avatarPlaceholder(initial: String(user.displayName.prefix(1)), size: 80)
                    } else {
                        avatarPlaceholder(initial: "?", size: 80)
                    }
                    if isUploadingPhoto {
                        Color.black.opacity(0.4)
                        ProgressView()
                            .tint(.white)
                    }
                }
                .frame(width: 80, height: 80)
                .clipShape(Circle())

                Button {
                    showPhotoPicker = true
                } label: {
                    Label("Change profile picture", systemImage: "photo")
                        .font(Theme.callout().weight(.semibold))
                        .foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)
                .disabled(isUploadingPhoto)
            }
        }
    }

    private func avatarPlaceholder(initial: String, size: CGFloat) -> some View {
        Circle()
            .fill(Theme.surface)
            .frame(width: size, height: size)
            .overlay(
                Text(initial)
                    .font(.system(size: size * 0.38, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
            )
    }

    private static func loadUIImage(from item: PhotosPickerItem) async -> UIImage? {
        if let data = try? await item.loadTransferable(type: Data.self),
           let image = UIImage(data: data) {
            return image
        }
        guard let url = try? await item.loadTransferable(type: URL.self) else { return nil }
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        if let data = try? Data(contentsOf: url), let image = UIImage(data: data) {
            return image
        }
        if FileManager.default.fileExists(atPath: url.path) {
            return UIImage(contentsOfFile: url.path)
        }
        return nil
    }

    private func uploadProfileImage(_ image: UIImage) async {
        guard let uid = authService.firebaseUser?.uid else { return }
        await MainActor.run {
            isUploadingPhoto = true
            photoUploadError = nil
        }
        do {
            let urlString = try await ProfilePhotoService.uploadProfilePhoto(uid: uid, image: image)
            let cacheBust = "\(urlString.contains("?") ? "&" : "?")t=\(Int(Date().timeIntervalSince1970))"
            let fullURLString = urlString + cacheBust
            if let profileURL = URL(string: fullURLString) {
                ProfileImageCache.shared.store(image, for: profileURL)
            }
            try await UserRepository().updateProfileImageURL(uid: uid, url: fullURLString)
            await authService.refreshAppUser()
            await MainActor.run {
                appState.currentUser = authService.appUser
                isUploadingPhoto = false
                photoUploadError = nil
            }
        } catch {
            await MainActor.run {
                photoUploadError = error.localizedDescription
                isUploadingPhoto = false
            }
        }
    }

    private func prefillFromExistingUser() {
        guard let u = authService.appUser else { return }
        if firstName.isEmpty, let f = u.firstName?.trimmingCharacters(in: .whitespacesAndNewlines), !f.isEmpty {
            firstName = f
        }
        if lastName.isEmpty, let l = u.lastName?.trimmingCharacters(in: .whitespacesAndNewlines), !l.isEmpty {
            lastName = l
        }
        if handle.isEmpty, !u.username.isEmpty {
            handle = ProfileHandleRules.sanitizeHandleInput(u.username)
        }
        if let g = u.readingGoal {
            readingGoalText = "\(g)"
        }
    }

    /// Apple / Google sometimes provide a display name before our form runs.
    private func prefillNameFromProviderIfNeeded() {
        guard firstName.isEmpty, lastName.isEmpty,
              let dn = authService.firebaseUser?.displayName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !dn.isEmpty else { return }
        let parts = dn.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true).map(String.init)
        if parts.count >= 2 {
            firstName = parts[0]
            lastName = parts[1]
        } else {
            firstName = parts[0]
        }
    }

    @ViewBuilder
    private func labeledField(title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(Theme.caption())
                .foregroundStyle(Theme.textSecondary)
            content()
                .font(Theme.body())
                .foregroundStyle(Theme.textPrimary)
                .padding()
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius))
        }
    }

    @ViewBuilder
    private var handleHintRow: some View {
        HStack(alignment: .top, spacing: 6) {
            if let handleCheckError {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange.opacity(0.9))
                Text(handleCheckError)
                    .font(Theme.caption())
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let handleAvailable {
                Image(systemName: handleAvailable ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(handleAvailable ? Theme.accent : .red.opacity(0.85))
                Text(handleAvailable ? "That handle is available." : "That handle is taken.")
                    .font(Theme.caption())
                    .foregroundStyle(Theme.textTertiary)
            } else if normalizedHandle.count >= 3 {
                ProgressView()
                    .scaleEffect(0.75)
                Text("Checking…")
                    .font(Theme.caption())
                    .foregroundStyle(Theme.textTertiary)
            } else {
                Text("3–24 characters: letters, numbers, underscores.")
                    .font(Theme.caption())
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .padding(.top, 4)
    }

    private var normalizedHandle: String {
        handle.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Valid range for “books to read this year.”
    private var parsedReadingGoal: Int? {
        let t = readingGoalText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let n = Int(t), (1...1000).contains(n) else { return nil }
        return n
    }

    private var canSubmit: Bool {
        let f = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        let l = lastName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !f.isEmpty, !l.isEmpty else { return false }
        guard ProfileHandleRules.isValidHandle(normalizedHandle) else { return false }
        guard !ProfileHandleRules.reservedHandles.contains(normalizedHandle) else { return false }
        guard handleAvailable == true else { return false }
        guard parsedReadingGoal != nil else { return false }
        return true
    }

    private func scheduleHandleAvailabilityCheck() {
        handleCheckTask?.cancel()
        let candidate = normalizedHandle
        guard ProfileHandleRules.isValidHandle(candidate), !ProfileHandleRules.reservedHandles.contains(candidate) else {
            handleAvailable = nil
            handleCheckError = nil
            return
        }
        // Debounce off the main thread — don’t clear handle state on every keystroke (avoids re-render/tap lag).
        handleCheckTask = Task {
            try? await Task.sleep(nanoseconds: 550_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard normalizedHandle == candidate else { return }
                handleAvailable = nil
                handleCheckError = nil
            }
            guard !Task.isCancelled else { return }
            let outcome = await authService.checkUsernameAvailability(candidate)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard normalizedHandle == candidate else { return }
                switch outcome {
                case .available:
                    handleAvailable = true
                    handleCheckError = nil
                case .taken:
                    handleAvailable = false
                    handleCheckError = nil
                case .failed:
                    handleAvailable = nil
                    handleCheckError = "Couldn’t verify this handle (Firestore permissions). In Firebase Console: Firestore → choose the database “wellread” (not default) → Rules → paste the repo’s firestore.rules → Publish."
                }
            }
        }
    }

    private func submit() {
        guard canSubmit, let goal = parsedReadingGoal else { return }
        errorMessage = nil
        isSubmitting = true
        Task {
            do {
                try await authService.completeProfileSetup(
                    firstName: firstName.trimmingCharacters(in: .whitespacesAndNewlines),
                    lastName: lastName.trimmingCharacters(in: .whitespacesAndNewlines),
                    handle: normalizedHandle,
                    readingGoal: goal
                )
                await MainActor.run {
                    isSubmitting = false
                    onDismiss?()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isSubmitting = false
                }
            }
        }
    }
}
