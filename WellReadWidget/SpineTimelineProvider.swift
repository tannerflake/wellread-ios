//
//  SpineTimelineProvider.swift
//  WellReadWidget
//
//  Renders whatever the app last wrote into the App Group. The app calls
//  WidgetCenter.reloadAllTimelines() after each snapshot write, so the
//  timeline policy is .never — data can only change via the app anyway.
//

import WidgetKit

struct SpineEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

struct SpineTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> SpineEntry {
        SpineEntry(date: .now, snapshot: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (SpineEntry) -> Void) {
        let snapshot = context.isPreview ? .sample : WidgetSharedStore.loadSnapshot()
        completion(SpineEntry(date: .now, snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SpineEntry>) -> Void) {
        let entry = SpineEntry(date: .now, snapshot: WidgetSharedStore.loadSnapshot())
        completion(Timeline(entries: [entry], policy: .never))
    }
}

extension WidgetSnapshot {
    /// Widget-gallery preview. Filenames stay nil so cells render title cards —
    /// no bundled assets needed.
    static let sample = WidgetSnapshot(
        schemaVersion: WidgetSharedStore.currentSchemaVersion,
        isSignedIn: true,
        myBooks: [
            BookEntry(bookId: "sample-1", title: "East of Eden", author: "John Steinbeck", coverFilename: nil),
        ],
        friends: [
            FriendEntry(uid: "f1", displayName: "Avery", avatarFilename: nil, books: [
                BookEntry(bookId: "sample-2", title: "The Secret History", author: "Donna Tartt", coverFilename: nil),
            ]),
            FriendEntry(uid: "f2", displayName: "Jordan", avatarFilename: nil, books: [
                BookEntry(bookId: "sample-3", title: "Pachinko", author: "Min Jin Lee", coverFilename: nil),
            ]),
            FriendEntry(uid: "f3", displayName: "Sam", avatarFilename: nil, books: [
                BookEntry(bookId: "sample-4", title: "Dune", author: "Frank Herbert", coverFilename: nil),
            ]),
        ],
        generatedAt: .now
    )
}
