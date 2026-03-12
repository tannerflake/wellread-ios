//
//  BookCoverView.swift
//  WellRead
//
//  Loads cover from primary URL; on failure tries fallback URLs. Uses in-memory + disk cache so covers persist across app launches and re-renders show instantly.
//

import SwiftUI
import UIKit
import CryptoKit

// Memory + disk cache for cover images. Disk cache persists across app launches so covers don't re-download every time.
private final class CoverImageCache {
    static let shared = CoverImageCache()
    private let cache = NSCache<NSString, UIImage>()
    private let session: URLSession
    private let fileManager = FileManager.default
    private let diskQueue = DispatchQueue(label: "com.wellread.covercache.disk")

    private init() {
        cache.countLimit = 200
        cache.totalCostLimit = 50 * 1024 * 1024 // 50 MB
        session = URLSession.shared
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

    /// Same check using image only (e.g. when returning from cache). Used to reject stale placeholders from memory cache.
    private func isGoogleBooksPlaceholder(image: UIImage, url: URL) -> Bool {
        guard url.absoluteString.contains("books.google.com") else { return false }
        let data = image.pngData() ?? Data()
        return isGoogleBooksPlaceholder(data: data, image: image, url: url)
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
        return img
    }

    private func saveToDisk(image: UIImage, url: URL) {
        guard let fileURL = diskFileURL(for: url),
              let data = image.pngData() else { return }
        try? data.write(to: fileURL)
    }

    func image(for url: URL) async -> UIImage? {
        let key = url.absoluteString as NSString
        if let cached = cache.object(forKey: key) {
            if isGoogleBooksPlaceholder(image: cached, url: url) {
                cache.removeObject(forKey: key)
                // Fall through to try disk/network or next URL
            } else {
                return cached
            }
        }

        // Try disk cache (on background queue to avoid blocking).
        if let diskImage = await withCheckedContinuation({ (cont: CheckedContinuation<UIImage?, Never>) in
            diskQueue.async {
                let img = self.loadFromDisk(url: url)
                cont.resume(returning: img)
            }
        }) {
            cache.setObject(diskImage, forKey: key, cost: (diskImage.pngData() ?? Data()).count)
            return diskImage
        }

        // Fetch from network.
        guard let (data, _) = try? await session.data(from: url),
              let img = UIImage(data: data) else { return nil }
        if isGoogleBooksPlaceholder(data: data, image: img, url: url) { return nil }

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

    /// Ordered candidates: primary + fallbacks (with zoom variants for Google Books to maximize chance of a real cover), then ID-based last resort.
    private var urlsToTry: [URL] {
        var list: [String] = []
        let primaryVariants = Book.coverURLsToTry(from: book.coverURL)
        list.append(contentsOf: primaryVariants)
        for s in book.fallbackCoverURLs ?? [] {
            let variants = Book.coverURLsToTry(from: s)
            for v in variants where !list.contains(v) { list.append(v) }
        }
        let idBased = Book.coverURLsFromBookId(book.id)
        for v in idBased where !list.contains(v) { list.append(v) }
        return list.compactMap { URL(string: $0) }.filter { !$0.absoluteString.isEmpty }
    }

    var body: some View {
        Group {
            if urlsToTry.isEmpty {
                TitleOnlyBookCover(title: book.title, size: size)
            } else {
                FallbackCoverImage(urls: urlsToTry, size: size, placeholderTitle: book.title)
            }
        }
        .frame(width: size, height: size * 1.5)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
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

/// Book-cover-style placeholder with the book title when no image is available. Uses theme colors so it reads as a real cover.
private struct TitleOnlyBookCover: View {
    let title: String
    let size: CGFloat

    var body: some View {
        ZStack {
            Theme.primary
            Text(title)
                .font(.system(size: fontSize, weight: .semibold, design: .serif))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
                .lineLimit(5)
                .padding(padding)
        }
    }

    private var fontSize: CGFloat { max(10, size * 0.14) }
    private var padding: CGFloat { max(4, size * 0.08) }
}

/// Tries each URL in order; uses memory + disk cached images so no re-fetch or spinner when the view re-appears or app relaunches.
private struct FallbackCoverImage: View {
    let urls: [URL]
    let size: CGFloat
    var placeholderTitle: String? = nil
    @State private var currentIndex: Int = 0
    @State private var loadedImage: UIImage?

    var body: some View {
        ZStack {
            if currentIndex >= urls.count {
                if let title = placeholderTitle, !title.isEmpty {
                    TitleOnlyBookCover(title: title, size: size)
                } else {
                    genericPlaceholder
                }
            } else if let img = loadedImage {
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                genericPlaceholder
                    .overlay(ProgressView().tint(Theme.accent))
            }
        }
        .task(id: currentIndex) {
            loadedImage = nil
            guard currentIndex < urls.count else { return }
            if let img = await CoverImageCache.shared.image(for: urls[currentIndex]) {
                loadedImage = img
            } else if currentIndex + 1 < urls.count {
                currentIndex += 1
            } else {
                currentIndex = urls.count // all URLs failed; show title placeholder
            }
        }
    }

    private var genericPlaceholder: some View {
        ZStack {
            Theme.surface
            Image(systemName: "book.closed")
                .font(.system(size: size * 0.4))
                .foregroundStyle(Theme.textTertiary)
        }
    }
}
