//
//  ProfilePhotoService.swift
//  WellRead
//
//  Uploads profile photo to Firebase Storage and returns the download URL.
//

import Foundation
import UIKit
import FirebaseStorage

enum ProfilePhotoService {
    private static let profilePrefix = "profile_photos"

    /// Uses the bucket from `GoogleService-Info.plist` (`STORAGE_BUCKET`). New projects use `*.firebasestorage.app`;
    /// an explicit `gs://` URL avoids mismatches where `Storage.storage()` targets a legacy `*.appspot.com` bucket.
    private static let storage: Storage = {
        guard let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
              let dict = NSDictionary(contentsOfFile: path) as? [String: Any],
              let bucket = dict["STORAGE_BUCKET"] as? String,
              !bucket.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return Storage.storage()
        }
        let gs = "gs://\(bucket)"
        return Storage.storage(url: gs)
    }()

    /// Uploads image data to Storage at profile_photos/{uid}.jpg, returns the download URL. Compresses as JPEG (0.8) to limit size.
    static func uploadProfilePhoto(uid: String, imageData: Data) async throws -> String {
        guard !imageData.isEmpty else {
            throw NSError(domain: "ProfilePhotoService", code: -2, userInfo: [NSLocalizedDescriptionKey: "Image data was empty. Try another photo."])
        }
        let ref = storage.reference().child("\(profilePrefix)/\(uid).jpg")
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        _ = try await ref.putDataAsync(imageData, metadata: metadata)
        // `downloadURL()` can briefly return "object does not exist" right after upload; retry with backoff.
        let url = try await downloadURLWithRetry(from: ref)
        return url.absoluteString
    }

    /// Convenience: upload from UIImage (e.g. from PhotosPicker). Converts to JPEG data.
    static func uploadProfilePhoto(uid: String, image: UIImage) async throws -> String {
        guard let data = image.jpegData(compressionQuality: 0.8) else {
            throw NSError(domain: "ProfilePhotoService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Could not encode image as JPEG"])
        }
        return try await uploadProfilePhoto(uid: uid, imageData: data)
    }

    private static func downloadURLWithRetry(from ref: StorageReference, maxAttempts: Int = 8) async throws -> URL {
        var lastError: Error?
        for attempt in 0..<maxAttempts {
            do {
                return try await ref.downloadURL()
            } catch {
                lastError = error
                let ns = error as NSError
                let message = ns.localizedDescription.lowercased()
                let isNotFound = message.contains("does not exist") || message.contains("not found")
                if attempt < maxAttempts - 1, isNotFound {
                    let delayMs = 150 + attempt * 100
                    try await Task.sleep(nanoseconds: UInt64(delayMs) * 1_000_000)
                    continue
                }
                throw error
            }
        }
        throw lastError ?? NSError(domain: "ProfilePhotoService", code: -3, userInfo: [NSLocalizedDescriptionKey: "Could not get download URL for profile photo."])
    }
}
