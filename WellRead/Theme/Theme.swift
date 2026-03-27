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
    /// Book profile Queue button — light powder blue.
    static let queuePowderBlue = Color(red: 0.78, green: 0.88, blue: 0.96)
    /// Text on `queuePowderBlue` (enough contrast on light blue).
    static let queuePowderBlueLabel = Color(red: 0.16, green: 0.30, blue: 0.44)

    // MARK: - Typography
    static func largeTitle() -> Font { .system(size: 28, weight: .bold, design: .default) }
    static func title() -> Font { .system(size: 22, weight: .bold, design: .default) }
    static func title2() -> Font { .system(size: 18, weight: .semibold, design: .default) }
    /// Feed screen section label for “Your friends” (and similar).
    static func feedSectionHeader() -> Font { .system(size: 17, weight: .semibold, design: .default) }
    /// The “Feed” title above the post list.
    static func feedBlockTitle() -> Font { .system(size: 22, weight: .semibold, design: .default) }
    static func headline() -> Font { .system(size: 16, weight: .semibold, design: .default) }
    /// Section titles on book profile (Summary, Notable quote, etc.) — ~2× headline for emphasis.
    static func profileSectionHeader() -> Font { .system(size: 32, weight: .bold, design: .default) }
    static func body() -> Font { .system(size: 16, weight: .regular, design: .default) }
    static func callout() -> Font { .system(size: 14, weight: .regular, design: .default) }
    static func caption() -> Font { .system(size: 12, weight: .regular, design: .default) }

    /// Comment row: show seconds only when the comment is under one minute old; otherwise minutes, hours, days, then a short date.
    static func commentRelativeTimestamp(_ date: Date, now: Date = Date()) -> String {
        let interval = now.timeIntervalSince(date)
        if interval < 0 {
            return date.formatted(date: .abbreviated, time: .shortened)
        }
        if interval < 60 {
            let s = Int(interval)
            if s < 1 { return "just now" }
            return "\(s) sec"
        }
        if interval < 3600 {
            let m = Int(interval / 60)
            return m == 1 ? "1 min" : "\(m) min"
        }
        if interval < 86400 {
            let h = Int(interval / 3600)
            return h == 1 ? "1 hr" : "\(h) hr"
        }
        let days = Int(interval / 86400)
        if days < 7 {
            return days == 1 ? "1 day" : "\(days) days"
        }
        if days < 60 {
            let w = max(1, days / 7)
            return w == 1 ? "1 week" : "\(w) weeks"
        }
        return date.formatted(date: .abbreviated, time: .omitted)
    }
    
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
    /// Approximate height of `MainTabView`’s custom tab bar (icons, labels, padding). Used to inset pushed views that don’t inherit the parent’s safe area.
    static let mainTabBarChromeHeight: CGFloat = 56
}

// MARK: - Main tab bar (custom)

private struct MainTabBarOverlapKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    /// Extra bottom padding for full-screen views (e.g. book profile) above the custom tab bar when inside `MainTabView`.
    var mainTabBarOverlapExtraHeight: CGFloat {
        get { self[MainTabBarOverlapKey.self] }
        set { self[MainTabBarOverlapKey.self] = newValue }
    }
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
