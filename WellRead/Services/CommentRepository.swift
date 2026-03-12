//
//  CommentRepository.swift
//  WellRead
//
//  Firestore comments: create, list by post.
//

import Foundation
import FirebaseFirestore

final class CommentRepository {
    private let db = FirestoreDatabase.firestore
    private let comments = "comments"
    private let userRepo = UserRepository()

    /// Listens to comments for a post.
    func listenComments(postId: String, onUpdate: @escaping ([Comment]) -> Void) -> ListenerRegistration {
        db.collection(comments)
            .whereField("postId", isEqualTo: postId)
            .order(by: "createdAt", descending: false)
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let self = self, let snapshot = snapshot else { return }
                let list = snapshot.documents.compactMap { doc -> Comment? in
                    self.comment(from: doc.data(), docId: doc.documentID)
                }
                onUpdate(list)
            }
    }

    /// Fetches comments for a post (one-shot).
    func fetchComments(postId: String) async -> [Comment] {
        do {
            let snapshot = try await db.collection(comments)
                .whereField("postId", isEqualTo: postId)
                .order(by: "createdAt", descending: false)
                .getDocuments()
            return snapshot.documents.compactMap { doc in
                comment(from: doc.data(), docId: doc.documentID)
            }
        } catch {
            return []
        }
    }

    /// Adds a comment and increments post's commentCount.
    func addComment(postId: String, userId: String, text: String, displayName: String?) async throws -> Comment {
        let id = UUID()
        let now = Date()
        let ref = db.collection(comments).document(id.uuidString)
        var data: [String: Any] = [
            "postId": postId,
            "userId": userId,
            "text": text,
            "createdAt": Timestamp(date: now),
        ]
        if let name = displayName { data["displayName"] = name }
        try await ref.setData(data)
        let postRef = db.collection("posts").document(postId)
        try await postRef.updateData([
            "commentCount": FieldValue.increment(Int64(1)),
        ])
        return Comment(id: id, postId: postId, userId: userId, text: text, createdAt: now, displayName: displayName)
    }

    private func comment(from data: [String: Any], docId: String) -> Comment? {
        guard let postId = data["postId"] as? String,
              let userId = data["userId"] as? String,
              let text = data["text"] as? String,
              let createdAt = (data["createdAt"] as? Timestamp)?.dateValue(),
              let id = UUID(uuidString: docId) else { return nil }
        let displayName = data["displayName"] as? String
        return Comment(id: id, postId: postId, userId: userId, text: text, createdAt: createdAt, displayName: displayName)
    }
}
