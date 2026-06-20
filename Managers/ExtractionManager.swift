//
//  ExtractionManager.swift
//  NekoRAR
//
//  Created by Claude Code on 2025/11/22.
//

import Foundation

/// 解壓縮管理器 - 統一處理所有解壓縮操作
@MainActor
class ExtractionManager {

    // MARK: - Dependencies

    private let fileAccessManager: FileAccessManager
    private let archiveDetector: ArchiveDetector
    private let progressParser = ProcessOutputParser()
    private let errorAnalyzer = ExtractionErrorAnalyzer()

    // MARK: - State

    private var currentProcess: Process?
    private var isCancelled: Bool = false

    // MARK: - Initialization

    init(
        fileAccessManager: FileAccessManager = FileAccessManager(),
        archiveDetector: ArchiveDetector = ArchiveDetector()
    ) {
        self.fileAccessManager = fileAccessManager
        self.archiveDetector = archiveDetector
    }

    // MARK: - Public API

    /// 解壓縮單一檔案
    /// - Parameters:
    ///   - archive: 壓縮檔 URL
    ///   - destination: 目的地 URL
    ///   - password: 密碼（可選）
    ///   - options: 解壓縮選項
    ///   - progressHandler: 進度回調（進度值 0-1，當前檔案）
    /// - Returns: 解壓縮結果
    func extract(
        archive: URL,
        to destination: URL,
        password: String? = nil,
        options: ExtractionOptions = ExtractionOptions(),
        progressHandler: @escaping (Double, String?) -> Void
    ) async throws -> ExtractionResult {
        // 重置取消狀態
        isCancelled = false

        // 偵測壓縮檔類型
        guard let archiveType = archiveDetector.detectType(of: archive) else {
            throw ExtractionError.unsupportedFormat(extension: archive.pathExtension)
        }

        // 驗證壓縮檔
        try archiveDetector.validateArchive(archive)

        // 準備目的地
        try await prepareDestination(destination, for: archive, options: options)

        // 執行解壓縮
        let result = try await performExtraction(
            archive: archive,
            type: archiveType,
            destination: destination,
            password: password,
            options: options,
            progressHandler: progressHandler
        )

        return result
    }

    /// 批次解壓縮
    /// - Parameters:
    ///   - archives: 壓縮檔 URL 陣列
    ///   - destination: 目的地 URL
    ///   - password: 密碼（可選）
    ///   - options: 解壓縮選項
    ///   - progressHandler: 批次進度回調（已處理數量，總數量，當前進度）
    /// - Returns: 解壓縮結果陣列
    func extractBatch(
        archives: [URL],
        to destination: URL,
        password: String? = nil,
        options: ExtractionOptions = ExtractionOptions(),
        progressHandler: @escaping (Int, Int, Double) -> Void
    ) async throws -> [ExtractionResult] {
        var results: [ExtractionResult] = []
        let total = archives.count

        for (index, archive) in archives.enumerated() {
            // 檢查是否已取消
            if isCancelled {
                throw ExtractionError.cancelled
            }

            do {
                let result = try await extract(
                    archive: archive,
                    to: destination,
                    password: password,
                    options: options
                ) { progress, currentFile in
                    progressHandler(index, total, progress)
                }

                results.append(result)
            } catch {
                // 記錄錯誤但繼續處理其他檔案
                let errorResult = ExtractionResult(
                    success: false,
                    archiveURL: archive,
                    extractedFolder: nil,
                    fileCount: nil,
                    duration: 0,
                    error: error as? ExtractionError
                )
                results.append(errorResult)
            }

            // 更新進度
            progressHandler(index + 1, total, 1.0)

            // 批次處理間隔
            try? await Task.sleep(nanoseconds: UInt64(ExtractionConstants.batchProcessingDelay * 1_000_000_000))
        }

        return results
    }

    /// 取消當前操作
    func cancel() {
        isCancelled = true
        currentProcess?.terminate()
        currentProcess = nil
    }

    // MARK: - Private Implementation

    /// 執行解壓縮
    private func performExtraction(
        archive: URL,
        type: ArchiveType,
        destination: URL,
        password: String?,
        options: ExtractionOptions,
        progressHandler: @escaping (Double, String?) -> Void
    ) async throws -> ExtractionResult {
        let startTime = Date()

        do {
            // 根據類型選擇策略
            let strategy = createStrategy(for: type)

            // 執行解壓縮
            try await strategy.execute(
                archive: archive,
                destination: destination,
                password: password,
                options: options,
                progressHandler: progressHandler,
                processProvider: { [weak self] process in
                    self?.currentProcess = process
                },
                cancellationCheck: { [weak self] in
                    return self?.isCancelled ?? false
                }
            )

            let duration = Date().timeIntervalSince(startTime)

            return ExtractionResult(
                success: true,
                archiveURL: archive,
                extractedFolder: destination,
                fileCount: nil,
                duration: duration,
                error: nil
            )

        } catch {
            let duration = Date().timeIntervalSince(startTime)

            return ExtractionResult(
                success: false,
                archiveURL: archive,
                extractedFolder: nil,
                fileCount: nil,
                duration: duration,
                error: error as? ExtractionError
            )
        }
    }

    /// 準備目的地
    private func prepareDestination(
        _ destination: URL,
        for archive: URL,
        options: ExtractionOptions
    ) async throws {
        // 驗證目的地
        try fileAccessManager.prepareDestination(destination)

        // 檢查磁碟空間（如果知道檔案大小）
        if let attributes = try? FileManager.default.attributesOfItem(atPath: archive.path),
           let fileSize = attributes[.size] as? Int64 {
            // 預估解壓後大小為原始大小的 3 倍
            let estimatedSize = fileSize * 3

            let hasSpace = try fileAccessManager.checkDiskSpace(
                at: destination,
                requiredSpace: estimatedSize
            )

            if !hasSpace {
                let available = try? FileManager.default.attributesOfFileSystem(forPath: destination.path)[.systemFreeSize] as? Int64
                throw ExtractionError.insufficientSpace(
                    required: estimatedSize,
                    available: available
                )
            }
        }
    }

    /// 創建解壓縮策略
    private func createStrategy(for type: ArchiveType) -> ExtractionStrategy {
        switch type {
        case .rar:
            return UnrarStrategy(
                progressParser: progressParser,
                errorAnalyzer: errorAnalyzer
            )

        case .zip, .sevenZip:
            return SevenZipStrategy(
                progressParser: progressParser,
                errorAnalyzer: errorAnalyzer
            )

        case .tar, .tarGz, .tarBz2:
            return TarStrategy(
                archiveType: type,
                errorAnalyzer: errorAnalyzer
            )
        }
    }
}

// MARK: - ExtractionStrategy Protocol

/// 解壓縮策略協議
protocol ExtractionStrategy {
    func execute(
        archive: URL,
        destination: URL,
        password: String?,
        options: ExtractionOptions,
        progressHandler: @escaping (Double, String?) -> Void,
        processProvider: @escaping (Process) -> Void,
        cancellationCheck: @escaping () -> Bool
    ) async throws
}

// MARK: - Concrete Strategies

/// unar 策略（單一 RAR 檔案）
class UnarStrategy: ExtractionStrategy {
    private let progressParser: ProcessOutputParser
    private let errorAnalyzer: ExtractionErrorAnalyzer

    init(progressParser: ProcessOutputParser, errorAnalyzer: ExtractionErrorAnalyzer) {
        self.progressParser = progressParser
        self.errorAnalyzer = errorAnalyzer
    }

    func execute(
        archive: URL,
        destination: URL,
        password: String?,
        options: ExtractionOptions,
        progressHandler: @escaping (Double, String?) -> Void,
        processProvider: @escaping (Process) -> Void,
        cancellationCheck: @escaping () -> Bool
    ) async throws {
        guard let unarPath = Bundle.main.resourceURL?.appendingPathComponent(ExtractionConstants.BundleResource.unar) else {
            throw ExtractionError.toolNotFound(tool: "unar")
        }

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = unarPath

                var arguments = ["-q", "-o", destination.path, archive.path]
                arguments.append("-force-overwrite")

                // 添加密碼參數
                if let password = password, !password.isEmpty {
                    arguments.append("-p")
                    arguments.append(password)
                }

                process.arguments = arguments
                processProvider(process)

                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe

                var output = ""
                pipe.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    if !data.isEmpty, let chunk = String(data: data, encoding: .utf8) {
                        output += chunk

                        // 解析進度
                        if let progress = self.progressParser.parseProgress(from: chunk, tool: .unar) {
                            DispatchQueue.main.async {
                                progressHandler(progress, nil)
                            }
                        }

                        // 解析當前檔案
                        if let currentFile = self.progressParser.parseCurrentFile(from: chunk, tool: .unar) {
                            DispatchQueue.main.async {
                                let currentProgress = self.progressParser.parseProgress(from: chunk, tool: .unar) ?? 0
                                progressHandler(currentProgress, currentFile)
                            }
                        }
                    }
                }

                process.terminationHandler = { proc in
                    pipe.fileHandleForReading.readabilityHandler = nil
                    pipe.fileHandleForReading.closeFile()

                    // 檢查是否被取消
                    if cancellationCheck() {
                        continuation.resume(throwing: ExtractionError.cancelled)
                        return
                    }

                    // 檢查結果
                    if proc.terminationStatus == 0 {
                        DispatchQueue.main.async {
                            progressHandler(1.0, nil)
                        }
                        continuation.resume()
                    } else {
                        let error = self.errorAnalyzer.analyze(
                            exitCode: proc.terminationStatus,
                            output: output,
                            errorOutput: output,
                            archiveURL: archive,
                            destinationURL: destination
                        )
                        continuation.resume(throwing: error)
                    }
                }

                do {
                    try process.run()
                    DispatchQueue.main.async {
                        progressHandler(0.1, nil)
                    }
                } catch {
                    continuation.resume(throwing: ExtractionError.unknown(message: error.localizedDescription))
                }
            }
        }
    }
}

/// unrar 策略（多分片 RAR）
class UnrarStrategy: ExtractionStrategy {
    private let progressParser: ProcessOutputParser
    private let errorAnalyzer: ExtractionErrorAnalyzer

    init(progressParser: ProcessOutputParser, errorAnalyzer: ExtractionErrorAnalyzer) {
        self.progressParser = progressParser
        self.errorAnalyzer = errorAnalyzer
    }

    func execute(
        archive: URL,
        destination: URL,
        password: String?,
        options: ExtractionOptions,
        progressHandler: @escaping (Double, String?) -> Void,
        processProvider: @escaping (Process) -> Void,
        cancellationCheck: @escaping () -> Bool
    ) async throws {
        let toolName = ExtractionConstants.BundleResource.unrar
        guard let unrarPath = ExtractionConstants.toolURL(for: toolName) else {
            throw ExtractionError.toolNotFound(tool: toolName)
        }

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = unrarPath
                var arguments = ["x", "-y"]
                arguments.append(contentsOf: PasswordHandler.prepareUnrarPassword(password))
                arguments.append(contentsOf: [archive.path, "\(destination.path)/"])
                process.arguments = arguments
                process.currentDirectoryURL = archive.deletingLastPathComponent()

                // 使用預設環境
                process.environment = ExtractionConstants.defaultEnvironment

                processProvider(process)

                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe

                var output = ""
                stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    if !data.isEmpty, let chunk = String(data: data, encoding: .utf8) {
                        output += chunk

                        // 解析當前檔案
                        if let currentFile = self.progressParser.parseCurrentFile(from: chunk, tool: .unrar) {
                            DispatchQueue.main.async {
                                progressHandler(0.5, currentFile)
                            }
                        }
                    }
                }

                var errorOutput = ""
                stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    if !data.isEmpty, let chunk = String(data: data, encoding: .utf8) {
                        errorOutput += chunk
                    }
                }

                process.terminationHandler = { proc in
                    stdoutPipe.fileHandleForReading.readabilityHandler = nil
                    stderrPipe.fileHandleForReading.readabilityHandler = nil
                    stdoutPipe.fileHandleForReading.closeFile()
                    stderrPipe.fileHandleForReading.closeFile()

                    if cancellationCheck() {
                        continuation.resume(throwing: ExtractionError.cancelled)
                        return
                    }

                    if proc.terminationStatus == 0 {
                        DispatchQueue.main.async {
                            progressHandler(1.0, nil)
                        }
                        continuation.resume()
                    } else {
                        let error = self.errorAnalyzer.analyze(
                            exitCode: proc.terminationStatus,
                            output: output,
                            errorOutput: errorOutput,
                            archiveURL: archive,
                            destinationURL: destination
                        )
                        continuation.resume(throwing: error)
                    }
                }

                do {
                    try process.run()
                    DispatchQueue.main.async {
                        progressHandler(0.1, nil)
                    }
                } catch {
                    continuation.resume(throwing: ExtractionError.unknown(message: error.localizedDescription))
                }
            }
        }
    }
}

/// 7zz 策略（ZIP 和 7z）
class SevenZipStrategy: ExtractionStrategy {
    private let progressParser: ProcessOutputParser
    private let errorAnalyzer: ExtractionErrorAnalyzer

    init(progressParser: ProcessOutputParser, errorAnalyzer: ExtractionErrorAnalyzer) {
        self.progressParser = progressParser
        self.errorAnalyzer = errorAnalyzer
    }

    func execute(
        archive: URL,
        destination: URL,
        password: String?,
        options: ExtractionOptions,
        progressHandler: @escaping (Double, String?) -> Void,
        processProvider: @escaping (Process) -> Void,
        cancellationCheck: @escaping () -> Bool
    ) async throws {
        let toolName = ExtractionConstants.BundleResource.sevenZip
        guard let sevenZipPath = ExtractionConstants.toolURL(for: toolName) else {
            throw ExtractionError.toolNotFound(tool: toolName)
        }

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = sevenZipPath

                var arguments = ["x", "-y", archive.path, "-o\(destination.path)"]

                // 使用 stdin 傳遞密碼
                var passwordPipe: Pipe?
                if let password = password, !password.isEmpty {
                    arguments.insert("-p", at: 2)
                    passwordPipe = PasswordHandler.createPasswordPipe(for: process, password: password)
                }

                process.arguments = arguments
                processProvider(process)

                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe

                var output = ""
                pipe.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    if !data.isEmpty, let chunk = String(data: data, encoding: .utf8) {
                        output += chunk

                        // 解析進度
                        if let progress = self.progressParser.parseProgress(from: chunk, tool: .sevenZip) {
                            DispatchQueue.main.async {
                                progressHandler(progress, nil)
                            }
                        }

                        // 解析當前檔案
                        if let currentFile = self.progressParser.parseCurrentFile(from: chunk, tool: .sevenZip) {
                            DispatchQueue.main.async {
                                progressHandler(0, currentFile)
                            }
                        }
                    }
                }

                process.terminationHandler = { proc in
                    pipe.fileHandleForReading.readabilityHandler = nil
                    pipe.fileHandleForReading.closeFile()
                    PasswordHandler.cleanup(passwordPipe)

                    if cancellationCheck() {
                        continuation.resume(throwing: ExtractionError.cancelled)
                        return
                    }

                    if proc.terminationStatus == 0 {
                        DispatchQueue.main.async {
                            progressHandler(1.0, nil)
                        }
                        continuation.resume()
                    } else {
                        let error = self.errorAnalyzer.analyze(
                            exitCode: proc.terminationStatus,
                            output: output,
                            errorOutput: output,
                            archiveURL: archive,
                            destinationURL: destination
                        )
                        continuation.resume(throwing: error)
                    }
                }

                do {
                    try process.run()
                    DispatchQueue.main.async {
                        progressHandler(0.1, nil)
                    }
                } catch {
                    continuation.resume(throwing: ExtractionError.unknown(message: error.localizedDescription))
                }
            }
        }
    }
}

/// tar 策略（TAR, TAR.GZ, TAR.BZ2）
class TarStrategy: ExtractionStrategy {
    private let archiveType: ArchiveType
    private let errorAnalyzer: ExtractionErrorAnalyzer

    init(archiveType: ArchiveType, errorAnalyzer: ExtractionErrorAnalyzer) {
        self.archiveType = archiveType
        self.errorAnalyzer = errorAnalyzer
    }

    func execute(
        archive: URL,
        destination: URL,
        password: String?,
        options: ExtractionOptions,
        progressHandler: @escaping (Double, String?) -> Void,
        processProvider: @escaping (Process) -> Void,
        cancellationCheck: @escaping () -> Bool
    ) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: ExtractionConstants.systemTarPath)

                // 根據類型選擇參數
                var flags = "-x"
                switch self.archiveType {
                case .tarGz:
                    flags += "z"
                case .tarBz2:
                    flags += "j"
                default:
                    break
                }
                flags += "f"

                process.arguments = [flags, archive.path, "-C", destination.path]
                processProvider(process)

                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe

                // tar 沒有進度輸出，使用估算器
                let estimator = ProgressEstimator(estimatedDuration: 30.0)

                // 啟動進度更新計時器
                let progressTimer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
                progressTimer.schedule(deadline: .now(), repeating: .milliseconds(500))
                progressTimer.setEventHandler {
                    let progress = estimator.estimatedProgress()
                    DispatchQueue.main.async {
                        progressHandler(max(0.2, progress), nil)
                    }
                }
                progressTimer.resume()

                var output = ""
                pipe.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    if !data.isEmpty, let chunk = String(data: data, encoding: .utf8) {
                        output += chunk
                    }
                }

                process.terminationHandler = { proc in
                    progressTimer.cancel()
                    pipe.fileHandleForReading.readabilityHandler = nil
                    pipe.fileHandleForReading.closeFile()

                    if cancellationCheck() {
                        continuation.resume(throwing: ExtractionError.cancelled)
                        return
                    }

                    if proc.terminationStatus == 0 {
                        DispatchQueue.main.async {
                            progressHandler(1.0, nil)
                        }
                        continuation.resume()
                    } else {
                        let error = self.errorAnalyzer.analyze(
                            exitCode: proc.terminationStatus,
                            output: output,
                            errorOutput: output,
                            archiveURL: archive,
                            destinationURL: destination
                        )
                        continuation.resume(throwing: error)
                    }
                }

                do {
                    try process.run()
                    DispatchQueue.main.async {
                        progressHandler(0.1, nil)
                    }
                } catch {
                    progressTimer.cancel()
                    continuation.resume(throwing: ExtractionError.unknown(message: error.localizedDescription))
                }
            }
        }
    }
}
