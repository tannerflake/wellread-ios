//
//  WellReadApp.swift
//  WellRead
//
//  Book tracking platform — modern, minimal, dark-first.
//

import SwiftUI

@main
struct WellReadApp: App {
    @StateObject private var appState = AppState()
    
    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .preferredColorScheme(.dark)
        }
    }
}
