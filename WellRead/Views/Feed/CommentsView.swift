//
//  CommentsView.swift
//  WellRead
//
//  Shows comments for a post and lets the user add a comment.
//

import SwiftUI
import FirebaseFirestore

struct CommentsView: View {
    let post: Post
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState
    @StateObject private var viewModel: CommentsViewModel

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
                        Text("No comments yet")
                            .font(Theme.body())
                            .foregroundStyle(Theme.textSecondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        List {
                            ForEach(viewModel.comments) { comment in
                                CommentRow(comment: comment)
                                    .listRowBackground(Theme.background)
                                    .listRowSeparatorTint(Theme.textTertiary.opacity(0.3))
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
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundStyle(Theme.accent)
                }
            }
        }
        .onAppear {
            viewModel.startListening()
        }
        .onDisappear {
            viewModel.stopListening()
        }
    }

    private var commentInputBar: some View {
        HStack(spacing: 12) {
            TextField("Add a comment…", text: $viewModel.commentText, axis: .vertical)
                .textFieldStyle(.plain)
                .padding(12)
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .lineLimit(1...4)
            Button {
                Task { await viewModel.sendComment(userId: appState.authUserId, displayName: appState.currentUser?.displayName) }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundStyle(viewModel.canSend ? Theme.accent : Theme.textTertiary)
            }
            .disabled(!viewModel.canSend || viewModel.isSending)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Theme.background)
    }
}

struct CommentRow: View {
    let comment: Comment

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(comment.displayName ?? "User")
                    .font(Theme.headline())
                    .foregroundStyle(Theme.textPrimary)
                Text(comment.createdAt, style: .relative)
                    .font(Theme.caption())
                    .foregroundStyle(Theme.textTertiary)
            }
            Text(comment.text)
                .font(Theme.body())
                .foregroundStyle(Theme.textPrimary)
        }
        .padding(.vertical, 6)
    }
}

final class CommentsViewModel: ObservableObject {
    @Published var comments: [Comment] = []
    @Published var commentText: String = ""
    @Published var isSending: Bool = false
    @Published var isLoading: Bool = true

    private let postId: String
    private let commentRepo = CommentRepository()
    private var listener: ListenerRegistration?

    var canSend: Bool {
        !commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    init(postId: String) {
        self.postId = postId
    }

    func startListening() {
        guard listener == nil else { return }
        isLoading = true
        listener = commentRepo.listenComments(postId: postId) { [weak self] list in
            Task { @MainActor in
                self?.comments = list
                self?.isLoading = false
            }
        }
    }

    func stopListening() {
        listener?.remove()
        listener = nil
    }

    func sendComment(userId: String?, displayName: String?) async {
        guard let uid = userId else { return }
        let text = commentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        await MainActor.run { isSending = true; commentText = "" }
        do {
            _ = try await commentRepo.addComment(postId: postId, userId: uid, text: text, displayName: displayName)
        } catch {
            await MainActor.run { commentText = text }
        }
        await MainActor.run { isSending = false }
    }
}
