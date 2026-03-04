//
//  BookCoverView.swift
//  WellRead
//
//  Loads cover from primary URL; on failure tries fallback URLs. Uses in-memory cache so re-renders (e.g. after drag-drop) show the image instantly with no spinner.
//

import SwiftUI
import UIKit

// In-memory cache for cover images so list updates (e.g. after tier drop) don't re-fetch and flash a spinner.
private final class CoverImageCache {
    static let shared = CoverImageCache()
    private let cache = NSCache<NSString, UIImage>()
    private let session: URLSession

    private init() {
        cache.countLimit = 200
        cache.totalCostLimit = 50 * 1024 * 1024 // 50 MB
        session = URLSession.shared
    }

    func image(for url: URL) async -> UIImage? {
        let key = url.absoluteString as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let (data, _) = try? await session.data(from: url),
              let img = UIImage(data: data) else { return nil }
        cache.setObject(img, forKey: key, cost: data.count)
        return img
    }
}

struct BookCoverView: View {
    let book: Book
    var size: CGFloat = 80

    /// All URLs to try in order: primary (high-res) then fallbacks.
    private var urlsToTry: [URL] {
        let primary = Book.highResCoverURLString(book.coverURL)
        guard let u = URL(string: primary), !book.coverURL.isEmpty else { return [] }
        var list = [u]
        for s in book.fallbackCoverURLs ?? [] {
            let normalized = Book.highResCoverURLString(s)
            if let url = URL(string: normalized), !list.contains(where: { $0.absoluteString == normalized }) {
                list.append(url)
            }
        }
        return list
    }

    var body: some View {
        Group {
            if urlsToTry.isEmpty {
                placeholder
            } else {
                FallbackCoverImage(urls: urlsToTry, size: size)
            }
        }
        .frame(width: size, height: size * 1.5)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
    }

    private var placeholder: some View {
        ZStack {
            Theme.surface
            Image(systemName: "book.closed")
                .font(.system(size: size * 0.4))
                .foregroundStyle(Theme.textTertiary)
        }
    }
}

/// Tries each URL in order; uses cached images so no re-fetch or spinner when the view re-appears (e.g. after drop).
private struct FallbackCoverImage: View {
    let urls: [URL]
    let size: CGFloat
    @State private var currentIndex: Int = 0
    @State private var loadedImage: UIImage?

    private var coverPlaceholder: some View {
        ZStack {
            Theme.surface
            Image(systemName: "book.closed")
                .font(.system(size: size * 0.4))
                .foregroundStyle(Theme.textTertiary)
        }
    }

    var body: some View {
        ZStack {
            if currentIndex >= urls.count {
                coverPlaceholder
            } else if let img = loadedImage {
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                coverPlaceholder
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
            }
        }
    }
}
