//
//  BookBlendStoryView.swift
//  Spine
//
//  The Book Blend story: full-bleed auto-advancing pages (Wrapped-style) built
//  from the stored blend result — score reveal, archetype, shared shelf, taste
//  map, insights, shelf-steal recs, fresh picks, outro. Hold to pause, tap the
//  edges to scrub, swipe down to leave. Rewatch is just replaying the doc.
//

import SwiftUI

struct BookBlendStoryView: View {
    let blend: BookBlend
    let myUid: String
    let onDismiss: () -> Void

    private enum Page {
        case intro
        case score
        case archetype
        case sharedShelf
        case genres
        case insight(BookBlend.Insight)
        case recs(forUid: String)
        case freshPicks
        case outro
    }

    @State private var pageIndex = 0
    @State private var pageProgress: Double = 0
    @State private var paused = false
    @State private var pressStarted: Date?
    /// Score page count-up.
    @State private var displayedScore = 0
    @State private var scoreRevealToken = 0

    private let tick = Timer.publish(every: 1.0 / 30.0, on: .main, in: .common).autoconnect()

    private var result: BookBlend.Result? { blend.result }
    private var otherUid: String { blend.otherUserId(from: myUid) }
    private var myName: String { blend.participants[myUid]?.firstName ?? "You" }
    private var otherName: String { blend.participants[otherUid]?.firstName ?? "Them" }

    private var pages: [Page] {
        guard let result else { return [.outro] }
        var list: [Page] = [.intro, .score, .archetype]
        if !result.sharedBooks.isEmpty { list.append(.sharedShelf) }
        if !result.sharedGenres.isEmpty || !(result.distinctGenres[myUid] ?? []).isEmpty || !(result.distinctGenres[otherUid] ?? []).isEmpty {
            list.append(.genres)
        }
        for insight in result.insights.prefix(2) { list.append(.insight(insight)) }
        if !(result.recs[myUid] ?? []).isEmpty { list.append(.recs(forUid: myUid)) }
        if !(result.recs[otherUid] ?? []).isEmpty { list.append(.recs(forUid: otherUid)) }
        if !result.freshPicks.isEmpty { list.append(.freshPicks) }
        list.append(.outro)
        return list
    }

    private var pageDuration: Double {
        switch pages[pageIndex] {
        case .score: return 8.5
        case .sharedShelf, .recs, .genres: return 9.0
        default: return 7.0
        }
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                BlendAuroraBackground(drift: true)
                    .hueRotation(.degrees(Double(pageIndex) * 16))
                    .animation(.easeInOut(duration: 0.8), value: pageIndex)

                pageView(pages[pageIndex])
                    .id(pageIndex)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 1.03)),
                        removal: .opacity
                    ))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                VStack(spacing: 0) {
                    progressBars
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                    HStack {
                        Text("\(myName) × \(otherName)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.phosphorWhite.opacity(0.7))
                        Spacer()
                        Button(action: onDismiss) {
                            Image(systemName: "xmark")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(Theme.phosphorWhite.opacity(0.85))
                                .padding(9)
                                .background(Circle().fill(.white.opacity(0.14)))
                        }
                        .buttonStyle(.springPress)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    Spacer()
                }
            }
            .contentShape(Rectangle())
            .gesture(storyGesture(width: geo.size.width))
        }
        .preferredColorScheme(.dark)
        .statusBarHidden()
        .sensoryFeedback(.impact(weight: .light), trigger: pageIndex)
        .onReceive(tick) { _ in
            guard !paused else { return }
            pageProgress += (1.0 / 30.0) / pageDuration
            if pageProgress >= 1 { advance() }
        }
        .onChange(of: pageIndex) { _, _ in
            if case .score = pages[pageIndex] { startScoreReveal() }
        }
    }

    // MARK: Mechanics

    /// One gesture does it all: press-and-hold pauses, a quick release taps
    /// (left third = back, rest = forward), a downward fling dismisses.
    private func storyGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                if pressStarted == nil { pressStarted = Date() }
                paused = true
            }
            .onEnded { value in
                defer {
                    paused = false
                    pressStarted = nil
                }
                if value.translation.height > 90 {
                    onDismiss()
                    return
                }
                let held = pressStarted.map { Date().timeIntervalSince($0) } ?? 0
                let moved = hypot(value.translation.width, value.translation.height)
                guard held < 0.35, moved < 24 else { return }
                if value.location.x < width / 3 {
                    goBack()
                } else {
                    advance()
                }
            }
    }

    private func advance() {
        if pageIndex >= pages.count - 1 {
            onDismiss()
            return
        }
        withAnimation(.easeOut(duration: 0.3)) {
            pageIndex += 1
        }
        pageProgress = 0
    }

    private func goBack() {
        if pageIndex == 0 {
            pageProgress = 0
            return
        }
        withAnimation(.easeOut(duration: 0.3)) {
            pageIndex -= 1
        }
        pageProgress = 0
    }

    private var progressBars: some View {
        HStack(spacing: 4) {
            ForEach(pages.indices, id: \.self) { i in
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.25))
                        Capsule()
                            .fill(Theme.phosphorWhite)
                            .frame(width: g.size.width * segmentFill(i))
                    }
                }
                .frame(height: 3)
            }
        }
    }

    private func segmentFill(_ i: Int) -> CGFloat {
        if i < pageIndex { return 1 }
        if i > pageIndex { return 0 }
        return CGFloat(min(1, max(0, pageProgress)))
    }

    private func startScoreReveal() {
        guard let target = result?.score else { return }
        scoreRevealToken += 1
        let token = scoreRevealToken
        displayedScore = 0
        Task { @MainActor in
            // Ease-out count-up: fast start, landing softly on the number.
            let steps = 45
            for step in 1...steps {
                guard token == scoreRevealToken else { return }
                let t = Double(step) / Double(steps)
                displayedScore = Int((1 - pow(1 - t, 3)) * Double(target))
                try? await Task.sleep(nanoseconds: 33_000_000)
            }
            displayedScore = target
        }
    }

    // MARK: Pages

    @ViewBuilder
    private func pageView(_ page: Page) -> some View {
        switch page {
        case .intro: introPage
        case .score: scorePage
        case .archetype: archetypePage
        case .sharedShelf: sharedShelfPage
        case .genres: genresPage
        case .insight(let insight): insightPage(insight)
        case .recs(let uid): recsPage(forUid: uid)
        case .freshPicks: freshPicksPage
        case .outro: outroPage
        }
    }

    private var introPage: some View {
        VStack(spacing: 24) {
            Spacer()
            BlendAvatarLockup(
                leftURL: blend.participants[myUid]?.photoURL,
                rightURL: blend.participants[otherUid]?.photoURL,
                leftName: myName,
                rightName: otherName,
                size: 96
            )
            VStack(spacing: 8) {
                Text("BOOK BLEND")
                    .font(.system(size: 14, weight: .heavy))
                    .tracking(5)
                    .foregroundStyle(Theme.phosphorWhite.opacity(0.7))
                Text("\(myName) × \(otherName)")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(Theme.phosphorWhite)
                if let count = mergedBookCount {
                    Text("\(count) books, two shelves, one verdict.")
                        .font(Theme.callout())
                        .foregroundStyle(Theme.phosphorWhite.opacity(0.7))
                }
            }
            Spacer()
            Text("Tap to begin")
                .font(Theme.caption())
                .foregroundStyle(Theme.phosphorWhite.opacity(0.5))
                .padding(.bottom, 40)
        }
    }

    private var mergedBookCount: Int? {
        let a = blend.participants[myUid]?.readCount ?? 0
        let b = blend.participants[otherUid]?.readCount ?? 0
        return a + b > 0 ? a + b : nil
    }

    private var scorePage: some View {
        VStack(spacing: 22) {
            Spacer()
            Text("Your taste match")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.phosphorWhite.opacity(0.75))
            ZStack {
                Circle()
                    .stroke(.white.opacity(0.15), lineWidth: 10)
                Circle()
                    .trim(from: 0, to: CGFloat(displayedScore) / 100)
                    .stroke(
                        AngularGradient(
                            colors: [Theme.chromeTeal, Theme.asicsBlue, Theme.magentaPunch, Theme.chromeTeal],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 10, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                Text("\(displayedScore)%")
                    .font(.system(size: 72, weight: .heavy))
                    .foregroundStyle(Theme.phosphorWhite)
                    .contentTransition(.numericText(value: Double(displayedScore)))
            }
            .frame(width: 230, height: 230)
            if let verdict = result?.verdict {
                Text(verdict)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Theme.phosphorWhite)
                    .opacity(displayedScore == result?.score ? 1 : 0)
                    .animation(.easeIn(duration: 0.4), value: displayedScore)
            }
            Spacer()
        }
        .onAppear { startScoreReveal() }
    }

    private var archetypePage: some View {
        VStack(spacing: 18) {
            Spacer()
            Text(result?.archetypeEmoji ?? "📚")
                .font(.system(size: 72))
            Text("You two are")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.phosphorWhite.opacity(0.75))
            Text(result?.archetype ?? "")
                .font(.system(size: 38, weight: .heavy))
                .multilineTextAlignment(.center)
                .foregroundStyle(
                    LinearGradient(
                        colors: [Theme.phosphorWhite, Theme.phosphorWhite.opacity(0.75)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .padding(.horizontal, 28)
            Text(result?.tagline ?? "")
                .font(Theme.body())
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.phosphorWhite.opacity(0.8))
                .padding(.horizontal, 44)
            Spacer()
        }
    }

    private var sharedShelfPage: some View {
        let shared = result?.sharedBooks ?? []
        return VStack(alignment: .leading, spacing: 18) {
            Spacer(minLength: 70)
            pageHeader("You've both read", big: "\(shared.count) of the same \(shared.count == 1 ? "book" : "books")")
            VStack(spacing: 12) {
                ForEach(Array(shared.prefix(4).enumerated()), id: \.offset) { _, book in
                    HStack(spacing: 12) {
                        BookCoverView(book: bookFor(shared: book), size: 44)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(book.title)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Theme.phosphorWhite)
                                .lineLimit(1)
                            HStack(spacing: 8) {
                                verdictChip(name: myName, uid: myUid, book: book)
                                verdictChip(name: otherName, uid: otherUid, book: book)
                            }
                        }
                        Spacer()
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.09)))
                }
            }
            if shared.count > 4 {
                Text("+ \(shared.count - 4) more in common")
                    .font(Theme.caption())
                    .foregroundStyle(Theme.phosphorWhite.opacity(0.6))
            }
            Spacer()
        }
        .padding(.horizontal, 24)
    }

    private func verdictChip(name: String, uid: String, book: BookBlend.SharedBook) -> some View {
        let text: String
        if let r = book.ratings[uid] {
            text = "\(name) \(Theme.formatRatingOutOfTen(r))"
        } else if let t = book.tiers[uid] {
            text = "\(name) \(t)-tier"
        } else {
            text = "\(name) read it"
        }
        return Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Theme.phosphorWhite.opacity(0.85))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(.white.opacity(0.14)))
    }

    private var genresPage: some View {
        let shared = result?.sharedGenres ?? []
        let mine = result?.distinctGenres[myUid] ?? []
        let theirs = result?.distinctGenres[otherUid] ?? []
        return VStack(alignment: .leading, spacing: 22) {
            Spacer(minLength: 70)
            pageHeader("The taste map", big: shared.first.map { "\($0) is your common ground" } ?? "Different shelves, same energy")
            if !shared.isEmpty {
                FlowLayout(spacing: 8) {
                    ForEach(shared, id: \.self) { genre in
                        Text(genre)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.phosphorWhite)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Capsule().fill(Theme.asicsBlue.opacity(0.55)))
                    }
                }
            }
            HStack(alignment: .top, spacing: 14) {
                broughtColumn(name: myName, genres: mine)
                broughtColumn(name: otherName, genres: theirs)
            }
            Spacer()
        }
        .padding(.horizontal, 24)
    }

    private func broughtColumn(name: String, genres: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(name.uppercased()) BRINGS")
                .font(.system(size: 10, weight: .heavy))
                .tracking(1.4)
                .foregroundStyle(Theme.phosphorWhite.opacity(0.55))
            if genres.isEmpty {
                Text("Pure overlap")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.phosphorWhite.opacity(0.75))
            } else {
                ForEach(genres.prefix(3), id: \.self) { genre in
                    Text(genre)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.phosphorWhite)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16).fill(.white.opacity(0.09)))
    }

    private func insightPage(_ insight: BookBlend.Insight) -> some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "quote.opening")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(Theme.magentaPunch)
            Text(insight.title)
                .font(.system(size: 30, weight: .heavy))
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.phosphorWhite)
                .padding(.horizontal, 30)
            Text(insight.body)
                .font(.system(size: 18, weight: .medium))
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .foregroundStyle(Theme.phosphorWhite.opacity(0.85))
                .padding(.horizontal, 36)
            Spacer()
        }
    }

    private func recsPage(forUid uid: String) -> some View {
        let recs = result?.recs[uid] ?? []
        let isMine = uid == myUid
        let shelfOwner = isMine ? otherName : myName
        return VStack(alignment: .leading, spacing: 18) {
            Spacer(minLength: 70)
            pageHeader(
                isMine ? "For you, \(myName)" : "And for \(otherName)",
                big: "Steal these from \(shelfOwner)'s shelf"
            )
            VStack(spacing: 12) {
                ForEach(Array(recs.prefix(3).enumerated()), id: \.offset) { _, rec in
                    HStack(alignment: .top, spacing: 12) {
                        BookCoverView(book: bookFor(rec: rec), size: 48)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(rec.title)
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(Theme.phosphorWhite)
                                .lineLimit(2)
                            Text(rec.author)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Theme.phosphorWhite.opacity(0.6))
                                .lineLimit(1)
                            if !rec.reason.isEmpty {
                                Text(rec.reason)
                                    .font(.system(size: 13, weight: .regular).italic())
                                    .foregroundStyle(Theme.phosphorWhite.opacity(0.85))
                                    .lineLimit(3)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 16).fill(.white.opacity(0.09)))
                }
            }
            Spacer()
        }
        .padding(.horizontal, 24)
    }

    private var freshPicksPage: some View {
        let picks = result?.freshPicks ?? []
        return VStack(alignment: .center, spacing: 20) {
            Spacer(minLength: 70)
            pageHeader("Neither of you has read", big: "Your next reads, together", centered: true)
            HStack(alignment: .top, spacing: 18) {
                ForEach(Array(picks.prefix(2).enumerated()), id: \.offset) { _, pick in
                    VStack(spacing: 8) {
                        BookCoverView(book: bookFor(rec: pick), size: 92)
                        Text(pick.title)
                            .font(.system(size: 15, weight: .bold))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(Theme.phosphorWhite)
                            .lineLimit(2)
                        Text(pick.reason)
                            .font(.system(size: 12, weight: .regular))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(Theme.phosphorWhite.opacity(0.75))
                            .lineLimit(4)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 24)
            Spacer()
        }
    }

    private var outroPage: some View {
        VStack(spacing: 16) {
            Spacer()
            if let result {
                Text("\(result.score)%")
                    .font(.system(size: 52, weight: .heavy))
                    .foregroundStyle(Theme.phosphorWhite)
                Text("\(result.archetypeEmoji) \(result.archetype)")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Theme.phosphorWhite.opacity(0.9))
            }
            Text("Saved for both of you — rewatch it anytime from \(otherName)'s profile.")
                .font(Theme.callout())
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.phosphorWhite.opacity(0.7))
                .padding(.horizontal, 44)
            Spacer()
            Button(action: onDismiss) {
                Text("Done")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Theme.phosphorWhite)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
            .glossyProminent(Theme.asicsBlue, cornerRadius: 28)
            .buttonStyle(.springPress)
            .padding(.horizontal, 28)
            .padding(.bottom, 34)
        }
    }

    private func pageHeader(_ small: String, big: String, centered: Bool = false) -> some View {
        VStack(alignment: centered ? .center : .leading, spacing: 6) {
            Text(small.uppercased())
                .font(.system(size: 11, weight: .heavy))
                .tracking(2)
                .foregroundStyle(Theme.phosphorWhite.opacity(0.6))
            Text(big)
                .font(.system(size: 27, weight: .bold))
                .foregroundStyle(Theme.phosphorWhite)
                .multilineTextAlignment(centered ? .center : .leading)
        }
        .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
    }

    // MARK: Book adapters (covers ride the shared BookCoverView pipeline)

    private func bookFor(shared: BookBlend.SharedBook) -> Book {
        Book(id: shared.bookId, title: shared.title, author: shared.author, coverURL: shared.coverURL, pageCount: nil, publishedDate: nil, description: nil, genres: [])
    }

    private func bookFor(rec: BookBlend.Rec) -> Book {
        Book(id: rec.bookId ?? UUID().uuidString, title: rec.title, author: rec.author, coverURL: rec.coverURL ?? "", pageCount: nil, publishedDate: nil, description: nil, genres: [])
    }
}

#if DEBUG
extension BookBlend {
    /// Demo blend for `-uiPreviewBlend` simulator runs — exercises every story page.
    static var uiPreviewDemo: BookBlend {
        let me = "ui-preview", them = "demo-friend"
        return BookBlend(
            id: pairId(me, them),
            userIds: [me, them].sorted(),
            requesterId: them,
            recipientId: me,
            status: .ready,
            createdAt: Date(),
            respondedAt: Date(),
            participants: [
                me: Participant(firstName: "Tanner", photoURL: nil, readCount: 42),
                them: Participant(firstName: "Alex", photoURL: nil, readCount: 57),
            ],
            result: Result(
                score: 84,
                verdict: "Same Chapter",
                archetype: "The Plot Twisters",
                archetypeEmoji: "🌀",
                tagline: "You read for the moment the floor drops out.",
                sharedBooks: [
                    SharedBook(bookId: "1", title: "Project Hail Mary", author: "Andy Weir", coverURL: "", ratings: [me: 9.4, them: 9.0], tiers: [me: "S"]),
                    SharedBook(bookId: "2", title: "Educated", author: "Tara Westover", coverURL: "", ratings: [them: 8.6], tiers: [me: "A"]),
                    SharedBook(bookId: "3", title: "The Martian", author: "Andy Weir", coverURL: "", ratings: [me: 8.8, them: 7.9], tiers: [:]),
                    SharedBook(bookId: "4", title: "Atomic Habits", author: "James Clear", coverURL: "", ratings: [me: 7.2], tiers: [them: "B"]),
                    SharedBook(bookId: "5", title: "Dune", author: "Frank Herbert", coverURL: "", ratings: [me: 9.9, them: 9.5], tiers: [:]),
                ],
                sharedGenres: ["Science Fiction", "Memoir", "Psychology"],
                distinctGenres: [me: ["History", "Economics"], them: ["Literary Fiction", "Horror"]],
                insights: [
                    Insight(title: "Weir believers", body: "Andy Weir is your load-bearing author — you both rated him a 9 or better, twice."),
                    Insight(title: "Rating twins", body: "When you both read a book, your scores land within half a point. Suspiciously in sync."),
                ],
                recs: [
                    me: [
                        Rec(title: "The Secret History", author: "Donna Tartt", bookId: nil, coverURL: nil, reason: "Alex's highest-rated fiction — dark academia you'd devour.", sourceUid: them),
                        Rec(title: "Mexican Gothic", author: "Silvia Moreno-Garcia", bookId: nil, coverURL: nil, reason: "The horror gateway Alex swears by.", sourceUid: them),
                    ],
                    them: [
                        Rec(title: "Basic Economics", author: "Thomas Sowell", bookId: nil, coverURL: nil, reason: "Tanner's A-tier — the nonfiction spine of his shelf.", sourceUid: me),
                        Rec(title: "Endurance", author: "Alfred Lansing", bookId: nil, coverURL: nil, reason: "Survival stakes with none of the fiction.", sourceUid: me),
                    ],
                ],
                freshPicks: [
                    Rec(title: "Piranesi", author: "Susanna Clarke", bookId: nil, coverURL: nil, reason: "A puzzle-box world for two plot twisters.", sourceUid: nil),
                    Rec(title: "Recursion", author: "Blake Crouch", bookId: nil, coverURL: nil, reason: "Sci-fi that rewrites itself — buddy-read bait.", sourceUid: nil),
                ],
                generatedAt: Date(),
                generatedBy: me
            )
        )
    }
}
#endif
