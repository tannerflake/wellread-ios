//
//  BookCoverView.swift
//  WellRead
//

import SwiftUI

struct BookCoverView: View {
    let book: Book
    var size: CGFloat = 80
    
    var body: some View {
        Group {
            if let url = book.coverURLRequest, !book.coverURL.isEmpty {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fill)
                    case .failure:
                        placeholder
                    case .empty:
                        placeholder.overlay(ProgressView().tint(Theme.accent))
                    @unknown default:
                        placeholder
                    }
                }
            } else {
                placeholder
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
