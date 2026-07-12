//
//  Theme.swift
//  Spine
//
//  Design system: terminal-paper foundation, CRT-black ink, teal chrome.
//  Translated from the Spine moodboard for iOS — keeps rounded corners,
//  gradients, and shadows; uses ASCII as accent only (never book covers);
//  preserves the universal tier-list colors (defined in TierListView.swift).
//

import SwiftUI

enum Theme {
    // MARK: - Colors — Foundation

    /// Terminal paper — primary background. (#E8E4DB)
    static let background = Color(red: 0.910, green: 0.894, blue: 0.859)
    /// CRT black — primary text and ink. (#0A0A0A)
    static let textPrimary = Color(red: 0.039, green: 0.039, blue: 0.039)
    /// Phosphor white — for inverted surfaces (teal/navy/black chrome). (#FFFFFF)
    static let phosphorWhite = Color.white

    // Surfaces stay close to background; differentiation comes from borders and
    // type, not big fill jumps.
    /// Cards / sheets — slightly cooler/darker than `background`. (#DCD7CC)
    static let surface = Color(red: 0.863, green: 0.843, blue: 0.800)
    /// Elevated cards — flips slightly lighter (paper-on-paper). (#F2EFE8)
    static let surfaceElevated = Color(red: 0.949, green: 0.937, blue: 0.910)

    // Text hierarchy — fades of CRT black on terminal paper.
    static let textSecondary = Color(red: 0.34, green: 0.32, blue: 0.30)
    static let textTertiary = Color(red: 0.55, green: 0.53, blue: 0.50)

    // MARK: - Colors — Chrome (load-bearing UI frames)

    /// Win95 desktop teal — window frames, dividers, badges, primary border. (#1B7B7E)
    static let chromeTeal = Color(red: 0.106, green: 0.482, blue: 0.494)
    /// Classic title-bar navy — OS-shell title bars / emphatic chrome. (#000080)
    static let chromeNavy = Color(red: 0.000, green: 0.000, blue: 0.502)
    /// Win95 system gray — retro button surfaces, used sparingly. (#C0C0C0)
    static let chromeGray = Color(red: 0.753, green: 0.753, blue: 0.753)

    // MARK: - Colors — One-shot accents (used rarely; they hit hard)

    /// "BANG BANG BANG" magenta — reserve for truly singular punches. (#E8408F)
    static let magentaPunch = Color(red: 0.910, green: 0.251, blue: 0.561)
    /// ASICS blue — primary CTA / "the real brand color moment". (#0F4FB8)
    static let asicsBlue = Color(red: 0.059, green: 0.310, blue: 0.722)

    // MARK: - Colors — Semantic aliases (stable API for existing views)

    /// Brand chrome (was deep indigo) — now teal.
    static let primary = chromeTeal
    /// Primary CTA color (Read button, rating pills) (was soft green) — now ASICS blue.
    static let accent = asicsBlue

    /// Queue button background — pale ASICS-blue tint.
    static let queuePowderBlue = Color(red: 0.815, green: 0.870, blue: 0.965)
    /// Text on `queuePowderBlue` — full-strength ASICS blue.
    static let queuePowderBlueLabel = asicsBlue

    /// Fallback "spine" color for books with no cover image — Win98-friendly indigo plum
    /// that harmonizes with chromeNavy and magentaPunch. Use phosphorWhite for text on it.
    static let defaultCoverFill = Color(red: 0.290, green: 0.240, blue: 0.550)

    /// Generated-cover palette: 12 deep book-jacket hues, each verified ≥ 7:1 contrast
    /// with `phosphorWhite` text (WCAG AA needs 4.5:1). A book picks one deterministically
    /// (stable hash of title+author) so its color never changes between renders/launches,
    /// and neighboring coverless books don't collapse into a wall of one color.
    static let coverPalette: [Color] = [
        Color(red: 74/255, green: 61/255, blue: 140/255),   // deep purple
        Color(red: 49/255, green: 46/255, blue: 129/255),   // indigo
        Color(red: 30/255, green: 58/255, blue: 110/255),   // navy
        Color(red: 37/255, green: 78/255, blue: 112/255),   // steel blue
        Color(red: 13/255, green: 92/255, blue: 99/255),    // petrol teal
        Color(red: 28/255, green: 92/255, blue: 58/255),    // forest green
        Color(red: 82/255, green: 78/255, blue: 26/255),    // dark olive
        Color(red: 146/255, green: 60/255, blue: 18/255),   // rust
        Color(red: 121/255, green: 68/255, blue: 34/255),   // sienna brown
        Color(red: 146/255, green: 34/255, blue: 30/255),   // deep red
        Color(red: 122/255, green: 28/255, blue: 56/255),   // burgundy
        Color(red: 108/255, green: 40/255, blue: 96/255)    // plum
    ]

    /// Stable palette pick — uses an FNV-1a hash (not `hashValue`, which is
    /// randomized per launch) so the same book always gets the same color.
    static func coverPaletteColor(for seed: String) -> Color {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in seed.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return coverPalette[Int(hash % UInt64(coverPalette.count))]
    }

    // Tier list colors (S/A/B/C/D) are universal and live in TierListView.swift.
    // They are intentionally *not* re-themed here.

    // MARK: - Typography
    //
    // Almost everything is monospace: titles, labels, buttons, metadata, ratings,
    // captions — the moodboard's "terminal cadence" stays where short labels live.
    // The exception is body() — used for long-form prose (book summaries, notable
    // quotes, review captions, comments). Mono walls of paragraph text fight the
    // reader; serif (New York) reads like a printed page and is on-brand for a
    // book app. Translates the moodboard rather than transcribing it.

    private static func mono(_ size: CGFloat, weight: Font.Weight) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    private static func serif(_ size: CGFloat, weight: Font.Weight) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    static func largeTitle() -> Font { mono(28, weight: .bold) }
    static func title() -> Font { mono(22, weight: .bold) }
    static func title2() -> Font { mono(18, weight: .semibold) }
    /// Feed section label ("Your friends", etc.).
    static func feedSectionHeader() -> Font { mono(17, weight: .semibold) }
    /// "Feed" title above the post list.
    static func feedBlockTitle() -> Font { mono(22, weight: .semibold) }
    static func headline() -> Font { mono(16, weight: .semibold) }
    /// Book profile section titles (Summary, Notable quote) — ~2× headline.
    static func profileSectionHeader() -> Font { mono(32, weight: .bold) }
    /// Long-form prose — serif for readability. UI chrome should NOT use this; use callout/caption/headline.
    static func body() -> Font { serif(17, weight: .regular) }
    static func callout() -> Font { mono(14, weight: .regular) }
    static func caption() -> Font { mono(12, weight: .regular) }

    /// Tracking applied to display type for "terminal cadence."
    static let displayTracking: CGFloat = 0.5
    /// Line spacing for body prose. Serif at 17pt reads well with a small extra leading.
    static let bodyLineSpacing: CGFloat = 3

    /// Comment rows and feed post timestamps: seconds only under one minute; otherwise minutes and hours until 24 h; then whole days/weeks—no hour remainder once a post is a day old.
    /// Feed post timestamp: relative ("3 days") within the last week, otherwise an absolute date.
    static func feedRelativeTimestamp(_ date: Date, now: Date = Date()) -> String {
        if now.timeIntervalSince(date) >= 7 * 86400 {
            return date.formatted(date: .abbreviated, time: .omitted)
        }
        return commentRelativeTimestamp(date, now: now)
    }

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
    /// Approximate height of `MainTabView`'s custom tab bar (icons, labels, padding). Used to inset pushed views that don't inherit the parent's safe area.
    static let mainTabBarChromeHeight: CGFloat = 56
    /// Stroke width for teal "window" frames around hero surfaces.
    static let windowBorderWidth: CGFloat = 2
    /// Hairline width for inline chrome (dividers, list separators, card outlines).
    static let chromeHairline: CGFloat = 1
}

// MARK: - ASCII / glyph decoration (accents only — never book covers)

enum SpinesGlyphs {
    /// Solid square — window close-button glyph.
    static let closeBox = "■"
    /// Phosphor-fade ramp — useful for empty/loading state decoration.
    static let phosphorFade = "█▓▒░"
    /// "─" — single horizontal-rule character; multiply for a divider line.
    static let ruleUnit = "─"

    /// Wraps a short label in mono-style brackets: `[ STATUS ]`.
    static func bracketed(_ s: String) -> String { "[ \(s.uppercased()) ]" }

    /// Builds a horizontal rule of the given character width, e.g. "────────".
    static func rule(width: Int) -> String { String(repeating: ruleUnit, count: max(1, width)) }
}

// MARK: - Card & window styles

/// Default card surface — paper background, subtle teal hairline, soft shadow.
struct ThemeCardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius)
                    .fill(Theme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius)
                    .stroke(Theme.chromeTeal.opacity(0.35), lineWidth: Theme.chromeHairline)
            )
            .shadow(color: Theme.textPrimary.opacity(0.06), radius: 6, x: 0, y: 2)
    }
}

/// Spines "window" — teal (or navy) title bar with optional title text and a
/// close-box glyph; framed body. Use on hero surfaces (book profile sections,
/// modals) — too many on one screen reads as costume.
struct WindowedCardStyle<TitleAccessory: View>: ViewModifier {
    let title: String?
    let chromeColor: Color
    /// Optional trailing view in the title bar (e.g. a tier badge), before the close box.
    let titleAccessory: TitleAccessory

    func body(content: Content) -> some View {
        VStack(spacing: 0) {
            if let title {
                HStack(spacing: 8) {
                    Text(title.uppercased())
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .tracking(1)
                        .foregroundStyle(Theme.phosphorWhite)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 10)
                    titleAccessory
                    Text(SpinesGlyphs.closeBox)
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(Theme.phosphorWhite)
                        .padding(.trailing, 10)
                }
                .padding(.vertical, 6)
                .background(chromeColor)
            }
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.surfaceElevated)
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius)
                .stroke(chromeColor, lineWidth: Theme.windowBorderWidth)
        )
        .shadow(color: Theme.textPrimary.opacity(0.10), radius: 8, x: 0, y: 3)
    }
}

extension View {
    /// Plain Spines card (paper surface, hairline teal border).
    func wellReadCard() -> some View {
        modifier(ThemeCardStyle())
    }

    /// Spines card framed as a Win95-style window with an optional title bar.
    /// - Parameters:
    ///   - title: Title-bar text. Pass `nil` to render just a teal-bordered frame.
    ///   - chrome: Title-bar color. Defaults to teal; use `.chromeNavy` for "system" emphasis.
    func windowedCard(title: String? = nil, chrome: Color = Theme.chromeTeal) -> some View {
        modifier(WindowedCardStyle(title: title, chromeColor: chrome, titleAccessory: EmptyView()))
    }

    /// Windowed card with a trailing view in the title bar (e.g. a tier badge on the review card).
    func windowedCard<Accessory: View>(
        title: String?,
        chrome: Color = Theme.chromeTeal,
        @ViewBuilder titleAccessory: () -> Accessory
    ) -> some View {
        modifier(WindowedCardStyle(title: title, chromeColor: chrome, titleAccessory: titleAccessory()))
    }
}

// MARK: - Main tab bar (custom)

private struct MainTabBarOverlapKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    /// Extra bottom padding for views (e.g. book profile) when the tab bar doesn't inset them. With `.safeAreaInset(tabBar)` on `MainTabView`, use `0`—otherwise you double the gap.
    var mainTabBarOverlapExtraHeight: CGFloat {
        get { self[MainTabBarOverlapKey.self] }
        set { self[MainTabBarOverlapKey.self] = newValue }
    }
}
