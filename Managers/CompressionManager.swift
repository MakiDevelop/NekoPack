import Foundation

@MainActor
class CompressionManager: ObservableObject {

    @Published var isCompressing = false
    @Published var progress: Double = 0.0
    @Published var statusMessage: String = ""
    @Published var currentFile: String = ""

    private var currentProcess: Process?
    private var isCancelled = false
    private let progressParser = ProcessOutputParser()

    static let junkPatterns = [
        "__MACOSX",
        ".DS_Store",
        "._*",
        ".Spotlight-V100",
        ".Trashes",
        "Thumbs.db",
        "desktop.ini",
    ]

    // MARK: - Public API

    func compress(
        sources: [URL],
        to outputURL: URL,
        format: CompressionFormat,
        password: String? = nil
    ) async -> Bool {
        guard !sources.isEmpty else {
            statusMessage = "❌ 沒有可壓縮的來源檔案"
            return false
        }

        isCancelled = false
        isCompressing = true
        progress = 0.0
        statusMessage = "準備壓縮中..."
        currentFile = ""

        defer {
            isCompressing = false
        }

        switch format {
        case .zip:
            return await compressWithSevenZip(sources: sources, to: outputURL, format: "zip", password: password)
        case .sevenZip:
            return await compressWithSevenZip(sources: sources, to: outputURL, format: "7z", password: password)
        case .tarGz:
            return await compressWithTar(sources: sources, to: outputURL, compression: "z")
        case .tarXz:
            return await compressWithTar(sources: sources, to: outputURL, compression: "J")
        case .tarZst:
            return await compressWithTar(sources: sources, to: outputURL, compression: "--zstd")
        }
    }

    func cancel() {
        isCancelled = true
        currentProcess?.terminate()
        currentProcess = nil
        isCompressing = false
        statusMessage = "已取消壓縮"
        progress = 0.0
    }

    // MARK: - 7zz (ZIP / 7z)

    private func compressWithSevenZip(
        sources: [URL],
        to outputURL: URL,
        format: String,
        password: String?
    ) async -> Bool {
        guard let toolPath = ExtractionConstants.toolURL(for: ExtractionConstants.BundleResource.sevenZip) else {
            statusMessage = "❌ 找不到 7zz 工具"
            return false
        }

        if FileManager.default.fileExists(atPath: outputURL.path) {
            do {
                try FileManager.default.removeItem(at: outputURL)
            } catch {
                statusMessage = "❌ 無法刪除既有壓縮檔：\(error.localizedDescription)"
                return false
            }
        }

        var arguments = ["a", "-t\(format)"]

        if format == "zip" {
            arguments.append("-mcu=on")
        }

        if format == "7z" {
            arguments.append("-mx=9")
        }

        if let password = password, !password.isEmpty {
            arguments.append("-p\(password)")
            if format == "7z" {
                arguments.append("-mhe=on")
            }
        }

        for pattern in Self.junkPatterns {
            arguments.append("-xr!\(pattern)")
        }

        arguments.append(outputURL.path)

        for source in sources {
            arguments.append(source.path)
        }

        return await runProcess(executableURL: toolPath, arguments: arguments)
    }

    // MARK: - tar (tar.gz / tar.xz / tar.zst)

    private func compressWithTar(
        sources: [URL],
        to outputURL: URL,
        compression: String
    ) async -> Bool {
        let tarPath = URL(fileURLWithPath: "/usr/bin/tar")

        var arguments = ["-cf", outputURL.path]

        if compression.hasPrefix("--") {
            arguments.append(compression)
        } else {
            arguments[0] = "-c\(compression)f"
        }

        for pattern in Self.junkPatterns {
            arguments.append("--exclude=\(pattern)")
        }

        for source in sources {
            arguments.append(contentsOf: ["-C", source.deletingLastPathComponent().path, source.lastPathComponent])
        }

        return await runProcess(executableURL: tarPath, arguments: arguments)
    }

    // MARK: - Process Runner

    private func runProcess(executableURL: URL, arguments: [String]) async -> Bool {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = executableURL
            process.arguments = arguments

            var env = ProcessInfo.processInfo.environment
            env["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin"
            env["LANG"] = "en_US.UTF-8"
            env["LC_ALL"] = "en_US.UTF-8"
            env["COPYFILE_DISABLE"] = "1"
            env["COPY_EXTENDED_ATTRIBUTES_DISABLE"] = "true"
            process.environment = env

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            var output = ""
            var didResume = false

            let safeResume: (Bool) -> Void = { result in
                DispatchQueue.main.async {
                    guard !didResume else { return }
                    didResume = true
                    continuation.resume(returning: result)
                }
            }

            pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }

                DispatchQueue.main.async {
                    output += chunk
                    if let progress = self?.progressParser.parseProgress(from: chunk, tool: .sevenZip) {
                        self?.progress = progress
                    }
                }
            }

            self.currentProcess = process

            process.terminationHandler = { [weak self] proc in
                pipe.fileHandleForReading.readabilityHandler = nil
                try? pipe.fileHandleForReading.close()

                DispatchQueue.main.async {
                    if self?.isCancelled == true {
                        safeResume(false)
                    } else if proc.terminationStatus == 0 {
                        self?.progress = 1.0
                        self?.statusMessage = "✅ 壓縮完成"
                        safeResume(true)
                    } else {
                        self?.progress = 0.0
                        self?.statusMessage = "❌ 壓縮失敗（代碼 \(proc.terminationStatus)）\n\(output.suffix(500))"
                        safeResume(false)
                    }
                    self?.currentProcess = nil
                }
            }

            do {
                try process.run()
                DispatchQueue.main.async {
                    self.statusMessage = "壓縮中..."
                    self.progress = 0.1
                }
            } catch {
                pipe.fileHandleForReading.readabilityHandler = nil
                try? pipe.fileHandleForReading.close()

                DispatchQueue.main.async {
                    self.statusMessage = "❌ 無法啟動壓縮：\(error.localizedDescription)"
                    self.progress = 0.0
                    safeResume(false)
                }
            }
        }
    }
}
