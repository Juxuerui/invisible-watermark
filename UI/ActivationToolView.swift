import SwiftUI
import CryptoKit

/// Variant shipped in the `ActivationTool` build (compile flag ACTIVATION_TOOL).
///
/// Licensing workstation: read or paste a device code, choose an expiry policy,
/// unlock with the private key (kept in memory only) and sign a licence.
/// Only the public key is compiled into the binary.
struct ActivationToolView: View {
    @EnvironmentObject private var model: AppModel

    @State private var deviceCode = ""
    @State private var expiryMode = ExpiryMode.days365
    @State private var customDays = "30"
    @State private var privateKeyPEM = ""
    @State private var unlockedKey: P256.Signing.PrivateKey?
    @State private var issuedCode = ""
    @State private var issuedExpire: UInt32 = 0
    @State private var message = ""
    @State private var messageIsError = false
    @State private var pastedLicense = ""
    @State private var verifyResult: String?
    @State private var verifyOK = false
    @State private var showKeyImporter = false

    enum ExpiryMode: String, CaseIterable, Identifiable {
        case days30 = "30 天"
        case days90 = "90 天"
        case days365 = "1 年"
        case permanent = "永久"
        case custom = "自定义"

        var id: String { rawValue }

        func seconds(customDays: Int?) -> UInt32 {
            switch self {
            case .days30: return LicenseIssuer.expireSeconds(days: 30)
            case .days90: return LicenseIssuer.expireSeconds(days: 90)
            case .days365: return LicenseIssuer.expireSeconds(days: 365)
            case .permanent: return LicenseIssuer.permanent
            case .custom: return LicenseIssuer.expireSeconds(days: customDays ?? 30)
            }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    keySection
                    issueSection
                    verifySection
                    formatSection
                }
                .padding(20)
            }
            .background(Color(red: 0.96, green: 0.96, blue: 0.98))
            .navigationTitle("隐形水印 · 授权工具")
            .inlineNavigationTitle()
            .onAppear {
                if deviceCode.isEmpty { deviceCode = License.deviceCode() }
            }
            .fileImporter(isPresented: $showKeyImporter,
                          allowedContentTypes: [.data, .text],
                          allowsMultipleSelection: false) { result in
                handleKeyImport(result)
            }
        }
    }

    private var keySection: some View {
        card("签名密钥") {
            if unlockedKey != nil {
                Label("已解锁，可签发授权码", systemImage: "key.fill")
                    .font(.footnote)
                    .foregroundStyle(.green)
                Text("公钥指纹 \(LicenseIssuer.publicKeyFingerprint().prefix(16))…")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Button("锁定并清除私钥", role: .destructive) {
                    unlockedKey = nil
                    privateKeyPEM = ""
                    issuedCode = ""
                }
                .font(.footnote)
            } else {
                Text("粘贴 PKCS#8 私钥（BEGIN PRIVATE KEY）。私钥只存在内存中，不写磁盘，也不打包进应用。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextEditor(text: $privateKeyPEM)
                    .font(.system(.caption2, design: .monospaced))
                    .frame(height: 90)
                    .padding(8)
                    .background(Color.secondary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                HStack(spacing: 10) {
                    Button {
                        unlock()
                    } label: {
                        Label("解锁", systemImage: "lock.open")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(privateKeyPEM.trimmingCharacters(in: .whitespaces).isEmpty)

                    Button {
                        showKeyImporter = true
                    } label: {
                        Label("导入文件", systemImage: "doc.badge.plus")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private var issueSection: some View {
        card("签发授权码") {
            Text("设备码").font(.caption.bold()).foregroundStyle(.secondary)
            TextField("4CNAL-MCNWJ-SYE", text: $deviceCode)
                .font(.system(.callout, design: .monospaced))
                .uppercaseInput()
                .autocorrectionDisabled()
                .padding(10)
                .background(Color.secondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            HStack(spacing: 8) {
                Button {
                    deviceCode = License.deviceCode()
                    copy(deviceCode)
                    model.toast = "已填入本机设备码"
                } label: {
                    Text("用本机设备码").font(.footnote)
                }
                .buttonStyle(.bordered)

                Button {
                    copy(deviceCode)
                    model.toast = "设备码已复制"
                } label: {
                    Text("复制").font(.footnote)
                }
                .buttonStyle(.bordered)
            }

            Text("有效期").font(.caption.bold()).foregroundStyle(.secondary)
                .padding(.top, 4)

            Picker("有效期", selection: $expiryMode) {
                ForEach(ExpiryMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            if expiryMode == .custom {
                TextField("天数", text: $customDays)
                    .numberKeyboard()
                    .padding(10)
                    .background(Color.secondary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            Button {
                issue()
            } label: {
                Label("生成授权码", systemImage: "signature")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
            }
            .buttonStyle(.borderedProminent)
            .disabled(unlockedKey == nil)

            if !issuedCode.isEmpty {
                Text("授权码（到期 \(License.expireText(issuedExpire))）")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Text(issuedCode)
                    .font(.system(.caption2, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Color.secondary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                HStack(spacing: 10) {
                    Button {
                        copy(issuedCode)
                        model.toast = "授权码已复制"
                    } label: {
                        Label("复制授权码", systemImage: "doc.on.doc")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                    }
                    .buttonStyle(.borderedProminent)

                    ShareLink(item: issuedCode) {
                        Label("分享", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                    }
                    .buttonStyle(.bordered)
                }
            }

            if !message.isEmpty {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(messageIsError ? .red : .green)
            }
        }
    }

    private var verifySection: some View {
        card("校验授权码") {
            TextEditor(text: $pastedLicense)
                .font(.system(.caption2, design: .monospaced))
                .frame(height: 80)
                .padding(8)
                .background(Color.secondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            Button {
                let result = License.verify(pastedLicense)
                verifyOK = result.ok
                verifyResult = result.ok
                    ? "校验通过 · 到期 \(License.expireText(result.expireSec))"
                    : result.reason
            } label: {
                Label("校验", systemImage: "checkmark.shield")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
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
        card("格式说明") {
            Text("""
            授权码：<base32(载荷)>.<base32(签名)>

            载荷 13 字节
              [0]     版本，固定 01
              [1..4]  到期 Unix 秒，大端
              [5..12] 设备指纹 8 字节

            签名 ECDSA P-256 / SHA-256
            永久授权到期值 FFFFFFFF
            """)
            .font(.system(.caption2, design: .monospaced))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)

            Text("签发私钥必须与完整版应用内置的公钥配对。更换密钥后要重新构建完整版应用。")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private func unlock() {
        do {
            unlockedKey = try LicenseIssuer.privateKey(fromPEM: privateKeyPEM)
            message = "密钥已解锁"
            messageIsError = false
            privateKeyPEM = ""
        } catch {
            unlockedKey = nil
            message = error.localizedDescription
            messageIsError = true
        }
    }

    private func issue() {
        guard let key = unlockedKey else {
            message = "请先解锁私钥"
            messageIsError = true
            return
        }
        do {
            let expire = expiryMode.seconds(customDays: Int(customDays))
            let issued = try LicenseIssuer.issue(deviceCode: deviceCode,
                                                 expire: expire,
                                                 privateKey: key)
            let check = License.verify(issued.code)
            issuedCode = issued.code
            issuedExpire = issued.expire
            if check.ok {
                message = "生成成功，已自检通过"
                messageIsError = false
            } else {
                message = "已生成，但自检未通过：\(check.reason)"
                messageIsError = true
            }
        } catch {
            issuedCode = ""
            message = error.localizedDescription
            messageIsError = true
        }
    }

    private func handleKeyImport(_ result: Result<[URL], Swift.Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            if let text = try? String(contentsOf: url, encoding: .utf8) {
                privateKeyPEM = text
                unlock()
            } else {
                message = "无法读取该文件"
                messageIsError = true
            }
        case .failure(let error):
            message = error.localizedDescription
            messageIsError = true
        }
    }

    private func card<Content: View>(_ title: String,
                                     @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 9) {
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
