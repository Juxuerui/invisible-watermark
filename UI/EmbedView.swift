import SwiftUI
import WatermarkCore
#if canImport(UIKit)
import UIKit
#endif

/// Mirrors EmbedActivity: pick images, paste QQ numbers, choose mode, then
/// export zips / mail them / save to photos.
struct EmbedView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showPicker = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                section("图片") {
                    Button {
                        showPicker = true
                    } label: {
                        Label("选择图片", systemImage: "photo.badge.plus")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)

                    Text("已选 \(model.embedImages.count) 张图片")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    if !model.embedImages.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(model.embedImages) { item in
                                    VStack(spacing: 4) {
                                        thumbnail(for: item)
                                        Text(item.name)
                                            .font(.caption2)
                                            .lineLimit(1)
                                            .frame(width: 76)
                                        Button("移除") {
                                            model.embedImages.removeAll { $0.id == item.id }
                                        }
                                        .font(.caption2)
                                        .buttonStyle(.borderless)
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }

                section("QQ 号") {
                    TextEditor(text: $model.qqInput)
                        .font(.system(.body, design: .monospaced))
                        .frame(height: 96)
                        .padding(8)
                        .background(Color.secondary.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(alignment: .topLeading) {
                            if model.qqInput.isEmpty {
                                Text("输入QQ号，每行一个，也可用逗号/空格分隔")
                                    .font(.footnote)
                                    .foregroundStyle(.tertiary)
                                    .padding(.horizontal, 13)
                                    .padding(.vertical, 16)
                                    .allowsHitTesting(false)
                            }
                        }
                    Text("已输入 \(model.parsedQQ.count) 个QQ号")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if !model.embedImages.isEmpty, model.parsedQQ.isEmpty {
                        Text("图片数量与QQ号数量不一致，已输入 0 个号码将无法开始")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    } else if model.embedImages.count > 1, model.parsedQQ.count > 1 {
                        Text("将按顺序循环匹配：第 i 张图片对应第 i mod N 个QQ号")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                section("水印模式") {
                    Picker("模式", selection: $model.robustMode) {
                        Text("标准（DCT 位平面）").tag(false)
                        Text("增强（抗剪裁/压缩）").tag(true)
                    }
                    .pickerStyle(.segmented)
                    Text(model.robustMode
                         ? "增强模式写入 32 位同步头 + 128 位载荷，抗裁剪与压缩更强，适合网络传播。"
                         : "标准模式写入 16 位同步头 + 11 位数字 + CRC，容量小、速度快，适合原图分发。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if model.embedRunning {
                    VStack(alignment: .leading, spacing: 6) {
                        ProgressView(value: model.embedProgress)
                        Text(model.embedStatus).font(.caption).foregroundStyle(.secondary)
                    }
                }

                Button {
                    model.startEmbedding()
                } label: {
                    Label("开始打标", systemImage: "wand.and.stars")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.embedRunning)

                section("导出与发送") {
                    HStack(spacing: 10) {
                        Button {
                            model.exportZips()
                        } label: {
                            Label("导出压缩包", systemImage: "archivebox")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                        }
                        .buttonStyle(.bordered)
                        .disabled(model.watermarkedFiles.isEmpty)

                        Button {
                            model.sendEmails()
                        } label: {
                            Label("发送到邮箱", systemImage: "paperplane")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                        }
                        .buttonStyle(.bordered)
                        .disabled(model.watermarkedFiles.isEmpty)
                    }

                    Button {
                        model.saveToPhotos()
                    } label: {
                        Label("保存图片到相册", systemImage: "photo.on.rectangle")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.watermarkedFiles.isEmpty)

                    Button {
                        model.showEmailConfig = true
                    } label: {
                        Label("邮箱配置", systemImage: "gearshape")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.bordered)
                }

                if !model.embedResultText.isEmpty {
                    section("结果") {
                        Text(model.embedResultText)
                            .font(.footnote)
                            .textSelection(.enabled)
                    }
                }

                if !model.generatedZips.isEmpty {
                    section("已生成的压缩包") {
                        ForEach(model.generatedZips, id: \.self) { url in
                            HStack {
                                Image(systemName: "doc.zipper")
                                Text(url.lastPathComponent).font(.footnote)
                                Spacer()
                                ShareLink(item: url) {
                                    Image(systemName: "square.and.arrow.up")
                                }
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
        .background(Color(red: 0.96, green: 0.96, blue: 0.98))
        .navigationTitle("批量打标")
        .inlineNavigationTitle()
        .sheet(isPresented: $showPicker) {
            FilePickerView(mode: .images(multiple: true)) { urls in
                showPicker = false
                model.embedImages.append(contentsOf: urls.map {
                    PickedImage(url: $0, name: $0.lastPathComponent, thumbnail: nil)
                })
            }
        }
        .sheet(isPresented: $model.showEmailConfig) {
            NavigationStack { EmailConfigView() }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.subheadline.bold()).foregroundStyle(.secondary)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder
    private func thumbnail(for item: PickedImage) -> some View {
        #if canImport(UIKit)
        if let image = UIImage(contentsOfFile: item.url.path) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 76, height: 76)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        } else {
            placeholderThumbnail
        }
        #else
        placeholderThumbnail
        #endif
    }

    private var placeholderThumbnail: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(Color.secondary.opacity(0.12))
            .frame(width: 76, height: 76)
            .overlay(Image(systemName: "photo").foregroundStyle(.tertiary))
    }
}
