//
//  PostRepository.swift
//  WellRead
//
//  Firestore posts: create, feed query, like/comment counts.
//

import Foundation
import FirebaseFirestore

/// The feed listener behind one-or-more snapshot registrations: Firestore `in`
/// filters cap at 30 values, so a following list larger than that becomes
/// several queries merged client-side.
final class FeedListenerHandle {
    fileprivate var registrations: [ListenerRegistration] = []

    func remove() {
        registrations.forEach { $0.remove() }
        registrations = []
    }
}

/// Merges per-chunk feed query results into one newest-first list. Hydration
/// (book + author fetches) is async, so a chunk's older snapshot can finish
/// after a newer one — generations guard against the stale write.
private actor FeedChunkMerger {
    private var postsByChunk: [Int: [Post]] = [:]
    private var appliedGeneration: [Int: Int] = [:]
    private let limit: Int
    private let onUpdate: ([Post]) -> Void

    init(limit: Int, onUpdate: @escaping ([Post]) -> Void) {
        self.limit = limit
        self.onUpdate = onUpdate
    }

    func update(chunk: Int, generation: Int, posts: [Post]) async {
        guard generation > appliedGeneration[chunk, default: 0] else { return }
        appliedGeneration[chunk] = generation
        postsByChunk[chunk] = posts
        let merged = Array(
            postsByChunk.values
                .flatMap { $0 }
                .sorted { $0.createdAt > $1.createdAt }
                .prefix(limit)
        )
        await MainActor.run { onUpdate(merged) }
    }
}

final class PostRepository {
    private let db = FirestoreDatabase.firestore
    private let posts = "posts"
    private let bookRepo = BookRepository.shared
    private let userRepo = UserRepository()

    /// Listens to feed: posts authored by `authorIds` (the viewer + everyone they
    /// follow), newest first. Query-time rather than fan-out, so following someone
    /// retroactively surfaces their whole post history.
    func listenFeed(authorIds: [String], onUpdate: @escaping ([Post]) -> Void) -> FeedListenerHandle {
        let handle = FeedListenerHandle()
        let ids = Array(Set(authorIds))
        guard !ids.isEmpty else {
            DispatchQueue.main.async { onUpdate([]) }
            return handle
        }
        let chunks = stride(from: 0, to: ids.count, by: 30).map { Array(ids[$0..<min($0 + 30, ids.count)]) }
        let merger = FeedChunkMerger(limit: 50, onUpdate: onUpdate)
        for (chunkIndex, chunk) in chunks.enumerated() {
            // Snapshot handlers for one query run serially on the main queue, so
            // this counter assigns generations in snapshot order.
            var latestGeneration = 0
            let registration = db.collection(posts)
                .whereField("userId", in: chunk)
                .order(by: "createdAt", descending: true)
                .limit(to: 50)
                .addSnapshotListener { [weak self] snapshot, _ in
                    guard let self = self, let snapshot = snapshot else { return }
                    latestGeneration += 1
                    let generation = latestGeneration
                    Task {
                        var list: [Post] = []
                        for doc in snapshot.documents {
                            if let uid = doc.data()["userId"] as? String, HiddenAccounts.isHiddenFromCurrentViewer(uid: uid) { continue }
                            guard let post = await self.post(from: doc.data(), docId: doc.documentID) else { continue }
                            list.append(post)
                        }
                        await merger.update(chunk: chunkIndex, generation: generation, posts: list)
                    }
                }
            handle.registrations.append(registration)
        }
        return handle
    }

    /// Loads a single post by Firestore document id (UUID string).
    func fetchPost(postId: String) async -> Post? {
        do {
            let snapshot = try await db.collection(posts).document(postId).getDocument()
            guard snapshot.exists, let data = snapshot.data() else { return nil }
            if let uid = data["userId"] as? String, HiddenAccounts.isHiddenFromCurrentViewer(uid: uid) { return nil }
            return await post(from: data, docId: snapshot.documentID)
        } catch {
            return nil
        }
    }

    /// Creates a post (e.g. when user finishes a book or writes a review).
    func createPost(userId: String, type: PostType, bookId: String?, caption: String?, rating: Double? = nil, dateFinished: Date? = nil, tier: String? = nil) async throws -> Post {
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
        if let r = rating { data["rating"] = Theme.normalizeRatingOutOfTen(r) }
        if let d = dateFinished { data["dateFinished"] = Timestamp(date: d) }
        if let t = tier { data["tier"] = t }
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
            rating: rating.map { Theme.normalizeRatingOutOfTen($0) },
            dateFinished: dateFinished,
            tier: tier
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
        let rating = decodePostRating(from: data)
        let dateFinished = (data["dateFinished"] as? Timestamp)?.dateValue()
        let tier = (data["tier"] as? String).flatMap { spineTierLabels.contains($0) ? $0 : nil }
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
            rating: rating,
            dateFinished: dateFinished,
            tier: tier
        )
        if let bid = bookId { post.book = await bookRepo.getBook(id: bid) }
        post.user = await userRepo.getUser(uid: userId)
        return post
    }

    /// Prefers `rating` (0–10); migrates legacy `ratingPercent` (1–100) → ÷10.
    private func decodePostRating(from data: [String: Any]) -> Double? {
        if let r = decodeNumericRating(data["rating"]) {
            return r
        }
        if let pct = data["ratingPercent"] as? Int {
            return Theme.normalizeRatingOutOfTen(Double(pct) / 10.0)
        }
        if let pct = data["ratingPercent"] as? Int64 {
            return Theme.normalizeRatingOutOfTen(Double(pct) / 10.0)
        }
        if let n = data["ratingPercent"] as? NSNumber {
            return Theme.normalizeRatingOutOfTen(Double(truncating: n) / 10.0)
        }
        return nil
    }

    private func decodeNumericRating(_ value: Any?) -> Double? {
        switch value {
        case nil: return nil
        case let d as Double: return Theme.normalizeRatingOutOfTen(d)
        case let i as Int: return Theme.normalizeRatingOutOfTen(Double(i))
        case let i64 as Int64: return Theme.normalizeRatingOutOfTen(Double(i64))
        case let n as NSNumber: return Theme.normalizeRatingOutOfTen(Double(truncating: n))
        default: return nil
        }
    }

    private let commentRepo = CommentRepository()

    /// All posts for this user + book (e.g. find feed posts to sync with a read entry).
    func fetchPostsForUserAndBook(userId: String, bookId: String) async -> [Post] {
        do {
            let snapshot = try await db.collection(posts)
                .whereField("userId", isEqualTo: userId)
                .whereField("bookId", isEqualTo: bookId)
                .getDocuments()
            var list: [Post] = []
            for doc in snapshot.documents {
                if let p = await post(from: doc.data(), docId: doc.documentID) {
                    list.append(p)
                }
            }
            return list
        } catch {
            return []
        }
    }

    /// Updates caption, rating, date finished, and tier on an existing post.
    func updatePost(postId: String, caption: String?, rating: Double?, dateFinished: Date?, tier: String?) async throws {
        let ref = db.collection(posts).document(postId)
        var data: [String: Any] = [:]
        if let c = caption {
            data["caption"] = c
        } else {
            data["caption"] = NSNull()
        }
        if let r = rating {
            data["rating"] = Theme.normalizeRatingOutOfTen(r)
        } else {
            data["rating"] = NSNull()
        }
        if let d = dateFinished {
            data["dateFinished"] = Timestamp(date: d)
        } else {
            data["dateFinished"] = NSNull()
        }
        if let t = tier {
            data["tier"] = t
        } else {
            data["tier"] = NSNull()
        }
        try await ref.updateData(data)
    }

    /// Updates only the tier field on an existing post (e.g. when user re-tiers a book and we want feed posts to stay in sync).
    func updatePostTier(postId: String, tier: String?) async throws {
        let ref = db.collection(posts).document(postId)
        try await ref.updateData(["tier": tier as Any? ?? NSNull()])
    }

    /// Removes comments, likes, then the post document.
    func deletePostCascade(postId: String) async throws {
        try await commentRepo.deleteAllCommentsForPost(postId: postId)
        let likesSnap = try await db.collection("postLikes")
            .whereField("postId", isEqualTo: postId)
            .getDocuments()
        let likeDocs = likesSnap.documents
        var i = 0
        while i < likeDocs.count {
            let end = min(i + 400, likeDocs.count)
            let batch = db.batch()
            for j in i..<end {
                batch.deleteDocument(likeDocs[j].reference)
            }
            try await batch.commit()
            i = end
        }
        try await db.collection(posts).document(postId).delete()
    }
}
