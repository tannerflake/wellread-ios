//
//  CachedProfileImage.swift
//  WellRead
//
//  Profile avatar loader that uses ProfileImageCache (memory + disk) instead of uncached AsyncImage.
//

import SwiftUI
import UIKit

struct CachedProfileImage<Placeholder: View>: View {
    let url: URL?
    var contentMode: ContentMode = .fill
    @ViewBuilder let placeholder: () -> Placeholder

    @State private var uiImage: UIImage?
    @State private var loadTask: Task<Void, Never>?

    var body: some View {
        Group {
            if let uiImage {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                placeholder()
            }
        }
        .onAppear(perform: loadIfNeeded)
        .onChange(of: url?.absoluteString) { _, _ in
            uiImage = nil
            loadIfNeeded()
        }
        .onDisappear {
            loadTask?.cancel()
            loadTask = nil
        }
    }

    private func loadIfNeeded() {
        loadTask?.cancel()
        guard let url else {
            uiImage = nil
            return
        }
        loadTask = Task {
            let img = await ProfileImageCache.shared.image(for: url)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                uiImage = img
            }
        }
    }
}
