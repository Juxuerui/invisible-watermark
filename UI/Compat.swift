import SwiftUI

extension View {
    /// `navigationBarTitleDisplayMode` does not exist on macOS, so route it
    /// through a conditional modifier to keep the shared sources compiling on
    /// both platforms.
    @ViewBuilder
    func inlineNavigationTitle() -> some View {
        #if os(iOS)
        self.navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }
}

/// Keyboard types shared between platforms.
public enum KeyboardKind {
    case `default`
    case URL
    case numberPad
    case emailAddress
}

extension View {
    @ViewBuilder
    func keyboardConfiguration(_ kind: KeyboardKind) -> some View {
        #if os(iOS)
        switch kind {
        case .default:
            self.keyboardType(.default)
        case .URL:
            self.keyboardType(.URL)
                .textInputAutocapitalization(.never)
        case .numberPad:
            self.keyboardType(.numberPad)
        case .emailAddress:
            self.keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
        }
        #else
        self
        #endif
    }
}
