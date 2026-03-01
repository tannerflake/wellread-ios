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
    private let bookRepo = BookRepository()
    private let userRepo = UserRepository()

    /// Listens to feed: posts ordered by createdAt (for now, all posts; later filter by following).
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

    /// One-shot feed fetch.
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
    func createPost(userId: String, type: PostType, bookId: String?, caption: String?) async throws -> Post {
        let id = UUID()
        let ref = db.collection(posts).document(id.uuidString)
        try await ref.setData([
            "userId": userId,
            "type": type.rawValue,
            "bookId": bookId as Any,
            "caption": caption as Any,
            "createdAt": Timestamp(date: Date()),
            "likeCount": 0,
            "commentCount": 0,
        ])
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
            user: nil
        )
        if let bid = bookId { post.book = await bookRepo.getBook(id: bid) }
        post.user = await userRepo.getUser(uid: userId)
        return post
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
            user: nil
        )
        if let bid = bookId { post.book = await bookRepo.getBook(id: bid) }
        post.user = await userRepo.getUser(uid: userId)
        return post
    }
}
