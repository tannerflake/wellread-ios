//
//  Toast.swift
//  Spine
//
//  Lightweight success toasts for major user actions (queue, mark-as-read,
//  feed posts, imports, recommendations). Non-blocking, self-dismissing,
//  styled to the terminal/Win95 design system.
//
//  Usage:
//    ToastCenter.shared.show(.addedToQueue(bookTitle: book.title))
//  and attach `.toastHost()` once near the root (see MainTabView).
//

import SwiftUI
import UIKit

// MARK: - Model

/// A single transient toast. Build via the factory helpers below rather than
/// constructing directly, so copy and styling stay consistent.
struct Toast: Identifiable, Equatable {
    enum Style: Equatable {
        case success
        case info
        case error

        /// Leading accent / badge color.
        var chrome: Color {
            switch self {
            case .success: return Theme.chrome
            case .info: return Theme.chromeStrong
            case .error: return Theme.danger
            }
        }

        /// SF Symbol shown in the badge.
        var icon: String {
            switch self {
            case .success: return "checkmark"
            case .info: return "info"
            case .error: return "exclamationmark"
            }
        }
    }

    let id = UUID()
    let style: Style
    /// Short uppercase status word, shown as `QUEUED`.
    let status: String
    /// Human-readable detail line. Optional — some toasts are status-only.
    let message: String?
    /// Seconds on screen before auto-dismiss.
    let duration: TimeInterval

    init(style: Style, status: String, message: String? = nil, duration: TimeInterval = 2.6) {
        self.style = style
        self.status = status
        self.message = message
        self.duration = duration
    }
}

// MARK: - Factories (canonical copy for each action)

extension Toast {
    /// Truncates a title so a long book name never blows out the toast.
    private static func short(_ title: String, max: Int = 40) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > max else { return trimmed }
        return String(trimmed.prefix(max - 1)).trimmingCharacters(in: .whitespaces) + "…"
    }

    static func addedToQueue(bookTitle: String) -> Toast {
        Toast(style: .success, status: "Queued", message: "“\(short(bookTitle))” added to your queue")
    }

    static func startedReading(bookTitle: String) -> Toast {
        Toast(style: .success, status: "Reading", message: "“\(short(bookTitle))” added to Currently Reading")
    }

    static func markedAsRead(bookTitle: String, sharedToFeed: Bool) -> Toast {
        Toast(
            style: .success,
            status: "Marked read",
            message: sharedToFeed
                ? "“\(short(bookTitle))” logged & shared to your feed"
                : "“\(short(bookTitle))” added to your shelf"
        )
    }

    static func reviewUpdated(sharedToFeed: Bool) -> Toast {
        Toast(
            style: .success,
            status: "Saved",
            message: sharedToFeed ? "Review updated & shared to your feed" : "Your review was updated"
        )
    }

    static func postedToFeed() -> Toast {
        Toast(style: .success, status: "Posted", message: "Shared to your feed")
    }

    static func postDeleted() -> Toast {
        Toast(style: .success, status: "Deleted", message: "Post removed from your feed")
    }

    static func commentDeleted() -> Toast {
        Toast(style: .success, status: "Deleted", message: "Your comment was removed")
    }

    static func importedBooks(count: Int) -> Toast {
        let noun = count == 1 ? "book" : "books"
        return Toast(
            style: .success,
            status: "Imported",
            message: count == 0 ? "No new books to import" : "\(count) \(noun) added to your library",
            duration: 3.0
        )
    }

    static func recommendationSent(to name: String) -> Toast {
        Toast(style: .success, status: "Sent", message: "Recommendation sent to \(name)")
    }

    /// A Goodreads row resolved to a book that's already in the library, so the
    /// import flow skipped past it without showing a review card.
    static func duplicateSkipped(bookTitle: String, readDateSaved: Bool) -> Toast {
        Toast(
            style: .info,
            status: "Already in library",
            message: readDateSaved
                ? "“\(short(bookTitle))” is on your shelf — added its read date"
                : "“\(short(bookTitle))” is already in your library — skipped",
            duration: 3.2
        )
    }
}

// MARK: - Center

/// Presents one toast at a time. `@MainActor` so mutations publish on the main
/// thread even when fired from background `Task`s in `AppState`.
@MainActor
final class ToastCenter: ObservableObject {
    static let shared = ToastCenter()

    @Published private(set) var current: Toast?

    private var dismissTask: Task<Void, Never>?

    private init() {}

    /// Show a toast, replacing any that's on screen. Fires a light success haptic.
    func show(_ toast: Toast) {
        dismissTask?.cancel()

        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(toast.style == .error ? .error : .success)

        withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
            current = toast
        }

        dismissTask = Task { [weak self, id = toast.id] in
            try? await Task.sleep(nanoseconds: UInt64(toast.duration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.dismiss(id: id)
        }
    }

    /// Dismiss the current toast. If `id` is given, only dismisses when it still
    /// matches (so a stale timer can't clear a newer toast).
    func dismiss(id: UUID? = nil) {
        if let id, current?.id != id { return }
        dismissTask?.cancel()
        dismissTask = nil
        withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) {
            current = nil
        }
    }
}

// MARK: - View

/// The pill itself. Rendered by `ToastHost`; not used directly.
private struct ToastView: View {
    let toast: Toast
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Badge — chrome square with an SF Symbol, echoing the window close-box glyph.
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(toast.style.chrome)
                Image(systemName: toast.style.icon)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.onChrome)
            }
            .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(SpinesGlyphs.caps(toast.status))
                    .font(.system(size: 12, weight: .bold))
                    .tracking(0.5)
                    .foregroundStyle(toast.style.chrome)
                if let message = toast.message {
                    Text(message)
                        .font(Theme.caption())
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, 12)
        .padding(.trailing, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius)
                .fill(Theme.surfaceElevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius)
                .stroke(toast.style.chrome.opacity(0.45), lineWidth: Theme.chromeHairline)
        )
        .shadow(color: Theme.shadowInk.opacity(0.14), radius: 10, x: 0, y: 4)
        .contentShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius))
        .onTapGesture(perform: onDismiss)
        // Swipe up to dismiss early.
        .gesture(
            DragGesture(minimumDistance: 12)
                .onEnded { value in
                    if value.translation.height < -20 { onDismiss() }
                }
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel([toast.status, toast.message].compactMap { $0 }.joined(separator: ". "))
    }
}

/// Overlays the active toast at the top of its content, below the status bar.
private struct ToastHostModifier: ViewModifier {
    @ObservedObject private var center = ToastCenter.shared

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let toast = center.current {
                    ToastView(toast: toast) { center.dismiss(id: toast.id) }
                        .padding(.horizontal, Theme.horizontalPadding)
                        .padding(.top, 8)
                        .transition(
                            .asymmetric(
                                insertion: .move(edge: .top).combined(with: .opacity),
                                removal: .move(edge: .top).combined(with: .opacity)
                            )
                        )
                        .id(toast.id)
                }
            }
    }
}

extension View {
    /// Attach once near the root so success toasts render above app content.
    func toastHost() -> some View {
        modifier(ToastHostModifier())
    }
}
