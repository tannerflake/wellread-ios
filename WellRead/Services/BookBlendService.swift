//
//  BookBlendService.swift
//  Spine
//
//  Book Blend: Firestore repo (request / decline / generate on accept) plus the
//  engine that merges two libraries into a stored result. Scoring is a
//  deterministic weighted blend (shared shelf, rating agreement, genre overlap —
//  MatchScoreService style); Claude writes the archetype, insights, and rec
//  reasons on top. Everything lands on the pair doc so rewatch is a read.
//

import Foundation
import FirebaseFirestore

final class BookBlendService {
    static let shared = BookBlendService()

    private let db = FirestoreDatabase.firestore
    private let collectionName = "bookBlends"
    private let userBookRepo = UserBookRepository()
    private let userRepo = UserRepository()

    private init() {}

    // MARK: - Repo

    func listenBlend(pairId: String, onUpdate: @escaping (BookBlend?) -> Void) -> ListenerRegistration {
        db.collection(collectionName).document(pairId).addSnapshotListener { snapshot, _ in
            guard let snapshot else { return }
            let blend = snapshot.data().flatMap { BookBlend.from(data: $0, docId: snapshot.documentID) }
            DispatchQueue.main.async { onUpdate(blend) }
        }
    }

    func fetchBlend(pairId: String) async -> BookBlend? {
        guard let snapshot = try? await db.collection(collectionName).document(pairId).getDocument(),
              let data = snapshot.data() else { return nil }
        return BookBlend.from(data: data, docId: snapshot.documentID)
    }

    /// Creates (or re-opens a declined) pair doc as pending. The Cloud Function on
    /// this write pushes the blend invite to the recipient.
    func requestBlend(myUid: String, me: User?, otherUid: String, other: User?) async throws -> BookBlend {
        let pairId = BookBlend.pairId(myUid, otherUid)
        var participants: [String: BookBlend.Participant] = [:]
        participants[myUid] = participant(from: me)
        participants[otherUid] = participant(from: other)
        let blend = BookBlend(
            id: pairId,
            userIds: [myUid, otherUid].sorted(),
            requesterId: myUid,
            recipientId: otherUid,
            status: .pending,
            createdAt: Date(),
            respondedAt: nil,
            participants: participants,
            result: nil
        )
        try await db.collection(collectionName).document(pairId).setData(blend.firestoreData)
        return blend
    }

    func decline(_ blend: BookBlend) async throws {
        try await db.collection(collectionName).document(blend.id).updateData([
            "status": BookBlendStatus.declined.rawValue,
            "respondedAt": Timestamp(date: Date()),
        ])
    }

    private func participant(from user: User?) -> BookBlend.Participant {
        let first: String
        if let fn = user?.firstName?.trimmingCharacters(in: .whitespacesAndNewlines), !fn.isEmpty {
            first = fn
        } else {
            first = user?.displayName.split(separator: " ").first.map(String.init) ?? "Reader"
        }
        return BookBlend.Participant(firstName: first, photoURL: user?.profileImageURL, readCount: 0)
    }

    // MARK: - Generate (runs on the accepter's device)

    /// Fetches both libraries, computes + writes the blend, and flips the doc to
    /// `ready` — which triggers the "your blend is ready" push to the requester.
    func generateAndSave(_ blend: BookBlend, accepterUid: String) async throws -> BookBlend {
        let otherUid = blend.otherUserId(from: accepterUid)

        async let mineTask = userBookRepo.fetchUserBooks(userId: accepterUid)
        async let theirsTask = userBookRepo.fetchUserBooks(userId: otherUid)
        async let meTask = userRepo.getUser(uid: accepterUid)
        async let otherTask = userRepo.getUser(uid: otherUid)
        let (mine, theirs, me, other) = await (mineTask, theirsTask, meTask, otherTask)

        let myReads = mine.filter { $0.status == .read }
        let theirReads = theirs.filter { $0.status == .read }

        var participants = blend.participants
        participants[accepterUid] = {
            var p = participant(from: me)
            p.readCount = myReads.count
            return p
        }()
        participants[otherUid] = {
            var p = participant(from: other)
            p.readCount = theirReads.count
            return p
        }()

        let myName = participants[accepterUid]?.firstName ?? "Reader"
        let otherName = participants[otherUid]?.firstName ?? "Reader"

        let stats = computeStats(
            uidA: accepterUid, readsA: myReads,
            uidB: otherUid, readsB: theirReads
        )

        var result = fallbackResult(
            stats: stats,
            uidA: accepterUid, nameA: myName, readsA: myReads, queueA: mine.filter { $0.status == .wantToRead },
            uidB: otherUid, nameB: otherName, readsB: theirReads,
            generatedBy: accepterUid
        )

        if let ai = await aiLayer(
            stats: stats,
            uidA: accepterUid, nameA: myName, libraryA: mine,
            uidB: otherUid, nameB: otherName, libraryB: theirs
        ) {
            result.archetype = ai.archetype
            result.archetypeEmoji = ai.archetypeEmoji
            result.tagline = ai.tagline
            if !ai.insights.isEmpty { result.insights = ai.insights }
            if let recsA = ai.recs[accepterUid], !recsA.isEmpty { result.recs[accepterUid] = recsA }
            if let recsB = ai.recs[otherUid], !recsB.isEmpty { result.recs[otherUid] = recsB }
            if !ai.freshPicks.isEmpty { result.freshPicks = ai.freshPicks }
        }

        result.recs[accepterUid] = hydrate(recs: result.recs[accepterUid] ?? [], fromShelfOf: theirReads, sourceUid: otherUid)
        result.recs[otherUid] = hydrate(recs: result.recs[otherUid] ?? [], fromShelfOf: myReads, sourceUid: accepterUid)
        result.freshPicks = await hydrateFreshPicks(result.freshPicks)

        var saved = blend
        saved.status = .ready
        saved.respondedAt = Date()
        saved.participants = participants
        saved.result = result
        try await db.collection(collectionName).document(blend.id).setData(saved.firestoreData)
        return saved
    }

    // MARK: - Deterministic layer

    private struct BlendStats {
        var score: Int
        var verdict: String
        var sharedBooks: [BookBlend.SharedBook]
        var sharedGenres: [String]
        var distinctGenres: [String: [String]]
        /// 0…1 rating agreement across shared rated books; nil when none shared.
        var agreement: Double?
    }

    private func computeStats(uidA: String, readsA: [UserBook], uidB: String, readsB: [UserBook]) -> BlendStats {
        // Shared shelf — match by bookId or normalized title+author (Goodreads
        // imports and Google Books often give the same book different ids).
        var aByBookId: [String: UserBook] = [:]
        var aByKey: [String: UserBook] = [:]
        for entry in readsA {
            aByBookId[entry.bookId] = entry
            if let key = normalizedKey(entry.book) { aByKey[key] = entry }
        }

        var shared: [BookBlend.SharedBook] = []
        var seenA = Set<UUID>()
        for entryB in readsB {
            let match: UserBook?
            if let m = aByBookId[entryB.bookId] {
                match = m
            } else if let key = normalizedKey(entryB.book), let m = aByKey[key] {
                match = m
            } else {
                match = nil
            }
            guard let entryA = match, !seenA.contains(entryA.id) else { continue }
            seenA.insert(entryA.id)
            let book = [entryA.book, entryB.book].compactMap { $0 }.first { !$0.coverURL.isEmpty }
                ?? entryA.book ?? entryB.book
            var ratings: [String: Double] = [:]
            var tiers: [String: String] = [:]
            if let r = entryA.rating { ratings[uidA] = r }
            if let r = entryB.rating { ratings[uidB] = r }
            if let t = entryA.tier { tiers[uidA] = t }
            if let t = entryB.tier { tiers[uidB] = t }
            shared.append(BookBlend.SharedBook(
                bookId: book?.id ?? entryA.bookId,
                title: book?.title ?? "Untitled",
                author: book?.author ?? "",
                coverURL: book?.coverURL ?? "",
                ratings: ratings,
                tiers: tiers
            ))
        }
        // Most-loved first: highest combined affinity leads the story page.
        shared.sort { combinedAffinity($0, uidA: uidA, uidB: uidB) > combinedAffinity($1, uidA: uidA, uidB: uidB) }

        // Rating agreement on the shared shelf.
        var agreements: [Double] = []
        for book in shared {
            guard let a = sharedAffinity(book, uid: uidA), let b = sharedAffinity(book, uid: uidB) else { continue }
            agreements.append(1.0 - abs(a - b) / 2.0)
        }
        let agreement = agreements.isEmpty ? nil : agreements.reduce(0, +) / Double(agreements.count)

        // Genre fingerprints.
        let genresA = genreCounts(readsA)
        let genresB = genreCounts(readsB)
        let setA = Set(genresA.keys), setB = Set(genresB.keys)
        let intersection = setA.intersection(setB)
        let union = setA.union(setB)
        let genreJaccard = union.isEmpty ? 0.0 : Double(intersection.count) / Double(union.count)

        let sharedGenres = intersection
            .sorted { (genresA[$0]! + genresB[$0]!) > (genresA[$1]! + genresB[$1]!) }
            .prefix(6).map { $0.capitalized }
        let distinctA = setA.subtracting(setB)
            .sorted { genresA[$0]! > genresA[$1]! }
            .prefix(4).map { $0.capitalized }
        let distinctB = setB.subtracting(setA)
            .sorted { genresB[$0]! > genresB[$1]! }
            .prefix(4).map { $0.capitalized }

        // Score: genre kinship + shared-shelf size + rating agreement → 30…98.
        // Genre Jaccard rarely clears 0.6 even for twins, so it gets stretched.
        let minLib = Double(min(readsA.count, readsB.count))
        let genreScore = min(1.0, genreJaccard * 1.9)
        let overlapScore = minLib < 1 ? 0.0 : min(1.0, Double(shared.count) / max(4.0, minLib * 0.25))
        let agreementScore = agreement ?? 0.55
        let score01 = 0.42 * genreScore + 0.30 * overlapScore + 0.28 * agreementScore
        let score = Int((30.0 + score01 * 68.0).rounded())

        return BlendStats(
            score: score,
            verdict: Self.verdict(for: score),
            sharedBooks: Array(shared.prefix(12)),
            sharedGenres: Array(sharedGenres),
            distinctGenres: [uidA: Array(distinctA), uidB: Array(distinctB)],
            agreement: agreement
        )
    }

    static func verdict(for score: Int) -> String {
        switch score {
        case 88...: return "Shelf Soulmates"
        case 75..<88: return "Same Chapter"
        case 62..<75: return "Plot Compatible"
        case 48..<62: return "Cross-Genre Chemistry"
        default: return "Opposite Shelves"
        }
    }

    /// How much a reader liked a book, −1…+1 (rating first, tier fallback) —
    /// same mapping as MatchScoreService.affinity.
    private func affinity(rating: Double?, tier: String?) -> Double? {
        if let rating { return min(1.0, max(-1.0, (rating - 5.5) / 4.5)) }
        switch tier {
        case "S": return 1.0
        case "A": return 0.6
        case "B": return 0.3
        case "C": return 0.0
        case "D": return -0.5
        case "F": return -1.0
        default: return nil
        }
    }

    private func sharedAffinity(_ book: BookBlend.SharedBook, uid: String) -> Double? {
        affinity(rating: book.ratings[uid], tier: book.tiers[uid])
    }

    private func combinedAffinity(_ book: BookBlend.SharedBook, uidA: String, uidB: String) -> Double {
        (sharedAffinity(book, uid: uidA) ?? 0) + (sharedAffinity(book, uid: uidB) ?? 0)
    }

    private func normalizedKey(_ book: Book?) -> String? {
        guard let book else { return nil }
        let title = book.title
            .split(separator: ":").first.map(String.init) ?? book.title
        let cleanTitle = title.lowercased().filter { $0.isLetter || $0.isNumber }
        guard !cleanTitle.isEmpty else { return nil }
        let authorLast = book.author
            .split(separator: ",").first.map(String.init)?
            .split(separator: " ").last.map(String.init)?.lowercased() ?? ""
        return "\(cleanTitle)|\(authorLast)"
    }

    /// Genre token → occurrence count across a shelf ("Fiction / Thrillers" splits
    /// into comparable tokens, dropping "general" — BookSearchRanker style).
    private func genreCounts(_ reads: [UserBook]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for entry in reads {
            guard let genres = entry.book?.genres else { continue }
            var tokens = Set<String>()
            for genre in genres {
                for part in genre.split(separator: "/") {
                    let token = part.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    if !token.isEmpty && token != "general" { tokens.insert(token) }
                }
            }
            for token in tokens { counts[token, default: 0] += 1 }
        }
        return counts
    }

    // MARK: - Fallback content (used whole when Claude is unavailable)

    private func fallbackResult(
        stats: BlendStats,
        uidA: String, nameA: String, readsA: [UserBook], queueA: [UserBook],
        uidB: String, nameB: String, readsB: [UserBook],
        generatedBy: String
    ) -> BookBlend.Result {
        var insights: [BookBlend.Insight] = []
        if let top = stats.sharedBooks.first {
            insights.append(.init(
                title: "Common ground",
                body: "You've both read \(top.title) — and \(stats.sharedBooks.count == 1 ? "that's where the overlap starts" : "\(stats.sharedBooks.count - 1) more besides")."
            ))
        }
        if let firstShared = stats.sharedGenres.first {
            insights.append(.init(
                title: "Shared wavelength",
                body: "\(firstShared) is the backbone of this blend — it shows up all over both shelves."
            ))
        }
        if let bringA = stats.distinctGenres[uidA]?.first, let bringB = stats.distinctGenres[uidB]?.first {
            insights.append(.init(
                title: "Trade routes",
                body: "\(nameA) brings the \(bringA.lowercased()), \(nameB) brings the \(bringB.lowercased()). That's the fun part."
            ))
        }
        if insights.isEmpty {
            insights.append(.init(
                title: "Blank page",
                body: "Not much overlap yet — which means everything's a recommendation waiting to happen."
            ))
        }

        return BookBlend.Result(
            score: stats.score,
            verdict: stats.verdict,
            archetype: stats.verdict,
            archetypeEmoji: "📚",
            tagline: "Two shelves, one story.",
            sharedBooks: stats.sharedBooks,
            sharedGenres: stats.sharedGenres,
            distinctGenres: stats.distinctGenres,
            insights: insights,
            recs: [
                uidA: topShelfRecs(for: readsA, from: readsB, otherName: nameB, sourceUid: uidB),
                uidB: topShelfRecs(for: readsB, from: readsA, otherName: nameA, sourceUid: uidA),
            ],
            freshPicks: [],
            generatedAt: Date(),
            generatedBy: generatedBy
        )
    }

    /// The other reader's highest-affinity books the target hasn't read.
    private func topShelfRecs(for target: [UserBook], from source: [UserBook], otherName: String, sourceUid: String) -> [BookBlend.Rec] {
        let targetIds = Set(target.map(\.bookId))
        let targetKeys = Set(target.compactMap { normalizedKey($0.book) })
        return source
            .filter { entry in
                guard !targetIds.contains(entry.bookId) else { return false }
                if let key = normalizedKey(entry.book), targetKeys.contains(key) { return false }
                return (affinity(rating: entry.rating, tier: entry.tier) ?? -1) > 0.4
            }
            .sorted { (affinity(rating: $0.rating, tier: $0.tier) ?? 0) > (affinity(rating: $1.rating, tier: $1.tier) ?? 0) }
            .prefix(3)
            .compactMap { entry in
                guard let book = entry.book else { return nil }
                return BookBlend.Rec(
                    title: book.title,
                    author: book.author,
                    bookId: book.id,
                    coverURL: book.coverURL,
                    reason: "One of \(otherName)'s top-shelf reads.",
                    sourceUid: sourceUid
                )
            }
    }

    // MARK: - AI layer

    private struct AIContent {
        var archetype: String
        var archetypeEmoji: String
        var tagline: String
        var insights: [BookBlend.Insight]
        var recs: [String: [BookBlend.Rec]]
        var freshPicks: [BookBlend.Rec]
    }

    private func aiLayer(
        stats: BlendStats,
        uidA: String, nameA: String, libraryA: [UserBook],
        uidB: String, nameB: String, libraryB: [UserBook]
    ) async -> AIContent? {
        let system = """
        You are the voice of Book Blend inside Spine, a social reading app. Two readers just merged their libraries. \
        Write punchy, specific, warm copy — Spotify-Wrapped energy, never generic, never cheesy. \
        Reference actual titles and tastes from the data. Keep every string under 140 characters. \
        Respond with ONLY a JSON object, no markdown fences, matching exactly:
        {
          "archetype": "fun 2-4 word name for this reader pair, like a duo band name",
          "archetypeEmoji": "one emoji",
          "tagline": "one-line subtitle for the archetype",
          "insights": [{"title": "2-4 word punchy header", "body": "one specific sentence about their combined taste"}, x3],
          "recsForA": [{"title": "...", "author": "...", "reason": "one punchy line on why A should steal this from B's shelf"}, x3 — MUST be books from B's list that A has not read],
          "recsForB": [same, from A's shelf, x3],
          "freshPicks": [{"title": "...", "author": "...", "reason": "why this fits both"}, x2 — real books NEITHER has read, to read together]
        }
        """
        let user = """
        Reader A is \(nameA). Reader B is \(nameB).
        Compatibility score (already computed): \(stats.score)% — verdict "\(stats.verdict)".
        Books BOTH have read: \(stats.sharedBooks.prefix(10).map(\.title).joined(separator: "; ")).
        Shared genres: \(stats.sharedGenres.joined(separator: ", ")).
        \(nameA) uniquely reads: \((stats.distinctGenres[uidA] ?? []).joined(separator: ", ")).
        \(nameB) uniquely reads: \((stats.distinctGenres[uidB] ?? []).joined(separator: ", ")).

        \(nameA)'s shelf (best first):
        \(shelfSummary(libraryA))

        \(nameB)'s shelf (best first):
        \(shelfSummary(libraryB))
        """
        guard let text = try? await ClaudeService.shared.sendMessage(system: system, userMessage: user, maxTokens: 1600) else {
            return nil
        }
        return parseAIContent(text, uidA: uidA, uidB: uidB)
    }

    private func shelfSummary(_ library: [UserBook]) -> String {
        let reads = library.filter { $0.status == .read }
            .sorted { (affinity(rating: $0.rating, tier: $0.tier) ?? -2) > (affinity(rating: $1.rating, tier: $1.tier) ?? -2) }
            .prefix(35)
            .compactMap { entry -> String? in
                guard let book = entry.book else { return nil }
                var line = "\(book.title) — \(book.author)"
                if let r = entry.rating { line += " (\(Theme.formatRatingOutOfTen(r))/10)" }
                else if let t = entry.tier { line += " (\(t)-tier)" }
                return line
            }
        let queue = library.filter { $0.status == .wantToRead }
            .prefix(8)
            .compactMap { $0.book?.title }
        var summary = reads.joined(separator: "\n")
        if !queue.isEmpty {
            summary += "\nQueued next: \(queue.joined(separator: "; "))"
        }
        return summary
    }

    private func parseAIContent(_ text: String, uidA: String, uidB: String) -> AIContent? {
        // Tolerate fences or prose around the object: slice first "{" to last "}".
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}") else { return nil }
        let jsonText = String(text[start...end])
        guard let data = jsonText.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

        func recs(_ key: String, sourceUid: String) -> [BookBlend.Rec] {
            ((obj[key] as? [[String: Any]]) ?? []).compactMap { r in
                guard let title = r["title"] as? String, let author = r["author"] as? String else { return nil }
                return BookBlend.Rec(
                    title: title,
                    author: author,
                    bookId: nil,
                    coverURL: nil,
                    reason: (r["reason"] as? String) ?? "",
                    sourceUid: sourceUid
                )
            }
        }
        let insights: [BookBlend.Insight] = ((obj["insights"] as? [[String: Any]]) ?? []).compactMap { i in
            guard let title = i["title"] as? String, let body = i["body"] as? String else { return nil }
            return BookBlend.Insight(title: title, body: body)
        }
        let freshPicks: [BookBlend.Rec] = ((obj["freshPicks"] as? [[String: Any]]) ?? []).compactMap { r in
            guard let title = r["title"] as? String, let author = r["author"] as? String else { return nil }
            return BookBlend.Rec(title: title, author: author, bookId: nil, coverURL: nil, reason: (r["reason"] as? String) ?? "", sourceUid: nil)
        }
        guard let archetype = obj["archetype"] as? String else { return nil }
        return AIContent(
            archetype: archetype,
            archetypeEmoji: (obj["archetypeEmoji"] as? String) ?? "📚",
            tagline: (obj["tagline"] as? String) ?? "",
            insights: insights,
            recs: [
                uidA: recs("recsForA", sourceUid: uidB),
                uidB: recs("recsForB", sourceUid: uidA),
            ],
            freshPicks: Array(freshPicks.prefix(2))
        )
    }

    // MARK: - Cover hydration

    /// AI recs come back as title+author; match them to the source shelf for real
    /// bookId/cover. Unmatched recs are kept (title-only placeholder covers render fine).
    private func hydrate(recs: [BookBlend.Rec], fromShelfOf source: [UserBook], sourceUid: String) -> [BookBlend.Rec] {
        var byKey: [String: Book] = [:]
        for entry in source {
            if let book = entry.book, let key = normalizedKey(book) { byKey[key] = book }
        }
        return recs.map { rec in
            guard rec.coverURL == nil || rec.coverURL?.isEmpty == true else { return rec }
            var rec = rec
            let probe = Book(id: "", title: rec.title, author: rec.author, coverURL: "", pageCount: nil, publishedDate: nil, description: nil, genres: [])
            if let key = normalizedKey(probe), let book = byKey[key] {
                rec.bookId = book.id
                rec.coverURL = book.coverURL
                rec.sourceUid = sourceUid
            }
            return rec
        }
    }

    /// Fresh picks exist nowhere in either library — best-effort Google Books lookup for covers.
    private func hydrateFreshPicks(_ picks: [BookBlend.Rec]) async -> [BookBlend.Rec] {
        var hydrated: [BookBlend.Rec] = []
        for pick in picks.prefix(2) {
            var pick = pick
            if let results = try? await GoogleBooksService.shared.search(query: "\(pick.title) \(pick.author)"),
               let match = results.first {
                pick.bookId = match.id
                pick.coverURL = match.coverURL
            }
            hydrated.append(pick)
        }
        return hydrated
    }
}
