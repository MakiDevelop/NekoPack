import SwiftUI
import UniformTypeIdentifiers

struct CompressView: View {
    @StateObject private var compressionManager = CompressionManager()

    @State private var sourceURLs: [URL] = []
    @State private var outputDirectory: URL?
    @State private var selectedFormat: CompressionFormat = .zip
    @State private var password: String = ""
    @State private var outputFileName: String = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                dropZone
                formatPicker
                outputNameField

                if selectedFormat.supportsPassword {
                    passwordField
                }

                outputDirectoryPicker
                compressButton

                if compressionManager.isCompressing || !compressionManager.statusMessage.isEmpty {
                    statusArea
                }
            }
            .padding()
        }
    }

    // MARK: - Components

    private var dropZone: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.secondary.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(
                            LinearGradient(
                                colors: [.green, .blue],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 2
                        )
                )
                .frame(height: 120)

            VStack(spacing: 8) {
                Image(systemName: sourceURLs.isEmpty ? "plus.rectangle.on.folder" : "folder.fill")
                    .font(.system(size: 28))
                    .foregroundColor(sourceURLs.isEmpty ? .blue : .green)

                if sourceURLs.isEmpty {
                    Text("拖放檔案或資料夾到這裡，或點擊選擇")
                        .font(.callout)
                        .foregroundColor(.secondary)
                } else {
                    Text("已選擇 \(sourceURLs.count) 個項目")
                        .font(.callout)
                        .foregroundColor(.green)
                    if let first = sourceURLs.first {
                        Text(first.lastPathComponent)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    if let url = url {
                        DispatchQueue.main.async {
                            if !sourceURLs.contains(url) {
                                sourceURLs.append(url)
                            }
                            if outputFileName.isEmpty {
                                outputFileName = url.deletingPathExtension().lastPathComponent
                            }
                            if outputDirectory == nil {
                                outputDirectory = url.deletingLastPathComponent()
                            }
                        }
                    }
                }
            }
            return true
        }
        .onTapGesture { selectSources() }
    }

    private var formatPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("壓縮格式")
                .font(.headline)

            Picker("", selection: $selectedFormat) {
                ForEach(CompressionFormat.allCases) { format in
                    Text(format.displayName).tag(format)
                }
            }
            .pickerStyle(SegmentedPickerStyle())

            Text(selectedFormat.hint)
                .font(.caption)
                .foregroundColor(.secondary)

            HStack(spacing: 16) {
                Label(selectedFormat.compatibility.rawValue, systemImage: "globe")
                Label(selectedFormat.compressionLevel.rawValue, systemImage: "arrow.down.right.circle")
                if selectedFormat.supportsPassword {
                    Label("可加密", systemImage: "lock")
                }
            }
            .font(.caption2)
            .foregroundColor(.secondary)
        }
    }

    private var outputNameField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("輸出檔名")
                .font(.headline)

            HStack {
                TextField("輸出檔名", text: $outputFileName)
                    .textFieldStyle(.roundedBorder)

                Text(".\(selectedFormat.fileExtension)")
                    .font(.callout)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var passwordField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("密碼保護（選填）")
                .font(.headline)

            SecureField("輸入密碼", text: $password)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var outputDirectoryPicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("輸出位置")
                .font(.headline)

            HStack {
                Text(outputDirectory?.path ?? "未選擇")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()

                Button(action: selectOutputDirectory) {
                    HStack(spacing: 4) {
                        Image(systemName: "folder")
                        Text("選擇")
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var compressButton: some View {
        Button(action: {
            if compressionManager.isCompressing {
                compressionManager.cancel()
            } else {
                startCompression()
            }
        }) {
            HStack(spacing: 8) {
                Image(systemName: compressionManager.isCompressing ? "stop.circle.fill" : "archivebox.fill")
                    .font(.title3)
                Text(compressionManager.isCompressing ? "停止" : "開始壓縮")
                    .font(.headline)
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                LinearGradient(
                    colors: compressionManager.isCompressing ? [.red, .orange] : [.green, .blue],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .foregroundColor(.white)
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
        .disabled(sourceURLs.isEmpty || outputDirectory == nil || outputFileName.isEmpty)
    }

    private var statusArea: some View {
        VStack(spacing: 8) {
            if compressionManager.isCompressing {
                ProgressView(value: compressionManager.progress)
                    .progressViewStyle(LinearProgressViewStyle(tint: .green))
            }

            Text(compressionManager.statusMessage)
                .font(.caption)
                .foregroundColor(compressionManager.statusMessage.contains("❌") ? .red : .secondary)
                .textSelection(.enabled)
        }
    }

    // MARK: - Actions

    private func selectSources() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.message = "選擇要壓縮的檔案或資料夾"
        panel.prompt = "選擇"

        if panel.runModal() == .OK {
            sourceURLs = panel.urls
            if let first = sourceURLs.first {
                if outputFileName.isEmpty {
                    outputFileName = first.deletingPathExtension().lastPathComponent
                }
                if outputDirectory == nil {
                    outputDirectory = first.deletingLastPathComponent()
                }
            }
        }
    }

    private func selectOutputDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "選擇輸出位置"
        panel.prompt = "選擇"

        if panel.runModal() == .OK {
            outputDirectory = panel.url
        }
    }

    private func startCompression() {
        guard let outputDir = outputDirectory else { return }
        let outputURL = outputDir.appendingPathComponent("\(outputFileName).\(selectedFormat.fileExtension)")

        Task {
            let success = await compressionManager.compress(
                sources: sourceURLs,
                to: outputURL,
                format: selectedFormat,
                password: password.isEmpty ? nil : password
            )

            if success {
                compressionManager.statusMessage = "✅ 壓縮完成：\(outputURL.lastPathComponent)"
            }
        }
    }
}
