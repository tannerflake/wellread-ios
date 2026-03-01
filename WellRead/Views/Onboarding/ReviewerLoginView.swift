//
//  ReviewerLoginView.swift
//  WellRead
//
//  Hidden email/password login for App Review. Trigger: long-press app logo on sign-in screen.
//

import SwiftUI

struct ReviewerLoginView: View {
    @EnvironmentObject var authService: AuthService
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                VStack(spacing: 24) {
                    Text("Reviewer Login")
                        .font(Theme.title())
                        .foregroundStyle(Theme.textPrimary)
                    Text("For App Review only")
                        .font(Theme.caption())
                        .foregroundStyle(Theme.textTertiary)

                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Email", text: $email)
                            .textFieldStyle(.plain)
                            .font(Theme.body())
                            .padding()
                            .background(Theme.surface)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                            .keyboardType(.emailAddress)

                        SecureField("Password", text: $password)
                            .textFieldStyle(.plain)
                            .font(Theme.body())
                            .padding()
                            .background(Theme.surface)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius))
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(Theme.caption())
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }

                    Button {
                        signIn()
                    } label: {
                        Text(isLoading ? "Signing In…" : "Sign In")
                            .font(Theme.headline())
                            .foregroundStyle(Theme.background)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(isLoading || email.isEmpty || password.isEmpty ? Theme.textTertiary : Theme.accent)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius))
                    }
                    .disabled(isLoading || email.isEmpty || password.isEmpty)
                }
                .padding(Theme.horizontalPadding)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(Theme.accent)
                }
            }
        }
    }

    private func signIn() {
        isLoading = true
        errorMessage = nil
        Task {
            do {
                try await authService.signInWithEmail(email, password: password)
                await MainActor.run { dismiss() }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                }
            }
            await MainActor.run { isLoading = false }
        }
    }
}
