//
//  LibraryCardView.swift
//  WellRead
//
//  The SPINE library card as a reusable, static face (no stamp choreography):
//  used by the profile card page (yours and other members') and by the
//  downloadable image both there and at the end of the onboarding wizard. The
//  wizard's own card (WizardCardStep) keeps its animated copy of this layout
//  because it stamps each field on individually. Copy rule: no em-dashes in
//  user-facing text.
//

import SwiftUI
import Photos
import PhotosUI
import UIKit

// MARK: - Details

/// Everything the card prints. Built from the wizard model or from a User doc.
struct LibraryCardDetails: Equatable {
    var name: String
    var handle: String
    var cardNumber: Int
    var memberSinceText: String
    var goalText: String
    /// Resolved avatar. Nil falls back to the ink monogram.
    var photo: UIImage?
    var monogramInitial: String
    /// Whether this member's OG stamp should show. Decided once at account
    /// creation and stored on the user doc (`User.ogIneligible`), NOT recomputed
    /// from `cardNumber` here — a live comparison would strip the stamp from
    /// members who already had it once real growth pushes past the cutoff.
    var isOGEligible: Bool

    static func from(user: User, cardNumber: Int, photo: UIImage?) -> LibraryCardDetails {
        let first = user.firstName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let last = user.lastName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let joined = [first, last].filter { !$0.isEmpty }.joined(separator: " ")
        let name = joined.isEmpty ? user.displayName : joined
        return LibraryCardDetails(
            name: name,
            handle: user.username,
            cardNumber: cardNumber,
            memberSinceText: Self.memberSince(user.joinedAt),
            goalText: Self.goalText(user.readingGoal),
            photo: photo,
            monogramInitial: String((name.isEmpty ? "R" : name).prefix(1)),
            isOGEligible: !user.ogIneligible
        )
    }

    /// OG stamp cutoff: new accounts only get the badge if fewer than this many
    /// real members (see `UserRepository.memberNumber`) existed at signup. Read
    /// once at creation into `User.ogIneligible`, not re-checked on every card
    /// view. Shared with `UserRepository.ensureUserDocument` and `WizardCardStep`.
    static let ogCutoff = 250

    static func memberSince(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM yyyy"
        return formatter.string(from: date).uppercased()
    }

    /// Same wording as the wizard's card stamp.
    static func goalText(_ goal: Int?) -> String {
        let year = Calendar.current.component(.year, from: Date())
        guard let goal, goal > 0 else { return "\(year): READING FREELY" }
        return "\(year) GOAL: \(goal) BOOKS"
    }
}

// MARK: - Palette

/// The card's tones. `.adaptive` follows the app appearance (for on-screen use);
/// `.fixedLight` is the printed card, used for the exported image so a download
/// taken in dark mode is still a cream card on white paper.
struct LibraryCardPalette {
    let page: Color
    let ink: Color
    let secondary: Color
    let tertiary: Color
    let stamp: Color

    static let adaptive = LibraryCardPalette(
        page: Theme.surfaceElevated,
        ink: Theme.textPrimary,
        secondary: Theme.textSecondary,
        tertiary: Theme.textTertiary,
        stamp: Theme.danger
    )

    static let fixedLight = LibraryCardPalette(
        page: Color(red: 246/255, green: 247/255, blue: 238/255),
        ink: Theme.inkFixed,
        secondary: Color(red: 69/255, green: 66/255, blue: 75/255),
        tertiary: Color(red: 129/255, green: 126/255, blue: 134/255),
        stamp: Color(red: 176/255, green: 53/255, blue: 44/255)
    )
}

// MARK: - Card face

struct LibraryCardFace: View {
    let details: LibraryCardDetails
    var palette: LibraryCardPalette = .adaptive

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Rectangle()
                .fill(palette.ink)
                .frame(height: 2)
            identityRow
            goalStamp
                .rotationEffect(.degrees(-1.8))
            Rectangle()
                .fill(palette.ink.opacity(0.18))
                .frame(height: 1)
            footer
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(palette.page)
                .overlay(watermark)
                .clipShape(RoundedRectangle(cornerRadius: 18))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(palette.ink, lineWidth: 2)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Library card number \(details.cardNumber). \(details.name), at \(details.handle). Member since \(details.memberSinceText)."
        )
    }

    private var watermark: some View {
        Image("SpineLogo")
            .resizable()
            .renderingMode(.template)
            .scaledToFit()
            .frame(width: 220)
            .foregroundStyle(palette.ink.opacity(0.05))
            .rotationEffect(.degrees(-10))
            .offset(x: 60, y: 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
            .allowsHitTesting(false)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("SPINE")
                .font(.system(size: 15, weight: .heavy))
                .tracking(4)
                .foregroundStyle(palette.ink)
            Spacer()
            Text("CARD № \(details.cardNumber)")
                .font(.system(size: 10.5, weight: .bold))
                .monospacedDigit()
                .tracking(1.4)
                .foregroundStyle(palette.tertiary)
        }
    }

    private var identityRow: some View {
        HStack(spacing: 16) {
            photoCircle
                .rotationEffect(.degrees(-2))
                .overlay(alignment: .topLeading) {
                    if details.isOGEligible {
                        ogStamp
                            .rotationEffect(.degrees(-14))
                            .offset(x: -12, y: -9)
                    }
                }
                .zIndex(1)
            // Long names have to shrink rather than push the card wider: in a
            // fixed-width frame the overflow clips the card's own border.
            VStack(alignment: .leading, spacing: 3) {
                Text(details.name)
                    .font(.system(size: 21, weight: .bold))
                    .foregroundStyle(palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                    .rotationEffect(.degrees(1.2))
                Text("@\(details.handle)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .rotationEffect(.degrees(-1.4))
            }
            Spacer(minLength: 0)
        }
    }

    /// Red is reserved for danger everywhere else in the app; here it is ink
    /// from a real rubber stamp, which is the one place it belongs.
    private var ogStamp: some View {
        Text("OG")
            .font(.system(size: 13, weight: .heavy))
            .tracking(1.8)
            .foregroundStyle(palette.stamp)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(palette.stamp, lineWidth: 1.8)
            )
    }

    private var photoCircle: some View {
        Group {
            if let photo = details.photo {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Circle().fill(palette.ink)
                    Text(details.monogramInitial)
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(palette.page)
                }
            }
        }
        .frame(width: 66, height: 66)
        .clipShape(Circle())
        .overlay(Circle().stroke(palette.ink, lineWidth: 2))
    }

    private var goalStamp: some View {
        Text(details.goalText)
            .font(.system(size: 12, weight: .heavy))
            .tracking(1.4)
            .foregroundStyle(palette.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(palette.ink, lineWidth: 1.5)
            )
    }

    private var footer: some View {
        HStack {
            Text("MEMBER SINCE \(details.memberSinceText)")
                .font(.system(size: 10, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(palette.tertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer()
        }
        .frame(minHeight: 16)
    }
}

// MARK: - Exported image

/// What actually gets saved to Photos: a full 9:16 story canvas (360x640
/// points, rendered at 3x for exactly 1080x1920 pixels, Instagram's story
/// size) so posting it needs no cropping. The card sits centered on either
/// the reader's chosen photo or the plain paper tone, with the App Store
/// line under it so a shared story tells people where to get SPINE.
struct LibraryCardStoryCanvas: View {
    let details: LibraryCardDetails
    /// Photo behind the card. Nil prints the plain paper background.
    var background: UIImage?

    /// Canvas in points. Rendered at 3x this is 1080x1920 pixels.
    static let size = CGSize(width: 360, height: 640)

    var body: some View {
        ZStack {
            backgroundLayer
            VStack(spacing: 24) {
                LibraryCardFace(details: details, palette: .fixedLight)
                    .frame(width: 306)
                    .shadow(
                        color: Color.black.opacity(background == nil ? 0.16 : 0.38),
                        radius: 16, y: 10
                    )

                Text("Download SPINE (Reading Tracker) in the App Store")
                    .font(.system(size: 13, weight: .semibold))
                    .tracking(0.3)
                    .foregroundStyle(captionColor)
                    .shadow(color: Color.black.opacity(background == nil ? 0 : 0.45), radius: 5, y: 1)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: 306)
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .clipped()
    }

    private var captionColor: Color {
        background == nil ? Theme.inkFixed.opacity(0.72) : Color.white.opacity(0.95)
    }

    @ViewBuilder
    private var backgroundLayer: some View {
        if let background {
            Image(uiImage: background)
                .resizable()
                .scaledToFill()
                .frame(width: Self.size.width, height: Self.size.height)
                .clipped()
                // Thin scrim so the card and caption read on any photo.
                .overlay(Color.black.opacity(0.15))
        } else {
            Theme.paperFixed
        }
    }
}

enum LibraryCardExporter {

    enum SaveOutcome {
        case saved
        case permissionDenied
        case failed
    }

    /// Renders the story canvas at 3x: 360x640 points comes out as exactly
    /// 1080x1920 pixels, the native Instagram story resolution.
    @MainActor
    static func renderImage(details: LibraryCardDetails, background: UIImage? = nil) -> UIImage? {
        let renderer = ImageRenderer(
            content: LibraryCardStoryCanvas(details: details, background: background)
        )
        renderer.scale = 3
        renderer.proposedSize = ProposedViewSize(LibraryCardStoryCanvas.size)
        return renderer.uiImage
    }

    /// Saves to the user's photo library, asking for add-only access first.
    static func saveToPhotos(details: LibraryCardDetails, background: UIImage? = nil) async -> SaveOutcome {
        guard let image = await renderImage(details: details, background: background) else { return .failed }
        let status = await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                continuation.resume(returning: status)
            }
        }
        guard status == .authorized || status == .limited else { return .permissionDenied }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }
            return .saved
        } catch {
            return .failed
        }
    }

    /// Resolves the avatar to a UIImage up front: ImageRenderer cannot wait on
    /// an async loader, so an unresolved photo would export as the monogram.
    static func loadPhoto(urlString: String?) async -> UIImage? {
        guard let urlString, let url = URL(string: urlString) else { return nil }
        if let cached = ProfileImageCache.shared.memoryImage(for: url) { return cached }
        return await ProfileImageCache.shared.image(for: url)
    }
}

// MARK: - Download button

/// Shared "download the card" control: opens the story composer sheet, where
/// the reader picks a background and saves. The wizard step and the settings
/// sheet behave identically.
struct LibraryCardDownloadButton: View {
    let details: LibraryCardDetails
    /// Ghost styling for the wizard (where Next is the primary action).
    var prominent: Bool = true

    @State private var showComposer = false

    var body: some View {
        Group {
            if prominent {
                WizardCTAButton(title: "Download my card") {
                    showComposer = true
                }
            } else {
                WizardSecondaryButton(title: "Download my card") {
                    showComposer = true
                }
            }
        }
        .sheet(isPresented: $showComposer) {
            LibraryCardStoryComposerSheet(details: details)
        }
    }
}

// MARK: - Story composer sheet

/// The step between "Download my card" and the saved image: a live preview of
/// the story canvas where the reader can put a photo of their own behind the
/// card, or keep the plain paper background, then save.
struct LibraryCardStoryComposerSheet: View {
    let details: LibraryCardDetails

    @Environment(\.dismiss) private var dismiss

    @State private var pickerItem: PhotosPickerItem?
    @State private var backgroundPhoto: UIImage?
    @State private var isSaving = false
    @State private var outcome: LibraryCardExporter.SaveOutcome?

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                VStack(spacing: 16) {
                    preview
                    photoControls

                    if let outcome {
                        Text(message(for: outcome))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(outcome == .saved ? Theme.textSecondary : Theme.danger)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .transition(.opacity)
                    }

                    WizardCTAButton(title: "Save to Photos", showsProgress: isSaving) {
                        save()
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 12)
                .animation(.easeInOut(duration: 0.2), value: outcome)
            }
            .navigationTitle("Your story card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .foregroundStyle(Theme.textPrimary)
                    }
                    .accessibilityLabel("Close")
                }
            }
        }
        .presentationDragIndicator(.visible)
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                let image = await Self.loadUIImage(from: item)
                await MainActor.run {
                    if let image {
                        withAnimation(.easeInOut(duration: 0.2)) { backgroundPhoto = image }
                    }
                    // Re-arm the picker so choosing the same photo again works.
                    pickerItem = nil
                }
            }
        }
    }

    /// The exact canvas that gets exported, scaled to fit the sheet. Sizing is
    /// done with scaleEffect rather than a smaller layout so text wrapping and
    /// minimum scale factors resolve identically to the saved image.
    private var preview: some View {
        GeometryReader { geo in
            let scale = min(
                geo.size.width / LibraryCardStoryCanvas.size.width,
                geo.size.height / LibraryCardStoryCanvas.size.height
            )
            LibraryCardStoryCanvas(details: details, background: backgroundPhoto)
                .clipShape(RoundedRectangle(cornerRadius: 36))
                .overlay(
                    RoundedRectangle(cornerRadius: 36)
                        .strokeBorder(Theme.textPrimary.opacity(0.14), lineWidth: 2)
                )
                .scaleEffect(scale)
                .frame(width: geo.size.width, height: geo.size.height)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var photoControls: some View {
        VStack(spacing: 8) {
            PhotosPicker(selection: $pickerItem, matching: .images, photoLibrary: .shared()) {
                Label(
                    backgroundPhoto == nil ? "Choose a background photo" : "Change photo",
                    systemImage: "photo"
                )
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Theme.textPrimary.opacity(0.22), lineWidth: 1.5)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.springPress)

            if backgroundPhoto != nil {
                WizardGhostButton(title: "No photo, keep it plain") {
                    withAnimation(.easeInOut(duration: 0.2)) { backgroundPhoto = nil }
                }
            }
        }
    }

    private func message(for outcome: LibraryCardExporter.SaveOutcome) -> String {
        switch outcome {
        case .saved: return "Saved to your Photos. Ready for your story."
        case .permissionDenied: return "SPINE needs photo access to save your card. Turn it on in Settings."
        case .failed: return "Could not save your card. Try again."
        }
    }

    private func save() {
        guard !isSaving else { return }
        isSaving = true
        outcome = nil
        let background = backgroundPhoto
        Task {
            let result = await LibraryCardExporter.saveToPhotos(details: details, background: background)
            await MainActor.run {
                isSaving = false
                outcome = result
                if result == .saved { WizardHaptics.success() }
            }
        }
    }

    private static func loadUIImage(from item: PhotosPickerItem) async -> UIImage? {
        if let data = try? await item.loadTransferable(type: Data.self),
           let image = UIImage(data: data) {
            return image
        }
        guard let url = try? await item.loadTransferable(type: URL.self) else { return nil }
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        if let data = try? Data(contentsOf: url), let image = UIImage(data: data) {
            return image
        }
        if FileManager.default.fileExists(atPath: url.path) {
            return UIImage(contentsOfFile: url.path)
        }
        return nil
    }
}

