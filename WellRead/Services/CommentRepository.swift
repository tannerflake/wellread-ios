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
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                if let error = error {
                    #if DEBUG
                    print("CommentRepository.listenComments: \(error.localizedDescription)")
                    #endif
                    onUpdate([])
                    return
                }
                guard let snapshot = snapshot else {
                    onUpdate([])
                    return
                }
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

    /// Deletes all comments for a post (e.g. when removing the post). Batched; requires rules allowing post author to delete.
    func deleteAllCommentsForPost(postId: String) async throws {
        let snapshot = try await db.collection(comments)
            .whereField("postId", isEqualTo: postId)
            .getDocuments()
        let docs = snapshot.documents
        var i = 0
        while i < docs.count {
            let end = min(i + 400, docs.count)
            let batch = db.batch()
            for j in i..<end {
                batch.deleteDocument(docs[j].reference)
            }
            try await batch.commit()
            i = end
        }
    }

    /// Adds a comment and increments post's commentCount.
    func addComment(
        postId: String,
        userId: String,
        text: String,
        displayName: String?,
        profileImageURL: String? = nil
    ) async throws -> Comment {
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
        if let url = profileImageURL, !url.isEmpty { data["profileImageURL"] = url }
        try await ref.setData(data)
        let postRef = db.collection("posts").document(postId)
        try await postRef.updateData([
            "commentCount": FieldValue.increment(Int64(1)),
        ])
        return Comment(
            id: id,
            postId: postId,
            userId: userId,
            text: text,
            createdAt: now,
            displayName: displayName,
            profileImageURL: profileImageURL
        )
    }

    private func comment(from data: [String: Any], docId: String) -> Comment? {
        guard let postId = data["postId"] as? String,
              let userId = data["userId"] as? String,
              let text = data["text"] as? String,
              let createdAt = (data["createdAt"] as? Timestamp)?.dateValue(),
              let id = UUID(uuidString: docId) else { return nil }
        let displayName = data["displayName"] as? String
        let profileImageURL = data["profileImageURL"] as? String
        return Comment(
            id: id,
            postId: postId,
            userId: userId,
            text: text,
            createdAt: createdAt,
            displayName: displayName,
            profileImageURL: profileImageURL
        )
    }
}
