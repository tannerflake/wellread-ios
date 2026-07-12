//
//  TagCatalogPicker.swift
//  Spine
//
//  Sectioned Tags.csv chip grid (onboarding order). Shared by onboarding step 2,
//  Edit profile, and the Discover criteria editor.
//

import SwiftUI

struct TagCatalogPicker: View {
    @Binding var selected: Set<String>

    var body: some View {
        ForEach(WellReadTagCatalog.shared.onboardingSectionsOrdered(), id: \.category) { section in
            VStack(alignment: .leading, spacing: 10) {
                Text(section.category.uppercased())
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
                    .tracking(0.6)
                FlowLayout(spacing: 10) {
                    ForEach(section.tags, id: \.self) { tag in
                        chip(tag)
                    }
                }
            }
        }
    }

    private func chip(_ tag: String) -> some View {
        Button {
            if selected.contains(tag) {
                selected.remove(tag)
            } else {
                selected.insert(tag)
            }
        } label: {
            let isSelected = selected.contains(tag)
            Text(tag)
                .font(Theme.callout())
                .foregroundStyle(isSelected ? Theme.accent : Theme.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .strokeBorder(isSelected ? Theme.accent : Color.white.opacity(0.12), lineWidth: isSelected ? 2 : 1)
                )
        }
        .buttonStyle(.plain)
    }
}
