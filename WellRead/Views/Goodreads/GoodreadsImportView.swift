//
//  GoodreadsImportView.swift
//  WellRead
//
//  Guided Goodreads CSV import: explainer → file picker → preview → import.
//

import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct GoodreadsImportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject var appState: AppState

    /// When non-nil (e.g. from Share Extension), skip explainer and go straight to preview.
    var initialRows: [GoodreadsRow]? = nil

    @State private var step: Step = .explainer
    @State private var showFileImporter = false
    @State private var rows: [GoodreadsRow] = []
    @State private var preview: GoodreadsImportPreview?
    @State private var isBuildingPreview = false
    @State private var isImporting = false
    @State private var importDone = false
    @State private var importProgressCurrent = 0
    @State private var importProgressTotal = 0

    @State private var skipDuplicates = true
    @State private var importRatings = true
    @State private var importReviews = true
    @State private var hasClipboardCSV = false
    @State private var isImportingFromClipboard = false
    @State private var clipboardError: String? = nil

    enum Step {
        case explainer
        case preview
    }

    init(initialRows: [GoodreadsRow]? = nil) {
        self.initialRows = initialRows
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                content
            }
            .navigationTitle("Import from Goodreads")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbarColorScheme(.light, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Theme.accent)
                }
            }
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [.commaSeparatedText, .plainText],
                allowsMultipleSelection: false
            ) { result in
                handleFileResult(result)
            }
            .onAppear {
                if let initial = initialRows, !initial.isEmpty {
                    rows = initial
                    step = .preview
                    isBuildingPreview = true
                    Task {
                        let existingIds = Set(appState.userBooks.map(\.bookId))
                        let p = await GoodreadsImportService().buildPreview(rows: rows, existingBookIds: existingIds)
                        await MainActor.run {
                            preview = p
                            isBuildingPreview = false
                        }
                    }
                } else if step == .explainer {
                    hasClipboardCSV = looksLikeGoodreadsCSV(UIPasteboard.general.string)
                }
            }
            .onChange(of: scenePhase) { _, newValue in
                if newValue == .active, step == .explainer {
                    hasClipboardCSV = looksLikeGoodreadsCSV(UIPasteboard.general.string)
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if importDone {
            importCompleteContent
        } else if isImporting {
            importingContent
        } else {
            switch step {
            case .explainer:
                explainerContent
            case .preview:
                if isBuildingPreview {
                    VStack(spacing: 16) {
                        ProgressView()
                            .tint(Theme.accent)
                            .scaleEffect(1.2)
                        Text("Matching books…")
                            .font(Theme.callout())
                            .foregroundStyle(Theme.textSecondary)
                        Text("This can take a couple of minutes if you have a large library. Keep the app open—maybe go touch grass while you wait.")
                            .font(Theme.caption())
                            .foregroundStyle(Theme.textTertiary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                            .padding(.top, 4)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let preview = preview {
                    previewContent(preview)
                }
            }
        }
    }

    private var importingContent: some View {
        VStack(spacing: 24) {
            ProgressView(value: Double(importProgressCurrent), total: Double(max(1, importProgressTotal)))
                .tint(Theme.accent)
                .padding(.horizontal, 32)
            Text("Importing… \(importProgressCurrent) of \(importProgressTotal)")
                .font(Theme.callout())
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var importCompleteContent: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(Theme.accent)
            Text("Import complete")
                .font(Theme.title2())
                .foregroundStyle(Theme.textPrimary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var explainerContent: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("How to Import:")
                            .font(Theme.headline())
                            .foregroundStyle(Theme.textPrimary)

                        Grid(alignment: .topLeading, horizontalSpacing: 12, verticalSpacing: 12) {
                            GridRow {
                                goodreadsStepNumberBadge(1)
                                goodreadsStepBody("In Goodreads, open your library export (e.g. goodreads_library_export.csv) and highlight all the text, then copy.")
                            }
                            GridRow {
                                goodreadsStepNumberBadge(2)
                                goodreadsStepBody("Come back to Spine and tap \"Allow Paste\".")
                            }
                            GridRow {
                                goodreadsStepNumberBadge(3)
                                goodreadsStepBody("Tap \"I copied my Goodreads data\" below.")
                            }
                        }
                    }

                    if hasClipboardCSV {
                        Button {
                            importFromClipboard()
                        } label: {
                            HStack {
                                if isImportingFromClipboard {
                                    ProgressView()
                                        .tint(Theme.background)
                                } else {
                                    Image(systemName: "doc.on.clipboard")
                                    Text("I copied my Goodreads data")
                                }
                            }
                            .font(Theme.headline())
                            .foregroundStyle(Theme.background)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Theme.accent)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius))
                        }
                        .disabled(isImportingFromClipboard)
                        .padding(.top, 16)
                        if let err = clipboardError {
                            Text(err)
                                .font(Theme.caption())
                                .foregroundStyle(Theme.textTertiary)
                                .padding(.top, 4)
                        }
                    }

                    Button {
                        if let url = URL(string: "https://www.goodreads.com/review/import") {
                            openURL(url)
                        }
                    } label: {
                        Text("Sign into Goodreads")
                            .font(Theme.headline())
                            .foregroundStyle(Theme.background)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Theme.accent)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 24)

                    GoodreadsImportTutorialEmbed()
                        .padding(.top, 20)
                }
                .padding(Theme.cardPadding)
                .padding(.bottom, 8)
            }

            VStack(spacing: 0) {
                Rectangle()
                    .fill(Theme.textTertiary.opacity(0.25))
                    .frame(height: 0.5)

                VStack(alignment: .leading, spacing: 8) {
                    Text("More advanced:")
                        .font(Theme.callout())
                        .foregroundStyle(Theme.textSecondary)

                    Button {
                        showFileImporter = true
                    } label: {
                        Text("Choose CSV file")
                            .font(Theme.callout())
                            .fontWeight(.medium)
                            .foregroundStyle(Theme.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Theme.surface)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius))
                            .overlay(
                                RoundedRectangle(cornerRadius: Theme.cardCornerRadius)
                                    .strokeBorder(Theme.textTertiary.opacity(0.35), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, Theme.cardPadding)
                .padding(.vertical, 12)
                .background(Theme.background.opacity(0.98))
            }
        }
    }

    private func looksLikeGoodreadsCSV(_ string: String?) -> Bool {
        guard let s = string?.trimmingCharacters(in: .whitespacesAndNewlines), s.count > 100 else { return false }
        let head = String(s.prefix(2000))
        return head.contains("Book Id") || head.contains("Title,")
    }

    private func importFromClipboard() {
        clipboardError = nil
        isImportingFromClipboard = true
        let csv = UIPasteboard.general.string ?? ""
        let parsed = GoodreadsCSVParser.parse(csv: csv)
        isImportingFromClipboard = false
        if parsed.isEmpty {
            clipboardError = "No book data found in the clipboard. Make sure you copied the full Goodreads export (it usually starts with \"Book Id\", \"Title\", etc.)."
        } else {
            rows = parsed
            step = .preview
            isBuildingPreview = true
            Task {
                let existingIds = Set(appState.userBooks.map(\.bookId))
                let p = await GoodreadsImportService().buildPreview(rows: rows, existingBookIds: existingIds)
                await MainActor.run {
                    preview = p
                    isBuildingPreview = false
                }
            }
        }
    }

    private func goodreadsStepNumberBadge(_ number: Int) -> some View {
        Text("\(number)")
            .font(Theme.headline())
            .foregroundStyle(Theme.background)
            .frame(width: 28, height: 28)
            .background(Theme.accent)
            .clipShape(Circle())
    }

    private func goodreadsStepBody(_ text: String) -> some View {
        Text(text)
            .font(Theme.callout())
            .foregroundStyle(Theme.textSecondary)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func previewContent(_ preview: GoodreadsImportPreview) -> some View {
        let toImport = preview.matched.filter { !$0.isDuplicate }
        let duplicateCount = preview.duplicateCount

        return ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Import \(toImport.count) books into Spine?")
                    .font(Theme.title2())
                    .foregroundStyle(Theme.textPrimary)
                summarySection(matched: toImport.count, unmatched: preview.unmatched.count, duplicates: duplicateCount)

                Toggle("Skip books already in library", isOn: $skipDuplicates)
                    .tint(Theme.accent)
                Toggle("Import ratings", isOn: $importRatings)
                    .tint(Theme.accent)
                Toggle("Import reviews", isOn: $importReviews)
                    .tint(Theme.accent)

                if !preview.unmatched.isEmpty {
                    Text("\(preview.unmatched.count) book(s) couldn't be matched (missing ISBN in your export, or no exact ISBN match in our catalog) and will be skipped.")
                        .font(Theme.caption())
                        .foregroundStyle(Theme.textTertiary)
                }

                Button {
                    runImport()
                } label: {
                    Text("Import \(toImport.count) books")
                        .font(Theme.headline())
                        .foregroundStyle(Theme.background)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(toImport.isEmpty ? Theme.textTertiary : Theme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius))
                }
                .disabled(toImport.isEmpty || isImporting)
                .padding(.top, 8)
            }
            .padding(Theme.cardPadding)
        }
    }

    private func summarySection(matched: Int, unmatched: Int, duplicates: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Preview")
                .font(Theme.title2())
                .foregroundStyle(Theme.textPrimary)
            HStack(spacing: 16) {
                labelCount("Matched", matched, color: Theme.accent)
                if unmatched > 0 { labelCount("Unmatched", unmatched, color: Theme.textTertiary) }
                if duplicates > 0 { labelCount("Already in library", duplicates, color: Theme.textSecondary) }
            }
        }
    }

    private func labelCount(_ label: String, _ count: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(count)")
                .font(Theme.title())
                .foregroundStyle(color)
            Text(label)
                .font(Theme.caption())
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private func handleFileResult(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        guard url.startAccessingSecurityScopedResource() else {
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }
        do {
            let data = try Data(contentsOf: url)
            rows = GoodreadsCSVParser.parse(data: data)
            if rows.isEmpty {
                return
            }
            step = .preview
            isBuildingPreview = true
            Task {
                let existingIds = Set(appState.userBooks.map(\.bookId))
                let p = await GoodreadsImportService().buildPreview(rows: rows, existingBookIds: existingIds)
                await MainActor.run {
                    preview = p
                    isBuildingPreview = false
                }
            }
        } catch {
            // Could show alert
        }
    }

    private func runImport() {
        guard let preview = preview else { return }
        let toImport = preview.matched.filter { !$0.isDuplicate }
        guard !toImport.isEmpty else { return }
        isImporting = true
        importProgressTotal = preview.matched.count
        importProgressCurrent = 0
        Task {
            await appState.importFromGoodreads(
                items: preview.matched,
                skipDuplicates: skipDuplicates,
                importRatings: importRatings,
                importReviews: importReviews,
                progress: { current, total in
                    Task { @MainActor in
                        self.importProgressCurrent = current
                        self.importProgressTotal = total
                    }
                }
            )
            await MainActor.run {
                isImporting = false
                importDone = true
            }
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            await MainActor.run {
                dismiss()
            }
        }
    }
}
