import SwiftUI
import UniformTypeIdentifiers

struct ExtractView: View {
    @State private var extractionManager = ExtractionManager()

    @State private var archiveURLs: [URL] = []
    @State private var destinationURL: URL?
    @State private var password: String = ""
    @State private var isExtracting = false
    @State private var progress: Double = 0.0
    @State private var currentFile: String = ""
    @State private var statusMessage: String = ""
    @State private var isBatchMode = false

    @State private var processedFiles: Int = 0
    @State private var totalFiles: Int = 0
    @State private var successCount: Int = 0
    @State private var failCount: Int = 0

    private let supportedExtensions = ["rar", "zip", "7z", "tar", "gz", "tgz", "bz2", "tbz", "xz", "zst"]

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                modeToggle
                dropZone
                passwordField
                destinationPicker
                extractButton

                if isExtracting || !statusMessage.isEmpty {
                    statusArea
                }
            }
            .padding()
        }
    }

    // MARK: - Components

    private var modeToggle: some View {
        HStack {
            Text("模式")
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Picker("", selection: $isBatchMode) {
                Text("單檔").tag(false)
                Text("批次").tag(true)
            }
            .pickerStyle(SegmentedPickerStyle())
            .frame(width: 140)
        }
        .onChange(of: isBatchMode) {
            archiveURLs = []
            statusMessage = ""
        }
    }

    private var dropZone: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.secondary.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(
                            LinearGradient(
                                colors: [.orange, .red],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 2
                        )
                )
                .frame(height: 120)

            VStack(spacing: 8) {
                Image(systemName: archiveURLs.isEmpty ? "doc.badge.plus" : "doc.fill")
                    .font(.system(size: 28))
                    .foregroundColor(archiveURLs.isEmpty ? .orange : .green)

                if archiveURLs.isEmpty {
                    Text(isBatchMode ? "拖放資料夾（含多個壓縮檔），或點擊選擇" : "拖放壓縮檔到這裡，或點擊選擇")
                        .font(.callout)
                        .foregroundColor(.secondary)
                } else if isBatchMode {
                    Text("已找到 \(archiveURLs.count) 個壓縮檔")
                        .font(.callout)
                        .foregroundColor(.green)
                } else {
                    Text(archiveURLs.first?.lastPathComponent ?? "")
                        .font(.callout)
                        .foregroundColor(.green)
                        .lineLimit(1)
                    Text(archiveTypeDescription(for: archiveURLs.first))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url = url else { return }
                    DispatchQueue.main.async {
                        handleDroppedURL(url)
                    }
                }
            }
            return true
        }
        .onTapGesture { selectArchive() }
    }

    private var passwordField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("密碼（選填）")
                .font(.headline)

            SecureField("如果壓縮檔有密碼保護", text: $password)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var destinationPicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("解壓到")
                .font(.headline)

            HStack {
                Text(destinationURL?.path ?? "預設為壓縮檔所在目錄")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()

                Button(action: selectDestination) {
                    HStack(spacing: 4) {
                        Image(systemName: "folder")
                        Text("選擇")
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.orange)
                    .foregroundColor(.white)
                    .cornerRadius(6)
                }
                .buttonStyle(.borderless)
            }
        }
    }

    private var extractButton: some View {
        Button(action: {
            if isExtracting {
                extractionManager.cancel()
                isExtracting = false
                statusMessage = "已取消解壓縮"
            } else {
                startExtraction()
            }
        }) {
            HStack(spacing: 8) {
                Image(systemName: isExtracting ? "stop.circle.fill" : "arrow.down.circle.fill")
                    .font(.title3)
                Text(isExtracting ? "停止" : "開始解壓縮")
                    .font(.headline)
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                LinearGradient(
                    colors: isExtracting ? [.red, .orange] : [.orange, .red],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .foregroundColor(.white)
            .cornerRadius(12)
        }
        .buttonStyle(.borderless)
        .disabled(archiveURLs.isEmpty)
    }

    private var statusArea: some View {
        VStack(spacing: 8) {
            if isExtracting {
                if isBatchMode && totalFiles > 0 {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("總進度")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(processedFiles)/\(totalFiles)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        ProgressView(value: totalFiles > 0 ? Double(processedFiles) / Double(totalFiles) : 0)
                            .progressViewStyle(LinearProgressViewStyle(tint: .orange))
                    }
                }

                if !currentFile.isEmpty {
                    Text(currentFile)
                        .font(.caption)
                        .foregroundColor(.blue)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                ProgressView(value: progress)
                    .progressViewStyle(LinearProgressViewStyle(tint: .orange))
            }

            if !statusMessage.isEmpty {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundColor(statusMessage.contains("❌") ? .red : .secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Actions

    private func handleDroppedURL(_ url: URL) {
        if isBatchMode {
            if url.hasDirectoryPath {
                scanDirectory(url)
            } else if isArchive(url) {
                if !archiveURLs.contains(url) {
                    archiveURLs.append(url)
                }
            }
        } else {
            archiveURLs = [url]
        }

        if destinationURL == nil {
            destinationURL = url.hasDirectoryPath ? url : url.deletingLastPathComponent()
        }
    }

    private func selectArchive() {
        let panel = NSOpenPanel()

        if isBatchMode {
            panel.canChooseDirectories = true
            panel.canChooseFiles = true
            panel.allowsMultipleSelection = true
            panel.message = "選擇壓縮檔或包含壓縮檔的資料夾"
        } else {
            panel.canChooseDirectories = false
            panel.canChooseFiles = true
            panel.allowsMultipleSelection = false
            panel.allowedContentTypes = supportedExtensions.compactMap { UTType(filenameExtension: $0) }
            panel.message = "選擇壓縮檔"
        }
        panel.prompt = "選擇"

        if panel.runModal() == .OK {
            if isBatchMode {
                archiveURLs = []
                for url in panel.urls {
                    handleDroppedURL(url)
                }
            } else if let url = panel.url {
                archiveURLs = [url]
                if destinationURL == nil {
                    destinationURL = url.deletingLastPathComponent()
                }
            }
        }
    }

    private func selectDestination() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "選擇解壓縮輸出位置"
        panel.prompt = "選擇"

        if panel.runModal() == .OK {
            destinationURL = panel.url
        }
    }

    private func startExtraction() {
        let destination = destinationURL ?? archiveURLs.first?.deletingLastPathComponent()
        guard let destination = destination else { return }

        isExtracting = true
        statusMessage = ""
        progress = 0.0
        currentFile = ""
        processedFiles = 0
        successCount = 0
        failCount = 0

        if isBatchMode {
            totalFiles = archiveURLs.count
            Task {
                await extractBatch(to: destination)
            }
        } else if let archive = archiveURLs.first {
            totalFiles = 1
            Task {
                await extractSingle(archive: archive, to: destination)
            }
        }
    }

    private func extractSingle(archive: URL, to destination: URL) async {
        do {
            let result = try await extractionManager.extract(
                archive: archive,
                to: destination,
                password: password.isEmpty ? nil : password
            ) { prog, file in
                Task { @MainActor in
                    self.progress = prog
                    if let file = file {
                        self.currentFile = file
                    }
                }
            }

            if result.success {
                statusMessage = "✅ 解壓縮完成：\(archive.lastPathComponent)"
            } else {
                statusMessage = "❌ 解壓縮失敗：\(result.error?.localizedDescription ?? "未知錯誤")"
            }
        } catch {
            statusMessage = "❌ \(error.localizedDescription)"
        }

        isExtracting = false
        progress = 1.0
    }

    private func extractBatch(to destination: URL) async {
        for (index, archive) in archiveURLs.enumerated() {
            if !isExtracting { break }

            currentFile = archive.lastPathComponent
            progress = 0.0

            do {
                let result = try await extractionManager.extract(
                    archive: archive,
                    to: destination,
                    password: password.isEmpty ? nil : password
                ) { prog, _ in
                    Task { @MainActor in
                        self.progress = prog
                    }
                }

                if result.success {
                    successCount += 1
                } else {
                    failCount += 1
                }
            } catch {
                failCount += 1
            }

            processedFiles = index + 1
        }

        isExtracting = false
        currentFile = ""
        statusMessage = "✅ 批次解壓縮完成：成功 \(successCount) / 失敗 \(failCount) / 共 \(totalFiles) 個"
    }

    // MARK: - Helpers

    private func isArchive(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        let name = url.lastPathComponent.lowercased()
        return supportedExtensions.contains(ext) ||
               name.hasSuffix(".tar.gz") ||
               name.hasSuffix(".tar.bz2") ||
               name.hasSuffix(".tar.xz") ||
               name.hasSuffix(".tar.zst")
    }

    private func scanDirectory(_ url: URL) {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil
        ) else { return }

        for file in contents where isArchive(file) {
            if !archiveURLs.contains(file) {
                archiveURLs.append(file)
            }
        }
        archiveURLs.sort { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func archiveTypeDescription(for url: URL?) -> String {
        guard let url = url else { return "" }
        guard let type = ArchiveType.detect(from: url) else { return url.pathExtension.uppercased() }
        return type.description
    }
}
