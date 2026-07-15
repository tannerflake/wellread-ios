//
//  BookCoverView.swift
//  WellRead
//
//  Loads cover from primary URL; on failure tries fallback URLs. Uses in-memory + disk cache so covers persist across app launches and re-renders show instantly.
//

import SwiftUI
import UIKit
import CoreGraphics
import CryptoKit

/// Outcome of one cover URL attempt — lets the loader distinguish "this book has no
/// cover here" (move on, maybe record a definitive failure) from "the network hiccuped"
/// (don't poison the persistent store) and "Open Library is rate-limiting us" (back off).
enum CoverFetchResult {
    case success(UIImage)
    /// Definitive: 404, non-cover placeholder image, or unparseable data. Never retried this session.
    case missing
    /// Open Library 403 — rate limit tripped; skip OL for a cooldown window and keep going.
    case rateLimited
    /// Timeout / connectivity / 5xx. Worth retrying later; not recorded as a hard failure.
    case transient
}

// Memory + disk cache for cover images. Disk cache persists across app launches so covers don't re-download every time.
final class CoverImageCache {
    static let shared = CoverImageCache()

    /// Max seconds for each URL attempt (network + decode). `FallbackCoverImage` also enforces a **total** budget per cover.
    static let loadTimeoutSeconds: TimeInterval = 4

    private let cache = NSCache<NSString, UIImage>()
    private let session: URLSession
    private let fileManager = FileManager.default
    private let diskQueue = DispatchQueue(label: "com.wellread.covercache.disk")

    /// Open Library rate limit (100 req / 5 min per IP for ISBN-keyed lookups): after a
    /// 403, skip OL URLs until this date so the chain falls through to Google instantly.
    private var openLibraryBackoffUntil: Date?
    /// URLs that definitively 404'd / returned placeholders this session — skip instantly on re-scroll.
    private var knownBadURLs = Set<String>()
    private let stateLock = NSLock()

    private init() {
        // Large libraries: avoid evicting hot covers when scrolling / tab switching.
        cache.countLimit = 800
        cache.totalCostLimit = 100 * 1024 * 1024 // ~100 MB decoded bitmap budget
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = Self.loadTimeoutSeconds
        config.timeoutIntervalForResource = Self.loadTimeoutSeconds
        config.waitsForConnectivity = false
        session = URLSession(configuration: config)
    }

    var isOpenLibraryBackedOff: Bool {
        stateLock.lock(); defer { stateLock.unlock() }
        guard let until = openLibraryBackoffUntil else { return false }
        return until > Date()
    }

    private func noteOpenLibraryRateLimited() {
        stateLock.lock(); defer { stateLock.unlock() }
        openLibraryBackoffUntil = Date().addingTimeInterval(5 * 60)
    }

    private func isKnownBad(_ url: URL) -> Bool {
        stateLock.lock(); defer { stateLock.unlock() }
        return knownBadURLs.contains(url.absoluteString)
    }

    private func markKnownBad(_ url: URL) {
        stateLock.lock(); defer { stateLock.unlock() }
        knownBadURLs.insert(url.absoluteString)
    }

    private func diskCacheDirectory() -> URL? {
        guard let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let dir = caches.appendingPathComponent("WellRead", isDirectory: true).appendingPathComponent("CoverCache", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func diskFileURL(for url: URL) -> URL? {
        let key = url.absoluteString
        let hash = SHA256.hash(data: Data(key.utf8))
        let hex = hash.map { String(format: "%02x", $0) }.joined()
        return diskCacheDirectory()?.appendingPathComponent(hex + ".dat")
    }

    /// Reject Google Books "image not available" placeholder so we try the next URL or show title pseudo-cover. Real covers are typically ~11KB+ and 400px+.
    private func isGoogleBooksPlaceholder(data: Data, image: UIImage, url: URL) -> Bool {
        guard url.absoluteString.contains("books.google.com") else { return false }
        if data.count < 12000 { return true }
        let w = image.size.width * (image.scale > 0 ? image.scale : 1)
        let h = image.size.height * (image.scale > 0 ? image.scale : 1)
        return w <= 400 && h <= 400
    }

    /// Open Library returns a tiny default image when no cover exists.
    private func isOpenLibraryMissingCover(data: Data, image: UIImage, url: URL) -> Bool {
        guard url.host?.contains("covers.openlibrary.org") == true else { return false }
        if data.count < 2500 { return true }
        return isOpenLibraryMissingCover(image: image, url: url)
    }

    private func isOpenLibraryMissingCover(image: UIImage, url: URL) -> Bool {
        guard url.host?.contains("covers.openlibrary.org") == true else { return false }
        let w = image.size.width * (image.scale > 0 ? image.scale : 1)
        let h = image.size.height * (image.scale > 0 ? image.scale : 1)
        return w < 90 || h < 120
    }

    /// Same check using image only (e.g. when returning from cache). Used to reject stale placeholders from memory cache.
    private func isGoogleBooksPlaceholder(image: UIImage, url: URL) -> Bool {
        guard url.absoluteString.contains("books.google.com") else { return false }
        let data = image.pngData() ?? Data()
        return isGoogleBooksPlaceholder(data: data, image: image, url: url)
    }

    /// Rejects mostly-flat bright images (e.g. publisher title page / interior scan) so we try the next URL (Open Library, another zoom, etc.).
    private func isGoogleBooksLikelyInteriorPageScan(image: UIImage, url: URL) -> Bool {
        guard url.absoluteString.contains("books.google.com") else { return false }
        let w = 48
        let h = 64
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: w, height: h), format: format)
        let sampled = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: CGSize(width: w, height: h)))
        }
        guard let cgImage = sampled.cgImage else { return false }
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(
                data: &pixels,
                width: w,
                height: h,
                bitsPerComponent: 8,
                bytesPerRow: w * 4,
                space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return false }
        ctx.interpolationQuality = .medium
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))
        var sum: Double = 0
        var sumSq: Double = 0
        let n = Double(w * h)
        for i in stride(from: 0, to: w * h * 4, by: 4) {
            let r = Double(pixels[i])
            let g = Double(pixels[i + 1])
            let b = Double(pixels[i + 2])
            let lum = (0.299 * r + 0.587 * g + 0.114 * b) / 255.0
            sum += lum
            sumSq += lum * lum
        }
        let mean = sum / n
        let variance = max(0, sumSq / n - mean * mean)
        return mean > 0.91 && variance < 0.022
    }

    /// Rejects Google Books' large **grey “synthetic” placeholder** (fake title bars, subtle texture, tiny logo) that isn’t a real cover. Those images are usually high-res so they pass byte/size checks.
    private func isGoogleBooksLikelyGreySyntheticPlaceholder(image: UIImage, url: URL) -> Bool {
        guard url.absoluteString.contains("books.google.com") else { return false }
        let w = 64
        let h = 96
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: w, height: h), format: format)
        let sampled = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: CGSize(width: w, height: h)))
        }
        guard let cgImage = sampled.cgImage else { return false }
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(
                data: &pixels,
                width: w,
                height: h,
                bitsPerComponent: 8,
                bytesPerRow: w * 4,
                space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return false }
        ctx.interpolationQuality = .medium
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))

        var sumLum: Double = 0
        var sumLumSq: Double = 0
        var sumChroma: Double = 0
        var lowChromaCount = 0
        var minLum: Double = 1
        var maxLum: Double = 0
        let n = Double(w * h)
        for i in stride(from: 0, to: w * h * 4, by: 4) {
            let r = Double(pixels[i])
            let g = Double(pixels[i + 1])
            let b = Double(pixels[i + 2])
            let lum = (0.299 * r + 0.587 * g + 0.114 * b) / 255.0
            let mx = max(r, max(g, b))
            let mn = min(r, min(g, b))
            let chroma = (mx - mn) / 255.0
            sumLum += lum
            sumLumSq += lum * lum
            sumChroma += chroma
            if chroma < 0.06 { lowChromaCount += 1 }
            minLum = min(minLum, lum)
            maxLum = max(maxLum, lum)
        }
        let meanLum = sumLum / n
        let lumVar = max(0, sumLumSq / n - meanLum * meanLum)
        let stdLum = sqrt(lumVar)
        let meanChroma = sumChroma / n
        let lowChromaFrac = Double(lowChromaCount) / n
        let lumRange = maxLum - minLum

        // Mostly achromatic, mid-grey overall, low contrast — matches Google’s generic template, not typical printed covers.
        let greyBand = (0.34...0.82).contains(meanLum)
        let flatContrast = stdLum < 0.13 && lumRange < 0.42
        let veryGrey = meanChroma < 0.048 && lowChromaFrac > 0.86
        if greyBand && flatContrast && veryGrey { return true }
        // Same sample: light grey “null cover” with horizontal fake text lines (stripes) — fails the flat test above.
        return isGreyStripedNullCoverFromSample(pixels: pixels, width: w, height: h, meanLum: meanLum, meanChroma: meanChroma)
    }

    /// Light grey template with horizontal bands mimicking text lines (and often a tiny corner glyph). Treat as no cover.
    private func isGreyStripedNullCoverFromSample(pixels: [UInt8], width w: Int, height h: Int, meanLum: Double, meanChroma: Double) -> Bool {
        guard meanChroma < 0.10 else { return false }
        guard (0.40...0.90).contains(meanLum) else { return false }
        var rowMean = [Double](repeating: 0, count: h)
        for y in 0..<h {
            var sum = 0.0
            let rowStart = y * w * 4
            for x in 0..<w {
                let i = rowStart + x * 4
                let r = Double(pixels[i])
                let g = Double(pixels[i + 1])
                let b = Double(pixels[i + 2])
                sum += (0.299 * r + 0.587 * g + 0.114 * b) / 255.0
            }
            rowMean[y] = sum / Double(w)
        }
        var stripeLikeEdges = 0
        for y in 0..<(h - 1) {
            let d = abs(rowMean[y + 1] - rowMean[y])
            // Fake “line” boundaries: subtle but consistent row-to-row steps
            if d >= 0.010 && d <= 0.32 {
                stripeLikeEdges += 1
            }
        }
        let edgeFrac = Double(stripeLikeEdges) / Double(max(1, h - 1))
        return edgeFrac >= 0.20
    }

    private func loadFromDisk(url: URL) -> UIImage? {
        guard let fileURL = diskFileURL(for: url),
              fileManager.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let img = UIImage(data: data) else { return nil }
        if isGoogleBooksPlaceholder(data: data, image: img, url: url) {
            try? fileManager.removeItem(at: fileURL)
            return nil
        }
        if isOpenLibraryMissingCover(data: data, image: img, url: url) {
            try? fileManager.removeItem(at: fileURL)
            return nil
        }
        if isGoogleBooksLikelyInteriorPageScan(image: img, url: url) {
            try? fileManager.removeItem(at: fileURL)
            return nil
        }
        if isGoogleBooksLikelyGreySyntheticPlaceholder(image: img, url: url) {
            try? fileManager.removeItem(at: fileURL)
            return nil
        }
        return img
    }

    private func saveToDisk(image: UIImage, url: URL) {
        guard let fileURL = diskFileURL(for: url),
              let data = image.pngData() else { return }
        try? data.write(to: fileURL)
    }

    /// Rough byte size for NSCache cost (avoids expensive `pngData()` on every disk→memory promotion).
    private func approximateImageCost(_ image: UIImage) -> Int {
        let w = image.size.width * (image.scale > 0 ? image.scale : 1)
        let h = image.size.height * (image.scale > 0 ? image.scale : 1)
        return max(1, Int(w * h * 4))
    }

    /// In-memory cache only — cheap and safe to call on the main thread (e.g. from a
    /// `View.init`) to paint a cached cover on the first frame with no shimmer. Images
    /// only enter the memory cache after passing the placeholder checks, so no need to
    /// re-run the (expensive, CoreGraphics-sampling) heuristics on every hit.
    func memoryImage(for url: URL) -> UIImage? {
        cache.object(forKey: url.absoluteString as NSString)
    }

    /// First in-memory hit across a book's candidate URLs (for synchronous hydration).
    func firstMemoryImage(forURLs urls: [URL]) -> UIImage? {
        for url in urls {
            if let img = memoryImage(for: url) { return img }
        }
        return nil
    }

    /// Memory + on-disk cache only (no network). Use so list reorder / tier moves can paint immediately without flashing `ProgressView`.
    func imageSyncFromCache(for url: URL) -> UIImage? {
        let key = url.absoluteString as NSString
        if let cached = cache.object(forKey: key) {
            if isGoogleBooksPlaceholder(image: cached, url: url) {
                cache.removeObject(forKey: key)
            } else if isOpenLibraryMissingCover(image: cached, url: url) {
                cache.removeObject(forKey: key)
            } else if isGoogleBooksLikelyInteriorPageScan(image: cached, url: url) {
                cache.removeObject(forKey: key)
            } else if isGoogleBooksLikelyGreySyntheticPlaceholder(image: cached, url: url) {
                cache.removeObject(forKey: key)
            } else {
                return cached
            }
        }
        if let diskImage = loadFromDisk(url: url) {
            cache.setObject(diskImage, forKey: key, cost: approximateImageCost(diskImage))
            return diskImage
        }
        return nil
    }

    func fetch(for url: URL) async -> CoverFetchResult {
        if let sync = imageSyncFromCache(for: url) { return .success(sync) }
        if isKnownBad(url) { return .missing }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(from: url)
        } catch {
            return .transient
        }
        guard let http = response as? HTTPURLResponse else { return .transient }
        let isOpenLibrary = url.host?.contains("covers.openlibrary.org") == true
        switch http.statusCode {
        case 200:
            break
        case 403 where isOpenLibrary:
            noteOpenLibraryRateLimited()
            return .rateLimited
        case 500...:
            return .transient
        default:
            // 404 (incl. Open Library `default=false` misses) and other 4xx — no cover here.
            markKnownBad(url)
            return .missing
        }
        guard let img = UIImage(data: data) else {
            markKnownBad(url)
            return .missing
        }
        if isGoogleBooksPlaceholder(data: data, image: img, url: url)
            || isOpenLibraryMissingCover(data: data, image: img, url: url)
            || isGoogleBooksLikelyInteriorPageScan(image: img, url: url)
            || isGoogleBooksLikelyGreySyntheticPlaceholder(image: img, url: url) {
            markKnownBad(url)
            return .missing
        }

        let key = url.absoluteString as NSString
        cache.setObject(img, forKey: key, cost: data.count)
        diskQueue.async { self.saveToDisk(image: img, url: url) }
        return .success(img)
    }
}

struct BookCoverView: View {
    let book: Book
    var size: CGFloat = 80
    /// When set, tapping the cover calls this (e.g. to open book profile).
    var onTap: (() -> Void)? = nil

    var body: some View {
        Group {
            if book.coverImageURLsToTry.isEmpty {
                TitleOnlyBookCover(title: book.title, author: book.author, size: size)
            } else {
                FallbackCoverImage(
                    bookId: book.id,
                    urls: book.coverImageURLsToTry,
                    size: size,
                    isbn: book.isbn,
                    placeholderTitle: book.title,
                    placeholderAuthor: book.author
                )
            }
        }
        .frame(width: size, height: size * 1.5)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Theme.chromeTeal.opacity(0.35), lineWidth: 0.75)
        )
        .shadow(color: Theme.shadowInk.opacity(0.12), radius: 3, x: 0, y: 2)
        .modifier(CoverTapModifier(onTap: onTap))
    }
}

private struct CoverTapModifier: ViewModifier {
    let onTap: (() -> Void)?
    func body(content: Content) -> some View {
        if let onTap = onTap {
            content.contentShape(Rectangle()).onTapGesture(perform: onTap)
        } else {
            content
        }
    }
}

/// Book-cover-style placeholder when no image is available: title centered, author along the bottom in a smaller type.
private struct TitleOnlyBookCover: View {
    let title: String
    var author: String? = nil
    let size: CGFloat

    private var trimmedAuthor: String? {
        guard let a = author?.trimmingCharacters(in: .whitespacesAndNewlines), !a.isEmpty else { return nil }
        return a
    }

    /// Stable per-book jacket color from the 12-color accessible palette — hashing
    /// title+author keeps it identical across renders, launches, and devices, and
    /// spreads neighboring coverless books across different hues.
    private var fillColor: Color {
        Theme.coverPaletteColor(for: "\(title)|\(trimmedAuthor ?? "")")
    }

    var body: some View {
        ZStack {
            fillColor
            // Slight darkening toward the base reads like a printed jacket and only
            // increases text contrast (palette is validated against the flat color).
            LinearGradient(
                colors: [Color.black.opacity(0.0), Color.black.opacity(0.22)],
                startPoint: .top,
                endPoint: .bottom
            )
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                Text(title)
                    .font(.system(size: fontSize, weight: .semibold, design: .serif))
                    .foregroundStyle(Theme.phosphorWhite)
                    .multilineTextAlignment(.center)
                    .lineLimit(5)
                    .padding(.horizontal, padding)
                Spacer(minLength: 0)
                if let author = trimmedAuthor {
                    Text(author)
                        .font(.system(size: authorFontSize, weight: .medium, design: .serif))
                        .foregroundStyle(Theme.phosphorWhite.opacity(0.75))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .padding(.horizontal, padding)
                        .padding(.bottom, bottomPadding)
                }
            }
        }
    }

    private var fontSize: CGFloat { max(10, size * 0.14) }
    /// Smaller than title so hierarchy reads clearly on the “spine” area.
    private var authorFontSize: CGFloat { max(8, size * 0.092) }
    private var padding: CGFloat { max(4, size * 0.08) }
    private var bottomPadding: CGFloat { max(6, size * 0.07) }
}

/// Total seconds to obtain **any** cover image (network or cache); after this, show title placeholder.
/// Generous on purpose: resolution locking means only the *first ever* load of a book pays
/// this — better a longer shimmer once than a permanent wrong placeholder on a slow network.
private let coverLoadTotalBudgetSeconds: TimeInterval = 10

/// Tries each URL in order within a single total time budget; uses memory + disk cached images when available.
/// Once a URL succeeds it's locked in `CoverResolutionStore`, so subsequent renders (and
/// launches) go straight to that URL's cache entry — no re-probing, no shimmer, no network.
private struct FallbackCoverImage: View {
    /// Stable identity for `.task` — tier/queue reorder recreates cells; sync cache hydrate avoids spinner when URLs unchanged.
    let bookId: String
    let urls: [URL]
    let size: CGFloat
    var isbn: String? = nil
    var placeholderTitle: String? = nil
    var placeholderAuthor: String? = nil
    @State private var loadedImage: UIImage?
    /// The `taskIdentity` the `loadedImage` belongs to, so a slot reused for a different
    /// book (positional ForEach ids) reloads instead of showing a stale cover.
    @State private var loadedIdentity: String?
    @State private var useTitlePlaceholder = false

    init(bookId: String, urls: [URL], size: CGFloat, isbn: String? = nil, placeholderTitle: String? = nil, placeholderAuthor: String? = nil) {
        self.bookId = bookId
        self.urls = urls
        self.size = size
        self.isbn = isbn
        self.placeholderTitle = placeholderTitle
        self.placeholderAuthor = placeholderAuthor
        // Paint the right thing on the very first frame. In a LazyVStack/LazyVGrid,
        // scrolling a cell offscreen tears down its @State; without this, scrolling back
        // would flash the shimmer (or re-generate the placeholder) even though the
        // outcome is already known.
        let identity = Self.identity(bookId: bookId, urls: urls)
        let signature = Self.signature(urls: urls, isbn: isbn)
        var cached = CoverImageCache.shared.firstMemoryImage(forURLs: urls)
        if cached == nil,
           let locked = CoverResolutionStore.shared.resolvedURL(bookId: bookId, signature: signature) {
            // Locked winner may be an iTunes artwork URL that isn't in `urls`; the disk
            // read here is one small file — cheaper than a shimmer flash on every scroll.
            cached = CoverImageCache.shared.imageSyncFromCache(for: locked)
        }
        _loadedImage = State(initialValue: cached)
        _loadedIdentity = State(initialValue: cached != nil ? identity : nil)
        if cached == nil, CoverResolutionStore.shared.hasRecentFailure(bookId: bookId, signature: signature) {
            _useTitlePlaceholder = State(initialValue: true)
        }
    }

    private static func identity(bookId: String, urls: [URL]) -> String {
        "\(bookId)-\(urls.map(\.absoluteString).joined(separator: "|"))"
    }

    private var taskIdentity: String {
        Self.identity(bookId: bookId, urls: urls)
    }

    /// Resolution-store signature: invalidates locks/failures when cover inputs change.
    private static func signature(urls: [URL], isbn: String?) -> String {
        CoverResolutionStore.signature(coverURL: urls.first?.absoluteString ?? "", isbn: isbn)
    }

    /// URLs the *previous* cover pipeline downloaded under, so covers already sitting in
    /// the disk cache keep working instead of re-downloading: Google zoom=0/4/5 variants
    /// (the old chain tried zoom=0 first, so most legacy cache entries live there) and
    /// Open Library URLs without `?default=false` (including the old -S size).
    /// Checked cache-only — these are never fetched from the network.
    private static func legacyCacheURLs(from urls: [URL]) -> [URL] {
        var out: [String] = []
        let current = Set(urls.map(\.absoluteString))
        for url in urls {
            let s = url.absoluteString
            if url.host?.contains("books.google.com") == true,
               var comp = URLComponents(string: s) {
                for zoom in [0, 4, 5] {
                    var q = comp.queryItems ?? []
                    q.removeAll { $0.name.lowercased() == "zoom" }
                    q.append(URLQueryItem(name: "zoom", value: "\(zoom)"))
                    comp.queryItems = q
                    if let v = comp.string, !current.contains(v), !out.contains(v) { out.append(v) }
                }
            } else if url.host?.contains("covers.openlibrary.org") == true,
                      var comp = URLComponents(string: s) {
                comp.query = nil
                if let bare = comp.string, !current.contains(bare), !out.contains(bare) {
                    out.append(bare)
                    if bare.hasSuffix("-L.jpg") {
                        let small = bare.replacingOccurrences(of: "-L.jpg", with: "-S.jpg")
                        if !out.contains(small) { out.append(small) }
                    }
                }
            }
        }
        return out.compactMap { URL(string: $0) }
    }

    /// Fetches within `timeout`; running out of time counts as a transient failure.
    private func loadCover(url: URL, timeout: TimeInterval) async -> CoverFetchResult {
        let ns = UInt64(max(0.05, timeout) * 1_000_000_000)
        return await withTaskGroup(of: CoverFetchResult.self) { group in
            group.addTask {
                await CoverImageCache.shared.fetch(for: url)
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: ns)
                return .transient
            }
            let first = await group.next()
            group.cancelAll()
            return first ?? .transient
        }
    }

    var body: some View {
        ZStack {
            if useTitlePlaceholder {
                if let title = placeholderTitle, !title.isEmpty {
                    TitleOnlyBookCover(title: title, author: placeholderAuthor, size: size)
                } else {
                    genericPlaceholder
                }
            } else if let img = loadedImage {
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size * 1.5)
                    .clipped()
            } else {
                CoverShimmer()
            }
        }
        .frame(width: size, height: size * 1.5)
        .clipped()
        .task(id: taskIdentity) {
            let identity = taskIdentity
            // Already showing the right cover (synchronous memory-cache hydrate from init) —
            // never blank it back to a shimmer just because the cell was recreated on scroll.
            if loadedImage != nil, loadedIdentity == identity { return }
            let signature = Self.signature(urls: urls, isbn: isbn)
            let store = CoverResolutionStore.shared
            // Cheap re-check: cover may have landed in the cache since init (a sibling cell
            // finished downloading it), or this slot was reused for a different book.
            if let mem = CoverImageCache.shared.firstMemoryImage(forURLs: urls) {
                loadedImage = mem
                loadedIdentity = identity
                return
            }
            // Holdover covers downloaded before resolution locking existed live in the
            // disk cache under old-scheme URLs. Reuse and lock them — cache-only, no
            // network — and let them heal books that were wrongly marked failed.
            if store.resolvedURL(bookId: bookId, signature: signature) == nil {
                for legacy in Self.legacyCacheURLs(from: urls) {
                    if let img = CoverImageCache.shared.imageSyncFromCache(for: legacy) {
                        store.lock(bookId: bookId, signature: signature, url: legacy)
                        loadedImage = img
                        loadedIdentity = identity
                        return
                    }
                }
            }
            // Known dead end (this session, or persisted recently) — show the generated
            // cover immediately and stay off the network entirely.
            if store.hasRecentFailure(bookId: bookId, signature: signature) {
                loadedImage = nil
                loadedIdentity = nil
                useTitlePlaceholder = true
                return
            }
            loadedImage = nil
            loadedIdentity = nil
            useTitlePlaceholder = false
            let start = Date()
            let budget = coverLoadTotalBudgetSeconds
            func remaining() -> TimeInterval { budget - Date().timeIntervalSince(start) }

            func succeed(_ img: UIImage, url: URL) {
                store.lock(bookId: bookId, signature: signature, url: url)
                loadedImage = img
                loadedIdentity = identity
            }

            // 1. A previously locked winner: go straight to it (usually a disk-cache hit).
            if let locked = store.resolvedURL(bookId: bookId, signature: signature) {
                if case .success(let img) = await loadCover(url: locked, timeout: remaining()) {
                    succeed(img, url: locked)
                    return
                }
                // Remote image vanished or network is down — clear the stale lock and
                // let the normal chain (below) re-resolve.
                store.clear(bookId: bookId)
            }

            // 2. Fallback chain: Open Library → Google Books (ordering built in Book.coverImageURLsToTry).
            var sawTransient = false
            for url in urls {
                if remaining() <= 0 { sawTransient = true; break }
                if url.host?.contains("covers.openlibrary.org") == true,
                   CoverImageCache.shared.isOpenLibraryBackedOff {
                    sawTransient = true // OL might have had it; don't record a hard failure
                    continue
                }
                switch await loadCover(url: url, timeout: remaining()) {
                case .success(let img):
                    succeed(img, url: url)
                    return
                case .missing:
                    continue
                case .rateLimited, .transient:
                    sawTransient = true
                    continue
                }
            }

            // 3. Last resort: iTunes/Apple Books artwork lookup.
            if remaining() > 0, let title = placeholderTitle, !title.isEmpty {
                let artworkURLs = await ITunesCoverService.shared.artworkURLs(
                    isbn: isbn, title: title, author: placeholderAuthor
                )
                for url in artworkURLs {
                    if remaining() <= 0 { sawTransient = true; break }
                    if case .success(let img) = await loadCover(url: url, timeout: remaining()) {
                        succeed(img, url: url)
                        return
                    }
                }
            }

            // 4. Nothing anywhere. Persist the failure only when every source definitively
            // said "no cover" — timeouts/rate limits just skip probing for this session.
            store.markFailed(bookId: bookId, signature: signature, definitive: !sawTransient)
            useTitlePlaceholder = true
        }
    }

    private var genericPlaceholder: some View {
        ZStack {
            Theme.surface
            Image(systemName: "book.closed")
                .font(.system(size: size * 0.4))
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Loading-state shimmer for book covers — a teal band sweeps across a paper surface
/// and repeats while we wait for the image. Replaces ProgressView spinners on covers.
private struct CoverShimmer: View {
    @State private var animate = false

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            // Band is ~60% of cover width; travels from fully off-left to fully off-right.
            let bandWidth = width * 0.6
            let startX = -bandWidth
            let endX = width + bandWidth
            ZStack {
                Theme.surface
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.0),
                        .init(color: Theme.chromeTeal.opacity(0.32), location: 0.5),
                        .init(color: .clear, location: 1.0)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: bandWidth)
                .offset(x: animate ? endX - bandWidth / 2 : startX - bandWidth / 2)
                .animation(
                    .linear(duration: 1.4).repeatForever(autoreverses: false),
                    value: animate
                )
            }
            .frame(width: width, height: geo.size.height)
            .clipped()
        }
        .onAppear { animate = true }
    }
}
