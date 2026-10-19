import SwiftUI
import WatermarkCore
#if canImport(UIKit)
import UIKit
#endif

/// Mirrors EmailConfigActivity.
struct EmailConfigView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var host = ""
    @State private var port = ""
    @State private var account = ""
    @State private var password = ""
    @State private var resultText = ""
    @State private var resultIsError = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                field("SMTP 服务器", text: $host, placeholder: "smtp.qq.com", keyboard: .URL, allowsAutocapitalization: false)
                field("端口", text: $port, placeholder: "465", keyboard: .numberPad, allowsAutocapitalization: false)
                field("发件邮箱", text: $account, placeholder: "your@qq.com", keyboard: .emailAddress, allowsAutocapitalization: false)
                field("邮箱授权码", text: $password, placeholder: "SMTP 授权码（非登录密码）", keyboard: .default, secure: true)

                Text("QQ 邮箱需在「设置 → 账户」开启 SMTP 服务并使用授权码；端口 465 走 SSL，587 走 STARTTLS。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button {
                    save()
                } label: {
                    Text("保存配置")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    testSend()
                } label: {
                    Text("测试发送")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.bordered)
                .disabled(!model.emailConfig.isValid)

                if !resultText.isEmpty {
                    Text(resultText)
                        .font(.footnote)
                        .foregroundStyle(resultIsError ? .red : .green)
                }
            }
            .padding(20)
        }
        .background(Color(red: 0.96, green: 0.96, blue: 0.98))
        .navigationTitle("邮箱配置")
        .inlineNavigationTitle()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("返回") { dismiss() }
            }
        }
        .onAppear(perform: load)
    }

    private func field(_ title: String, text: Binding<String>, placeholder: String,
                       keyboard: KeyboardKind, secure: Bool = false,
                       allowsAutocapitalization: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.footnote.bold()).foregroundStyle(.secondary)
            Group {
                if secure {
                    SecureField(placeholder, text: text)
                } else {
                    TextField(placeholder, text: text)
                }
            }
            .autocorrectionDisabled()
            .keyboardConfiguration(keyboard)
            .padding(10)
            .background(.white)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private func load() {
        let config = model.emailConfig
        host = config.smtpHost
        port = config.smtpPort
        account = config.account
        password = config.password
    }

    private func save() {
        var config = model.emailConfig
        config.smtpHost = host.trimmingCharacters(in: .whitespaces)
        config.smtpPort = port.trimmingCharacters(in: .whitespaces)
        config.account = account.trimmingCharacters(in: .whitespaces)
        config.password = password.trimmingCharacters(in: .whitespaces)
        if config.account.isEmpty || config.password.isEmpty {
            resultText = "请填写完整的邮箱和授权码"
            resultIsError = true
            return
        }
        EmailUtil.saveConfig(config)
        model.emailConfig = config
        resultText = "配置已保存！"
        resultIsError = false
        model.toast = "邮箱配置已保存"
    }

    private func testSend() {
        guard model.emailConfig.isValid else {
            resultText = "请先保存配置"
            resultIsError = true
            return
        }
        resultText = "正在测试发送..."
        resultIsError = false
        let config = model.emailConfig
        DispatchQueue.global(qos: .userInitiated).async {
            let temp = FileManager.default.temporaryDirectory.appendingPathComponent("测试附件.txt")
            try? Data("WorkBuddy watermark SMTP test".utf8).write(to: temp)
            do {
                try EmailUtil.send(config: config,
                                   to: config.account,
                                   subject: "隐形水印 SMTP 测试",
                                   htmlBody: "<p>这是一封测试邮件，收到说明 SMTP 配置正确。</p>",
                                   attachment: temp)
                DispatchQueue.main.async {
                    resultText = "测试发送成功"
                    resultIsError = false
                }
            } catch {
                DispatchQueue.main.async {
                    resultText = "发送失败：\(error.localizedDescription)"
                    resultIsError = true
                }
            }
        }
    }
}
