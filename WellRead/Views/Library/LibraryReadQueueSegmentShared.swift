//
//  LibraryReadQueueSegmentShared.swift
//  WellRead
//
//  Read / Queue tab type, spring constants, and read-only segment UI shared between
//  your library (`ProfileLibraryView`) and a friend’s (`UserLibraryDetailView`).
//

import SwiftUI

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
                RoundedRectangle(cornerRadius: 10).fill(Color(white: 0.16))
                GeometryReader { geo in
                    let half = geo.size.width / 2
                    let pillW = max(0, half - 6)
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(white: 0.24))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(Theme.textTertiary.opacity(0.55), lineWidth: 1.25)
                        )
                        .shadow(color: Color.black.opacity(0.45), radius: 4, y: 1)
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
                .padding(.vertical, 11)
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
                .padding(.vertical, 11)
                .padding(.horizontal, 8)
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .padding(.vertical, 4)
        .padding(.trailing, 2)
    }
}
