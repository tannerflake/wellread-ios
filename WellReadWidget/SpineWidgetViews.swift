//
//  SpineWidgetViews.swift
//  WellReadWidget
//

import SwiftUI
import WidgetKit

/// Local echo of the app's Theme palette (SPINE paper #EDEEE3 / ink #141018,
/// inverted in dark). The widget target doesn't compile app sources, so these
/// are duplicated on purpose.
enum SpinePalette {
    private static func dynamic(light: UIColor, dark: UIColor) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }

    static let paper = dynamic(
        light: UIColor(red: 237/255, green: 238/255, blue: 227/255, alpha: 1),
        dark: UIColor(red: 20/255, green: 16/255, blue: 24/255, alpha: 1)
    )
    static let surface = dynamic(
        light: UIColor(red: 226/255, green: 227/255, blue: 214/255, alpha: 1),
        dark: UIColor(red: 29/255, green: 25/255, blue: 36/255, alpha: 1)
    )
    static let textPrimary = dynamic(
        light: UIColor(red: 20/255, green: 16/255, blue: 24/255, alpha: 1),
        dark: UIColor(red: 237/255, green: 238/255, blue: 227/255, alpha: 1)
    )
    static let textSecondary = dynamic(
        light: UIColor(red: 69/255, green: 66/255, blue: 75/255, alpha: 1),
        dark: UIColor(red: 181/255, green: 182/255, blue: 171/255, alpha: 1)
    )
    /// Chrome — solid ink (paper in dark); replaces the retired teal.
    static let chrome = dynamic(
        light: UIColor(red: 20/255, green: 16/255, blue: 24/255, alpha: 1),
        dark: UIColor(red: 237/255, green: 238/255, blue: 227/255, alpha: 1)
    )
    /// Text on a `chrome` fill.
    static let onChrome = dynamic(
        light: UIColor(red: 237/255, green: 238/255, blue: 227/255, alpha: 1),
        dark: UIColor(red: 20/255, green: 16/255, blue: 24/255, alpha: 1)
    )

    /// Echo of the app's `Theme.coverPalette` + `coverPaletteColor(for:)` (see
    /// UserAvatarView.swift): 12 deep hues, white text, FNV-1a seeded by the
    /// normalized display name so a friend's fallback avatar color matches the app.
    static let avatarPalette: [Color] = [
        Color(red: 74/255, green: 61/255, blue: 140/255),
        Color(red: 49/255, green: 46/255, blue: 129/255),
        Color(red: 30/255, green: 58/255, blue: 110/255),
        Color(red: 37/255, green: 78/255, blue: 112/255),
        Color(red: 13/255, green: 92/255, blue: 99/255),
        Color(red: 28/255, green: 92/255, blue: 58/255),
        Color(red: 82/255, green: 78/255, blue: 26/255),
        Color(red: 146/255, green: 60/255, blue: 18/255),
        Color(red: 121/255, green: 68/255, blue: 34/255),
        Color(red: 146/255, green: 34/255, blue: 30/255),
        Color(red: 122/255, green: 28/255, blue: 56/255),
        Color(red: 108/255, green: 40/255, blue: 96/255)
    ]

    static func avatarColor(for name: String) -> Color {
        let seed = name.split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .lowercased()
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in seed.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return avatarPalette[Int(hash % UInt64(avatarPalette.count))]
    }

    static func avatarInitials(for name: String) -> String {
        let words = name.split(whereSeparator: { $0.isWhitespace })
        guard let first = words.first?.first else { return "?" }
        if words.count >= 2, let last = words.last?.first {
            return String(first).uppercased() + String(last).uppercased()
        }
        return String(first).uppercased()
    }
}

enum WidgetImageLoader {
    static func image(_ filename: String?) -> UIImage? {
        guard let url = WidgetSharedStore.imageURL(for: filename) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }
}

extension WidgetSnapshot {
    /// Every (friend, book) pairing flattened in snapshot order — a friend
    /// reading two books occupies two rotation slots.
    struct FriendBookItem {
        let friend: FriendEntry
        let book: BookEntry
    }

    var friendBookItems: [FriendBookItem] {
        friends.flatMap { friend in
            friend.books.map { FriendBookItem(friend: friend, book: $0) }
        }
    }
}

// MARK: - Entry view

struct SpineWidgetEntryView: View {
    var entry: SpineEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .systemMedium:
            MediumWidgetView(snapshot: entry.snapshot, tick: entry.tick)
        default:
            SmallWidgetView(snapshot: entry.snapshot)
        }
    }
}

// MARK: - Small: your current read

struct SmallWidgetView: View {
    let snapshot: WidgetSnapshot?

    var body: some View {
        Group {
            if let snapshot, snapshot.isSignedIn {
                if let book = snapshot.myBooks.first {
                    if let cover = WidgetImageLoader.image(book.coverFilename) {
                        Color.clear
                            .containerBackground(for: .widget) {
                                Image(uiImage: cover)
                                    .resizable()
                                    .scaledToFill()
                            }
                    } else {
                        TitleCard(book: book)
                            .containerBackground(SpinePalette.paper, for: .widget)
                    }
                } else {
                    MessageCard(title: "Nothing on deck", subtitle: "Pick your next read in SPINE")
                        .containerBackground(SpinePalette.paper, for: .widget)
                }
            } else {
                MessageCard(title: "SPINE", subtitle: "Open the app to sign in")
                    .containerBackground(SpinePalette.paper, for: .widget)
            }
        }
        .widgetURL(URL(string: "wellread://queue"))
    }
}

// MARK: - Medium: your stack + friends

struct MediumWidgetView: View {
    let snapshot: WidgetSnapshot?
    let tick: Int

    /// Friend books shown per rotation page.
    static let friendsPerPage = 3

    var body: some View {
        Group {
            if let snapshot, snapshot.isSignedIn {
                HStack(alignment: .center, spacing: 14) {
                    myStack(snapshot)
                    friendsPane(snapshot)
                }
                .containerBackground(SpinePalette.paper, for: .widget)
            } else {
                MessageCard(title: "SPINE", subtitle: "Open the app to sign in")
                    .containerBackground(SpinePalette.paper, for: .widget)
            }
        }
        .widgetURL(URL(string: "wellread://queue"))
    }

    @ViewBuilder
    private func myStack(_ snapshot: WidgetSnapshot) -> some View {
        if snapshot.myBooks.isEmpty {
            RoundedRectangle(cornerRadius: 10)
                .fill(SpinePalette.surface)
                .aspectRatio(2 / 3, contentMode: .fit)
                .overlay {
                    Text("Nothing\non deck")
                        .font(.system(size: 11, weight: .medium))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(SpinePalette.textSecondary)
                }
        } else {
            MyBooksFan(books: snapshot.myBooks, tick: tick)
        }
    }

    private func friendsPane(_ snapshot: WidgetSnapshot) -> some View {
        let items = snapshot.friendBookItems
        let pageCount = max(1, Int(ceil(Double(items.count) / Double(Self.friendsPerPage))))
        let pageStart = (tick % pageCount) * Self.friendsPerPage
        let page = Array(items.dropFirst(pageStart).prefix(Self.friendsPerPage))

        return VStack(alignment: .leading, spacing: 7) {
            Text("FRIENDS READING")
                .font(.system(size: 9, weight: .semibold))
                .tracking(1.1)
                .foregroundStyle(SpinePalette.textSecondary)

            if items.isEmpty {
                Text("No one you follow is reading yet")
                    .font(.system(size: 12))
                    .foregroundStyle(SpinePalette.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                // Fixed 3-slot row so covers keep the same size on short pages.
                HStack(alignment: .top, spacing: 10) {
                    ForEach(0..<Self.friendsPerPage, id: \.self) { slot in
                        if slot < page.count {
                            FriendCoverCell(item: page[slot])
                        } else {
                            Color.clear.aspectRatio(2 / 3, contentMode: .fit)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// All of the user's reading-now books fanned into one stack: the front cover
/// is full size, the rest peek out behind it to the right. Each rotation tick
/// brings the next book to the front, so every cover gets its turn.
struct MyBooksFan: View {
    let books: [WidgetSnapshot.BookEntry]
    let tick: Int

    private static let peek: CGFloat = 15
    private static let depthScale: CGFloat = 0.07

    var body: some View {
        let count = books.count
        let front = tick % count
        let ordered = (0..<count).map { books[(front + $0) % count] }

        ZStack(alignment: .bottomLeading) {
            ForEach(Array(ordered.enumerated()), id: \.element.bookId) { depth, book in
                CoverTile(book: book, cornerRadius: 10)
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(SpinePalette.textPrimary.opacity(0.14 * Double(depth)))
                    }
                    .scaleEffect(1 - Self.depthScale * CGFloat(depth), anchor: .bottomLeading)
                    .offset(x: CGFloat(depth) * Self.peek)
                    .zIndex(Double(count - depth))
            }
        }
        .padding(.trailing, CGFloat(count - 1) * Self.peek)
    }
}

// MARK: - Cells

/// Book cover at 2:3 with rounded corners; title tile when no image landed.
struct CoverTile: View {
    let book: WidgetSnapshot.BookEntry
    var cornerRadius: CGFloat = 8

    var body: some View {
        Group {
            if let cover = WidgetImageLoader.image(book.coverFilename) {
                Color.clear
                    .overlay {
                        Image(uiImage: cover)
                            .resizable()
                            .scaledToFill()
                    }
            } else {
                SpinePalette.surface
                    .overlay(alignment: .topLeading) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(book.title)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(SpinePalette.textPrimary)
                                .lineLimit(4)
                            Text(book.author)
                                .font(.system(size: 8))
                                .foregroundStyle(SpinePalette.textSecondary)
                                .lineLimit(1)
                        }
                        .padding(6)
                    }
            }
        }
        .aspectRatio(2 / 3, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}

/// One friend-book pairing with the friend's profile pic badged on the corner.
struct FriendCoverCell: View {
    let item: WidgetSnapshot.FriendBookItem

    var body: some View {
        CoverTile(book: item.book, cornerRadius: 6)
            .overlay(alignment: .bottomLeading) {
                avatarBadge
                    .offset(x: -5, y: 5)
            }
    }

    private var avatarBadge: some View {
        Group {
            if let avatar = WidgetImageLoader.image(item.friend.avatarFilename) {
                Image(uiImage: avatar)
                    .resizable()
                    .scaledToFill()
            } else {
                SpinePalette.avatarColor(for: item.friend.displayName)
                    .overlay {
                        Text(SpinePalette.avatarInitials(for: item.friend.displayName))
                            .font(.system(size: 7.5, weight: .bold))
                            .foregroundStyle(.white)
                            .minimumScaleFactor(0.7)
                    }
            }
        }
        .frame(width: 21, height: 21)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(SpinePalette.paper, lineWidth: 1.5))
    }
}

// MARK: - Fallback cards

/// Small-widget fallback when the cover image is missing: big title on paper.
struct TitleCard: View {
    let book: WidgetSnapshot.BookEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Spacer(minLength: 0)
            Text(book.title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(SpinePalette.textPrimary)
                .lineLimit(4)
                .minimumScaleFactor(0.7)
            Text(book.author)
                .font(.system(size: 11))
                .foregroundStyle(SpinePalette.textSecondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
    }
}

struct MessageCard: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(SpinePalette.textPrimary)
            Text(subtitle)
                .font(.system(size: 11))
                .foregroundStyle(SpinePalette.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}
