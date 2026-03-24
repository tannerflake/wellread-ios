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
    /// Feed screen section labels (“Your friends”, “Feed”) — same size, between old large nav title and headline.
    static func feedSectionHeader() -> Font { .system(size: 17, weight: .semibold, design: .default) }
    static func headline() -> Font { .system(size: 16, weight: .semibold, design: .default) }
    /// Section titles on book profile (Summary, Notable quote, etc.) — ~2× headline for emphasis.
    static func profileSectionHeader() -> Font { .system(size: 32, weight: .bold, design: .default) }
    static func body() -> Font { .system(size: 16, weight: .regular, design: .default) }
    static func callout() -> Font { .system(size: 14, weight: .regular, design: .default) }
    static func caption() -> Font { .system(size: 12, weight: .regular, design: .default) }
    
    // MARK: - Ratings (out of 10, one decimal — e.g. 8.8)
    static func formatRatingOutOfTen(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    /// Slider / form input → stored value (1.0…10.0, one decimal).
    static func normalizeRatingOutOfTen(_ value: Double) -> Double {
        let clamped = min(10, max(0, value))
        return (clamped * 10).rounded() / 10
    }

    /// "Jordan's Library" / "James' Library" from a person's display name.
    static func possessiveLibraryTitle(displayName: String) -> String {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Library" }
        if trimmed.lowercased().hasSuffix("s") {
            return "\(trimmed)' Library"
        }
        return "\(trimmed)'s Library"
    }

    /// Same possessive rules, but uses first name only (`User.firstName`, else first word of `displayName`).
    static func possessiveLibraryTitleFirstNameOnly(user: User) -> String {
        let first: String
        if let fn = user.firstName?.trimmingCharacters(in: .whitespacesAndNewlines), !fn.isEmpty {
            first = fn
        } else {
            let trimmed = user.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            let parts = trimmed.split(separator: " ").map(String.init)
            first = parts.first ?? trimmed
        }
        guard !first.isEmpty else { return "Library" }
        return possessiveLibraryTitle(displayName: first)
    }

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
