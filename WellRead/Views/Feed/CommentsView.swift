//
//  CommentsView.swift
//  Spine
//
//  Comments thread for a post. Listens to Firestore live updates; posts are
//  optimistically merged so a freshly-sent comment doesn't disappear before
//  the snapshot catches up.
//

import SwiftUI
import FirebaseFirestore

struct CommentsView: View {
    let post: Post
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var authService: AuthService
    @StateObject private var viewModel: CommentsViewModel
    @FocusState private var isCommentFieldFocused: Bool

    init(post: Post) {
        self.post = post
        _viewModel = StateObject(wrappedValue: CommentsViewModel(postId: post.id.uuidString))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                VStack(spacing: 0) {
                    if viewModel.comments.isEmpty && !viewModel.isLoading {
                        VStack(spacing: 8) {
                            Image(systemName: "bubble.left")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundStyle(Theme.chrome.opacity(0.7))
                            Text("no comments yet")
                                .font(.system(size: 13, weight: .regular))
                                .tracking(0.5)
                                .foregroundStyle(Theme.textTertiary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        List {
                            ForEach(viewModel.threadedComments, id: \.comment.id) { item in
                                CommentRow(
                                    comment: item.comment,
                                    profileImageURL: viewModel.profileImageURL(for: item.comment),
                                    isReply: item.isReply,
                                    onReply: { viewModel.replyingTo = item.comment }
                                )
                                    .padding(.leading, item.isReply ? 38 : 0)
                                    .listRowBackground(Theme.background)
                                    .listRowSeparatorTint(Theme.chrome.opacity(0.3))
                            }
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                    }
                    commentInputBar
                }
            }
            .navigationTitle("Comments")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .accessibilityLabel("Close")
                }
            }
            .navigationDestination(for: String.self) { userId in
                UserLibraryDetailView(userId: userId)
                    .environmentObject(authService)
                    .environmentObject(appState)
            }
        }
        .onAppear {
            viewModel.startListening()
        }
        .task {
            // Focus right away so the keyboard rises with the sheet instead of
            // after it lands. SwiftUI drops focus set mid-presentation (and
            // resets the binding to false), so re-assert until it sticks.
            for _ in 0..<6 {
                isCommentFieldFocused = true
                try? await Task.sleep(nanoseconds: 80_000_000)
                if isCommentFieldFocused { return }
            }
        }
        .onChange(of: viewModel.replyingTo?.id) { _, newValue in
            if newValue != nil { isCommentFieldFocused = true }
        }
        .onDisappear {
            viewModel.stopListening()
        }
    }

    private var commentInputBar: some View {
        VStack(spacing: 0) {
            if let replyTarget = viewModel.replyingTo {
                HStack(spacing: 8) {
                    Text("Replying to \(replyTarget.displayName ?? "comment")")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Button {
                        viewModel.replyingTo = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Cancel reply")
                }
                .padding(.horizontal)
                .padding(.top, 8)
            }
            commentInputRow
        }
        .background(
            VStack(spacing: 0) {
                Rectangle()
                    .fill(Theme.chrome.opacity(0.35))
                    .frame(height: Theme.chromeHairline)
                Theme.background
            }
        )
    }

    private var commentInputRow: some View {
        HStack(spacing: 10) {
            TextField(viewModel.replyingTo == nil ? "> add a comment…" : "> add a reply…", text: $viewModel.commentText, axis: .vertical)
                .textFieldStyle(.plain)
                .focused($isCommentFieldFocused)
                .font(Theme.body())
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Theme.surfaceElevated)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Theme.chrome.opacity(0.4), lineWidth: 1)
                )
                .lineLimit(1...4)
            Button {
                Task {
                    await viewModel.sendComment(
                        userId: appState.authUserId,
                        displayName: appState.currentUser?.displayName,
                        profileImageURL: appState.currentUser?.profileImageURL
                    )
                }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundStyle(viewModel.canSend ? Theme.accent : Theme.textTertiary)
            }
            .disabled(!viewModel.canSend || viewModel.isSending)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}

struct CommentRow: View {
    let comment: Comment
    /// Resolved URL (from comment doc or fetched profile).
    var profileImageURL: String?
    /// True when this comment is a reply — rendered indented with a smaller avatar.
    var isReply: Bool = false
    /// Shows a "Reply" affordance under the comment when set.
    var onReply: (() -> Void)? = nil

    private static let avatarSize: CGFloat = 36

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Avatar sits beside the name/body column so the comment text
            // starts right under the name, not below the avatar's height.
            // The NavigationLink hides behind the content (zero-opacity overlay)
            // so the List doesn't render its disclosure chevron.
            HStack(alignment: .top, spacing: 10) {
                commentAvatar
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(comment.displayName ?? "User")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Theme.textPrimary)
                        TimelineView(.periodic(from: .now, by: 15)) { context in
                            Text(Theme.commentRelativeTimestamp(comment.createdAt, now: context.date))
                                .font(.system(size: 10, weight: .regular))
                                .tracking(0.5)
                                .foregroundStyle(Theme.chrome)
                        }
                    }
                    Text(comment.text)
                        .font(Theme.body())
                        .foregroundStyle(Theme.textPrimary)
                        .lineSpacing(Theme.bodyLineSpacing)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .overlay(
                NavigationLink(value: comment.userId) { EmptyView() }
                    .opacity(0)
            )
            if let onReply {
                Button(action: onReply) {
                    Text("Reply")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.textTertiary)
                }
                .buttonStyle(.plain)
                .padding(.leading, Self.avatarSize + 10)
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 6)
    }

    private var commentAvatar: some View {
        UserAvatarView(urlString: profileImageURL, displayName: comment.displayName, size: Self.avatarSize)
            .overlay(
                Circle()
                    .strokeBorder(Theme.chrome.opacity(0.5), lineWidth: 1)
            )
    }
}

final class CommentsViewModel: ObservableObject {
    @Published var comments: [Comment] = []
    @Published var commentText: String = ""
    @Published var isSending: Bool = false
    @Published var isLoading: Bool = true
    /// Comment being replied to; the next send becomes its reply.
    @Published var replyingTo: Comment? = nil
    /// Cached `userId` → profile image URL (`""` = loaded, no image).
    @Published private(set) var avatarURLByUserId: [String: String] = [:]

    private let postId: String
    private let commentRepo = CommentRepository()
    private let userRepo = UserRepository()
    private var listener: ListenerRegistration?

    func profileImageURL(for comment: Comment) -> String? {
        if let u = comment.profileImageURL, !u.isEmpty { return u }
        guard let cached = avatarURLByUserId[comment.userId] else { return nil }
        return cached.isEmpty ? nil : cached
    }

    var canSend: Bool {
        !commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Comments in display order: top-level chronological, each followed by its replies
    /// (also chronological). Replies-to-replies flatten under the same top-level ancestor,
    /// Instagram-style. Replies whose parent was deleted render as top-level.
    var threadedComments: [(comment: Comment, isReply: Bool)] {
        let byId = Dictionary(uniqueKeysWithValues: comments.map { ($0.id.uuidString, $0) })

        /// Walk up the parent chain to the top-level ancestor (nil parent). Bails to self on a broken/cyclic chain.
        func rootId(of comment: Comment) -> String {
            var current = comment
            var hops = 0
            while let pid = current.parentCommentId, let parent = byId[pid], hops < 20 {
                current = parent
                hops += 1
            }
            return current.id.uuidString
        }

        let topLevel = comments
            .filter { $0.parentCommentId == nil || byId[$0.parentCommentId!] == nil }
            .sorted { $0.createdAt < $1.createdAt }
        let replies = comments.filter { $0.parentCommentId != nil && byId[$0.parentCommentId!] != nil }
        let repliesByRoot = Dictionary(grouping: replies, by: rootId(of:))

        var result: [(Comment, Bool)] = []
        for c in topLevel {
            result.append((c, false))
            for r in (repliesByRoot[c.id.uuidString] ?? []).sorted(by: { $0.createdAt < $1.createdAt }) {
                result.append((r, true))
            }
        }
        return result
    }

    init(postId: String) {
        self.postId = postId
    }

    func startListening() {
        guard listener == nil else { return }
        isLoading = true
        listener = commentRepo.listenComments(postId: postId) { [weak self] list in
            Task { @MainActor in
                self?.applyServerComments(list)
            }
        }
    }

    /// Merges Firestore snapshots with comments already shown. Stale snapshots (before the new doc appears)
    /// would otherwise replace the list and hide a comment you just posted until reopening.
    private func applyServerComments(_ serverList: [Comment]) {
        var mergedById = [UUID: Comment]()
        for c in serverList { mergedById[c.id] = c }
        for c in comments where mergedById[c.id] == nil {
            mergedById[c.id] = c
        }
        comments = mergedById.values.sorted { $0.createdAt < $1.createdAt }
        isLoading = false
        Task { await resolveMissingAvatars() }
    }

    private func resolveMissingAvatars() async {
        let uidsNeedingFetch = Set(
            comments
                .filter { ($0.profileImageURL == nil || $0.profileImageURL?.isEmpty == true) && !avatarURLByUserId.keys.contains($0.userId) }
                .map(\.userId)
        )
        for uid in uidsNeedingFetch {
            guard let user = await userRepo.getUser(uid: uid) else {
                await MainActor.run {
                    var next = avatarURLByUserId
                    next[uid] = ""
                    avatarURLByUserId = next
                }
                continue
            }
            let url = user.profileImageURL ?? ""
            await MainActor.run {
                var next = avatarURLByUserId
                next[uid] = url
                avatarURLByUserId = next
            }
        }
    }

    func stopListening() {
        listener?.remove()
        listener = nil
    }

    func sendComment(userId: String?, displayName: String?, profileImageURL: String?) async {
        guard let uid = userId else { return }
        let text = commentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let parentId = await MainActor.run { replyingTo?.id.uuidString }
        await MainActor.run { isSending = true; commentText = "" }
        do {
            let new = try await commentRepo.addComment(
                postId: postId,
                userId: uid,
                text: text,
                displayName: displayName,
                profileImageURL: profileImageURL,
                parentCommentId: parentId
            )
            await MainActor.run {
                if !comments.contains(where: { $0.id == new.id }) {
                    comments.append(new)
                    comments.sort { $0.createdAt < $1.createdAt }
                }
                replyingTo = nil
            }
        } catch {
            await MainActor.run { commentText = text }
        }
        await MainActor.run { isSending = false }
    }
}
