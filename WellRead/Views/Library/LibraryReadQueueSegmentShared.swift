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

/// Skinny progress bar + compact caption under the nav title, above the Read/Queue control.
struct LibraryReadingGoalProgressStrip: View {
    let calendarYear: Int
    let booksRead: Int
    let goal: Int
    var copy: LibraryReadingGoalStripCopy = .own

    private var goalTotal: Double {
        max(Double(goal), 1)
    }

    private var caption: String {
        switch copy {
        case .own:
            return "Read \(booksRead) of \(goal) for your \(calendarYear) goal"
        case .other(let first):
            let trimmed = first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !trimmed.isEmpty {
                return "Read \(booksRead) of \(goal) for \(trimmed)'s \(calendarYear) goal"
            }
            return "Read \(booksRead) of \(goal) for their \(calendarYear) goal"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(caption)
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .fixedSize(horizontal: false, vertical: true)
            ProgressView(value: min(Double(booksRead), goalTotal), total: goalTotal)
                .progressViewStyle(.linear)
                .tint(Theme.accent)
                .scaleEffect(x: 1, y: 0.5, anchor: .center)
                .frame(height: 3)
                .accessibilityLabel("\(calendarYear) reading goal")
                .accessibilityValue("\(booksRead) of \(goal) books")
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

/// Springs for Read / Queue control — selection uses a slightly slower, smoother curve than drag chrome (your library only).
enum LibrarySegmentControlAnimation {
    /// Used when the Read/Queue highlight slides between segments (tap).
    static let selection = Animation.spring(response: 0.32, dampingFraction: 0.78, blendDuration: 0)
    static let dragChrome = Animation.spring(response: 0.24, dampingFraction: 0.82, blendDuration: 0)
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
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Theme.surfaceElevated)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(Theme.chromeTeal.opacity(0.55), lineWidth: 1.25)
                        )
                        .shadow(color: Theme.textPrimary.opacity(0.12), radius: 4, y: 1)
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
