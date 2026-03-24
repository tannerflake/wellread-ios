//
//  QueueBookDragCover.swift
//  WellRead
//
//  UIKit drag on top of SwiftUI `BookCoverView` so queue cells match normal covers (including title placeholders)
//  and we still get `UIDragInteraction` session callbacks for Read/Queue tab chrome.
//

import SwiftUI
import UIKit
import UniformTypeIdentifiers

// MARK: - Library scroll during drag (top edge only)

/// Drives `UIScrollView.contentOffset` while a `UIDragSession` is active.
///
/// **Downward** auto-scroll is intentionally **disabled**. `UIDragSession` + nested SwiftUI scroll views repeatedly
/// reported the drag in the “bottom edge” while scrolling (worse when already scrolled far down the list), which
/// caused runaway `contentOffset` changes. **Upward** scroll at the top edge is reliable and keeps long lists usable
/// when dragging near the top. To scroll down while dragging, scroll with another finger or move the drag away from
/// the bottom and use the list normally.
private final class DragAutoScrollDriver: NSObject {
    weak var scrollView: UIScrollView?
    weak var session: UIDragSession?

    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval?
    private var sessionStartTimestamp: CFTimeInterval?
    private var framesSinceStart: Int = 0

    /// Fixed scroll speed (points / second) while the finger is in an edge band — moderate, not “max at rim”.
    private let scrollSpeed: CGFloat = 420
    /// Edge inset from top/bottom of the scroll view used for auto-scroll (capped so bands never overlap).
    private let edgeFraction: CGFloat = 0.10
    private let edgeMinPoints: CGFloat = 44
    private let edgeMaxPoints: CGFloat = 72
    /// Brief delay after lift so the first noisy location frames don’t scroll.
    private let armDelaySeconds: CFTimeInterval = 0.12
    private let warmupFrames: Int = 1

    func start() {
        guard displayLink == nil else { return }
        lastTimestamp = nil
        sessionStartTimestamp = nil
        framesSinceStart = 0
        let link = CADisplayLink(target: self, selector: #selector(step))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
        lastTimestamp = nil
        sessionStartTimestamp = nil
        framesSinceStart = 0
    }

    @objc private func step(_ link: CADisplayLink) {
        guard let session, let sv = scrollView else { return }
        let now = link.timestamp
        if sessionStartTimestamp == nil {
            sessionStartTimestamp = now
        }
        framesSinceStart += 1
        guard framesSinceStart > warmupFrames else { return }

        let dt: CGFloat
        if let last = lastTimestamp {
            dt = CGFloat(now - last)
        } else {
            dt = 0
        }
        lastTimestamp = now
        guard dt > 0, dt < 0.25 else { return }

        let start = sessionStartTimestamp ?? now
        guard now - start >= armDelaySeconds else { return }

        sv.layoutIfNeeded()

        let h = max(1, sv.bounds.height)
        /// Scroll-view space keeps **negative** y when the drag is above the visible list (under nav / safe area).
        let fingerY = session.location(in: sv).y

        var rawZone = min(edgeMaxPoints, max(edgeMinPoints, h * edgeFraction))
        rawZone = min(rawZone, max(24, (h - 40) / 2))

        let inset = sv.adjustedContentInset
        let minY = -inset.top
        let maxY = max(minY, sv.contentSize.height - h + inset.bottom)
        let y0 = sv.contentOffset.y

        let inTop = fingerY < rawZone

        var delta: CGFloat = 0
        if inTop, y0 > minY + 0.5 {
            delta = -scrollSpeed * dt
        }

        guard abs(delta) > 0.2 else { return }

        var offset = sv.contentOffset
        offset.y += delta
        offset.y = min(maxY, max(minY, offset.y))
        sv.contentOffset = offset
    }
}

/// Pins the enclosing `UIScrollView` so drag auto-scroll can adjust `contentOffset`.
struct LibraryScrollViewAnchor: UIViewRepresentable {
    @ObservedObject var dragCoordinator: QueueBookDragCoordinator

    func makeUIView(context: Context) -> ScrollViewAnchorUIView {
        let v = ScrollViewAnchorUIView()
        v.onScrollViewFound = { [weak dragCoordinator] sv in
            dragCoordinator?.registerLibraryScrollView(sv)
        }
        return v
    }

    func updateUIView(_ uiView: ScrollViewAnchorUIView, context: Context) {
        uiView.onScrollViewFound = { [weak dragCoordinator] sv in
            dragCoordinator?.registerLibraryScrollView(sv)
        }
    }
}

final class ScrollViewAnchorUIView: UIView {
    var onScrollViewFound: ((UIScrollView) -> Void)?
    private weak var lastSent: UIScrollView?

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let sv = findEnclosingScrollView() else { return }
        if lastSent !== sv {
            lastSent = sv
            onScrollViewFound?(sv)
        }
    }

    /// SwiftUI can nest several `UIScrollView`s (lazy containers, etc.). The **first** one up the tree is often a
    /// small inner scroller — auto-scroll then thinks the finger is always in the “bottom edge” and death-scrolls.
    /// Prefer the **largest** scroll view among ancestors (the main library `ScrollView`).
    private func findEnclosingScrollView() -> UIScrollView? {
        var v: UIView? = superview
        var best: UIScrollView?
        var bestArea: CGFloat = 0
        while let cur = v {
            if let sc = cur as? UIScrollView {
                let area = sc.bounds.width * sc.bounds.height
                if area > bestArea {
                    bestArea = area
                    best = sc
                }
            }
            v = cur.superview
        }
        return best
    }
}

@MainActor
final class QueueBookDragCoordinator: ObservableObject {
    @Published private(set) var isDraggingQueueBook = false
    @Published private(set) var isDraggingReadBook = false

    private let autoScrollDriver = DragAutoScrollDriver()

    func registerLibraryScrollView(_ scrollView: UIScrollView?) {
        autoScrollDriver.scrollView = scrollView
    }

    func beginDragSession(_ session: UIDragSession) {
        autoScrollDriver.session = session
        autoScrollDriver.start()
    }

    func endDragSession() {
        autoScrollDriver.session = nil
        autoScrollDriver.stop()
        LibraryDragHaptics.resetDropHoverThrottle()
    }

    func setDraggingQueueBook(_ value: Bool) {
        guard isDraggingQueueBook != value else { return }
        isDraggingQueueBook = value
    }

    func setDraggingReadBook(_ value: Bool) {
        guard isDraggingReadBook != value else { return }
        isDraggingReadBook = value
    }
}

/// Hosts `BookCoverView` (same visuals as everywhere else) + `UIDragInteraction` for `TierDragItem` payload.
struct QueueBookDragCover: UIViewControllerRepresentable {
    let book: Book
    let userBookId: UUID
    let bookSize: CGFloat
    var onTap: (() -> Void)?
    @ObservedObject var dragCoordinator: QueueBookDragCoordinator

    func makeCoordinator() -> Coordinator {
        Coordinator(
            userBookId: userBookId,
            dragCoordinator: dragCoordinator,
            onTap: onTap
        )
    }

    func makeUIViewController(context: Context) -> UIHostingController<BookCoverView> {
        let root = BookCoverView(book: book, size: bookSize, onTap: onTap)
        let host = UIHostingController(rootView: root)
        host.view.backgroundColor = .clear
        context.coordinator.host = host
        context.coordinator.userBookId = userBookId
        context.coordinator.onTap = onTap

        let drag = UIDragInteraction(delegate: context.coordinator)
        host.view.addInteraction(drag)

        return host
    }

    func updateUIViewController(_ host: UIHostingController<BookCoverView>, context: Context) {
        host.rootView = BookCoverView(book: book, size: bookSize, onTap: onTap)
        context.coordinator.host = host
        context.coordinator.userBookId = userBookId
        context.coordinator.onTap = onTap
    }

    final class Coordinator: NSObject, UIDragInteractionDelegate {
        var userBookId: UUID
        let dragCoordinator: QueueBookDragCoordinator
        var onTap: (() -> Void)?
        weak var host: UIHostingController<BookCoverView>?

        init(
            userBookId: UUID,
            dragCoordinator: QueueBookDragCoordinator,
            onTap: (() -> Void)?
        ) {
            self.userBookId = userBookId
            self.dragCoordinator = dragCoordinator
            self.onTap = onTap
        }

        // MARK: UIDragInteractionDelegate

        func dragInteraction(_ interaction: UIDragInteraction, sessionWillBegin session: UIDragSession) {
            Task { @MainActor in
                dragCoordinator.setDraggingQueueBook(true)
                dragCoordinator.beginDragSession(session)
            }
        }

        func dragInteraction(_ interaction: UIDragInteraction, session: UIDragSession, didEndWith operation: UIDropOperation) {
            Task { @MainActor in
                dragCoordinator.setDraggingQueueBook(false)
                dragCoordinator.endDragSession()
            }
        }

        func dragInteraction(_ interaction: UIDragInteraction, itemsForBeginning session: UIDragSession) -> [UIDragItem] {
            let provider = NSItemProvider()
            let idString = userBookId.uuidString
            provider.registerDataRepresentation(for: UTType.plainText, visibility: .all) { completion in
                completion(Data(idString.utf8), nil)
                return nil
            }
            let item = UIDragItem(itemProvider: provider)
            item.localObject = idString
            return [item]
        }

        func dragInteraction(_ interaction: UIDragInteraction, previewForLifting item: UIDragItem, session: UIDragSession) -> UITargetedDragPreview? {
            guard let view = host?.view else { return nil }
            let params = UIDragPreviewParameters()
            params.visiblePath = UIBezierPath(roundedRect: view.bounds, cornerRadius: 6)
            return UITargetedDragPreview(view: view, parameters: params)
        }
    }
}

/// Same as `QueueBookDragCover` but drives **Read** tab chrome (red −) while dragging a tier-list read book.
struct ReadListBookDragCover: UIViewControllerRepresentable {
    let book: Book
    let userBookId: UUID
    let bookSize: CGFloat
    var onTap: (() -> Void)?
    @ObservedObject var dragCoordinator: QueueBookDragCoordinator

    func makeCoordinator() -> ReadCoordinator {
        ReadCoordinator(
            userBookId: userBookId,
            dragCoordinator: dragCoordinator,
            onTap: onTap
        )
    }

    func makeUIViewController(context: Context) -> UIHostingController<BookCoverView> {
        let root = BookCoverView(book: book, size: bookSize, onTap: onTap)
        let host = UIHostingController(rootView: root)
        host.view.backgroundColor = .clear
        context.coordinator.host = host
        context.coordinator.userBookId = userBookId
        context.coordinator.onTap = onTap

        let drag = UIDragInteraction(delegate: context.coordinator)
        host.view.addInteraction(drag)

        return host
    }

    func updateUIViewController(_ host: UIHostingController<BookCoverView>, context: Context) {
        host.rootView = BookCoverView(book: book, size: bookSize, onTap: onTap)
        context.coordinator.host = host
        context.coordinator.userBookId = userBookId
        context.coordinator.onTap = onTap
    }

    final class ReadCoordinator: NSObject, UIDragInteractionDelegate {
        var userBookId: UUID
        let dragCoordinator: QueueBookDragCoordinator
        var onTap: (() -> Void)?
        weak var host: UIHostingController<BookCoverView>?

        init(
            userBookId: UUID,
            dragCoordinator: QueueBookDragCoordinator,
            onTap: (() -> Void)?
        ) {
            self.userBookId = userBookId
            self.dragCoordinator = dragCoordinator
            self.onTap = onTap
        }

        func dragInteraction(_ interaction: UIDragInteraction, sessionWillBegin session: UIDragSession) {
            Task { @MainActor in
                LibraryDragHaptics.dragLiftBegan()
                dragCoordinator.setDraggingReadBook(true)
                dragCoordinator.beginDragSession(session)
            }
        }

        func dragInteraction(_ interaction: UIDragInteraction, session: UIDragSession, didEndWith operation: UIDropOperation) {
            Task { @MainActor in
                dragCoordinator.setDraggingReadBook(false)
                dragCoordinator.endDragSession()
            }
        }

        func dragInteraction(_ interaction: UIDragInteraction, itemsForBeginning session: UIDragSession) -> [UIDragItem] {
            let provider = NSItemProvider()
            let idString = userBookId.uuidString
            provider.registerDataRepresentation(for: UTType.plainText, visibility: .all) { completion in
                completion(Data(idString.utf8), nil)
                return nil
            }
            let item = UIDragItem(itemProvider: provider)
            item.localObject = idString
            return [item]
        }

        func dragInteraction(_ interaction: UIDragInteraction, previewForLifting item: UIDragItem, session: UIDragSession) -> UITargetedDragPreview? {
            guard let view = host?.view else { return nil }
            let params = UIDragPreviewParameters()
            params.visiblePath = UIBezierPath(roundedRect: view.bounds, cornerRadius: 6)
            return UITargetedDragPreview(view: view, parameters: params)
        }
    }
}
