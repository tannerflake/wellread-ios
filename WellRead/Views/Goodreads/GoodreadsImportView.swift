//
//  GoodreadsImportView.swift
//  WellRead
//
//  Goodreads import wizard. Single entry path: grab the CSV export from
//  Goodreads (in-app browser) or upload it. Read books are reviewed one at a
//  time on an inline-editable card (stars, date read, tier, review → Skip /
//  Looks good), then the user is offered their queue (to-read) books. Progress
//  is persisted after every action so closing the app resumes exactly where
//  they left off.
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - Model

@MainActor
final class GoodreadsWizardModel: ObservableObject {
    enum Step: Equatable {
        case explainer
        case readWizard
        case queuePrompt
        case queueWizard
        case bulkImporting
        case done
    }

    enum MatchState: Equatable {
        case matching
        case matched(Book)
        case unmatched
    }

    @Published var step: Step = .explainer
    @Published private(set) var session: GoodreadsWizardSession?
    @Published private(set) var matchStates: [String: MatchState] = [:]
    @Published var bulkDone = 0
    @Published var bulkTotal = 0
    @Published var parseError: String?

    private let service = GoodreadsImportService()
    private weak var appState: AppState?
    private var inFlightRowIds: Set<String> = []
    /// Imported this session — the Firestore listener lags the write, so `appState.userBooks` alone can't catch same-session duplicates.
    private var importedBookIds: Set<String> = []
    private var configured = false

    /// How many upcoming books to match ahead of the user so cards appear instantly.
    private let prefetchWindow = 4

    var currentRow: GoodreadsRow? { session?.currentRow }

    var currentMatch: MatchState? {
        currentRow.flatMap { matchStates[$0.id] }
    }

    var currentBook: Book? {
        if case .matched(let b)? = currentMatch { return b }
        return nil
    }

    func configure(appState: AppState, initialRows: [GoodreadsRow]?) {
        guard !configured else { return }
        configured = true
        self.appState = appState
        if let rows = initialRows, !rows.isEmpty {
            startSession(rows: rows)
        } else if let saved = appState.loadGoodreadsWizardSession(), saved.hasRemainingWork {
            resume(saved)
        }
    }

    // MARK: Session lifecycle

    func startSession(rows: [GoodreadsRow]) {
        parseError = nil
        var s = GoodreadsWizardSession.fromRows(rows)
        guard !s.readRows.isEmpty || !s.queueRows.isEmpty else {
            parseError = "No books were found in that file. Make sure it's your Goodreads library export (goodreads_library_export.csv)."
            return
        }
        if s.readRows.isEmpty {
            s.phase = .queuePrompt
        }
        session = s
        matchStates = [:]
        importedBookIds = []
        persist()
        enterStep(for: s.phase)
        advancePastUndecidable()
    }

    private func resume(_ saved: GoodreadsWizardSession) {
        session = saved
        matchStates = saved.matchedBooks.mapValues { .matched($0) }
        enterStep(for: saved.phase)
        advancePastUndecidable()
    }

    func startOver() {
        appState?.clearGoodreadsWizardSession()
        session = nil
        matchStates = [:]
        importedBookIds = []
        parseError = nil
        step = .explainer
    }

    private func enterStep(for phase: GoodreadsWizardPhase) {
        switch phase {
        case .readBooks: step = .readWizard
        case .queuePrompt: step = .queuePrompt
        case .queueBooks: step = .queueWizard
        case .done: step = .done
        }
    }

    private func persist() {
        guard let s = session else { return }
        appState?.saveGoodreadsWizardSession(s)
    }

    // MARK: Matching

    private var pendingActiveRows: [GoodreadsRow] {
        guard let s = session else { return [] }
        return s.activeRows.filter { s.decisions[$0.id] == nil }
    }

    private func prefetchMatches() {
        guard let s = session, s.phase == .readBooks || s.phase == .queueBooks else { return }
        for row in pendingActiveRows.prefix(prefetchWindow) {
            guard matchStates[row.id] == nil, !inFlightRowIds.contains(row.id) else { continue }
            inFlightRowIds.insert(row.id)
            matchStates[row.id] = .matching
            Task { [weak self] in
                guard let self else { return }
                let book = await self.service.matchRowToBook(row)
                self.inFlightRowIds.remove(row.id)
                if let book {
                    self.matchStates[row.id] = .matched(book)
                    self.session?.matchedBooks[row.id] = book
                    self.persist()
                } else {
                    self.matchStates[row.id] = .unmatched
                }
                self.advancePastUndecidable()
            }
        }
    }

    /// Skip forward over rows the user never needs to see: unmatched rows
    /// (never surface unconfident matches) and books already in the library.
    private func advancePastUndecidable() {
        guard var s = session else { return }
        var changed = false
        loop: while let row = s.currentRow {
            switch matchStates[row.id] {
            case .none, .matching:
                break loop
            case .unmatched:
                s.decisions[row.id] = .unmatched
                changed = true
            case .matched(let book):
                if isDuplicate(book) {
                    // Re-read of a book already on the shelf: log the date on the
                    // existing entry (single tier entry, extra year for goals).
                    if s.phase == .readBooks, let appState {
                        let dateRead = row.dateRead
                        Task { await appState.mergeGoodreadsReReadDate(bookId: book.id, dateRead: dateRead) }
                    }
                    s.decisions[row.id] = .duplicate
                    changed = true
                } else {
                    break loop
                }
            }
        }
        if changed {
            session = s
            persist()
        }
        transitionIfPhaseFinished()
        prefetchMatches()
    }

    private func isDuplicate(_ book: Book) -> Bool {
        guard let appState else { return false }
        if importedBookIds.contains(book.id) { return true }
        switch session?.phase {
        case .queuePrompt, .queueBooks:
            return appState.isBookInQueue(bookId: book.id) || appState.isBookOnReadList(bookId: book.id)
        default:
            return appState.isBookOnReadList(bookId: book.id)
        }
    }

    // MARK: Decisions

    private func decideCurrent(_ decision: GoodreadsRowDecision) {
        guard var s = session, let row = s.currentRow else { return }
        s.decisions[row.id] = decision
        session = s
        persist()
        advancePastUndecidable()
    }

    func skipCurrent() {
        decideCurrent(.skipped)
    }

    /// "Looks good" — import with the values currently on the card (all inline-editable).
    func acceptCurrentEdited(stars: Int?, review: String?, dateFinished: Date?, tier: String?) {
        guard currentRow != nil, let book = currentBook else { return }
        importRead(
            book: book,
            rating: GoodreadsImportService.ratingOutOfTen(from: stars),
            review: review,
            dateFinished: dateFinished,
            tier: tier
        )
    }

    private func importRead(book: Book, rating: Double?, review: String?, dateFinished: Date?, tier: String?) {
        guard let appState else { return }
        importedBookIds.insert(book.id)
        decideCurrent(.imported)
        Task {
            _ = await appState.importGoodreadsReadBook(book: book, rating: rating, review: review, dateFinished: dateFinished, tier: tier)
        }
    }

    // MARK: Queue phase

    func chooseQueueOneByOne() {
        guard var s = session else { return }
        s.phase = .queueBooks
        session = s
        persist()
        step = .queueWizard
        advancePastUndecidable()
    }

    func declineQueue() {
        guard var s = session else { return }
        for row in s.queueRows where s.decisions[row.id] == nil {
            s.decisions[row.id] = .declined
        }
        session = s
        finish()
    }

    // MARK: Summary screen

    /// Books the user tapped Skip on (matched book included when we have it).
    var skippedBooks: [(row: GoodreadsRow, book: Book?)] {
        guard let s = session else { return [] }
        return (s.readRows + s.queueRows)
            .filter { s.decisions[$0.id] == .skipped }
            .map { ($0, s.matchedBooks[$0.id]) }
    }

    /// Rows that never got a confident catalog match.
    var unmatchedRows: [GoodreadsRow] {
        guard let s = session else { return [] }
        return (s.readRows + s.queueRows).filter { s.decisions[$0.id] == .unmatched }
    }

    /// Put every user-skipped book back in play and jump back into the wizard.
    func reopenSkippedBooks() {
        guard var s = session else { return }
        var reopenedRead = false
        var reopenedQueue = false
        for row in s.readRows where s.decisions[row.id] == .skipped {
            s.decisions.removeValue(forKey: row.id)
            reopenedRead = true
        }
        for row in s.queueRows where s.decisions[row.id] == .skipped {
            s.decisions.removeValue(forKey: row.id)
            reopenedQueue = true
        }
        guard reopenedRead || reopenedQueue else { return }
        s.phase = reopenedRead ? .readBooks : .queueBooks
        session = s
        persist()
        enterStep(for: s.phase)
        advancePastUndecidable()
    }

    func acceptCurrentQueueBook() {
        guard let book = currentBook, let appState else { return }
        importedBookIds.insert(book.id)
        decideCurrent(.imported)
        Task {
            _ = await appState.importGoodreadsQueueBook(book: book)
        }
    }

    // MARK: Bulk import (import-all)

    /// Import every remaining book in the active phase automatically (no tiers).
    func importAllRemaining() {
        // From the queue prompt, "Add all automatically" starts the queue phase.
        if var s = session, s.phase == .queuePrompt {
            s.phase = .queueBooks
            session = s
            persist()
        }
        guard let s = session, s.phase == .readBooks || s.phase == .queueBooks else { return }
        let rows = pendingActiveRows
        guard !rows.isEmpty else { return }
        let phase = s.phase
        bulkTotal = rows.count
        bulkDone = 0
        step = .bulkImporting
        Task { [weak self] in
            guard let self else { return }
            for row in rows {
                let book: Book?
                switch self.matchStates[row.id] {
                case .matched(let b): book = b
                case .unmatched: book = nil
                default: book = await self.service.matchRowToBook(row)
                }
                let decision: GoodreadsRowDecision
                if let book {
                    self.matchStates[row.id] = .matched(book)
                    self.session?.matchedBooks[row.id] = book
                    if self.isDuplicate(book) {
                        if phase == .readBooks {
                            await self.appState?.mergeGoodreadsReReadDate(bookId: book.id, dateRead: row.dateRead)
                        }
                        decision = .duplicate
                    } else if let appState = self.appState {
                        let ok: Bool
                        if phase == .readBooks {
                            ok = await appState.importGoodreadsReadBook(
                                book: book,
                                rating: GoodreadsImportService.ratingOutOfTen(from: row.myRating),
                                review: row.myReview,
                                dateFinished: row.dateRead,
                                tier: nil
                            )
                        } else {
                            ok = await appState.importGoodreadsQueueBook(book: book)
                        }
                        if ok { self.importedBookIds.insert(book.id) }
                        decision = ok ? .imported : .duplicate
                    } else {
                        decision = .skipped
                    }
                } else {
                    self.matchStates[row.id] = .unmatched
                    decision = .unmatched
                }
                self.session?.decisions[row.id] = decision
                self.bulkDone += 1
                self.persist()
            }
            self.transitionIfPhaseFinished()
        }
    }

    // MARK: Phase transitions

    private func transitionIfPhaseFinished() {
        guard var s = session else { return }
        switch s.phase {
        case .readBooks:
            guard s.pendingReadCount == 0 else { return }
            // pendingQueueCount == 0 covers re-entry from "Review skipped books"
            // after the queue phase already ran — don't re-prompt for an empty queue.
            if s.queueRows.isEmpty || s.pendingQueueCount == 0 {
                finish()
            } else {
                s.phase = .queuePrompt
                session = s
                persist()
                step = .queuePrompt
            }
        case .queueBooks:
            guard s.pendingQueueCount == 0 else { return }
            finish()
        case .queuePrompt, .done:
            break
        }
    }

    private func finish() {
        guard var s = session else { return }
        s.phase = .done
        session = s
        appState?.clearGoodreadsWizardSession()
        step = .done
    }
}

// MARK: - View

struct GoodreadsImportView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState

    /// When non-nil (e.g. from Share Extension), skip the explainer and go straight to the wizard.
    var initialRows: [GoodreadsRow]? = nil

    @StateObject private var model = GoodreadsWizardModel()
    @State private var showFileImporter = false
    @State private var showExportWebView = false
    @State private var showImportAllConfirm = false
    @State private var showStartOverConfirm = false
    // Inline-editable card state, re-seeded from the Goodreads row for each book.
    @State private var selectedTier: String? = nil
    @State private var cardReview: String = ""
    @State private var cardDateRead: Date = Date()

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
            // Mid-import, a scroll attempt on the card easily reads as a sheet drag
            // and throws the drawer away. Kill swipe-to-dismiss there — Close (with
            // its progress-saved modal) is the exit. Explainer/summary stay swipeable.
            .interactiveDismissDisabled(isMidImport)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(model.session?.hasRemainingWork == true ? "Close" : "Cancel") {
                        dismiss()
                    }
                    .font(Theme.callout())
                    .foregroundStyle(Theme.textTertiary)
                }
                if model.session != nil {
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Button("Start over and delete progress", role: .destructive) {
                                showStartOverConfirm = true
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .font(.system(size: 15))
                                .foregroundStyle(Theme.textTertiary)
                        }
                    }
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
                model.configure(appState: appState, initialRows: initialRows)
            }
            .onChange(of: model.currentRow?.id) { _, _ in
                syncCardState()
            }
            .fullScreenCover(isPresented: $showExportWebView) {
                GoodreadsExportWebView { rows in
                    showExportWebView = false
                    model.startSession(rows: rows)
                }
            }
            .alert("Delete import progress?", isPresented: $showStartOverConfirm) {
                Button("Delete progress", role: .destructive) { model.startOver() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Starting over deletes your place in this import and every book still waiting for review — you'd begin again from a fresh CSV. Books you've already imported stay in your library.")
            }
            .alert("Import all remaining?", isPresented: $showImportAllConfirm) {
                Button("Import all anyway") { model.importAllRemaining() }
                Button("Keep reviewing", role: .cancel) {}
            } message: {
                Text("Importing everything at once can occasionally mismatch books, so going book by book is recommended. Your progress is always saved — you can close this and pick up right where you left off anytime.")
            }
        }
    }

    /// True while the user is actively working through books (or a bulk import is
    /// running) — the steps where an accidental swipe-down would hurt.
    private var isMidImport: Bool {
        switch model.step {
        case .readWizard, .queuePrompt, .queueWizard, .bulkImporting:
            return true
        case .explainer, .done:
            return false
        }
    }

    /// Seed the inline-editable card fields from the current Goodreads row.
    private func syncCardState() {
        selectedTier = nil
        guard let row = model.currentRow else { return }
        cardReview = row.myReview ?? ""
        cardDateRead = row.dateRead ?? Date()
    }

    @ViewBuilder
    private var content: some View {
        switch model.step {
        case .explainer:
            explainerContent
        case .readWizard:
            readWizardContent
        case .queuePrompt:
            queuePromptContent
        case .queueWizard:
            queueWizardContent
        case .bulkImporting:
            bulkImportingContent
        case .done:
            doneContent
        }
    }

    // MARK: Explainer (CSV-only entry path)

    private var explainerContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("How to Import:")
                        .font(Theme.headline())
                        .foregroundStyle(Theme.textPrimary)

                    Grid(alignment: .topLeading, horizontalSpacing: 12, verticalSpacing: 12) {
                        GridRow {
                            stepNumberBadge(1)
                            stepBody("Tap the button below — your Goodreads export page opens right here in Spine. Sign in if asked.")
                        }
                        GridRow {
                            stepNumberBadge(2)
                            stepBody("Tap \"Export Library\", then tap the \"Your export from…\" link once it appears.")
                        }
                        GridRow {
                            stepNumberBadge(3)
                            stepBody("That's it — Spine grabs the file and starts your import automatically.")
                        }
                    }
                }

                Button {
                    showExportWebView = true
                } label: {
                    HStack {
                        Image(systemName: "square.and.arrow.down")
                        Text("Get my Goodreads export")
                    }
                    .font(Theme.headline())
                    .foregroundStyle(Theme.background)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Theme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius))
                }
                .buttonStyle(.plain)

                Button {
                    showFileImporter = true
                } label: {
                    HStack {
                        Image(systemName: "square.and.arrow.up")
                        Text("Already have the CSV? Upload it")
                    }
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

                if let err = model.parseError {
                    Text(err)
                        .font(Theme.caption())
                        .foregroundStyle(Theme.magentaPunch)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(Theme.cardPadding)
            .padding(.bottom, 16)
        }
    }

    private func stepNumberBadge(_ number: Int) -> some View {
        Text("\(number)")
            .font(Theme.headline())
            .foregroundStyle(Theme.background)
            .frame(width: 28, height: 28)
            .background(Theme.accent)
            .clipShape(Circle())
    }

    private func stepBody(_ text: String) -> some View {
        Text(text)
            .font(Theme.callout())
            .foregroundStyle(Theme.textSecondary)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    // MARK: Read-books wizard

    @ViewBuilder
    private var readWizardContent: some View {
        if let session = model.session {
            VStack(spacing: 0) {
                wizardProgressHeader(
                    position: session.currentPosition,
                    total: session.readRows.count,
                    remaining: session.pendingReadCount
                )

                ScrollView {
                    VStack(spacing: 20) {
                        if let book = model.currentBook, let row = model.currentRow {
                            readBookCard(book: book, row: row)
                        } else {
                            matchingCard
                        }
                    }
                    .padding(Theme.cardPadding)
                }
            }
        }
    }

    private func readBookCard(book: Book, row: GoodreadsRow) -> some View {
        VStack(spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                BookCoverView(book: book, size: 100)

                VStack(alignment: .leading, spacing: 8) {
                    Text(book.title)
                        .font(Theme.title2())
                        .foregroundStyle(Theme.textPrimary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(3)
                    Text(book.author)
                        .font(Theme.callout())
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(2)
                    GoodreadsStarsRow(rating: row.myRating)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Date read")
                            .font(Theme.caption())
                            .foregroundStyle(Theme.textSecondary)
                        DatePicker("", selection: $cardDateRead, in: ...Date(), displayedComponents: .date)
                            .datePickerStyle(.compact)
                            .labelsHidden()
                            .tint(Theme.accent)
                    }
                    .padding(.top, 2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            InlineTierPicker(selection: $selectedTier)

            reviewSection

            HStack(spacing: 10) {
                Button {
                    model.skipCurrent()
                } label: {
                    Text("Skip")
                        .font(Theme.headline())
                        .foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Theme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius))
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.cardCornerRadius)
                                .strokeBorder(Theme.textTertiary.opacity(0.35), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)

                Button {
                    model.acceptCurrentEdited(
                        stars: row.myRating,
                        review: cardReview,
                        dateFinished: cardDateRead,
                        tier: selectedTier
                    )
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 15, weight: .bold))
                        Text("Add")
                            .font(Theme.headline())
                    }
                    .foregroundStyle(Theme.background)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Theme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius))
                }
                .buttonStyle(.plain)
            }
        }
        .onAppear { syncCardState() }
    }

    private func cardSectionLabel(_ text: String) -> some View {
        Text(SpinesGlyphs.bracketed(text))
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .tracking(0.5)
            .foregroundStyle(Theme.chromeTeal)
    }

    /// Inline-editable review with a one-tap wipe button (doesn't focus the keyboard).
    private var reviewSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                cardSectionLabel("Your review")
                Spacer()
                if !cardReview.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button {
                        cardReview = ""
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 12))
                            Text("CLEAR")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .tracking(0.5)
                        }
                        .foregroundStyle(Theme.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            ZStack(alignment: .topLeading) {
                if cardReview.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Thoughts on this book…")
                        .font(Theme.body())
                        .foregroundStyle(Theme.textSecondary.opacity(0.7))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 8)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $cardReview)
                    .font(Theme.body())
                    .foregroundStyle(Theme.textPrimary)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 90, maxHeight: 180)
            }
            .padding(10)
            .background(Theme.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Theme.chromeTeal.opacity(0.3), lineWidth: Theme.chromeHairline)
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var matchingCard: some View {
        VStack(spacing: 16) {
            RoundedRectangle(cornerRadius: 6)
                .fill(Theme.surface)
                .frame(width: 120, height: 180)
                .overlay(
                    ProgressView()
                        .tint(Theme.accent)
                )
            Text("Finding your book…")
                .font(Theme.callout())
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.top, 40)
    }

    private func wizardProgressHeader(position: Int, total: Int, remaining: Int) -> some View {
        VStack(spacing: 8) {
            HStack {
                Text("BOOK \(position) OF \(total)")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .tracking(1)
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Button {
                    showImportAllConfirm = true
                } label: {
                    Text("Import all")
                        .font(Theme.caption())
                        .fontWeight(.medium)
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Theme.surface)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .strokeBorder(Theme.textTertiary.opacity(0.35), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .disabled(remaining == 0)
            }
            ProgressView(value: Double(max(0, total - remaining)), total: Double(max(total, 1)))
                .tint(Theme.accent)
        }
        .padding(.horizontal, Theme.cardPadding)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    // MARK: Queue prompt + wizard

    private var queuePromptContent: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "books.vertical")
                .font(.system(size: 44))
                .foregroundStyle(Theme.chromeTeal)
            VStack(spacing: 8) {
                Text("Read books done!")
                    .font(Theme.title2())
                    .foregroundStyle(Theme.textPrimary)
                Text("You have \(model.session?.pendingQueueCount ?? 0) books on your Goodreads to-read shelf. Add them to your Spine queue?")
                    .font(Theme.callout())
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }

            VStack(spacing: 10) {
                Button {
                    model.importAllRemaining()
                } label: {
                    Text("Add all automatically")
                        .font(Theme.headline())
                        .foregroundStyle(Theme.background)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Theme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius))
                }
                .buttonStyle(.plain)

                Button {
                    model.chooseQueueOneByOne()
                } label: {
                    Text("Review one by one")
                        .font(Theme.headline())
                        .foregroundStyle(Theme.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Theme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius))
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.cardCornerRadius)
                                .strokeBorder(Theme.textTertiary.opacity(0.35), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)

                Button {
                    model.declineQueue()
                } label: {
                    Text("No thanks")
                        .font(Theme.callout())
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(Theme.cardPadding)
    }

    @ViewBuilder
    private var queueWizardContent: some View {
        if let session = model.session {
            VStack(spacing: 0) {
                wizardProgressHeader(
                    position: session.currentPosition,
                    total: session.queueRows.count,
                    remaining: session.pendingQueueCount
                )

                ScrollView {
                    VStack(spacing: 20) {
                        if let book = model.currentBook {
                            queueBookCard(book: book)
                        } else {
                            matchingCard
                        }
                    }
                    .padding(Theme.cardPadding)
                }
            }
        }
    }

    private func queueBookCard(book: Book) -> some View {
        VStack(spacing: 16) {
            BookCoverView(book: book, size: 120)
            VStack(spacing: 4) {
                Text(book.title)
                    .font(Theme.title2())
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                Text(book.author)
                    .font(Theme.callout())
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
            }

            HStack(spacing: 10) {
                Button {
                    model.skipCurrent()
                } label: {
                    Text("Skip")
                        .font(Theme.headline())
                        .foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Theme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius))
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.cardCornerRadius)
                                .strokeBorder(Theme.textTertiary.opacity(0.35), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)

                Button {
                    model.acceptCurrentQueueBook()
                } label: {
                    Text("Add to queue")
                        .font(Theme.headline())
                        .foregroundStyle(Theme.background)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Theme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Bulk importing + done

    private var bulkImportingContent: some View {
        VStack(spacing: 24) {
            ProgressView(value: Double(model.bulkDone), total: Double(max(1, model.bulkTotal)))
                .tint(Theme.accent)
                .padding(.horizontal, 32)
            Text("Importing… \(model.bulkDone) of \(model.bulkTotal)")
                .font(Theme.callout())
                .foregroundStyle(Theme.textSecondary)
            Text("Keep the app open — this can take a bit for a large library.")
                .font(Theme.caption())
                .foregroundStyle(Theme.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var doneContent: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(Theme.accent)
                    .padding(.top, 32)
                Text("Import complete")
                    .font(Theme.title2())
                    .foregroundStyle(Theme.textPrimary)

                if let s = model.session {
                    VStack(spacing: 6) {
                        doneStatLine("\(s.importedCount) imported")
                        if s.duplicateCount > 0 {
                            doneStatLine("\(s.duplicateCount) already in your library")
                        }
                    }
                }

                skippedBooksSection

                unmatchedBooksSection

                Button {
                    let count = model.session?.importedCount ?? 0
                    dismiss()
                    ToastCenter.shared.show(.importedBooks(count: count))
                } label: {
                    Text("Done")
                        .font(Theme.headline())
                        .foregroundStyle(Theme.background)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Theme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius))
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
            }
            .padding(Theme.cardPadding)
            .padding(.bottom, 16)
        }
    }

    private func doneStatLine(_ text: String) -> some View {
        Text(text)
            .font(Theme.callout())
            .foregroundStyle(Theme.textSecondary)
    }

    /// Books the user skipped, with a way to jump back into the wizard for them.
    @ViewBuilder
    private var skippedBooksSection: some View {
        let skipped = model.skippedBooks
        if !skipped.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                cardSectionLabel("Skipped · \(skipped.count)")
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(skipped, id: \.row.id) { item in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("·")
                                .font(Theme.caption())
                                .foregroundStyle(Theme.textTertiary)
                            Text(item.book?.title ?? item.row.title)
                                .font(Theme.caption())
                                .foregroundStyle(Theme.textPrimary)
                                .lineLimit(1)
                            Text(item.book?.author ?? item.row.author)
                                .font(Theme.caption())
                                .foregroundStyle(Theme.textTertiary)
                                .lineLimit(1)
                        }
                    }
                }
                Button {
                    model.reopenSkippedBooks()
                } label: {
                    Text("Review skipped books")
                        .font(Theme.callout())
                        .fontWeight(.medium)
                        .foregroundStyle(Theme.textPrimary)
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
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius)
                    .strokeBorder(Theme.chromeTeal.opacity(0.3), lineWidth: Theme.chromeHairline)
            )
        }
    }

    /// Rows with no confident catalog match — listed so the user can add them manually.
    @ViewBuilder
    private var unmatchedBooksSection: some View {
        let unmatched = model.unmatchedRows
        if !unmatched.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                cardSectionLabel("Couldn't match · \(unmatched.count)")
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(unmatched) { row in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("·")
                                .font(Theme.caption())
                                .foregroundStyle(Theme.textTertiary)
                            Text(row.title)
                                .font(Theme.caption())
                                .foregroundStyle(Theme.textPrimary)
                                .lineLimit(1)
                            Text(row.author)
                                .font(Theme.caption())
                                .foregroundStyle(Theme.textTertiary)
                                .lineLimit(1)
                        }
                    }
                }
                Text("You can add these by hand with Search.")
                    .font(Theme.caption())
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius)
                    .strokeBorder(Theme.chromeTeal.opacity(0.3), lineWidth: Theme.chromeHairline)
            )
        }
    }

    // MARK: File handling

    private func handleFileResult(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        guard url.startAccessingSecurityScopedResource() else {
            model.parseError = "Couldn't open that file. Try picking it again."
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }
        do {
            let data = try Data(contentsOf: url)
            let rows = GoodreadsCSVParser.parse(data: data)
            if rows.isEmpty {
                model.parseError = "No book data found in that file. Make sure you picked your Goodreads library export (goodreads_library_export.csv)."
            } else {
                model.startSession(rows: rows)
            }
        } catch {
            model.parseError = "Couldn't read that file. Try downloading your export again."
        }
    }
}

// MARK: - Goodreads stars (read-only)

private struct GoodreadsStarsRow: View {
    let rating: Int?

    var body: some View {
        HStack(spacing: 3) {
            if let r = rating, r > 0 {
                ForEach(1...5, id: \.self) { i in
                    Image(systemName: i <= r ? "star.fill" : "star")
                        .font(.system(size: 14))
                        .foregroundStyle(i <= r ? Theme.accent : Theme.textTertiary.opacity(0.6))
                }
            } else {
                Text("No rating")
                    .font(Theme.caption())
                    .foregroundStyle(Theme.textTertiary)
            }
        }
    }
}

// Tier picker moved to TierBadge.swift as `InlineTierPicker` so the mark-as-read
// card can share it.
