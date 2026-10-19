import SwiftUI
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit

/// Document picker for images, PSD and zip.
///
/// Filters by explicit file extensions instead of broad UTTypes: a plain `.data`
/// filter greys out PNGs coming from some providers (Files, iCloud Drive, third
/// party apps) because those files do not declare a conforming type. Extension
/// based UTType declarations match the filename, which is what users expect.
public struct FilePickerView: UIViewControllerRepresentable {

    public enum Mode {
        case images(multiple: Bool)
        case zip
    }

    let mode: Mode
    let onPick: ([URL]) -> Void

    public init(mode: Mode, onPick: @escaping ([URL]) -> Void) {
        self.mode = mode
        self.onPick = onPick
    }

    /// Every common raster format plus PSD, declared by extension so the picker
    /// never greys out a file it can actually decode.
    static let imageExtensions = ["png", "jpg", "jpeg", "heic", "heif",
                                  "tif", "tiff", "bmp", "gif", "webp", "psd"]

    static func imageTypes() -> [UTType] {
        imageExtensions.compactMap { UTType(filenameExtension: $0) }
    }

    public func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let types: [UTType]
        switch mode {
        case .images:
            types = Self.imageTypes()
        case .zip:
            types = [.zip]
        }
        let controller = UIDocumentPickerViewController(forOpeningContentTypes: types,
                                                        asCopy: true)
        controller.allowsMultipleSelection = {
            if case .images(let multiple) = mode { return multiple }
            return false
        }()
        controller.shouldShowFileExtensions = true
        controller.delegate = context.coordinator
        return controller
    }

    public func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    public func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    public final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: ([URL]) -> Void

        init(onPick: @escaping ([URL]) -> Void) {
            self.onPick = onPick
        }

        public func documentPicker(_ controller: UIDocumentPickerViewController,
                                   didPickDocumentsAt urls: [URL]) {
            onPick(urls)
        }
    }
}

#else

/// Non-iOS placeholder so shared sources still type-check on macOS.
public struct FilePickerView: View {
    public enum Mode {
        case images(multiple: Bool)
        case zip
    }

    let mode: Mode
    let onPick: ([URL]) -> Void

    public init(mode: Mode, onPick: @escaping ([URL]) -> Void) {
        self.mode = mode
        self.onPick = onPick
    }

    public var body: some View {
        Text("文件选择仅在 iOS 可用")
            .font(.footnote)
            .foregroundStyle(.secondary)
    }
}

#endif
