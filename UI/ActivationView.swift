import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Mirrors AuthSplash + LicenseGate: block the app until a valid, device bound
/// licence is entered.
struct ActivationView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("隐形水印 · 软件激活")
                    .font(.title2.bold())
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.bottom, 6)

                Text("本软件为一机一码授权。请把下面的「设备码」发给授权方，再把返回的授权码粘贴到下方激活。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Text("本机设备码")
                    .font(.footnote.bold())
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)

                Text(License.deviceCode())
                    .font(.system(.body, design: .monospaced).bold())
                    .foregroundStyle(Color(red: 0.12, green: 0.37, blue: 0.66))
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                Button {
                    copyToPasteboard(License.deviceCode())
                    model.toast = "设备码已复制"
                } label: {
                    Text("复制设备码")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.87, green: 0.92, blue: 0.97))

                Text("获取授权 / 续期，请联系 QQ：3409813753")
                    .font(.footnote)
                    .foregroundStyle(Color(red: 0.83, green: 0.33, blue: 0))
                    .padding(.top, 8)

                Button {
                    copyToPasteboard("3409813753")
                    model.toast = "已复制联系QQ"
                } label: {
                    Text("复制联系QQ")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.bordered)

                Text("授权码")
                    .font(.footnote.bold())
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)

                TextEditor(text: $model.licenseCodeInput)
                    .font(.system(.footnote, design: .monospaced))
                    .frame(minHeight: 110)
                    .padding(8)
                    .background(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(alignment: .topLeading) {
                        if model.licenseCodeInput.isEmpty {
                            Text("粘贴授权码（xxxx.yyyy，一整段）")
                                .font(.footnote)
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 13)
                                .padding(.vertical, 16)
                                .allowsHitTesting(false)
                        }
                    }

                Button {
                    model.activate()
                } label: {
                    Text("激活")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.licenseCodeInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                if !model.licenseReason.isEmpty {
                    Text(model.licenseReason)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                Text("设备码由本机标识经 SHA-256 派生，用于授权码绑定；授权码含 ECDSA 签名，复制到其他设备无效。")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 12)
            }
            .padding(20)
        }
        .background(Color(red: 0.96, green: 0.96, blue: 0.98))
        .navigationTitle("软件激活")
        .inlineNavigationTitle()
    }

    private func copyToPasteboard(_ value: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = value
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        #endif
    }
}
