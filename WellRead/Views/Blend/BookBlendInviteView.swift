//
//  BookBlendInviteView.swift
//  Spine
//
//  Book Blend entry flow: the profile button, and the full-screen landing that
//  routes a pair doc to the right moment — invite (accept / decline), the
//  "blending" generation interlude, waiting-on-them, or straight into the story.
//

import SwiftUI
import FirebaseFirestore

// MARK: - Profile entry button

enum BookBlendEntryState: Equatable {
    /// No blend yet (or a declined one) — show "Request a Book Blend".
    case none
    case requestedByMe
    case invitedMe
    case ready
}

/// Gradient capsule on another member's profile — the single doorway into a blend.
struct BookBlendEntryButton: View {
    let state: BookBlendEntryState
    let otherFirstName: String
    let action: () -> Void

    @State private var pulse = false

    private var label: String {
        switch state {
        case .none: return "Request a Book Blend"
        case .requestedByMe: return "Blend requested"
        case .invitedMe: return "\(otherFirstName) invited you to Blend"
        case .ready: return "Watch your Book Blend"
        }
    }

    private var icon: String {
        switch state {
        case .none: return "sparkles"
        case .requestedByMe: return "hourglass"
        case .invitedMe: return "envelope.open.fill"
        case .ready: return "play.fill"
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .bold))
                Text(label)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(state == .requestedByMe ? Theme.textSecondary : Theme.onChrome)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity)
            .background(
                Capsule().fill(
                    state == .requestedByMe
                        ? AnyShapeStyle(Theme.chromeGray)
                        : AnyShapeStyle(Theme.gloss(Theme.chrome))
                )
            )
            .clipShape(Capsule())
            .overlay(
                Capsule().strokeBorder(Theme.onChrome.opacity(0.35), lineWidth: 1)
            )
            .shadow(color: Theme.accent.opacity(state == .requestedByMe ? 0 : 0.35), radius: 8, y: 3)
            // Faint breathing pulse — alive without shouting.
            .scaleEffect(state == .requestedByMe ? 1 : (pulse ? 1.015 : 1))
        }
        .buttonStyle(.springPress)
        .disabled(state == .requestedByMe)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}

// MARK: - Push presentation

/// Presents the blend landing when a blend push is tapped — warm (NotificationCenter)
/// or cold start (stash consumed on appear). Applied once, on `MainTabView`.
struct BookBlendPushPresenter: ViewModifier {
    @EnvironmentObject var authService: AuthService
    @EnvironmentObject var appState: AppState
    @State private var presented: Presentation?
    #if DEBUG
    /// `-uiPreviewBlend` (with `-uiPreview`): opens the blend story on demo data
    /// for simulator UI verification — no Firestore, no second account.
    @State private var showDemoStory = false
    #endif

    private struct Presentation: Identifiable {
        let id: String
    }

    func body(content: Content) -> some View {
        content
            .onAppear {
                if let blendId = PushNotificationService.consumePendingBlendTap() {
                    presented = Presentation(id: blendId)
                }
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("-uiPreviewBlend") {
                    showDemoStory = true
                }
                #endif
            }
            #if DEBUG
            .fullScreenCover(isPresented: $showDemoStory) {
                BookBlendStoryView(blend: .uiPreviewDemo, myUid: "ui-preview") {
                    showDemoStory = false
                }
                .environmentObject(appState)
            }
            #endif
            .onReceive(NotificationCenter.default.publisher(for: .spineOpenBookBlend)) { note in
                if let blendId = note.userInfo?["blendId"] as? String {
                    // Consume the cold-start stash too, so onAppear doesn't re-present.
                    _ = PushNotificationService.consumePendingBlendTap()
                    presented = Presentation(id: blendId)
                }
            }
            .fullScreenCover(item: $presented) { presentation in
                BookBlendLandingView(blendId: presentation.id)
                    .environmentObject(authService)
                    .environmentObject(appState)
            }
    }
}

extension View {
    func bookBlendPushPresenter() -> some View {
        modifier(BookBlendPushPresenter())
    }
}

// MARK: - Landing (router)

/// Full-screen destination for the profile button and both blend pushes. Routes
/// the pair doc by status + my role; accepting runs generation right here and
/// drops straight into the story.
struct BookBlendLandingView: View {
    let blendId: String

    @EnvironmentObject var authService: AuthService
    @Environment(\.dismiss) private var dismiss

    private enum Phase: Equatable {
        case loading
        case invite
        case generating
        case story(BookBlend)
        case waiting
        case gone
    }

    @State private var blend: BookBlend?
    @State private var listener: ListenerRegistration?
    @State private var phase: Phase = .loading
    @State private var acceptError: String?

    private var myUid: String { authService.firebaseUser?.uid ?? "" }

    private var otherName: String {
        guard let blend else { return "them" }
        return blend.participants[blend.otherUserId(from: myUid)]?.firstName ?? "them"
    }

    var body: some View {
        ZStack {
            BlendAuroraBackground(drift: true)

            switch phase {
            case .loading:
                ProgressView().tint(Theme.paperFixed)
            case .invite:
                if let blend {
                    inviteScreen(blend)
                }
            case .generating:
                BlendGeneratingView(
                    myPhotoURL: blend?.participants[myUid]?.photoURL,
                    otherPhotoURL: blend.flatMap { $0.participants[$0.otherUserId(from: myUid)]?.photoURL },
                    myName: blend?.participants[myUid]?.firstName ?? "You",
                    otherName: otherName
                )
            case .story(let ready):
                BookBlendStoryView(blend: ready, myUid: myUid) { dismiss() }
            case .waiting:
                waitingScreen
            case .gone:
                goneScreen
            }

            // Close chip — the story page has its own dismiss affordances. Kept
            // during generation as an escape hatch: the accept Task owns its own
            // copies, so generation finishes and saves even if the cover closes.
            if !isStory {
                VStack {
                    HStack {
                        Spacer()
                        Button { dismiss() } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(Theme.paperFixed.opacity(0.85))
                                .padding(10)
                                .background(Circle().fill(.white.opacity(0.14)))
                        }
                        .buttonStyle(.springPress)
                    }
                    Spacer()
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { startListening() }
        .onDisappear {
            listener?.remove()
            listener = nil
        }
    }

    private var isStory: Bool {
        if case .story = phase { return true }
        return false
    }

    private func startListening() {
        guard listener == nil else { return }
        listener = BookBlendService.shared.listenBlend(pairId: blendId) { updated, isFromCache in
            blend = updated
            route(updated, isFromCache: isFromCache)
        }
    }

    /// Local phases the listener must not stomp: generation in flight, or a story
    /// already playing (a doc refresh mid-story would restart it). Cache snapshots
    /// can be stale, so they never lock a phase the server can't correct: a story
    /// entered from cache is re-routed if the server later disagrees, and a
    /// cached "no doc" stays on the loading spinner until the server confirms.
    private func route(_ updated: BookBlend?, isFromCache: Bool) {
        if phase == .generating { return }
        if isStory {
            // Same ready doc refreshing mid-story: keep playing. Server
            // contradiction (e.g. the story came from a stale cache): re-route.
            if isFromCache || updated?.status == .ready { return }
        }
        guard let updated else {
            // A cached miss isn't truth — wait for the server before "gone".
            if !isFromCache { phase = .gone }
            return
        }
        switch updated.status {
        case .ready:
            if let _ = updated.result {
                phase = .story(updated)
            } else if !isFromCache {
                phase = .gone
            }
        case .pending:
            phase = updated.recipientId == myUid ? .invite : .waiting
        case .declined:
            phase = .gone
        }
    }

    // MARK: Invite (accept / decline)

    private func inviteScreen(_ blend: BookBlend) -> some View {
        VStack(spacing: 0) {
            Spacer()

            BlendAvatarLockup(
                leftURL: blend.participants[blend.requesterId]?.photoURL,
                rightURL: blend.participants[blend.recipientId]?.photoURL,
                leftName: blend.participants[blend.requesterId]?.firstName ?? "?",
                rightName: blend.participants[blend.recipientId]?.firstName ?? "?",
                size: 92
            )
            .padding(.bottom, 28)

            Text("BOOK BLEND")
                .font(.system(size: 13, weight: .heavy))
                .tracking(4)
                .foregroundStyle(Theme.paperFixed.opacity(0.7))
                .padding(.bottom, 10)

            Text("\(otherName) wants to blend\nlibraries with you")
                .font(.system(size: 28, weight: .bold))
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.paperFixed)
                .padding(.horizontal, 28)
                .padding(.bottom, 14)

            Text("Get a taste match score. See which books you both loved. Get fun insights and books to steal from one another.")
                .font(Theme.callout())
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.paperFixed.opacity(0.75))
                .padding(.horizontal, 40)

            Spacer()

            if let acceptError {
                Text(acceptError)
                    .font(Theme.caption())
                    .foregroundStyle(Theme.paperFixed.opacity(0.9))
                    .padding(.horizontal, 32)
                    .padding(.bottom, 10)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 12) {
                Button { accept(blend) } label: {
                    Text("Let's Blend")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Theme.onChrome)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                .glossyProminent(Theme.accent, cornerRadius: 28)
                .buttonStyle(.springPress)

                Button { declineAndDismiss(blend) } label: {
                    Text("Not now")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.paperFixed.opacity(0.7))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.springPress)

                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 11))
                    Text("Blends are best when your full library is imported.")
                        .font(Theme.caption())
                }
                .foregroundStyle(Theme.paperFixed.opacity(0.55))
                .padding(.top, 2)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 30)
        }
    }

    private func accept(_ blend: BookBlend) {
        acceptError = nil
        phase = .generating
        Task {
            do {
                let ready = try await BookBlendService.shared.generateAndSave(blend, accepterUid: myUid)
                // Let the merge animation land before the reveal.
                try? await Task.sleep(nanoseconds: 600_000_000)
                await MainActor.run { phase = .story(ready) }
            } catch {
                await MainActor.run {
                    phase = .invite
                    acceptError = "Couldn't build the blend — check your connection and try again."
                }
            }
        }
    }

    private func declineAndDismiss(_ blend: BookBlend) {
        Task {
            try? await BookBlendService.shared.decline(blend)
            await MainActor.run { dismiss() }
        }
    }

    // MARK: Waiting / gone

    private var waitingScreen: some View {
        VStack(spacing: 16) {
            BlendAvatarLockup(
                leftURL: blend?.participants[myUid]?.photoURL,
                rightURL: blend.flatMap { $0.participants[$0.otherUserId(from: myUid)]?.photoURL },
                leftName: blend?.participants[myUid]?.firstName ?? "?",
                rightName: otherName,
                size: 72
            )
            Text("Blend requested")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(Theme.paperFixed)
            Text("We'll ping you the moment \(otherName) accepts. The blend builds itself from there.")
                .font(Theme.callout())
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.paperFixed.opacity(0.7))
                .padding(.horizontal, 44)
        }
    }

    private var goneScreen: some View {
        VStack(spacing: 12) {
            Text("📖")
                .font(.system(size: 44))
            Text("No blend here yet")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Theme.paperFixed)
            Text("Visit a reader's profile and request a Book Blend to get one going.")
                .font(Theme.callout())
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.paperFixed.opacity(0.7))
                .padding(.horizontal, 44)
        }
    }
}

// MARK: - Generating interlude

/// The "shelves merging" moment: avatars orbit into each other while status
/// lines rotate. Runs as long as generation takes.
struct BlendGeneratingView: View {
    let myPhotoURL: String?
    let otherPhotoURL: String?
    let myName: String
    let otherName: String

    @State private var merged = false
    @State private var lineIndex = 0

    private let lines = [
        "Merging shelves…",
        "Comparing ratings…",
        "Weighing tiers…",
        "Consulting the librarian…",
        "Pouring the blend…",
    ]

    var body: some View {
        VStack(spacing: 36) {
            Spacer()
            ZStack {
                Circle()
                    .strokeBorder(Theme.paperFixed.opacity(0.18), lineWidth: 1)
                    .frame(width: 190, height: 190)
                    .scaleEffect(merged ? 1.12 : 0.9)
                    .opacity(merged ? 0.2 : 0.7)
                BlendAvatar(urlString: myPhotoURL, name: myName, size: 84)
                    .offset(x: merged ? -18 : -62)
                BlendAvatar(urlString: otherPhotoURL, name: otherName, size: 84)
                    .offset(x: merged ? 18 : 62)
            }
            .animation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true), value: merged)

            VStack(spacing: 10) {
                Text("Blending")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(Theme.paperFixed)
                Text(lines[lineIndex])
                    .font(Theme.callout())
                    .foregroundStyle(Theme.paperFixed.opacity(0.7))
                    .contentTransition(.opacity)
                    .id(lineIndex)
                    .transition(.opacity)
            }
            Spacer()
        }
        .onAppear { merged = true }
        .onReceive(Timer.publish(every: 1.8, on: .main, in: .common).autoconnect()) { _ in
            withAnimation(.easeInOut(duration: 0.4)) {
                lineIndex = (lineIndex + 1) % lines.count
            }
        }
    }
}

// MARK: - Shared bits

struct BlendAvatar: View {
    let urlString: String?
    let name: String
    var size: CGFloat = 72

    var body: some View {
        ZStack {
            if let urlString, let url = URL(string: urlString) {
                CachedProfileImage(url: url, contentMode: .fill) { initialCircle }
            } else {
                initialCircle
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Theme.paperFixed.opacity(0.85), lineWidth: 2))
        .shadow(color: Theme.shadowInk.opacity(0.35), radius: 8, y: 3)
    }

    private var initialCircle: some View {
        Circle()
            .fill(Theme.defaultCoverFill)
            .overlay(
                Text(String(name.prefix(1)).uppercased())
                    .font(.system(size: size * 0.4, weight: .bold))
                    .foregroundStyle(Theme.paperFixed)
            )
    }
}

struct BlendAvatarLockup: View {
    let leftURL: String?
    let rightURL: String?
    let leftName: String
    let rightName: String
    var size: CGFloat = 84

    var body: some View {
        HStack(spacing: -size * 0.28) {
            BlendAvatar(urlString: leftURL, name: leftName, size: size)
            BlendAvatar(urlString: rightURL, name: rightName, size: size)
        }
    }
}

/// Immersive blend backdrop — SPINE ink base with drifting paper-glow auroras
/// (the inverted mark, in motion). Fixed dark treatment in both appearance
/// modes (Wrapped-style full bleed).
struct BlendAuroraBackground: View {
    var drift: Bool = true
    @State private var animate = false

    var body: some View {
        ZStack {
            Theme.inkFixed

            blob(Theme.paperFixed.opacity(0.16), size: 420)
                .offset(x: animate ? -110 : -30, y: animate ? -220 : -140)
            blob(Theme.paperFixed.opacity(0.10), size: 380)
                .offset(x: animate ? 130 : 60, y: animate ? -40 : 60)
            blob(Theme.paperFixed.opacity(0.07), size: 360)
                .offset(x: animate ? -70 : 40, y: animate ? 260 : 180)
            blob(Theme.paperFixed.opacity(0.12), size: 300)
                .offset(x: animate ? 100 : -60, y: animate ? 120 : 260)
        }
        .ignoresSafeArea()
        .onAppear {
            guard drift else { return }
            withAnimation(.easeInOut(duration: 9).repeatForever(autoreverses: true)) {
                animate = true
            }
        }
    }

    private func blob(_ color: Color, size: CGFloat) -> some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .blur(radius: 90)
    }
}
