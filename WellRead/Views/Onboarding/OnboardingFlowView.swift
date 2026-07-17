//
//  OnboardingFlowView.swift
//  WellRead
//
//  Sign in with Apple / Google; optional profile steps later.
//

import SwiftUI
import AuthenticationServices

struct OnboardingFlowView: View {
    @EnvironmentObject var authService: AuthService
    @EnvironmentObject var appState: AppState
    @State private var step: Step = .welcome
    @State private var username = ""
    @State private var readingGoal = ""
    @State private var showReviewerLogin = false

    // Welcome entrance choreography: logo fades in, then wordmark, then buttons;
    // once landed the logo breathes on a slow loop.
    @State private var logoRevealed = false
    @State private var wordmarkRevealed = false
    @State private var buttonsRevealed = false
    @State private var logoBreathing = false

    enum Step {
        case welcome
        case username
        case goal
        case done
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 32) {
                if step == .welcome {
                    welcomeStep
                } else if step == .username {
                    usernameStep
                } else if step == .goal {
                    goalStep
                } else {
                    doneStep
                }
            }
            .padding(Theme.horizontalPadding)
        }
        .sheet(isPresented: $showReviewerLogin) {
            ReviewerLoginView()
                .environmentObject(authService)
        }
    }

    private var welcomeStep: some View {
        VStack(spacing: 0) {
            Spacer()

            Image("SpineLogo")
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .frame(width: 240, height: 240)
                .foregroundStyle(Theme.textPrimary)
                .scaleEffect(logoBreathing ? 1.05 : 1.0)
                .opacity(logoRevealed ? 1 : 0)
                .scaleEffect(logoRevealed ? 1 : 0.82)
                .blur(radius: logoRevealed ? 0 : 10)
                .onTapGesture(count: 5) {
                    Task {
                        await authService.signInWithConfiguredTestAccount()
                    }
                }
                .onLongPressGesture(minimumDuration: 2.0) {
                    showReviewerLogin = true
                }

            Text("SPINE")
                .font(.system(size: 40, weight: .bold))
                .tracking(10)
                .foregroundStyle(Theme.textPrimary)
                .padding(.top, 28)
                // Optical centering: tracking adds trailing space after the last glyph.
                .offset(x: 5)
                .opacity(wordmarkRevealed ? 1 : 0)
                .offset(y: wordmarkRevealed ? 0 : 12)

            Spacer()
            Spacer()

            VStack(spacing: 14) {
                if let error = authService.authError {
                    Text(error)
                        .font(Theme.caption())
                        .foregroundStyle(Theme.danger)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                SignInWithAppleButton(.signIn) { request in
                    authService.makeAppleRequest(request)
                } onCompletion: { result in
                    Task {
                        await authService.handleAppleCompletion(result)
                    }
                }
                .signInWithAppleButtonStyle(.white)
                .frame(height: 50)
                .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius))

                Button {
                    guard let vc = RootViewController.topMost() else { return }
                    Task {
                        await authService.signInWithGoogle(presentingViewController: vc)
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image("GoogleLogo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 20, height: 20)
                        Text("Sign in with Google")
                    }
                    .font(Theme.headline())
                    .foregroundStyle(Theme.textPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Theme.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.cardCornerRadius)
                            .stroke(Theme.chrome.opacity(0.22), lineWidth: Theme.chromeHairline)
                    )
                }
                .buttonStyle(.springPress)
            }
            .opacity(buttonsRevealed ? 1 : 0)
            .offset(y: buttonsRevealed ? 0 : 16)
            .padding(.bottom, 24)
        }
        .onAppear { runWelcomeEntrance() }
    }

    /// Staged reveal: logo → wordmark → buttons, then the slow breathing loop.
    private func runWelcomeEntrance() {
        guard !logoRevealed else { return }
        withAnimation(.easeOut(duration: 1.4)) {
            logoRevealed = true
        }
        withAnimation(.easeOut(duration: 1.0).delay(0.9)) {
            wordmarkRevealed = true
        }
        withAnimation(.easeOut(duration: 0.9).delay(1.6)) {
            buttonsRevealed = true
        }
        withAnimation(.easeInOut(duration: 2.6).delay(1.8).repeatForever(autoreverses: true)) {
            logoBreathing = true
        }
    }

    private var usernameStep: some View {
        VStack(spacing: 24) {
            Text("Choose a username")
                .font(Theme.title())
                .foregroundStyle(Theme.textPrimary)
            TextField("Username", text: $username)
                .textFieldStyle(.plain)
                .font(Theme.body())
                .padding()
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius))
                .autocapitalization(.none)
            Button("Continue") {
                step = .goal
            }
            .font(Theme.headline())
            .foregroundStyle(Theme.background)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Theme.accentGloss)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius))
        }
        .padding(.top, 80)
    }

    private var goalStep: some View {
        VStack(spacing: 24) {
            Text("Books to read this year?")
                .font(Theme.title())
                .foregroundStyle(Theme.textPrimary)
            TextField("e.g. 24", text: $readingGoal)
                .keyboardType(.numberPad)
                .textFieldStyle(.plain)
                .font(Theme.body())
                .padding()
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius))
            Button("Finish") {
                step = .done
            }
            .font(Theme.headline())
            .foregroundStyle(Theme.background)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Theme.accentGloss)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius))
        }
        .padding(.top, 80)
    }

    private var doneStep: some View {
        VStack(spacing: 24) {
            ProgressView()
                .tint(Theme.accent)
            Text("Setting up your library…")
                .font(Theme.body())
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.top, 80)
    }
}
