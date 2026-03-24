//
//  ProfileCompletionView.swift
//  WellRead
//
//  First name, last name, and handle. Shown as a sheet over the main app until complete;
//  dismissible, but reappears on each launch until saved.
//

import SwiftUI

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
