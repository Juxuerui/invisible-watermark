import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Variant shipped in the `ActivationTool` build (compile flag ACTIVATION_TOOL).
///
/// Intended for the licence issuer: it shows the host device code, lets the
/// operator paste a licence back to verify it locally, and documents the payload
/// layout needed by the signing side. It cannot create signatures because the
/// private key is not part of the app.
struct ActivationToolView: View {
    @EnvironmentObject private var model: AppModel
    @State private var pastedLicense = ""
    @State private var verifyResult: String?
    @State private var verifyOK = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    deviceSection
                    verifySection
                    formatSection
                }
                .padding(20)
            }
            .background(Color(red: 0.96, green: 0.96, blue: 0.98))
            .navigationTitle("隐形水印 · 授权工具")
            .inlineNavigationTitle()
        }
    }

    private var deviceSection: some View {
        card("本机设备码") {
            Text(License.deviceCode())
                .font(.system(.title3, design: .monospaced).bold())
                .foregroundStyle(Color(red: 0.12, green: 0.37, blue: 0.66))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color.secondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            Button {
                copy(License.deviceCode())
                model.toast = "设备码已复制"
            } label: {
                Label("复制设备码", systemImage: "doc.on.doc")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)

            Text("把这段设备码填入授权码生成器，用同一把私钥签名后，产出的授权码即可在完整版应用中激活。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var verifySection: some View {
        card("校验授权码") {
            TextEditor(text: $pastedLicense)
                .font(.system(.footnote, design: .monospaced))
                .frame(height: 100)
                .padding(8)
                .background(Color.secondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(alignment: .topLeading) {
                    if pastedLicense.isEmpty {
                        Text("粘贴授权码（xxxx.yyyy）")
                            .font(.footnote)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 16)
                            .allowsHitTesting(false)
                    }
                }

            Button {
                let result = License.verify(pastedLicense)
                verifyOK = result.ok
                if result.ok {
                    verifyResult = "校验通过，到期：\(License.expireText(result.expireSec))"
                } else {
                    verifyResult = result.reason
                }
            } label: {
                Label("校验", systemImage: "checkmark.shield")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.bordered)

            if let verifyResult {
                Text(verifyResult)
                    .font(.footnote)
                    .foregroundStyle(verifyOK ? .green : .red)
            }
        }
    }

    private var formatSection: some View {
        card("授权码格式") {
            Text("""
            结构：<base32(载荷)>.<base32(签名)>

            载荷 13 字节：
              [0]     版本，固定 01
              [1..4]  到期时间，Unix 秒，大端
              [5..12] 设备指纹 8 字节
                       = SHA-256(设备标识) 前 8 字节

            签名：ECDSA P-256 / SHA-256，覆盖全部 13 字节载荷
            到期值 FFFFFFFF 表示永久
            """)
            .font(.system(.caption, design: .monospaced))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)

            Text("本工具只做校验，不包含私钥，因此无法生成签名。签名请在授权码生成器侧完成。")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private func card<Content: View>(_ title: String,
                                     @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.subheadline.bold()).foregroundStyle(.secondary)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func copy(_ value: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = value
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        #endif
    }
}
