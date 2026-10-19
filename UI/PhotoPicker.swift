import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

#if canImport(UIKit)
import UIKit

/// Photo library picker. Defaults to the system photo library (the album the
/// user normally sees) and accepts every common raster format iOS can decode.
/// PSD is not a system image type, so a secondary entry point covers it.
struct PhotoPickerView: UIViewControllerRepresentable {

    /// Maximum number of selectable images; 1 means single selection.
    let limit: Int
    let onPick: ([PickedAsset]) -> Void

    init(limit: Int = 1, onPick: @escaping ([PickedAsset]) -> Void) {
        self.limit = limit
        self.onPick = onPick
    }

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = .images                    // jpeg/png/heic/gif/tiff/bmp/webp...
        // PHPicker treats 0 as "no limit"; .single only applies to exactly one.
        config.selectionLimit = max(0, limit)
        config.selection = limit == 1 ? .single : .ordered
        config.preferredAssetRepresentationMode = .current
        let controller = PHPickerViewController(configuration: config)
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(limit: limit, onPick: onPick)
    }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let limit: Int
        let onPick: ([PickedAsset]) -> Void

        init(limit: Int, onPick: @escaping ([PickedAsset]) -> Void) {
            self.limit = limit
            self.onPick = onPick
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard !results.isEmpty else { return }

            let group = DispatchGroup()
            var assets: [PickedAsset] = []
            let lock = NSLock()

            for (index, result) in results.enumerated() {
                let provider = result.itemProvider
                guard provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) else { continue }
                group.enter()
                provider.loadFileRepresentation(forTypeIdentifier: UTType.image.identifier) { url, _ in
                    defer { group.leave() }
                    guard let url else { return }
                    // The temporary file is deleted as soon as this closure returns,
                    // so copy it into our own directory before continuing.
                    let name = url.lastPathComponent
                    let ext = url.pathExtension.isEmpty ? "jpg" : url.pathExtension
                    let destination = MediaStore.tempDirectory()
                        .appendingPathComponent("picked-\(UUID().uuidString).\(ext)")
                    try? FileManager.default.createDirectory(at: destination.deletingLastPathComponent(),
                                                            withIntermediateDirectories: true)
                    do {
                        try FileManager.default.copyItem(at: url, to: destination)
                    } catch {
                        return
                    }
                    let asset = PickedAsset(url: destination, name: name, order: index)
                    lock.lock()
                    assets.append(asset)
                    lock.unlock()
                }
            }

            group.notify(queue: .main) {
                self.onPick(assets.sorted { $0.order < $1.order })
            }
        }
    }
}

#else

/// Non-iOS placeholder so shared sources still type-check on macOS.
struct PhotoPickerView: View {
    let limit: Int
    let onPick: ([PickedAsset]) -> Void

    init(limit: Int = 1, onPick: @escaping ([PickedAsset]) -> Void) {
        self.limit = limit
        self.onPick = onPick
    }

    var body: some View {
        Text("相册选择仅在 iOS 可用")
            .font(.footnote)
            .foregroundStyle(.secondary)
    }
}

#endif

public struct PickedAsset: Identifiable, Equatable {
    public let id = UUID()
    public let url: URL
    public let name: String
    public let order: Int
}
