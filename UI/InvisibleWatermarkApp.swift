import SwiftUI

@main
struct InvisibleWatermarkApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .onAppear { model.checkLicense() }
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Group {
            #if ACTIVATION_TOOL
            ActivationToolView()
            #else
            if model.licenseOK {
                HomeView()
            } else {
                NavigationStack {
                    ActivationView()
                }
            }
            #endif
        }
        .overlay(alignment: .bottom) {
            if let toast = model.toast {
                Text(toast)
                    .font(.footnote)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .padding(.bottom, 24)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                            if model.toast == toast { model.toast = nil }
                        }
                    }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: model.toast)
    }
}
