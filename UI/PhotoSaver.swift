import Foundation
#if canImport(Photos)
import Photos
#endif

/// Photo library access. Saving to a custom album requires the iOS app target.
public enum PhotoSaver {

    #if canImport(Photos)
    public static func requestAuthorization() async -> Bool {
        let current = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        if current == .authorized || current == .limited { return true }
        return await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                continuation.resume(returning: status == .authorized || status == .limited)
            }
        }
    }

    public static func save(_ image: RGBAImage, named name: String) async -> Bool {
        await withCheckedContinuation { continuation in
            PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                if let data = Encoder.pngData(image) {
                    request.addResource(with: .photo, data: data, options: nil)
                }
            } completionHandler: { success, _ in
                continuation.resume(returning: success)
            }
        }
    }
    #else
    public static func requestAuthorization() async -> Bool { false }
    public static func save(_ image: RGBAImage, named name: String) async -> Bool { false }
    #endif
}
