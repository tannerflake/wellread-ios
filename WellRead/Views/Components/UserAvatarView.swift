//
//  UserAvatarView.swift
//  WellRead
//
//  The one standardized user avatar. Shows the profile photo when the user has
//  one; otherwise a two-letter monogram (first + last initial) on a deterministic
//  cover-palette color, so the same person keeps the same color on every surface.
//

import SwiftUI

enum AvatarMonogram {
    /// First + last initials, uppercased. The display name leads — the monogram
    /// must agree with the label rendered next to it, and displayName is the one
    /// field every surface has. Explicit first/last names only fill gaps.
    static func initials(displayName: String?, firstName: String? = nil, lastName: String? = nil) -> String {
        let words = splitWords(displayName)
        let f = trimmed(firstName)
        let l = trimmed(lastName)
        if words.count >= 2, let first = words.first?.first, let last = words.last?.first {
            return String(first).uppercased() + String(last).uppercased()
        }
        if let word = words.first, let first = word.first {
            // Single-word display name: add the real last initial only when the
            // word IS the first name — otherwise the monogram would contradict
            // the label (e.g. displayName "June" with an unrelated firstName).
            if let last = l.first, f.isEmpty || f.caseInsensitiveCompare(word) == .orderedSame {
                return String(first).uppercased() + String(last).uppercased()
            }
            return String(first).uppercased()
        }
        // No display name at all (wizard, pre-onboarding): explicit fields.
        if let first = f.first, let last = l.first {
            return String(first).uppercased() + String(last).uppercased()
        }
        if let only = (f.isEmpty ? l : f).first { return String(only).uppercased() }
        return "?"
    }

    /// Color seed — the normalized display name. Denormalized surfaces (comments,
    /// blend participants) only carry a display name, so seeding by it is what
    /// keeps one user the same color everywhere; first/last are the fallback for
    /// pre-onboarding surfaces where displayName ("First Last") doesn't exist yet.
    /// (`User.id` is a fresh UUID per Firestore decode and must never seed color.)
    static func seed(displayName: String?, firstName: String? = nil, lastName: String? = nil) -> String {
        let words = splitWords(displayName)
        if !words.isEmpty { return words.joined(separator: " ").lowercased() }
        return [trimmed(firstName), trimmed(lastName)]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .lowercased()
    }

    private static func splitWords(_ name: String?) -> [String] {
        (name ?? "").split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }

    private static func trimmed(_ s: String?) -> String {
        (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Monogram fallback: palette-colored circle with white two-letter initials.
struct InitialsAvatarView: View {
    let displayName: String?
    var firstName: String? = nil
    var lastName: String? = nil
    let size: CGFloat

    var body: some View {
        Circle()
            .fill(Theme.coverPaletteColor(
                for: AvatarMonogram.seed(displayName: displayName, firstName: firstName, lastName: lastName)
            ))
            .overlay(
                Text(AvatarMonogram.initials(displayName: displayName, firstName: firstName, lastName: lastName))
                    .font(.system(size: size * 0.36, weight: .bold))
                    .foregroundStyle(Theme.phosphorWhite)
                    .minimumScaleFactor(0.7)
            )
            .frame(width: size, height: size)
    }
}

/// Photo-or-monogram avatar, circle-clipped at `size`. Rings and shadows stay
/// at the call site (they're surface styling, not part of the avatar).
struct UserAvatarView: View {
    let urlString: String?
    let displayName: String?
    var firstName: String? = nil
    var lastName: String? = nil
    let size: CGFloat

    var body: some View {
        CachedProfileImage(url: url, contentMode: .fill) {
            InitialsAvatarView(displayName: displayName, firstName: firstName, lastName: lastName, size: size)
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var url: URL? {
        guard let urlString, !urlString.isEmpty else { return nil }
        return URL(string: urlString)
    }
}
