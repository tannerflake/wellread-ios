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
    private static let storage = Storage.storage()
    private static let profilePrefix = "profile_photos"

    /// Uploads image data to Storage at profile_photos/{uid}.jpg, returns the download URL. Compresses as JPEG (0.8) to limit size.
    static func uploadProfilePhoto(uid: String, imageData: Data) async throws -> String {
        let ref = storage.reference().child("\(profilePrefix)/\(uid).jpg")
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        _ = try await ref.putDataAsync(imageData, metadata: metadata)
        let url = try await ref.downloadURL()
        return url.absoluteString
    }

    /// Convenience: upload from UIImage (e.g. from PhotosPicker). Converts to JPEG data.
    static func uploadProfilePhoto(uid: String, image: UIImage) async throws -> String {
        guard let data = image.jpegData(compressionQuality: 0.8) else {
            throw NSError(domain: "ProfilePhotoService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Could not encode image as JPEG"])
        }
        return try await uploadProfilePhoto(uid: uid, imageData: data)
    }
}
