//
//  ProfilePhotoService.swift
//  WellRead
//
//  Uploads profile photos to Firebase Storage (no in-app cropping — image is JPEG-compressed as-is).
//

import FirebaseStorage
import UIKit

enum ProfilePhotoService {
    private static let profilePrefix = "profile_photos"

    /// Uploads image data to Storage at `profile_photos/{uid}.jpg`, returns the download URL.
    static func uploadProfilePhoto(uid: String, imageData: Data) async throws -> String {
        guard !imageData.isEmpty else {
            throw NSError(
                domain: "ProfilePhotoService",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "Image data was empty. Try another photo."]
            )
        }
        let ref = Storage.storage().reference().child("\(profilePrefix)/\(uid).jpg")
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        _ = try await ref.putDataAsync(imageData, metadata: metadata)
        return try await downloadURL(after: ref)
    }

    /// Convenience: upload from `UIImage` (e.g. from PhotosPicker). Converts to JPEG (0.82).
    static func uploadProfilePhoto(uid: String, image: UIImage) async throws -> String {
        guard let data = image.jpegData(compressionQuality: 0.82) else {
            throw NSError(
                domain: "ProfilePhotoService",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Could not encode image as JPEG"]
            )
        }
        return try await uploadProfilePhoto(uid: uid, imageData: data)
    }

    private static func downloadURL(after ref: StorageReference) async throws -> String {
        var lastError: Error?
        for attempt in 0 ..< 4 {
            do {
                return try await ref.downloadURL().absoluteString
            } catch {
                lastError = error
                try await Task.sleep(nanoseconds: UInt64(200_000_000 * (attempt + 1)))
            }
        }
        throw lastError ?? NSError(
            domain: "ProfilePhotoService",
            code: -3,
            userInfo: [NSLocalizedDescriptionKey: "Could not get download URL for profile photo."]
        )
    }
}
