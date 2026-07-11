//
//  TierBadge.swift
//  Spine
//
//  Shared tier color palette + the bracketed `[ S TIER ]` badge used wherever a
//  review's tier is displayed (book profile, feed posts).
//

import SwiftUI

/// Tier ladder used by the tier list and review badges. S → F.
let spineTierLabels: [String] = ["S", "A", "B", "C", "D", "F"]

/// Color for a tier letter. `nil` returns the neutral surface color (Unranked).
/// Keep in sync with `TierRowView` swatches.
func spineTierColor(for tier: String?) -> Color {
    guard let tier else { return Theme.surface }
    switch tier {
    case "S": return Color(red: 0.95, green: 0.55, blue: 0.50)   // salmon / light red
    case "A": return Color(red: 0.98, green: 0.72, blue: 0.55)   // light orange / peach
    case "B": return Color(red: 0.98, green: 0.78, blue: 0.45)   // yellow-orange
    case "C": return Color(red: 0.98, green: 0.92, blue: 0.55)   // light yellow
    case "D": return Color(red: 0.65, green: 0.85, blue: 0.60)   // light green
    case "F": return Color(red: 0.55, green: 0.70, blue: 0.92)   // soft blue
    default:  return Theme.surface
    }
}

/// Bracketed mono badge `[ S TIER ]` filled with the tier color. Sized to match the old
/// rating pill so layouts that previously showed `[ 8.8/10 ]` don't shift.
struct TierBadge: View {
    let tier: String
    var size: Size = .regular

    enum Size { case small, regular }

    private var fontSize: CGFloat { size == .small ? 11 : 12 }
    private var horizontalPadding: CGFloat { size == .small ? 7 : 10 }
    private var verticalPadding: CGFloat { size == .small ? 3 : 5 }

    var body: some View {
        Text("[ \(tier) TIER ]")
            .font(.system(size: fontSize, weight: .bold, design: .monospaced))
            .tracking(0.5)
            .foregroundStyle(Color.black.opacity(0.78))
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(spineTierColor(for: tier))
            .clipShape(Capsule())
    }
}
