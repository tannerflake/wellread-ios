//
//  WidgetSnapshot.swift
//  WellRead
//
//  Shared between the app target (writer) and WellReadWidget (reader).
//  Foundation-only: the widget target compiles this file without the app's
//  models, so it must never reference Book/User/Theme.
//

import Foundation

/// Compact "reading now" payload the app writes into the App Group for the widget.
struct WidgetSnapshot: Codable {
    struct BookEntry: Codable {
        let bookId: String
        let title: String
        let author: String
        /// Filename inside `WidgetSharedStore.imagesDirectory`; nil renders a title-card fallback.
        let coverFilename: String?
    }

    struct FriendEntry: Codable {
        let uid: String
        let displayName: String
        let avatarFilename: String?
        let books: [BookEntry]
    }

    let schemaVersion: Int
    let isSignedIn: Bool
    /// Own reading-now shelf in queue order (widget shows the first).
    let myBooks: [BookEntry]
    /// Friends with at least one reading-now book, at most 4.
    let friends: [FriendEntry]
    let generatedAt: Date
}

/// App Group paths + JSON coding used identically by app and widget.
/// Encoder and decoder live side by side so the date strategy can't drift.
enum WidgetSharedStore {
    static let appGroupId = "group.com.wellread.app"
    static let currentSchemaVersion = 1

    static var containerURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupId)?
            .appendingPathComponent("WidgetData", isDirectory: true)
    }

    static var snapshotURL: URL? {
        containerURL?.appendingPathComponent("snapshot.json")
    }

    static var imagesDirectory: URL? {
        containerURL?.appendingPathComponent("images", isDirectory: true)
    }

    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// nil on missing file, decode failure, or schema version mismatch.
    static func loadSnapshot() -> WidgetSnapshot? {
        guard let url = snapshotURL,
              let data = try? Data(contentsOf: url),
              let snapshot = try? makeDecoder().decode(WidgetSnapshot.self, from: data),
              snapshot.schemaVersion == currentSchemaVersion else { return nil }
        return snapshot
    }

    static func imageURL(for filename: String?) -> URL? {
        guard let filename, !filename.isEmpty, let dir = imagesDirectory else { return nil }
        return dir.appendingPathComponent(filename)
    }
}
