//
//  RootView.swift
//  WellRead
//
//  Root: auth gate or main tab bar.
//

import SwiftUI

struct RootView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        Group {
            if appState.isAuthenticated {
                MainTabView()
            } else {
                OnboardingFlowView()
            }
        }
        .animation(.easeInOut(duration: 0.25), value: appState.isAuthenticated)
    }
}
