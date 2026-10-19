import SwiftUI

/// Mirrors MainActivity: three entries plus licence state.
struct HomeView: View {
    @EnvironmentObject private var model: AppModel
    @State private var path: [Route] = []

    enum Route: Hashable {
        case embed
        case detect
        case emailConfig
        case activation
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(spacing: 16) {
                    header

                    menuCard(icon: "photo.on.rectangle.angled",
                             title: "批量打标",
                             subtitle: "选择图片与 QQ 号，写入隐形水印并导出/发送",
                             tint: Color(red: 0.12, green: 0.37, blue: 0.66)) {
                        path.append(.embed)
                    }

                    menuCard(icon: "magnifyingglass",
                             title: "批量查标",
                             subtitle: "单图、多图或压缩包检测隐藏的 QQ 号",
                             tint: Color(red: 0.13, green: 0.55, blue: 0.4)) {
                        path.append(.detect)
                    }

                    menuCard(icon: "envelope",
                             title: "邮箱配置",
                             subtitle: "SMTP 发件配置，用于把压缩包自动发送到对应邮箱",
                             tint: Color(red: 0.83, green: 0.33, blue: 0)) {
                        path.append(.emailConfig)
                    }

                    licenseCard
                }
                .padding(20)
            }
            .background(Color(red: 0.96, green: 0.96, blue: 0.98))
            .navigationTitle("隐形水印")
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .embed: EmbedView()
                case .detect: DetectView()
                case .emailConfig: EmailConfigView()
                case .activation: ActivationView()
                }
            }
        }
    }

    private var header: some View {
        VStack(spacing: 6) {
            Image(systemName: "eye.slash.circle.fill")
                .font(.system(size: 52))
                .foregroundStyle(Color(red: 0.12, green: 0.37, blue: 0.66))
            Text("隐形水印")
                .font(.largeTitle.bold())
            Text("DCT 频域隐形水印 · 批量打标与溯源")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
    }

    private func menuCard(icon: String, title: String, subtitle: String, tint: Color,
                          action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 26))
                    .foregroundStyle(tint)
                    .frame(width: 44, height: 44)
                    .background(tint.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.headline)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(.white)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
        }
        .buttonStyle(.plain)
    }

    private var licenseCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: model.licenseOK ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(model.licenseOK ? .green : .orange)
                Text(model.licenseOK ? "已授权（\(model.licenseExpireText)）" : "未授权")
                    .font(.subheadline.bold())
                Spacer()
                Button("管理") { path.append(.activation) }
                    .font(.footnote)
            }
            Text("设备码 \(License.deviceCode())")
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .padding(14)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}
