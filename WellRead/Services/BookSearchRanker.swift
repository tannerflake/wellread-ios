//
//  BookSearchRanker.swift
//  WellRead
//
//  Ranks and de-duplicates Google Books search results so the edition a user
//  expects lands at the top. Google's raw relevance order surfaces reissues
//  ("10th Anniversary Edition"), foreign-language editions, and duplicate
//  entries of the same work; this re-scores results on query match, popularity
//  (ratingsCount), metadata completeness, and edition noise, then collapses
//  editions of the same work down to the best one.
//

import Foundation

/// Per-result signals from the search payload that `Book` doesn't carry.
struct BookSearchSignals {
    var ratingsCount: Int?
    var averageRating: Double?
    var language: String?
}

enum BookSearchRanker {

    struct Candidate {
        let book: Book
        let signals: BookSearchSignals
    }

    /// Ranks candidates against the query. When `deduplicate` is true, editions
    /// of the same work (same core title + primary author) collapse to the
    /// highest-scored one. `libraryAuthors` are author names already in the
    /// user's library; their books get a small personalization boost.
    static func rank(
        _ candidates: [Candidate],
        query: String,
        deduplicate: Bool = true,
        libraryAuthors: Set<String> = []
    ) -> [Book] {
        let normQuery = normalize(query)
        guard !normQuery.isEmpty else { return candidates.map(\.book) }
        let queryTokens = normQuery.split(separator: " ").map(String.init)
        let deviceLanguage = Locale.current.language.languageCode?.identifier.lowercased()
        let normalizedLibraryAuthors = Set(libraryAuthors.map(normalize).filter { !$0.isEmpty })

        // Google's own relevance order breaks score ties (stable sort by index).
        let scored = candidates.enumerated()
            .map { (index: $0.offset, candidate: $0.element, score: score(
                $0.element,
                normQuery: normQuery,
                queryTokens: queryTokens,
                deviceLanguage: deviceLanguage,
                libraryAuthors: normalizedLibraryAuthors
            )) }
            .sorted { $0.score != $1.score ? $0.score > $1.score : $0.index < $1.index }

        guard deduplicate else { return scored.map(\.candidate.book) }
        var seenWorks = Set<String>()
        return scored.compactMap { entry in
            let key = workKey(title: entry.candidate.book.title, author: entry.candidate.book.author)
            return seenWorks.insert(key).inserted ? entry.candidate.book : nil
        }
    }

    // MARK: - Scoring

    private static func score(
        _ candidate: Candidate,
        normQuery: String,
        queryTokens: [String],
        deviceLanguage: String?,
        libraryAuthors: Set<String>
    ) -> Double {
        let book = candidate.book
        let rawMainTitle = book.title.split(separator: ":", maxSplits: 1).first.map(String.init) ?? book.title
        let normTitle = normalize(book.title)
        let normMainTitle = normalize(rawMainTitle)
        let normAuthor = normalize(book.author)
        let titleTokens = normTitle.split(separator: " ").map(String.init)
        let authorTokens = normAuthor.split(separator: " ").map(String.init)

        var score = 0.0

        // Title match: exact > prefix (supports search-as-you-type) > token coverage.
        if normTitle == normQuery || normMainTitle == normQuery {
            score += 120
        } else if normMainTitle.hasPrefix(normQuery) || normQuery.hasPrefix(normMainTitle) {
            score += 80
        }
        var titleCoverage = 0.0
        var authorCoverage = 0.0
        var tokensFoundAnywhere = 0
        for (i, queryToken) in queryTokens.enumerated() {
            // The token still being typed may be a prefix of a full word.
            let allowPrefix = i == queryTokens.count - 1
            let inTitle = bestTokenMatch(queryToken, in: titleTokens, allowPrefix: allowPrefix)
            let inAuthor = bestTokenMatch(queryToken, in: authorTokens, allowPrefix: allowPrefix)
            titleCoverage += inTitle
            authorCoverage += inAuthor
            if max(inTitle, inAuthor) >= 0.7 { tokensFoundAnywhere += 1 }
        }
        let queryTokenCount = Double(queryTokens.count)
        score += 60 * titleCoverage / queryTokenCount
        score += 40 * authorCoverage / queryTokenCount
        // Every query word accounted for across title+author (e.g. "hobbit tolkien").
        if tokensFoundAnywhere == queryTokens.count { score += 25 }

        // Popularity: ratingsCount separates the canonical edition from catalog noise.
        let ratings = candidate.signals.ratingsCount ?? 0
        score += min(36, log10(Double(ratings) + 1) * 12)

        // Metadata completeness correlates strongly with "real" editions.
        if !book.coverURL.isEmpty { score += 12 }
        if book.isbn != nil { score += 8 }
        if !(book.description ?? "").isEmpty { score += 4 }

        // Language: soft preference for the device language, not a hard filter.
        if let lang = candidate.signals.language?.lowercased(), let device = deviceLanguage {
            score += lang == device ? 8 : -15
        }

        // Reissue noise sinks below the standard edition unless explicitly searched for.
        if containsEditionNoise(normTitle) && !containsEditionNoise(normQuery) {
            score -= 18
        }

        // Slight preference for concise titles over keyword-stuffed catalog entries.
        let extraTokens = titleTokens.count - queryTokens.count - 2
        if extraTokens > 0 { score -= min(12, Double(extraTokens) * 1.5) }

        // Personalization: the user already reads this author.
        if !libraryAuthors.isEmpty {
            let bookAuthors = book.author.split(separator: ",").map { normalize(String($0)) }
            if bookAuthors.contains(where: { libraryAuthors.contains($0) }) { score += 10 }
        }

        return score
    }

    /// 1.0 exact token, 0.9 prefix (last query token only), 0.7 fuzzy (typo), 0 none.
    private static func bestTokenMatch(_ queryToken: String, in tokens: [String], allowPrefix: Bool) -> Double {
        var best = 0.0
        for token in tokens {
            if token == queryToken { return 1.0 }
            if allowPrefix, queryToken.count >= 2, token.hasPrefix(queryToken) {
                best = max(best, 0.9)
            } else if queryToken.count >= 5 {
                let threshold = queryToken.count >= 8 ? 2 : 1
                if abs(token.count - queryToken.count) <= threshold,
                   levenshtein(queryToken, token, limit: threshold) <= threshold {
                    best = max(best, 0.7)
                }
            }
        }
        return best
    }

    // MARK: - Deduplication

    /// Editions of the same work share a key: core title (parentheticals and
    /// edition phrases stripped, subtitle dropped) + primary author. Digits in
    /// the subtitle (volume/part numbers) stay in the key so "Vol 1" and
    /// "Vol 2" never merge.
    static func workKey(title: String, author: String) -> String {
        var raw = title
        raw = raw.replacingOccurrences(of: #"\([^)]*\)|\[[^\]]*\]"#, with: " ", options: .regularExpression)
        let parts = raw.split(separator: ":", maxSplits: 1)
        var main = parts.first.map(String.init) ?? raw
        let subtitle = parts.count > 1 ? String(parts[1]) : ""
        main = stripEditionPhrases(from: main)
        var norm = normalize(main)
        // Leading articles differ between catalog entries of the same work.
        for article in ["the ", "a ", "an "] where norm.hasPrefix(article) {
            norm = String(norm.dropFirst(article.count))
            break
        }
        let subtitleDigits = subtitle.filter(\.isNumber)
        // Surname only: catalogs list the same author as "J.R.R. Tolkien",
        // "J. R. R. Tolkien", and "John Ronald Reuel Tolkien".
        let primaryAuthor = normalize(String(author.split(separator: ",").first ?? ""))
        let surname = primaryAuthor.split(separator: " ").last.map(String.init) ?? primaryAuthor
        return norm + "|" + subtitleDigits + "|" + surname
    }

    private static let editionPhrasePatterns: [String] = [
        #"(\d+(st|nd|rd|th)\s+)?anniversary(\s+edition)?"#,
        #"deluxe(\s+edition)?"#,
        #"collector'?s?(\s+edition)?"#,
        #"special\s+edition"#,
        #"illustrated(\s+edition)?"#,
        #"annotated(\s+edition)?"#,
        #"commemorative(\s+edition)?"#,
        #"large\s+print"#,
        #"(movie|tv|media)\s+tie[- ]?in(\s+edition)?"#,
        #"unabridged"#,
        #"abridged"#,
        #"box(ed)?\s+set"#
    ]

    private static func stripEditionPhrases(from title: String) -> String {
        var result = title
        for pattern in editionPhrasePatterns {
            result = result.replacingOccurrences(
                of: pattern, with: " ", options: [.regularExpression, .caseInsensitive]
            )
        }
        return result
    }

    private static let editionNoiseTerms: [String] = [
        "anniversary", "deluxe", "collectors", "special edition", "illustrated",
        "annotated", "commemorative", "large print", "tie in", "unabridged",
        "abridged", "boxed set", "box set"
    ]

    private static func containsEditionNoise(_ normalized: String) -> Bool {
        editionNoiseTerms.contains { normalized.contains($0) }
    }

    // MARK: - Text utilities

    /// Lowercased, diacritics folded, apostrophes removed, all other
    /// punctuation collapsed to single spaces.
    static func normalize(_ s: String) -> String {
        let folded = s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "\u{2019}", with: "")
        let mapped = folded.map { $0.isLetter || $0.isNumber ? $0 : " " }
        return String(mapped).split(separator: " ").joined(separator: " ")
    }

    /// Edit distance with early exit once every path exceeds `limit`.
    private static func levenshtein(_ a: String, _ b: String, limit: Int) -> Int {
        let aChars = Array(a), bChars = Array(b)
        if abs(aChars.count - bChars.count) > limit { return limit + 1 }
        var previous = Array(0...bChars.count)
        var current = [Int](repeating: 0, count: bChars.count + 1)
        for i in 1...aChars.count {
            current[0] = i
            var rowMin = current[0]
            for j in 1...bChars.count {
                let cost = aChars[i - 1] == bChars[j - 1] ? 0 : 1
                current[j] = Swift.min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
                rowMin = Swift.min(rowMin, current[j])
            }
            if rowMin > limit { return limit + 1 }
            swap(&previous, &current)
        }
        return previous[bChars.count]
    }
}
