import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Mirrors DetectActivity: single image, batch images or a zip archive.
struct DetectView: View {
    @EnvironmentObject private var model: AppModel
    @State private var pickerMode: FilePickerView.Mode?
    @State private var showPicker = false
    @State private var showPhotoPicker = false
    @State private var photoLimit = 1

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                section("选择来源") {
                    Button {
                        photoLimit = 1
                        showPhotoPicker = true
                    } label: {
                        Label("单图查标", systemImage: "photo")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        photoLimit = 0
                        showPhotoPicker = true
                    } label: {
                        Label("批量查标", systemImage: "photo.stack")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        pickerMode = .zip
                        showPicker = true
                    } label: {
                        Label("压缩包查标", systemImage: "doc.zipper")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        pickerMode = .images(multiple: true)
                        showPicker = true
                    } label: {
                        Label("从文件选择（PSD 等）", systemImage: "folder")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.bordered)
                }

                if model.detectRunning || !model.detectStatus.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ProgressView(value: model.detectProgress)
                        Text(model.detectStatus).font(.caption).foregroundStyle(.secondary)
                    }
                }

                if !model.detectResults.isEmpty {
                    section("检测结果") {
                        ForEach(model.detectResults) { item in
                            HStack(spacing: 10) {
                                Image(systemName: item.detected ? "checkmark.circle.fill" : "xmark.circle")
                                    .foregroundStyle(item.detected ? .green : .secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name).font(.footnote).lineLimit(1)
                                    Text(item.detected ? "检测到 QQ: \(item.qq ?? "-")" : "未检测到水印")
                                        .font(.caption)
                                        .foregroundStyle(item.detected ? Color.green : Color.secondary)
                                }
                                Spacer()
                                if let qq = item.qq {
                                    Button {
                                        copyToPasteboard(qq)
                                        model.toast = "已复制 QQ 号"
                                    } label: {
                                        Image(systemName: "doc.on.doc")
                                    }
                                    .buttonStyle(.borderless)
                                }
                            }
                            .padding(.vertical, 4)
                        }

                        let hits = model.detectResults.filter(\.detected).count
                        Text("共 \(model.detectResults.count) 张，\(hits) 张含水印")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Button("清空结果") { model.clearDetection() }
                            .font(.footnote)
                    }
                }
            }
            .padding(20)
        }
        .background(Color(red: 0.96, green: 0.96, blue: 0.98))
        .navigationTitle("批量查标")
        .inlineNavigationTitle()
        .sheet(isPresented: $showPicker) {
            pickerSheet
        }
        .sheet(isPresented: $showPhotoPicker) {
            PhotoPickerView(limit: photoLimit) { assets in
                showPhotoPicker = false
                let urls = assets.map(\.url)
                let names = assets.map(\.name)
                model.detectImages(urls, names: names)
            }
        }
    }

    @ViewBuilder
    private var pickerSheet: some View {
        if let mode = pickerMode {
            FilePickerView(mode: mode) { urls in
                showPicker = false
                switch mode {
                case .images:
                    model.detectImages(urls, names: urls.map(\.lastPathComponent))
                case .zip:
                    if let first = urls.first { model.detectZip(first) }
                }
            }
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

    private func copyToPasteboard(_ value: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = value
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        #endif
    }
}
