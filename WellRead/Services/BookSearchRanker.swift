//
//  BookSearchRanker.swift
//  WellRead
//
//  Ranks and de-duplicates Google Books search results so the edition a user
//  expects lands at the top. Google's raw relevance order surfaces reissues
//  ("10th Anniversary Edition"), foreign-language editions, knockoff listings
//  with publisher-as-author, and duplicate entries of the same work; this
//  re-scores results on query match, popularity (ratingsCount, when Google
//  returns it), metadata completeness, and edition noise, then collapses
//  editions of the same work down to the best one, backfilling missing
//  metadata (cover, ISBN, description) from sibling editions.
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
    /// `popularKeys` are `popularityKey` values of works 2+ SPINE members have
    /// logged (see `BookPopularityService`); those get a large boost — a book
    /// real users shelved beats any catalog-noise listing.
    static func rank(
        _ candidates: [Candidate],
        query: String,
        deduplicate: Bool = true,
        libraryAuthors: Set<String> = [],
        popularKeys: Set<String> = []
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
                libraryAuthors: normalizedLibraryAuthors,
                popularKeys: popularKeys
            )) }
            .sorted { $0.score != $1.score ? $0.score > $1.score : $0.index < $1.index }

        guard deduplicate else { return scored.map(\.candidate.book) }
        // Collapse each work to its best-scored edition, but backfill metadata the
        // winner lacks from sibling editions: Google often lists the canonical
        // edition without a cover while a reissue of the same work has one.
        var order: [String] = []
        var winners: [String: Book] = [:]
        for entry in scored {
            let key = workKey(title: entry.candidate.book.title, author: entry.candidate.book.author)
            if var winner = winners[key] {
                let sibling = entry.candidate.book
                if winner.coverURL.isEmpty && !sibling.coverURL.isEmpty {
                    winner.coverURL = sibling.coverURL
                    winner.fallbackCoverURLs = sibling.fallbackCoverURLs
                }
                if winner.isbn == nil { winner.isbn = sibling.isbn }
                if (winner.description ?? "").isEmpty { winner.description = sibling.description }
                winners[key] = winner
            } else {
                order.append(key)
                winners[key] = entry.candidate.book
            }
        }
        return order.compactMap { winners[$0] }
    }

    // MARK: - Scoring

    private static func score(
        _ candidate: Candidate,
        normQuery: String,
        queryTokens: [String],
        deviceLanguage: String?,
        libraryAuthors: Set<String>,
        popularKeys: Set<String>
    ) -> Double {
        let book = candidate.book
        let rawMainTitle = book.title.split(separator: ":", maxSplits: 1).first.map(String.init) ?? book.title
        let normTitle = normalize(book.title)
        let normMainTitle = normalize(rawMainTitle)
        let normAuthor = normalize(book.author)
        let titleTokens = normTitle.split(separator: " ").map(String.init)
        let authorTokens = normAuthor.split(separator: " ").map(String.init)

        var score = 0.0

        // Title match: exact > main-title exact > prefix (supports search-as-you-type)
        // > token coverage. A subtitle-only exact match ranks below the whole-title
        // one so "Sapiens" beats "Sapiens: A Graphic History" for query "sapiens".
        if normTitle == normQuery {
            score += 120
        } else if normMainTitle == normQuery {
            score += 100
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
        // Records with no explicit language (common from ISBNdb) fall back to the
        // language implied by the ISBN registration group — a 978-602 ISBN is an
        // Indonesian-market edition even when the record and title say nothing.
        let language = candidate.signals.language ?? impliedLanguageCode(fromISBN: book.isbn)
        if let lang = language?.lowercased(), let device = deviceLanguage {
            score += lang == device ? 8 : -15
        }

        // Reissue noise sinks below the standard edition unless explicitly searched for.
        if containsEditionNoise(normTitle) && !containsEditionNoise(normQuery) {
            score -= 18
        }

        // Derivative works (graphic adaptations, workbooks, journals) rank below
        // the original unless the query asks for them.
        if containsDerivativeMarker(normTitle) && !containsDerivativeMarker(normQuery) {
            score -= 18
        }

        // Knockoff listings credit a publisher-sounding name ("University Press",
        // "Readtrepreneur Publishing") as the author. Sink them hard: they only
        // matter when nothing legitimate matches.
        if authorLooksLikePublisher(book.author) {
            score -= 60
        } else if normAuthor.isEmpty || normAuthor == "unknown" {
            score -= 20
        }

        // Slight preference for concise titles over keyword-stuffed catalog entries.
        let extraTokens = titleTokens.count - queryTokens.count - 2
        if extraTokens > 0 { score -= min(12, Double(extraTokens) * 1.5) }

        // Personalization: the user already reads this author.
        if !libraryAuthors.isEmpty {
            let bookAuthors = book.author.split(separator: ",").map { normalize(String($0)) }
            if bookAuthors.contains(where: { libraryAuthors.contains($0) }) { score += 10 }
        }

        // Community signal: 2+ SPINE members shelved this work. Big enough to
        // dominate metadata/edition noise, small enough that an exact title
        // match on something else still wins.
        if !popularKeys.isEmpty, popularKeys.contains(popularityKey(title: book.title, author: book.author)) {
            score += 30
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
    /// "Vol 2" never merge, and derivative markers ("A Graphic History") stay
    /// so adaptations never merge with the original work.
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
        let normSubtitle = normalize(subtitle)
        let subtitleMarkers = derivativeMarkers.filter { normSubtitle.contains($0) }.joined(separator: " ")
        let subtitleDigits = subtitle.filter(\.isNumber)
        // Surname only: catalogs list the same author as "J.R.R. Tolkien",
        // "J. R. R. Tolkien", and "John Ronald Reuel Tolkien".
        let primaryAuthor = normalize(String(author.split(separator: ",").first ?? ""))
        let surname = primaryAuthor.split(separator: " ").last.map(String.init) ?? primaryAuthor
        return norm + "|" + subtitleMarkers + subtitleDigits + "|" + surname
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

    // MARK: - Junk listings

    /// Catalog listings that aren't a real standalone edition of a work: multi-book
    /// collection sets, study guides / summaries, and foreign-language reprints.
    /// Patterns run against *normalized* text (lowercased, punctuation collapsed
    /// to spaces), for both the title and the query.
    private static let junkListingPatterns: [String] = [
        // Multi-book bundles: "5 Books Collection Set", "3-Book Box Set", "2 in 1".
        #"\d+\s+(books?|volumes?|novels?)\s+(collection|set|box|boxed|bundle)"#,
        #"\bbooks?\s+(collection|set|bundle)\b"#,
        #"\bcollection\s+set\b"#,
        #"\bbox(ed)?\s+set\b"#,
        #"\b\d+\s+in\s+1\b"#,
        #"\b(double|dual)\s+edition\b"#,
        // Study-guide / summary knockoffs, and free promotional excerpt
        // collections ("Brandon Sanderson Sampler") that author searches surface.
        #"summar"#,
        #"\bsampler\b"#,
        #"\bstudy\s+guide\b"#,
        #"sparknotes"#,
        #"cliffsnotes"#,
        #"\bbook\s+review\b"#,
        #"\banalysis\s+of\b"#,
        #"\breading\s+guide\b"#,
        #"\bconversation\s+starters\b"#,
        #"\bkey\s+takeaways\b"#,
        // Foreign-language reprints labeled in English: "(French Edition)".
        #"\b(french|spanish|german|italian|portuguese|dutch|russian|chinese|japanese|korean|polish|romanian|czech|swedish|norwegian|danish|finnish|turkish|arabic|hindi|thai|vietnamese|indonesian|greek|hebrew|ukrainian|hungarian|bulgarian|croatian|serbian|slovak|persian|urdu|bengali|multilingual|bilingual)\s+(edition|version)\b"#
    ]

    /// True when the title is a junk listing the query didn't explicitly ask for.
    /// A query that itself matches any junk pattern disables the filter entirely —
    /// the user is deliberately hunting that kind of listing. Used as a hard filter
    /// in the search chain (the "show all editions" fallback also bypasses it, so
    /// nothing becomes unfindable).
    static func isJunkListing(title: String, query: String) -> Bool {
        let normQuery = normalize(query)
        let matchesAny: (String) -> Bool = { text in
            junkListingPatterns.contains { text.range(of: $0, options: .regularExpression) != nil }
        }
        if matchesAny(normQuery) { return false }
        return matchesAny(normalize(title))
    }

    /// Words marking a distinct derivative work rather than another edition:
    /// "Sapiens: A Graphic History" is not an edition of "Sapiens".
    private static let derivativeMarkers: [String] = [
        "graphic", "workbook", "journal", "coloring", "screenplay", "cookbook", "companion"
    ]

    private static func containsDerivativeMarker(_ normalized: String) -> Bool {
        derivativeMarkers.contains { normalized.contains($0) }
    }

    /// Publisher names credited as the author are a strong knockoff signal
    /// ("University Press", "Summareads Media"). Matches whole words only, so
    /// real authors with e.g. surname "Pressfield" are unaffected.
    private static let publisherAuthorTerms: Set<String> = [
        "press", "publishing", "publishers", "publication", "publications",
        "media", "summaries", "library", "editions", "print", "books"
    ]

    private static func authorLooksLikePublisher(_ author: String) -> Bool {
        author.split(separator: ",").contains { segment in
            normalize(String(segment)).split(separator: " ")
                .contains { publisherAuthorTerms.contains(String($0)) }
        }
    }

    // MARK: - Popularity key

    /// Cross-edition identity for the community-popularity signal: normalized
    /// main title (parentheticals stripped, subtitle dropped, leading article
    /// removed) + "|" + primary author's surname. Coarser than `workKey` on
    /// purpose — it must be reproduced exactly by the Cloud Functions trigger
    /// that maintains `bookStats` (see functions/src/index.ts `popularityKey`);
    /// keep the two implementations in lockstep. Empty when the title
    /// normalizes to nothing.
    static func popularityKey(title: String, author: String) -> String {
        var raw = title.replacingOccurrences(of: #"\([^)]*\)|\[[^\]]*\]"#, with: " ", options: .regularExpression)
        raw = raw.split(separator: ":", maxSplits: 1).first.map(String.init) ?? raw
        var t = normalize(raw)
        for article in ["the ", "a ", "an "] where t.hasPrefix(article) {
            t = String(t.dropFirst(article.count))
            break
        }
        guard !t.isEmpty else { return "" }
        let primary = normalize(String(author.split(separator: ",").first ?? ""))
        let surname = primary.split(separator: " ").last.map(String.init) ?? ""
        return t + "|" + surname
    }

    // MARK: - ISBN language inference

    /// ISO 639-1 language implied by the ISBN's registration group (the digits
    /// after the 978/979 prefix). Catalog records — ISBNdb especially — often
    /// carry no language field, but the registration group still identifies the
    /// publishing market: 978-602 is Indonesia, so 9786021606810 is almost
    /// certainly an Indonesian translation even when the title is left in
    /// English. Groups covering multilingual or heavily-English markets (India,
    /// Philippines, Singapore, international agencies, …) are omitted and infer
    /// nothing. ISBN-10s share the 978 group space.
    static func impliedLanguageCode(fromISBN isbn: String?) -> String? {
        guard let isbn else { return nil }
        let digits = isbn.filter(\.isNumber)
        let group: Substring
        let table: [String: String]
        if digits.count == 13, digits.hasPrefix("978") {
            group = digits.dropFirst(3)
            table = isbn978GroupLanguages
        } else if digits.count == 13, digits.hasPrefix("979") {
            group = digits.dropFirst(3)
            table = isbn979GroupLanguages
        } else if digits.count == 10 {
            group = Substring(digits)
            table = isbn978GroupLanguages
        } else {
            return nil
        }
        // Registration groups have variable length; in the 978 space 1-digit
        // (0–7), 2-digit (80–94), and 3-digit (600s, 950s–980s) ranges don't
        // overlap, so the first table hit is the group.
        for length in 1...3 where group.count >= length {
            if let lang = table[String(group.prefix(length))] { return lang }
        }
        return nil
    }

    private static let isbn978GroupLanguages: [String: String] = [
        "0": "en", "1": "en",
        "2": "fr", "3": "de", "4": "ja", "5": "ru", "7": "zh",
        "80": "cs", "82": "no", "83": "pl", "84": "es", "85": "pt", "87": "da",
        "88": "it", "89": "ko", "90": "nl", "91": "sv", "94": "nl",
        "600": "fa", "602": "id", "603": "ar", "604": "vi", "605": "tr",
        "606": "ro", "607": "es", "608": "mk", "609": "lt", "611": "th",
        "612": "es", "614": "ar", "615": "hu", "616": "th", "617": "uk",
        "618": "el", "619": "bg", "622": "fa", "623": "id", "625": "tr",
        "626": "zh", "628": "es",
        "950": "es", "951": "fi", "952": "fi", "953": "hr", "954": "bg",
        "956": "es", "957": "zh", "958": "es", "959": "es", "960": "el",
        "961": "sl", "963": "hu", "964": "fa", "965": "he", "966": "uk",
        "968": "es", "970": "es", "972": "pt", "973": "ro", "974": "th",
        "975": "tr", "977": "ar", "980": "es", "986": "zh", "987": "es",
        "989": "pt"
    ]

    private static let isbn979GroupLanguages: [String: String] = [
        "8": "en", "10": "fr", "11": "ko", "12": "it"
    ]

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
