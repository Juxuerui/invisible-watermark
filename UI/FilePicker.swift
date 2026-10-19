import SwiftUI
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit

/// Bridges SwiftUI to the document picker. A document picker (instead of the
/// photo picker) is used so that PSD files and zip archives can be selected too.
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

    public func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let types: [UTType]
        switch mode {
        case .images:
            // `.image` covers png/jpeg/tiff/heic; PSD is not a system image type,
            // so it is admitted through `.data` and filtered by extension.
            types = [.image, .data]
        case .zip:
            types = [.zip, .archive]
        }
        let controller = UIDocumentPickerViewController(forOpeningContentTypes: types,
                                                        asCopy: true)
        controller.allowsMultipleSelection = {
            if case .images(let multiple) = mode { return multiple }
            return false
        }()
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

/// Non-iOS placeholder so the shared UI sources still type-check on macOS.
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
