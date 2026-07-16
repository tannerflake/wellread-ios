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
}

enum WidgetImageLoader {
    static func image(_ filename: String?) -> UIImage? {
        guard let url = WidgetSharedStore.imageURL(for: filename) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }
}

// MARK: - Entry view

struct SpineWidgetEntryView: View {
    var entry: SpineEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .systemMedium:
            MediumWidgetView(snapshot: entry.snapshot)
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

// MARK: - Medium: you + friends

struct MediumWidgetView: View {
    let snapshot: WidgetSnapshot?

    var body: some View {
        Group {
            if let snapshot, snapshot.isSignedIn {
                HStack(alignment: .center, spacing: 14) {
                    myCover(snapshot)
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
    private func myCover(_ snapshot: WidgetSnapshot) -> some View {
        if let book = snapshot.myBooks.first {
            CoverTile(book: book, cornerRadius: 10)
        } else {
            RoundedRectangle(cornerRadius: 10)
                .fill(SpinePalette.surface)
                .aspectRatio(2 / 3, contentMode: .fit)
                .overlay {
                    Text("Nothing\non deck")
                        .font(.system(size: 11, weight: .medium))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(SpinePalette.textSecondary)
                }
        }
    }

    private func friendsPane(_ snapshot: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("FRIENDS ARE READING")
                .font(.system(size: 9, weight: .semibold))
                .tracking(1.1)
                .foregroundStyle(SpinePalette.textSecondary)

            if snapshot.friends.isEmpty {
                Text("No friends reading yet")
                    .font(.system(size: 12))
                    .foregroundStyle(SpinePalette.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(snapshot.friends.prefix(4), id: \.uid) { friend in
                        FriendCoverCell(friend: friend)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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

/// Friend's current read with their profile pic badged on the corner.
struct FriendCoverCell: View {
    let friend: WidgetSnapshot.FriendEntry

    var body: some View {
        if let book = friend.books.first {
            CoverTile(book: book, cornerRadius: 6)
                .overlay(alignment: .bottomLeading) {
                    avatarBadge
                        .offset(x: -5, y: 5)
                }
        }
    }

    private var avatarBadge: some View {
        Group {
            if let avatar = WidgetImageLoader.image(friend.avatarFilename) {
                Image(uiImage: avatar)
                    .resizable()
                    .scaledToFill()
            } else {
                SpinePalette.chrome
                    .overlay {
                        Text(friend.displayName.prefix(1).uppercased())
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(SpinePalette.onChrome)
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
