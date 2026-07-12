//
//  ProfileImageCache.swift
//  WellRead
//
//  In-memory + on-disk cache for profile avatars (current user + friends) to avoid repeated downloads.
//

import CryptoKit
import Foundation
import UIKit

final class ProfileImageCache {
    static let shared = ProfileImageCache()

    private let memory = NSCache<NSString, UIImage>()
    private let diskDirectory: URL
    private let ioQueue = DispatchQueue(label: "com.wellread.profileImageCache.io", qos: .utility)
    private let fileManager = FileManager.default

    private init() {
        memory.countLimit = 200
        let base = try? fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let dir = base?
            .appendingPathComponent("WellRead", isDirectory: true)
            .appendingPathComponent("ProfileImages", isDirectory: true)
        diskDirectory = dir ?? URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("WellReadProfileImages", isDirectory: true)
        try? fileManager.createDirectory(at: diskDirectory, withIntermediateDirectories: true)
    }

    private func diskURL(for url: URL) -> URL {
        diskDirectory.appendingPathComponent(Self.filename(for: url.absoluteString))
    }

    private static func filename(for urlString: String) -> String {
        let digest = SHA256.hash(data: Data(urlString.utf8))
        return digest.map { String(format: "%02x", $0) }.joined() + ".dat"
    }

    /// In-memory cache only — cheap and main-thread safe, for synchronous hydration in a
    /// `View.init` so a cached avatar paints on the first frame (no placeholder flash on scroll).
    func memoryImage(for url: URL?) -> UIImage? {
        guard let url else { return nil }
        return memory.object(forKey: url.absoluteString as NSString)
    }

    /// Loads from memory, then disk, then network; writes disk after a successful download.
    func image(for url: URL) async -> UIImage? {
        let key = url.absoluteString as NSString
        if let cached = memory.object(forKey: key) {
            return cached
        }

        let diskURL = diskURL(for: url)
        if fileManager.fileExists(atPath: diskURL.path) {
            let data = await Task.detached(priority: .utility) {
                try? Data(contentsOf: diskURL)
            }.value
            if let data, let img = UIImage(data: data) {
                memory.setObject(img, forKey: key)
                return img
            }
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let img = UIImage(data: data) else { return nil }
            memory.setObject(img, forKey: key)
            ioQueue.async { [diskURL] in
                try? data.write(to: diskURL, options: [.atomic])
            }
            return img
        } catch {
            return nil
        }
    }

    /// Call after uploading a new photo so the next display hits memory/disk immediately.
    func store(_ image: UIImage, for url: URL) {
        let key = url.absoluteString as NSString
        memory.setObject(image, forKey: key)
        let diskURL = diskURL(for: url)
        ioQueue.async {
            guard let data = image.jpegData(compressionQuality: 0.88) else { return }
            try? data.write(to: diskURL, options: [.atomic])
        }
    }
}
