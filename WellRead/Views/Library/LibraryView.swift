//
//  LibraryView.swift
//  WellRead
//
//  Library-only tab (labeled "Profile" in tab bar): "Your Library". Profile photo in top-right toolbar.
//

import SwiftUI
import PhotosUI

// MARK: - Library (Profile tab content)

struct ProfileLibraryView: View {
    @EnvironmentObject var authService: AuthService
    @EnvironmentObject var appState: AppState
    @State private var segment: LibrarySegment = .read
    @State private var viewMode: LibraryViewMode = .tierList
    @State private var selectedYear: Int? = nil
    @State private var selectedBookForProfile: Book? = nil
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var isUploadingPhoto = false
    @State private var photoUploadError: String? = nil

    enum LibrarySegment: String, CaseIterable {
        case read = "Read"
        case wantToRead = "Queue"
    }

    var filteredBooks: [UserBook] {
        switch segment {
        case .read: return readBooksFilteredByYear
        case .wantToRead: return appState.wantToRead
        }
    }

    private var readBooksFilteredByYear: [UserBook] {
        let read = appState.readBooks
        guard let year = selectedYear else { return read }
        return read.filter { ub in
            guard let d = ub.dateFinished else { return false }
            return Calendar.current.component(.year, from: d) == year
        }
    }

    private var availableYears: [Int] {
        let years = Set(appState.readBooks.compactMap { ub -> Int? in
            ub.dateFinished.map { Calendar.current.component(.year, from: $0) }
        })
        return years.sorted(by: >)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                VStack(spacing: 0) {
                    if segment == .read && !availableYears.isEmpty {
                        yearFilterBar
                    }

                    Picker("", selection: $segment) {
                        ForEach(LibrarySegment.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .padding()

                    libraryContent
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .navigationDestination(item: $selectedBookForProfile) { book in
                BookProfileView(
                    book: book,
                    readBooksForSimilar: appState.readBooks,
                    onNotInterested: nil,
                    onWantToRead: { appState.addToWantToRead(book: book); selectedBookForProfile = nil },
                    onHaveRead: { appState.addAsRead(book: book); selectedBookForProfile = nil }
                )
                .padding(.horizontal)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Your Library")
                        .font(Theme.title())
                        .foregroundStyle(Theme.textPrimary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    toolbarProfilePhoto
                }
            }
            .onChange(of: selectedPhotoItem) { _, newItem in
                guard let item = newItem else { return }
                Task { await uploadSelectedPhoto(item) }
            }
        }
    }

    @ViewBuilder
    private var toolbarProfilePhoto: some View {
        if let user = appState.currentUser, authService.firebaseUser?.uid != nil {
            Menu {
                PhotosPicker(selection: $selectedPhotoItem, matching: .images, photoLibrary: .shared()) {
                    Text("Change photo")
                }
                .disabled(isUploadingPhoto)
                ForEach(LibraryViewMode.allCases, id: \.self) { mode in
                    Button {
                        viewMode = mode
                    } label: {
                        Label(mode.label, systemImage: mode.icon)
                    }
                }
                Divider()
                Button("Sign out", role: .destructive) {
                    authService.signOut()
                }
            } label: {
                ZStack {
                    if let urlString = user.profileImageURL, let url = URL(string: urlString) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            case .failure, .empty:
                                avatarPlaceholder(initial: String(user.displayName.prefix(1)), compact: true)
                            @unknown default:
                                avatarPlaceholder(initial: String(user.displayName.prefix(1)), compact: true)
                            }
                        }
                    } else {
                        avatarPlaceholder(initial: String(user.displayName.prefix(1)), compact: true)
                    }
                    if isUploadingPhoto {
                        Color.black.opacity(0.4)
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(0.8)
                    }
                }
                .frame(width: 36, height: 36)
                .clipShape(Circle())
            }
            .buttonStyle(.plain)
        } else {
            Menu {
                ForEach(LibraryViewMode.allCases, id: \.self) { mode in
                    Button {
                        viewMode = mode
                    } label: {
                        Label(mode.label, systemImage: mode.icon)
                    }
                }
                Divider()
                Button("Sign out", role: .destructive) {
                    authService.signOut()
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private func avatarPlaceholder(initial: String, compact: Bool = false) -> some View {
        Circle()
            .fill(Theme.surface)
            .overlay(
                Text(initial)
                    .font(compact ? Theme.headline() : Theme.largeTitle())
                    .foregroundStyle(Theme.textSecondary)
            )
    }

    private func uploadSelectedPhoto(_ item: PhotosPickerItem) async {
        guard let uid = authService.firebaseUser?.uid else { return }
        await MainActor.run { isUploadingPhoto = true; photoUploadError = nil }
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                await MainActor.run { photoUploadError = "Could not load image"; isUploadingPhoto = false }
                return
            }
            let urlString = try await ProfilePhotoService.uploadProfilePhoto(uid: uid, image: image)
            try await UserRepository().updateProfileImageURL(uid: uid, url: urlString)
            await authService.refreshAppUser()
            await MainActor.run {
                appState.currentUser = authService.appUser
                isUploadingPhoto = false
                photoUploadError = nil
                selectedPhotoItem = nil
            }
        } catch {
            await MainActor.run {
                photoUploadError = error.localizedDescription
                isUploadingPhoto = false
                selectedPhotoItem = nil
            }
        }
    }

    private var yearFilterBar: some View {
        HStack(spacing: 8) {
            Text("Year:")
                .font(Theme.caption())
                .foregroundStyle(Theme.textSecondary)
            Menu {
                Button("All") { selectedYear = nil }
                ForEach(availableYears, id: \.self) { year in
                    Button(String(year)) { selectedYear = year }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(selectedYear.map { String($0) } ?? "All")
                        .font(Theme.callout())
                        .foregroundStyle(Theme.textPrimary)
                    Image(systemName: "chevron.down.circle.fill")
                        .font(.caption)
                        .foregroundStyle(Theme.textTertiary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            Spacer()
        }
        .padding(.horizontal)
        .padding(.top, 4)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var libraryContent: some View {
        if viewMode == .tierList && segment == .read {
            TierListView(userBooks: readBooksFilteredByYear, onUpdateTierAndOrder: { id, tier, order in
                appState.setTierAndOrder(for: id, tier: tier, order: order)
            }, onBookTap: { selectedBookForProfile = $0 })
        } else {
            GridLibraryView(
                userBooks: filteredBooks,
                onMoveToRead: segment == .wantToRead ? { appState.moveToRead($0) } : nil,
                onBookTap: { selectedBookForProfile = $0 }
            )
        }
    }
}

// MARK: - Library view mode (shared)

enum LibraryViewMode: String, CaseIterable {
    case tierList
    case grid
    var icon: String {
        switch self {
        case .tierList: return "list.number"
        case .grid: return "square.grid.2x2"
        }
    }
    var label: String {
        switch self {
        case .tierList: return "Tier List"
        case .grid: return "Grid"
        }
    }
}
