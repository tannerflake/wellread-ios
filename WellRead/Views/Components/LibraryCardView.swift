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
    /// Set by on-screen callers to blow the photo up on a long press (see
    /// `AvatarZoomOverlay`). Left nil for the exported image, which is rendered
    /// by ImageRenderer and has nothing to gesture on.
    var onPhotoLongPress: (() -> Void)? = nil

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
        // The card face is one accessibility element, so the hold is discovered
        // by touch, same as holding the avatar on a profile page.
        .contentShape(Circle())
        .onLongPressGesture(minimumDuration: 0.35) { onPhotoLongPress?() }
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

            LibraryCardFace(details: details, palette: .fixedLight)
                .frame(width: 306)
                .shadow(
                    color: Color.black.opacity(background == nil ? 0.16 : 0.38),
                    radius: 16, y: 10
                )

            // The pitch hugs the bottom edge (27px at 3x). Instagram's reply
            // bar no longer overlaps story images.
            ctaBlock
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 9)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .clipped()
    }

    private var ctaBlock: some View {
        HStack(spacing: 8) {
            Text("Track your reading with SPINE")
                .font(.system(size: 12.5, weight: .semibold))
                .tracking(0.3)
                .foregroundStyle(captionColor)
                .lineLimit(1)
                .fixedSize()
            Image("AppStoreBadge")
                .resizable()
                .scaledToFit()
                .frame(height: 22)
                .foregroundStyle(captionColor)
        }
        .shadow(color: Color.black.opacity(background == nil ? 0 : 0.45), radius: 5, y: 1)
    }

    private var captionColor: Color {
        background == nil ? Theme.inkFixed.opacity(0.8) : Color.white.opacity(0.95)
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

    // MARK: Instagram story share

    /// Whether Instagram is installed (and its story scheme is declared in our
    /// Info.plist, so canOpenURL is allowed to answer).
    @MainActor
    static var canShareToInstagramStories: Bool {
        guard let url = URL(string: "instagram-stories://share") else { return false }
        return UIApplication.shared.canOpenURL(url)
    }

    /// Meta's "Sharing to Stories" integration, the same one Strava uses: the
    /// composed canvas rides the pasteboard under Instagram's documented keys
    /// and the instagram-stories:// scheme drops the reader straight into the
    /// story editor with the image preloaded as the background.
    @MainActor
    static func shareToInstagramStories(details: LibraryCardDetails, background: UIImage? = nil) -> Bool {
        guard let image = renderImage(details: details, background: background) else { return false }
        // Photo backgrounds compress far better as JPEG; the plain card keeps
        // PNG so its flat paper tone and thin rules stay crisp.
        let imageData: Data? = background == nil
            ? image.pngData()
            : image.jpegData(compressionQuality: 0.92)
        guard let imageData else { return false }

        let appID = ApiKeys.metaAppID ?? Bundle.main.bundleIdentifier ?? "com.wellread.app"
        guard let url = URL(string: "instagram-stories://share?source_application=\(appID)"),
              UIApplication.shared.canOpenURL(url) else { return false }

        UIPasteboard.general.setItems(
            [[
                "com.instagram.sharedSticker.backgroundImage": imageData,
                "com.instagram.sharedSticker.appID": appID
            ]],
            options: [.expirationDate: Date().addingTimeInterval(60 * 5)]
        )
        UIApplication.shared.open(url)
        return true
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

/// Shared "share the card" control: opens the story composer sheet, where the
/// reader picks a background, then posts to Instagram or saves. The wizard step
/// and the settings sheet behave identically.
struct LibraryCardDownloadButton: View {
    let details: LibraryCardDetails
    /// Ghost styling for the wizard (where Next is the primary action).
    var prominent: Bool = true

    @State private var showComposer = false

    var body: some View {
        Group {
            if prominent {
                WizardCTAButton(title: "View my card", systemImage: "square.and.arrow.up") {
                    showComposer = true
                }
            } else {
                WizardSecondaryButton(title: "View my card", systemImage: "square.and.arrow.up") {
                    showComposer = true
                }
            }
        }
        .sheet(isPresented: $showComposer) {
            LibraryCardStoryComposerSheet(details: details)
        }
    }
}

// MARK: - Instagram share button

/// The Instagram story CTA: official brand gradient, the app glyph, white
/// text, dressed with the same gloss treatment as the app's hero buttons.
/// Deliberately off-palette for SPINE: it borrows Instagram's brand so the
/// destination is unmistakable, matching the share convention users know.
private struct InstagramStoryShareButton: View {
    let action: () -> Void

    /// Instagram's brand gradient, diagonal like their app icon.
    private static let gradient = LinearGradient(
        colors: [
            Color(red: 64/255, green: 93/255, blue: 230/255),
            Color(red: 131/255, green: 58/255, blue: 180/255),
            Color(red: 225/255, green: 48/255, blue: 108/255),
            Color(red: 253/255, green: 89/255, blue: 73/255),
            Color(red: 247/255, green: 119/255, blue: 55/255)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image("InstagramLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 26, height: 26)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                    .shadow(color: Color.black.opacity(0.3), radius: 3, y: 1)
                Text("Share to Instagram Story")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(color: Color.black.opacity(0.18), radius: 2, y: 1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .contentShape(Rectangle())
        }
        .background(Self.gradient, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.35), Color.white.opacity(0.05)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: Theme.shadowInk.opacity(0.30), radius: 9, x: 0, y: 4)
        .buttonStyle(.springPress)
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
    @State private var showPhotoPicker = false
    @State private var backgroundPhoto: UIImage?
    @State private var isSaving = false
    @State private var outcome: LibraryCardExporter.SaveOutcome?
    /// Whether Instagram is installed; decides which action leads.
    @State private var instagramAvailable = false
    @State private var instagramShareFailed = false

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                VStack(spacing: 16) {
                    preview
                    if backgroundPhoto != nil {
                        VStack(spacing: 6) {
                            changePhotoChip
                            WizardGhostButton(title: "No photo, keep it plain") {
                                withAnimation(.easeInOut(duration: 0.2)) { backgroundPhoto = nil }
                            }
                        }
                    }

                    if let resultLine {
                        Text(resultLine.text)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(resultLine.isError ? Theme.danger : Theme.textSecondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .transition(.opacity)
                    }

                    if instagramAvailable {
                        InstagramStoryShareButton {
                            shareToInstagram()
                        }
                        WizardSecondaryButton(title: isSaving ? "Saving…" : "Save to Photos") {
                            save()
                        }
                    } else {
                        WizardCTAButton(title: "Save to Photos", showsProgress: isSaving) {
                            save()
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 12)
                .animation(.easeInOut(duration: 0.2), value: outcome)
                .animation(.easeInOut(duration: 0.2), value: instagramShareFailed)
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
        .photosPicker(isPresented: $showPhotoPicker, selection: $pickerItem, matching: .images)
        .onAppear {
            // -uiPreviewInstagramShare forces the Instagram CTA in the
            // simulator, where Instagram can't be installed.
            instagramAvailable = LibraryCardExporter.canShareToInstagramStories
                || ProcessInfo.processInfo.arguments.contains("-uiPreviewInstagramShare")
        }
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
    /// minimum scale factors resolve identically to the saved image. The whole
    /// preview is the photo picker's tap target: choosing the background IS
    /// tapping the card, with a pulsing hint chip until a photo is picked.
    private var preview: some View {
        GeometryReader { geo in
            let scale = min(
                geo.size.width / LibraryCardStoryCanvas.size.width,
                geo.size.height / LibraryCardStoryCanvas.size.height
            )
            LibraryCardStoryCanvas(details: details, background: backgroundPhoto)
                .overlay(alignment: .bottom) { emptyCanvasPrompt }
                .clipShape(RoundedRectangle(cornerRadius: 36))
                .overlay(
                    RoundedRectangle(cornerRadius: 36)
                        .strokeBorder(Theme.textPrimary.opacity(0.14), lineWidth: 2)
                )
                .contentShape(RoundedRectangle(cornerRadius: 36))
                .onTapGesture { showPhotoPicker = true }
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel(
                    backgroundPhoto == nil ? "Choose a background photo" : "Change the background photo"
                )
                .scaleEffect(scale)
                .frame(width: geo.size.width, height: geo.size.height)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The "no photo yet" prompt, drawn ON the empty canvas where it pulls the
    /// eye into the thing it wants tapped. Safe to sit there because the canvas
    /// is still blank: nothing here can be mistaken for the finished image.
    /// Once a photo lands, this disappears and `changePhotoChip` takes over
    /// below the preview. Fixed ink/paper tones, not Theme.chrome, because the
    /// canvas is always the light card regardless of app appearance.
    ///
    /// The pulse is a phaseAnimator scoped to this view only: an unscoped
    /// repeatForever here would hijack the sheet's drag-to-dismiss tracking.
    @ViewBuilder
    private var emptyCanvasPrompt: some View {
        if backgroundPhoto == nil {
            HStack(spacing: 7) {
                Image(systemName: "photo")
                Text("Tap to choose a background")
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Theme.paperFixed)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Capsule().fill(Theme.inkFixed.opacity(0.85)))
            .padding(.bottom, 150)
            .phaseAnimator([false, true]) { view, pulsing in
                view
                    .scaleEffect(pulsing ? 1.05 : 0.97)
                    .opacity(pulsing ? 1 : 0.72)
            } animation: { _ in .easeInOut(duration: 1.0) }
            // The canvas's own tap gesture opens the picker.
            .allowsHitTesting(false)
        }
    }

    /// The "swap it out" affordance once a photo IS in. Lives below the preview
    /// on purpose: from here on the canvas shows exactly what gets posted, so
    /// anything drawn over it would read as part of the image.
    private var changePhotoChip: some View {
        Button {
            showPhotoPicker = true
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "photo")
                Text("Tap to change the photo")
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Theme.onChrome)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Capsule().fill(Theme.chrome.opacity(0.55)))
            .contentShape(Capsule())
        }
        .buttonStyle(.springPress)
    }

    private var resultLine: (text: String, isError: Bool)? {
        if instagramShareFailed {
            return ("Could not open Instagram. Try again.", true)
        }
        guard let outcome else { return nil }
        switch outcome {
        case .saved: return ("Saved to your Photos. Ready for your story.", false)
        case .permissionDenied: return ("SPINE needs photo access to save your card. Turn it on in Settings.", true)
        case .failed: return ("Could not save your card. Try again.", true)
        }
    }

    private func shareToInstagram() {
        outcome = nil
        instagramShareFailed = !LibraryCardExporter.shareToInstagramStories(
            details: details, background: backgroundPhoto
        )
        if !instagramShareFailed { WizardHaptics.success() }
    }

    private func save() {
        guard !isSaving else { return }
        isSaving = true
        outcome = nil
        instagramShareFailed = false
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

