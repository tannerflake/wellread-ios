//
//  MatchScoreService.swift
//  Spine
//
//  Netflix-style "% match" for a book, computed on-device from the user's
//  library (ratings + tiers → genre/author affinities), their interest tags,
//  and followed readers' ratings of the book — each friend weighted by how
//  closely their taste has agreed with the user's on books they've both rated.
//  Deterministic weighted-points scorer in the BookSearchRanker style.
//

import Foundation

final class MatchScoreService {
    static let shared = MatchScoreService()

    /// Trust weight per followed reader (uid → 0.25…2.0), session-scoped.
    private var trustCache: [String: Double] = [:]
    private let queue = DispatchQueue(label: "com.wellread.matchscore.cache")

    private init() {}

    // MARK: - Public API

    /// Percentage match (40–99) for `book`, or `nil` when there's no taste
    /// signal to score against (cold start: no rated/tiered reads, no interest
    /// tags, no followed readers of this book).
    ///
    /// - Parameters:
    ///   - profileTags: AI profile tags for the book (canonical Tags.csv strings); may be empty.
    ///   - library: the current user's full library (`AppState.userBooks`).
    ///   - friendEntries: followed readers' read rows for this book (deduped, self excluded).
    func matchScore(
        for book: Book,
        profileTags: [String],
        library: [UserBook],
        user: User?,
        friendEntries: [UserBook]
    ) async -> Int? {
        let history = library.filter { $0.bookId != book.id && $0.status == .read }
        let ratedHistory = history.filter { affinity(of: $0) != nil }
        let interestTags = Set(
            ((user?.readingInterestTags ?? []) + (user?.discoverCriteria.tags ?? []))
                .map { $0.lowercased() }
        )

        guard ratedHistory.count >= 3 || !interestTags.isEmpty || !friendEntries.isEmpty else {
            return nil
        }

        var points = 60.0
        var hasSignal = false

        // Interest-tag overlap: two or more shared tags is a full-marks match.
        if !interestTags.isEmpty && !profileTags.isEmpty {
            let matches = profileTags.filter { interestTags.contains($0.lowercased()) }.count
            if matches > 0 { hasSignal = true }
            points += min(1.0, Double(matches) / 2.0) * 16.0
        }

        // Genre affinity from the library.
        let genreAffinities = genreAffinityMap(history: ratedHistory)
        let candidateTokens = genreTokens(book.genres)
        var genreWeight = 0.0
        var genreSum = 0.0
        for token in candidateTokens {
            guard let (sum, count) = genreAffinities[token] else { continue }
            let weight = min(Double(count), 4.0) / 4.0
            genreSum += (sum / Double(count)) * weight
            genreWeight += weight
        }
        if genreWeight > 0 {
            hasSignal = true
            let g = genreSum / genreWeight
            points += g * (g >= 0 ? 14.0 : 10.0) * min(1.0, genreWeight)
        }

        // Author affinity: the user has read (and rated) this author before.
        let candidateAuthors = authorTokens(book.author)
        var authorValues: [Double] = []
        for entry in ratedHistory {
            guard let entryBook = entry.book, let a = affinity(of: entry) else { continue }
            if !authorTokens(entryBook.author).isDisjoint(with: candidateAuthors) {
                authorValues.append(a)
            }
        }
        if !authorValues.isEmpty {
            hasSignal = true
            let mean = authorValues.reduce(0, +) / Double(authorValues.count)
            let confidence = 0.5 + 0.5 * min(Double(authorValues.count), 3.0) / 3.0
            points += mean * 10.0 * confidence
        }

        // Followed readers' verdicts, trust-weighted by taste agreement.
        let friends = Array(friendEntries.prefix(8))
        var trustSum = 0.0
        var verdictSum = 0.0
        for entry in friends {
            guard let a = affinity(of: entry) else { continue }
            let trust = await trustWeight(friendUid: entry.userId, myHistory: ratedHistory)
            verdictSum += a * trust
            trustSum += trust
        }
        if trustSum > 0 {
            hasSignal = true
            let n = Double(friends.count)
            points += (verdictSum / trustSum) * 15.0 * (n / (n + 2.0))
        }

        guard hasSignal else { return nil }
        return Int(min(99.0, max(40.0, points)).rounded())
    }

    // MARK: - Trust (taste similarity with a followed reader)

    /// 0.25…2.0 multiplier for a friend's verdict: 1.0 = neutral (no shared
    /// rated books), >1 = their past ratings agreed with the user's, <1 = clashed.
    private func trustWeight(friendUid: String, myHistory: [UserBook]) async -> Double {
        if let cached = queue.sync(execute: { trustCache[friendUid] }) { return cached }

        let friendRows = await UserBookRepository().fetchReadEntriesLite(userId: friendUid)
        var mineByBook: [String: Double] = [:]
        for entry in myHistory {
            if let a = affinity(of: entry) { mineByBook[entry.bookId] = a }
        }

        var agreements: [Double] = []
        for row in friendRows {
            guard let mine = mineByBook[row.bookId], let theirs = affinity(of: row) else { continue }
            agreements.append(1.0 - abs(mine - theirs) / 2.0)
        }

        let trust: Double
        if agreements.isEmpty {
            trust = 1.0
        } else {
            let n = Double(agreements.count)
            let similarity = ((agreements.reduce(0, +) / n) - 0.5) * 2.0 * (n / (n + 2.0))
            trust = min(2.0, max(0.25, 1.0 + similarity))
        }
        queue.sync { trustCache[friendUid] = trust }
        return trust
    }

    // MARK: - Signals

    /// How much the reader liked a book, in −1…+1. Rating (0–10) wins; tier is
    /// the fallback for rated-by-vibe rows. `nil` when the row carries neither.
    private func affinity(of entry: UserBook) -> Double? {
        if let rating = entry.rating {
            return min(1.0, max(-1.0, (rating - 5.5) / 4.5))
        }
        switch entry.tier {
        case "S": return 1.0
        case "A": return 0.6
        case "B": return 0.3
        case "C": return 0.0
        case "D": return -0.5
        case "F": return -1.0
        default: return nil
        }
    }

    private func genreAffinityMap(history: [UserBook]) -> [String: (sum: Double, count: Int)] {
        var map: [String: (sum: Double, count: Int)] = [:]
        for entry in history {
            guard let entryBook = entry.book, let a = affinity(of: entry) else { continue }
            for token in genreTokens(entryBook.genres) {
                let existing = map[token] ?? (0, 0)
                map[token] = (existing.sum + a, existing.count + 1)
            }
        }
        return map
    }

    /// Google/publisher categories arrive as "Fiction / Thrillers / Suspense" —
    /// split into comparable lowercase tokens, dropping the meaningless "general".
    private func genreTokens(_ genres: [String]) -> Set<String> {
        var tokens = Set<String>()
        for genre in genres {
            for part in genre.split(separator: "/") {
                let token = part.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if !token.isEmpty && token != "general" { tokens.insert(token) }
            }
        }
        return tokens
    }

    private func authorTokens(_ author: String) -> Set<String> {
        Set(
            author.split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty }
        )
    }
}
