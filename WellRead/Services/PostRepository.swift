//
//  PostRepository.swift
//  WellRead
//
//  Firestore posts: create, feed query, like/comment counts.
//

import Foundation
import FirebaseFirestore

final class PostRepository {
    private let db = FirestoreDatabase.firestore
    private let posts = "posts"
    private let bookRepo = BookRepository.shared
    private let userRepo = UserRepository()

    /// Listens to feed: all users see all posts (early-days behavior; switch to following-based feed later).
    func listenFeed(onUpdate: @escaping ([Post]) -> Void) -> ListenerRegistration {
        db.collection(posts)
            .order(by: "createdAt", descending: true)
            .limit(to: 50)
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let self = self, let snapshot = snapshot else { return }
                Task {
                    var list: [Post] = []
                    for doc in snapshot.documents {
                        guard let post = await self.post(from: doc.data(), docId: doc.documentID) else { continue }
                        list.append(post)
                    }
                    await MainActor.run { onUpdate(list) }
                }
            }
    }

    /// One-shot feed fetch (same as listenFeed: all users see all posts).
    func fetchFeed() async -> [Post] {
        do {
            let snapshot = try await db.collection(posts)
                .order(by: "createdAt", descending: true)
                .limit(to: 50)
                .getDocuments()
            var list: [Post] = []
            for doc in snapshot.documents {
                guard let post = await post(from: doc.data(), docId: doc.documentID) else { continue }
                list.append(post)
            }
            return list
        } catch {
            return []
        }
    }

    /// Creates a post (e.g. when user finishes a book or writes a review).
    func createPost(userId: String, type: PostType, bookId: String?, caption: String?, ratingPercent: Int? = nil, dateFinished: Date? = nil) async throws -> Post {
        let id = UUID()
        let ref = db.collection(posts).document(id.uuidString)
        var data: [String: Any] = [
            "userId": userId,
            "type": type.rawValue,
            "bookId": bookId as Any,
            "caption": caption as Any,
            "createdAt": Timestamp(date: Date()),
            "likeCount": 0,
            "commentCount": 0,
        ]
        if let pct = ratingPercent { data["ratingPercent"] = pct }
        if let d = dateFinished { data["dateFinished"] = Timestamp(date: d) }
        try await ref.setData(data)
        var post = Post(
            id: id,
            userId: userId,
            type: type,
            bookId: bookId,
            book: nil,
            caption: caption,
            createdAt: Date(),
            likeCount: 0,
            commentCount: 0,
            user: nil,
            ratingPercent: ratingPercent,
            dateFinished: dateFinished
        )
        if let bid = bookId { post.book = await bookRepo.getBook(id: bid) }
        post.user = await userRepo.getUser(uid: userId)
        return post
    }

    /// Record that the user liked the post. Idempotent. Increments post's likeCount.
    func addLike(postId: String, userId: String) async throws {
        let docId = "\(userId)_\(postId)"
        let likeRef = db.collection("postLikes").document(docId)
        let postRef = db.collection(posts).document(postId)
        let snapshot = try await likeRef.getDocument()
        guard !snapshot.exists else { return }
        try await likeRef.setData([
            "userId": userId,
            "postId": postId,
            "createdAt": Timestamp(date: Date()),
        ])
        try await postRef.updateData([
            "likeCount": FieldValue.increment(Int64(1)),
        ])
    }

    /// Remove the user's like. Idempotent. Decrements post's likeCount.
    func removeLike(postId: String, userId: String) async throws {
        let docId = "\(userId)_\(postId)"
        let likeRef = db.collection("postLikes").document(docId)
        let postRef = db.collection(posts).document(postId)
        let snapshot = try await likeRef.getDocument()
        guard snapshot.exists else { return }
        try await likeRef.delete()
        try await postRef.updateData([
            "likeCount": FieldValue.increment(Int64(-1)),
        ])
    }

    /// Fetches the set of post IDs the user has liked (for showing heart state in feed).
    func fetchLikedPostIds(userId: String) async -> Set<String> {
        do {
            let snapshot = try await db.collection("postLikes")
                .whereField("userId", isEqualTo: userId)
                .getDocuments()
            let ids = snapshot.documents.compactMap { $0.data()["postId"] as? String }
            return Set(ids)
        } catch {
            return []
        }
    }

    private func post(from data: [String: Any], docId: String) async -> Post? {
        guard let userId = data["userId"] as? String,
              let typeRaw = data["type"] as? String,
              let type = PostType(rawValue: typeRaw),
              let createdAt = (data["createdAt"] as? Timestamp)?.dateValue(),
              let id = UUID(uuidString: docId) else { return nil }
        let bookId = data["bookId"] as? String
        let likeCount = data["likeCount"] as? Int ?? 0
        let commentCount = data["commentCount"] as? Int ?? 0
        let ratingPercent = data["ratingPercent"] as? Int
        let dateFinished = (data["dateFinished"] as? Timestamp)?.dateValue()
        var post = Post(
            id: id,
            userId: userId,
            type: type,
            bookId: bookId,
            book: nil,
            caption: data["caption"] as? String,
            createdAt: createdAt,
            likeCount: likeCount,
            commentCount: commentCount,
            user: nil,
            ratingPercent: ratingPercent,
            dateFinished: dateFinished
        )
        if let bid = bookId { post.book = await bookRepo.getBook(id: bid) }
        post.user = await userRepo.getUser(uid: userId)
        return post
    }
}
