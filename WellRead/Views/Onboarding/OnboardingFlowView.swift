//
//  OnboardingFlowView.swift
//  WellRead
//
//  Sign up / login, choose username, set goal, add 3 books (simplified for MVP).
//

import SwiftUI

struct OnboardingFlowView: View {
    @EnvironmentObject var appState: AppState
    @State private var step: Step = .welcome
    @State private var username = ""
    @State private var readingGoal = "24"
    
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
    }
    
    private var welcomeStep: some View {
        VStack(spacing: 24) {
            Image(systemName: "book.closed.fill")
                .font(.system(size: 64))
                .foregroundStyle(Theme.accent)
            Text("WellRead")
                .font(Theme.largeTitle())
                .foregroundStyle(Theme.textPrimary)
            Text("Track books. Discover what's next. Share with friends.")
                .font(Theme.body())
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
            Spacer().frame(height: 24)
            Button("Get started") {
                step = .username
            }
            .font(Theme.headline())
            .foregroundStyle(Theme.background)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Theme.accent)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius))
            Button("I already have an account") {
                appState.loadDemoState()
            }
            .font(Theme.callout())
            .foregroundStyle(Theme.accent)
        }
        .padding(.top, 80)
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
            .background(Theme.accent)
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
                appState.loadDemoState()
            }
            .font(Theme.headline())
            .foregroundStyle(Theme.background)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Theme.accent)
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
