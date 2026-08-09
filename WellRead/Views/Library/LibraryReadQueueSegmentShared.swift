//
//  LibraryReadQueueSegmentShared.swift
//  WellRead
//
//  Read / Queue tab type, spring constants, and read-only segment UI shared between
//  your library (`ProfileLibraryView`) and a friend’s (`UserLibraryDetailView`).
//

import SwiftUI

// MARK: - Reading goal strip (calendar year vs goal)

enum LibraryReadingGoalStripCopy {
    /// Signed-in viewer’s own library.
    case own
    /// Another member’s library (`displayFirstName` used for “Name’s goal”, else “their”).
    case other(displayFirstName: String?)
}

/// Goal progress bar + compact caption under the nav title, above the Read/Queue control.
struct LibraryReadingGoalProgressStrip: View {
    let calendarYear: Int
    let booksRead: Int
    let goal: Int
    var copy: LibraryReadingGoalStripCopy = .own

    private var goalTotal: Double {
        max(Double(goal), 1)
    }

    /// Pace vs. a straight-line schedule through the calendar year.
    private enum GoalPace {
        case goalMet
        case ahead(Int)
        case onTrack
        case behind(Int)
    }

    /// On track means within one full book of the straight-line pace; ahead/behind
    /// only count whole books so the label never overstates a fractional gap.
    private var pace: GoalPace {
        if booksRead >= goal { return .goalMet }
        let cal = Calendar.current
        let now = Date()
        let dayOfYear = cal.ordinality(of: .day, in: .year, for: now) ?? 1
        let daysInYear = cal.range(of: .day, in: .year, for: now)?.count ?? 365
        let expected = Double(goal) * Double(dayOfYear) / Double(daysInYear)
        let diff = Double(booksRead) - expected
        if diff >= 1 { return .ahead(Int(diff)) }
        if diff <= -1 { return .behind(Int(-diff)) }
        return .onTrack
    }

    private var paceText: String {
        switch pace {
        case .goalMet:
            return "goal met!"
        case .ahead(let n):
            return "\(n) book\(n == 1 ? "" : "s") ahead"
        case .onTrack:
            return "on track"
        case .behind(let n):
            return "\(n) book\(n == 1 ? "" : "s") behind"
        }
    }

    /// Pace commentary (and its color) is only for your own goal — on someone
    /// else's library we just report progress, never how far behind they are.
    private var showsPace: Bool {
        if case .own = copy { return true }
        return false
    }

    private var barFill: LinearGradient {
        guard showsPace else { return Theme.accentGloss }
        switch pace {
        case .goalMet, .ahead: return Theme.accentGloss
        case .onTrack: return Theme.gloss(Theme.textSecondary)
        case .behind: return Theme.gloss(Theme.danger)
        }
    }

    /// The parenthetical only celebrates: goal met or ahead. Behind/on-track
    /// stay silent (the bar color still tells the story).
    private var showsPaceText: Bool {
        guard showsPace else { return false }
        switch pace {
        case .goalMet, .ahead: return true
        case .onTrack, .behind: return false
        }
    }

    private var caption: String {
        showsPaceText
            ? "Read \(booksRead)/\(goal) for \(calendarYear) (\(paceText))"
            : "Read \(booksRead)/\(goal) for \(calendarYear)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(caption)
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .fixedSize(horizontal: false, vertical: true)
            GeometryReader { geo in
                let fraction = min(Double(booksRead), goalTotal) / goalTotal
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.textSecondary.opacity(0.18))
                    if fraction > 0 {
                        Capsule()
                            .fill(barFill)
                            .frame(width: max(geo.size.height, geo.size.width * fraction))
                    }
                }
            }
            .frame(height: 10)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(calendarYear) reading goal")
            .accessibilityValue(showsPaceText ? "\(booksRead) of \(goal) books. \(paceText)" : "\(booksRead) of \(goal) books.")
        }
        .padding(.top, 4)
        .padding(.bottom, 6)
    }
}

/// Read vs Queue — used by your library and friend library screens.
enum LibraryReadQueueTab: String, CaseIterable {
    case read = "Read"
    case wantToRead = "Queue"
}

/// Springs for Read / Queue control — selection matches the main tab bar's lens spring so
/// every sliding selector in the app moves the same way; drag chrome stays a touch quicker.
enum LibrarySegmentControlAnimation {
    /// Used when the Read/Queue lens slides between segments (tap).
    static let selection = Animation.snappy(duration: 0.3, extraBounce: 0.12)
    static let dragChrome = Animation.spring(response: 0.24, dampingFraction: 0.82, blendDuration: 0)
}

/// Sliding indicator for the Read/Queue control — the same liquid-glass lens as the main
/// tab bar on iOS 26+, with the old elevated-pill look as the pre-26 fallback.
struct LibrarySegmentGlassLens: View {
    var cornerRadius: CGFloat = 8

    var body: some View {
        if #available(iOS 26.0, *) {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(.clear)
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius))
        } else {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(Theme.surfaceElevated)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(Theme.chrome.opacity(0.55), lineWidth: 1.25)
                )
                .shadow(color: Theme.shadowInk.opacity(0.12), radius: 4, y: 1)
        }
    }
}

/// Same pill styling as your library’s Read/Queue control, without drag-and-drop chrome.
struct LibraryReadQueueSegmentControlReadOnly: View {
    @Binding var segment: LibraryReadQueueTab

    var body: some View {
        HStack(spacing: 0) {
            readPill
            queuePill
        }
        .padding(3)
        .background {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 10).fill(Theme.surface)
                GeometryReader { geo in
                    let half = geo.size.width / 2
                    let pillW = max(0, half - 6)
                    LibrarySegmentGlassLens()
                        .frame(width: pillW)
                        .offset(x: 3 + (segment == .read ? 0 : half))
                        .animation(LibrarySegmentControlAnimation.selection, value: segment)
                }
                .allowsHitTesting(false)
            }
        }
        .sensoryFeedback(.selection, trigger: segment)
    }

    private var readPill: some View {
        let isSelected = segment == .read
        return Button {
            segment = .read
        } label: {
            Text("Read")
                .font(Theme.callout().weight(isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Theme.textPrimary : Theme.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .padding(.vertical, 4)
        .padding(.leading, 2)
        .padding(.trailing, 2)
    }

    private var queuePill: some View {
        let isSelected = segment == .wantToRead
        return Button {
            segment = .wantToRead
        } label: {
            Text("Queue")
                .font(Theme.callout().weight(isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Theme.textPrimary : Theme.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .padding(.vertical, 4)
        .padding(.trailing, 2)
    }
}
