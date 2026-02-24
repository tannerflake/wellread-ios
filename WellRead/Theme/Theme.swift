//
//  Theme.swift
//  WellRead
//
//  Design system: deep indigo primary, soft green accent, near-black background.
//

import SwiftUI

enum Theme {
    // MARK: - Colors
    static let primary = Color(red: 0.29, green: 0.24, blue: 0.55)      // Deep indigo
    static let accent = Color(red: 0.45, green: 0.78, blue: 0.58)        // Soft green
    static let background = Color(red: 0.08, green: 0.08, blue: 0.10)   // Near black
    static let surface = Color(red: 0.12, green: 0.12, blue: 0.14)
    static let surfaceElevated = Color(red: 0.16, green: 0.16, blue: 0.18)
    static let textPrimary = Color.white
    static let textSecondary = Color(white: 0.65)
    static let textTertiary = Color(white: 0.45)
    
    // MARK: - Typography
    static func largeTitle() -> Font { .system(size: 28, weight: .bold, design: .default) }
    static func title() -> Font { .system(size: 22, weight: .bold, design: .default) }
    static func title2() -> Font { .system(size: 18, weight: .semibold, design: .default) }
    static func headline() -> Font { .system(size: 16, weight: .semibold, design: .default) }
    static func body() -> Font { .system(size: 16, weight: .regular, design: .default) }
    static func callout() -> Font { .system(size: 14, weight: .regular, design: .default) }
    static func caption() -> Font { .system(size: 12, weight: .regular, design: .default) }
    
    // MARK: - Layout
    static let cardCornerRadius: CGFloat = 14
    static let cardPadding: CGFloat = 16
    static let gridSpacing: CGFloat = 12
    static let horizontalPadding: CGFloat = 20
}

// Card style with subtle blur / elevation
struct ThemeCardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius)
                    .fill(Theme.surfaceElevated.opacity(0.9))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius)
                    .stroke(Theme.textTertiary.opacity(0.2), lineWidth: 1)
            )
    }
}

extension View {
    func wellReadCard() -> some View {
        modifier(ThemeCardStyle())
    }
}
