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

// Memory + disk cache for cover images. Disk cache persists across app launches so covers don't re-download every time.
final class CoverImageCache {
    static let shared = CoverImageCache()

    /// Max seconds for each URL attempt (network + decode). `FallbackCoverImage` also enforces a **total** budget per cover.
    static let loadTimeoutSeconds: TimeInterval = 2

    private let cache = NSCache<NSString, UIImage>()
    private let session: URLSession
    private let fileManager = FileManager.default
    private let diskQueue = DispatchQueue(label: "com.wellread.covercache.disk")

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

    func image(for url: URL) async -> UIImage? {
        if let sync = imageSyncFromCache(for: url) { return sync }

        // Fetch from network.
        guard let (data, _) = try? await session.data(from: url),
              let img = UIImage(data: data) else { return nil }
        if isGoogleBooksPlaceholder(data: data, image: img, url: url) { return nil }
        if isOpenLibraryMissingCover(data: data, image: img, url: url) { return nil }
        if isGoogleBooksLikelyInteriorPageScan(image: img, url: url) { return nil }
        if isGoogleBooksLikelyGreySyntheticPlaceholder(image: img, url: url) { return nil }

        let key = url.absoluteString as NSString
        cache.setObject(img, forKey: key, cost: data.count)
        diskQueue.async { self.saveToDisk(image: img, url: url) }
        return img
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
        .shadow(color: Theme.textPrimary.opacity(0.12), radius: 3, x: 0, y: 2)
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

    var body: some View {
        ZStack {
            Theme.defaultCoverFill
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
private let coverLoadTotalBudgetSeconds: TimeInterval = 2

/// Tries each URL in order within a single total time budget; uses memory + disk cached images when available.
private struct FallbackCoverImage: View {
    /// Stable identity for `.task` — tier/queue reorder recreates cells; sync cache hydrate avoids spinner when URLs unchanged.
    let bookId: String
    let urls: [URL]
    let size: CGFloat
    var placeholderTitle: String? = nil
    var placeholderAuthor: String? = nil
    @State private var loadedImage: UIImage?
    @State private var useTitlePlaceholder = false

    private var taskIdentity: String {
        "\(bookId)-\(urls.map(\.absoluteString).joined(separator: "|"))"
    }

    /// Loads from cache/network within `timeout`, or `nil` when time runs out.
    private func loadCoverImage(url: URL, timeout: TimeInterval) async -> UIImage? {
        let ns = UInt64(max(0.05, timeout) * 1_000_000_000)
        return await withTaskGroup(of: UIImage?.self) { group in
            group.addTask {
                await CoverImageCache.shared.image(for: url)
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: ns)
                return nil
            }
            let first = await group.next()
            group.cancelAll()
            return first ?? nil
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
            loadedImage = nil
            useTitlePlaceholder = false
            let start = Date()
            let budget = coverLoadTotalBudgetSeconds

            for url in urls {
                let elapsed = Date().timeIntervalSince(start)
                if elapsed >= budget {
                    useTitlePlaceholder = true
                    return
                }
                if let cached = CoverImageCache.shared.imageSyncFromCache(for: url) {
                    loadedImage = cached
                    return
                }
                let remaining = budget - Date().timeIntervalSince(start)
                if remaining <= 0 {
                    useTitlePlaceholder = true
                    return
                }
                if let img = await loadCoverImage(url: url, timeout: remaining) {
                    loadedImage = img
                    return
                }
            }
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
