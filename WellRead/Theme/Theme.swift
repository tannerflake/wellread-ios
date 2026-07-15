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
    // MARK: - Dark-mode plumbing
    //
    // Every palette color is a UIKit dynamic color: it resolves per trait
    // collection, so the whole `Theme.*` API adapts to light/dark automatically
    // (driven by `preferredColorScheme` at the app root — see AppearancePreference).
    // Dark mode inverts the paper metaphor: terminal paper becomes the ink,
    // CRT black becomes the page. Chrome hues are lifted for contrast on dark.

    /// Trait-aware color pair — light appearance / dark appearance.
    private static func dynamic(light: Color, dark: Color) -> Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
    }

    // MARK: - Colors — Foundation

    /// Terminal paper — primary background. Light #E8E4DB / dark warm CRT-black #14120F.
    static let background = dynamic(
        light: Color(red: 0.910, green: 0.894, blue: 0.859),
        dark: Color(red: 20/255, green: 18/255, blue: 15/255)
    )
    /// CRT black ink — flips to warm paper-white in dark. #0A0A0A / #ECE8DE.
    static let textPrimary = dynamic(
        light: Color(red: 0.039, green: 0.039, blue: 0.039),
        dark: Color(red: 236/255, green: 232/255, blue: 222/255)
    )
    /// Phosphor white — for inverted surfaces (teal/navy/black chrome). Static:
    /// it always sits on saturated chrome, never on the page. (#FFFFFF)
    static let phosphorWhite = Color.white

    // Surfaces stay close to background; differentiation comes from borders and
    // type, not big fill jumps. In dark they step *lighter* than the background.
    /// Cards / sheets. Light #DCD7CC / dark #1F1D19.
    static let surface = dynamic(
        light: Color(red: 0.863, green: 0.843, blue: 0.800),
        dark: Color(red: 31/255, green: 29/255, blue: 25/255)
    )
    /// Elevated cards. Light #F2EFE8 (paper-on-paper) / dark #2A2723.
    static let surfaceElevated = dynamic(
        light: Color(red: 0.949, green: 0.937, blue: 0.910),
        dark: Color(red: 42/255, green: 39/255, blue: 35/255)
    )

    // Text hierarchy — fades of the ink toward the page.
    static let textSecondary = dynamic(
        light: Color(red: 0.34, green: 0.32, blue: 0.30),
        dark: Color(red: 181/255, green: 175/255, blue: 163/255)
    )
    static let textTertiary = dynamic(
        light: Color(red: 0.55, green: 0.53, blue: 0.50),
        dark: Color(red: 139/255, green: 133/255, blue: 122/255)
    )

    /// Shadow ink — always dark in both modes (never use `textPrimary` for
    /// shadows: it flips light in dark mode and shadows become white glows).
    static let shadowInk = dynamic(
        light: Color(red: 0.039, green: 0.039, blue: 0.039),
        dark: Color.black
    )

    // MARK: - Colors — Chrome (load-bearing UI frames)

    /// Win95 desktop teal — window frames, dividers, badges, primary border.
    /// Light #1B7B7E / dark lifted phosphor teal #3FA9AD.
    static let chromeTeal = dynamic(
        light: Color(red: 0.106, green: 0.482, blue: 0.494),
        dark: Color(red: 63/255, green: 169/255, blue: 173/255)
    )
    /// Classic title-bar navy — OS-shell title bars / emphatic chrome.
    /// Light #000080 / dark lifted indigo #5C5CE2 (pure navy vanishes on near-black).
    static let chromeNavy = dynamic(
        light: Color(red: 0.000, green: 0.000, blue: 0.502),
        dark: Color(red: 92/255, green: 92/255, blue: 226/255)
    )
    /// Win95 system gray — retro button surfaces, used sparingly.
    /// Light #C0C0C0 / dark #55524E.
    static let chromeGray = dynamic(
        light: Color(red: 0.753, green: 0.753, blue: 0.753),
        dark: Color(red: 85/255, green: 82/255, blue: 78/255)
    )

    // MARK: - Colors — One-shot accents (used rarely; they hit hard)

    /// "BANG BANG BANG" magenta — reserve for truly singular punches.
    /// Light #E8408F / dark #F2609F.
    static let magentaPunch = dynamic(
        light: Color(red: 0.910, green: 0.251, blue: 0.561),
        dark: Color(red: 242/255, green: 96/255, blue: 159/255)
    )
    /// ASICS blue — primary CTA / "the real brand color moment".
    /// Light #0F4FB8 / dark #3D74E6 (holds ≥4:1 both as white-text fill and as
    /// text on the dark page).
    static let asicsBlue = dynamic(
        light: Color(red: 0.059, green: 0.310, blue: 0.722),
        dark: Color(red: 61/255, green: 116/255, blue: 230/255)
    )

    // MARK: - Colors — Semantic aliases (stable API for existing views)

    /// Brand chrome (was deep indigo) — now teal.
    static let primary = chromeTeal
    /// Primary CTA color (Read button, rating pills) (was soft green) — now ASICS blue.
    static let accent = asicsBlue

    /// Queue button background — pale ASICS-blue tint. Dark: deep navy-blue tint #1D2B47.
    static let queuePowderBlue = dynamic(
        light: Color(red: 0.815, green: 0.870, blue: 0.965),
        dark: Color(red: 29/255, green: 43/255, blue: 71/255)
    )
    /// Text on `queuePowderBlue` — full-strength blue, lifted light blue in dark. #8FB2F2.
    static let queuePowderBlueLabel = dynamic(
        light: Color(red: 0.059, green: 0.310, blue: 0.722),
        dark: Color(red: 143/255, green: 178/255, blue: 242/255)
    )

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
    // One voice: SF Pro everywhere — weight and tracking carry the hierarchy,
    // covers and tier colors carry the personality. The old terminal-mono +
    // literary-serif pairing is retired; the only exceptions live outside the
    // theme (serif on generated book-cover placeholders, where it imitates a
    // printed jacket, and mono in debug diagnostics for raw tokens).

    private static func sans(_ size: CGFloat, weight: Font.Weight) -> Font {
        .system(size: size, weight: weight)
    }

    static func largeTitle() -> Font { sans(28, weight: .bold) }
    static func title() -> Font { sans(22, weight: .bold) }
    static func title2() -> Font { sans(18, weight: .semibold) }
    /// Feed section label ("Your friends", etc.).
    static func feedSectionHeader() -> Font { sans(17, weight: .semibold) }
    /// "Feed" title above the post list.
    static func feedBlockTitle() -> Font { sans(22, weight: .semibold) }
    static func headline() -> Font { sans(16, weight: .semibold) }
    /// Book profile section titles (Summary, Notable quote) — ~2× headline.
    static func profileSectionHeader() -> Font { sans(32, weight: .bold) }
    /// Long-form prose (book summaries, quotes, review captions, comments).
    static func body() -> Font { sans(17, weight: .regular) }
    static func callout() -> Font { sans(14, weight: .regular) }
    static func caption() -> Font { sans(12, weight: .regular) }

    /// Tracking applied to display type (wordmark headers, overline labels).
    static let displayTracking: CGFloat = 0.5
    /// Line spacing for body prose.
    static let bodyLineSpacing: CGFloat = 3

    /// Feed post and comment timestamps are always relative — never an exact date:
    /// seconds under a minute, minutes until 1 hr, hours until 24 hr, days until
    /// 1 week, then weeks, then months.
    static func feedRelativeTimestamp(_ date: Date, now: Date = Date()) -> String {
        commentRelativeTimestamp(date, now: now)
    }

    static func commentRelativeTimestamp(_ date: Date, now: Date = Date()) -> String {
        let interval = now.timeIntervalSince(date)
        if interval < 60 {
            let s = Int(max(0, interval))
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
        let months = max(2, days / 30)
        return "\(months) months"
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

    // MARK: - Gloss (liquid-glass depth — Apple TV icon treatment for filled controls)

    /// Mixes `color` toward `mix` by `fraction` (0–1). Resolves per trait
    /// collection so dynamic (light/dark) inputs blend correctly in both modes.
    static func blend(_ color: Color, toward mix: Color, by fraction: CGFloat) -> Color {
        blend(color, toward: mix, light: fraction, dark: fraction)
    }

    /// Trait-aware blend with separate light/dark fractions — used for surface
    /// sheens, where a white blend that reads as subtle on paper would blow out
    /// a dark surface.
    static func blend(_ color: Color, toward mix: Color, light lightFraction: CGFloat, dark darkFraction: CGFloat) -> Color {
        Color(UIColor { traits in
            let f = min(1, max(0, traits.userInterfaceStyle == .dark ? darkFraction : lightFraction))
            let c1 = UIColor(color).resolvedColor(with: traits)
            let c2 = UIColor(mix).resolvedColor(with: traits)
            var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
            var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
            c1.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
            c2.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
            return UIColor(
                red: r1 + (r2 - r1) * f,
                green: g1 + (g2 - g1) * f,
                blue: b1 + (b2 - b1) * f,
                alpha: a1 + (a2 - a1) * f
            )
        })
    }

    /// Top-lit gradient over a tint — drop-in wherever a flat `fill(tint)` used to be.
    static func gloss(_ tint: Color) -> LinearGradient {
        LinearGradient(
            stops: [
                .init(color: blend(tint, toward: .white, by: 0.18), location: 0.0),
                .init(color: tint, location: 0.55),
                .init(color: blend(tint, toward: .black, by: 0.12), location: 1.0)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// Glossy accent — drop-in replacement for flat `Theme.accent` fills.
    static var accentGloss: LinearGradient { gloss(accent) }

    // MARK: - Layout
    static let cardCornerRadius: CGFloat = 14
    static let cardPadding: CGFloat = 16
    static let gridSpacing: CGFloat = 12
    static let horizontalPadding: CGFloat = 20
    /// Approximate height of `MainTabView`'s custom tab bar (icons, labels, padding). Used to inset pushed views that don't inherit the parent's safe area.
    static let mainTabBarChromeHeight: CGFloat = 50
    /// Stroke width for teal "window" frames around hero surfaces.
    static let windowBorderWidth: CGFloat = 2
    /// Hairline width for inline chrome (dividers, list separators, card outlines).
    static let chromeHairline: CGFloat = 1
}

// MARK: - Appearance preference (Light / Dark / System)

/// User-selected appearance, persisted via `@AppStorage(AppearancePreference.storageKey)`
/// and applied at the app root with `.preferredColorScheme`. Defaults to `.light`
/// while dark mode is being vetted; the plan is to flip the default to `.system`.
enum AppearancePreference: String, CaseIterable, Identifiable {
    case light
    case dark
    case system

    static let storageKey = "appearancePreference"
    static let defaultValue: AppearancePreference = .light

    var id: String { rawValue }

    var label: String {
        switch self {
        case .light: return "Light"
        case .dark: return "Dark"
        case .system: return "System"
        }
    }

    var iconName: String {
        switch self {
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        case .system: return "circle.lefthalf.filled"
        }
    }

    /// `nil` means "follow the system setting".
    var colorScheme: ColorScheme? {
        switch self {
        case .light: return .light
        case .dark: return .dark
        case .system: return nil
        }
    }
}

// MARK: - Glyph helpers (terminal ASCII decoration retired — use BrandRule for dividers)

enum SpinesGlyphs {
    /// Solid square — window close-button glyph (Win95 windowed-card chrome only).
    static let closeBox = "■"

    /// Uppercases a short status/overline label, e.g. `STATUS`.
    static func caps(_ s: String) -> String { s.uppercased() }
}

/// Short brand accent rule under wordmark headers — replaces the old ASCII "────" glyph run.
struct BrandRule: View {
    var width: CGFloat = 44
    var color: Color = Theme.chromeTeal

    var body: some View {
        Capsule()
            .fill(color)
            .frame(width: width, height: 3)
    }
}

// MARK: - Gloss modifiers & press feedback

/// Full liquid-gloss treatment for hero CTAs: top-lit gradient fill, inner top
/// highlight, and a soft tinted drop shadow — Apple TV icon depth.
struct GlossyProminentStyle: ViewModifier {
    let tint: Color
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(Theme.gloss(tint), in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Theme.phosphorWhite.opacity(0.5), Theme.phosphorWhite.opacity(0.05)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: tint.opacity(0.35), radius: 9, x: 0, y: 4)
    }
}

extension View {
    /// Hero-CTA gloss: gradient fill + inner highlight + tinted shadow.
    func glossyProminent(_ tint: Color = Theme.accent, cornerRadius: CGFloat = Theme.cardCornerRadius) -> some View {
        modifier(GlossyProminentStyle(tint: tint, cornerRadius: cornerRadius))
    }
}

/// Press feedback for tappable chrome: quick scale-down on a soft spring — the
/// "buttons feel physical" half of the liquid-glass direction.
struct SpringPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == SpringPressButtonStyle {
    static var springPress: SpringPressButtonStyle { SpringPressButtonStyle() }
}

// MARK: - Card & window styles

/// Default card surface — paper background with a faint top sheen, subtle teal
/// hairline, soft shadow.
struct ThemeCardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius)
                    .fill(
                        LinearGradient(
                            colors: [Theme.blend(Theme.surface, toward: .white, light: 0.25, dark: 0.06), Theme.surface],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius)
                    .stroke(Theme.chromeTeal.opacity(0.35), lineWidth: Theme.chromeHairline)
            )
            .shadow(color: Theme.shadowInk.opacity(0.10), radius: 10, x: 0, y: 4)
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
                        .font(.system(size: 12, weight: .bold))
                        .tracking(1)
                        .foregroundStyle(Theme.phosphorWhite)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 10)
                    titleAccessory
                    Text(SpinesGlyphs.closeBox)
                        .font(.system(size: 12, weight: .bold))
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
        .shadow(color: Theme.shadowInk.opacity(0.10), radius: 8, x: 0, y: 3)
    }
}

/// Hinge-style profile section: airy rounded card with a small overline label
/// inside the card (no title bar), generous padding, and a soft shadow. Used for
/// book-profile sections; modals keep the Win95 `windowedCard` treatment.
struct HingeSectionCardStyle<TitleLeadingAccessory: View, TitleAccessory: View>: ViewModifier {
    let title: String?
    let accentColor: Color
    /// Optional view tucked right after the overline label (e.g. an edit pencil).
    let titleLeadingAccessory: TitleLeadingAccessory
    /// Optional trailing view beside the overline label (e.g. a tier badge).
    let titleAccessory: TitleAccessory

    func body(content: Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if let title {
                HStack(spacing: 8) {
                    Text(title.uppercased())
                        .font(.system(size: 11, weight: .bold))
                        .tracking(1.8)
                        .foregroundStyle(accentColor)
                    titleLeadingAccessory
                    Spacer(minLength: 0)
                    titleAccessory
                }
            }
            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(
                    LinearGradient(
                        colors: [Theme.blend(Theme.surfaceElevated, toward: .white, light: 0.5, dark: 0.07), Theme.surfaceElevated],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(accentColor.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: Theme.shadowInk.opacity(0.10), radius: 14, x: 0, y: 6)
    }
}

extension View {
    /// Plain Spines card (paper surface, hairline teal border).
    func wellReadCard() -> some View {
        modifier(ThemeCardStyle())
    }

    /// Hinge-style profile section card with an overline label.
    func hingeSectionCard(title: String?, accent: Color = Theme.chromeTeal) -> some View {
        modifier(HingeSectionCardStyle(title: title, accentColor: accent, titleLeadingAccessory: EmptyView(), titleAccessory: EmptyView()))
    }

    /// Hinge-style section card with a trailing view beside the label (e.g. a tier badge).
    func hingeSectionCard<Accessory: View>(
        title: String?,
        accent: Color = Theme.chromeTeal,
        @ViewBuilder titleAccessory: () -> Accessory
    ) -> some View {
        modifier(HingeSectionCardStyle(title: title, accentColor: accent, titleLeadingAccessory: EmptyView(), titleAccessory: titleAccessory()))
    }

    /// Hinge-style section card with a view tucked after the label (e.g. an edit
    /// pencil) plus the trailing accessory.
    func hingeSectionCard<Leading: View, Accessory: View>(
        title: String?,
        accent: Color = Theme.chromeTeal,
        @ViewBuilder titleLeading: () -> Leading,
        @ViewBuilder titleAccessory: () -> Accessory
    ) -> some View {
        modifier(HingeSectionCardStyle(title: title, accentColor: accent, titleLeadingAccessory: titleLeading(), titleAccessory: titleAccessory()))
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
