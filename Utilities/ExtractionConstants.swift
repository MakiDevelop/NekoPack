//
//  ExtractionConstants.swift
//  NekoRAR
//
//  Created by Claude Code on 2025/11/22.
//

import Foundation

/// 解壓縮相關常數
enum ExtractionConstants {
    // MARK: - 正規表達式模式

    /// 多分片 RAR 檔案模式（例如：.part01.rar, .part001.rar）
    static let multipartRARPattern = #"\.part0*[1-9]\d*\.rar$"#

    /// 分片編號模式
    static let partNumberPattern = #"(?i)\.part0*\d+\.rar$"#

    /// 分片編號提取模式
    static let partExtractPattern = #"(?i)part(\d+)\.rar"#

    // MARK: - 進度值

    /// 開始解壓縮
    static let progressStart: Double = 0.1

    /// 驗證完成
    static let progressValidated: Double = 0.2

    /// 找到工具
    static let progressToolFound: Double = 0.3

    /// 程序已啟動
    static let progressProcessStarted: Double = 0.4

    /// 中途進度
    static let progressMidway: Double = 0.5

    /// 接近完成
    static let progressNearComplete: Double = 0.9

    /// 完成
    static let progressComplete: Double = 1.0

    /// 失敗
    static let progressFailed: Double = 0.0

    // MARK: - 支援的壓縮格式

    /// 支援的壓縮檔副檔名
    static let supportedArchiveExtensions = ["rar", "zip", "7z", "tar", "gz", "bz2", "tgz", "tbz"]

    /// 支援的複合副檔名
    static let compoundExtensions = ["tar.gz", "tar.bz2"]

    // MARK: - 延遲時間

    /// 批次處理間隔（秒）
    static let batchProcessingDelay: TimeInterval = 0.1

    /// 進度更新間隔（毫秒）
    static let progressUpdateInterval: Int = 500

    // MARK: - 檔案大小限制

    /// 最小檔案大小（位元組）
    static let minimumFileSize: Int64 = 1

    /// 輸出緩衝區大小限制（位元組）
    static let outputBufferLimit: Int = 1_048_576 // 1MB

    // MARK: - 超時設定

    /// 預設解壓縮超時（秒）
    static let defaultTimeout: TimeInterval = 3600 // 1 小時

    /// 小檔案超時（秒）
    static let smallFileTimeout: TimeInterval = 300 // 5 分鐘

    /// 大檔案超時（秒）
    static let largeFileTimeout: TimeInterval = 7200 // 2 小時

    // MARK: - 工具路徑

    /// 系統 tar 工具路徑
    static let systemTarPath = "/usr/bin/tar"

    /// Bundle 資源名稱
    enum BundleResource {
        static let toolsDirectory = "Tools"
        static let sevenZip = "7zz"
        static let unar = "unar"
        static let unrar = "unrar"
    }

    // MARK: - 環境變數

    /// 預設環境變數
    static let defaultEnvironment: [String: String] = [
        "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
        "LANG": "en_US.UTF-8",
        "LC_ALL": "en_US.UTF-8"
    ]

    /// unrar 密碼環境變數名稱
    static let unrarPasswordEnvVar = "UNRAR_PASSWORD"

    /// 取得內建解壓縮工具的路徑（位於 Resources/Tools）
    /// - Parameter toolName: 工具檔名（如 7zz、unrar）
    /// - Returns: 工具的檔案 URL（若不存在則為 nil）
    static func toolURL(for toolName: String) -> URL? {
        var candidates: [URL] = []

        if let url = Bundle.main.url(
            forResource: toolName,
            withExtension: nil,
            subdirectory: BundleResource.toolsDirectory
        ) {
            candidates.append(url)
        }

        if let resourceRoot = Bundle.main.resourceURL {
            candidates.append(
                resourceRoot
                    .appendingPathComponent(BundleResource.toolsDirectory)
                    .appendingPathComponent(toolName)
            )
        }

        // 直接拼出 Contents/Resources/Tools 以防 bundle 路徑解析異常
        candidates.append(
            Bundle.main.bundleURL
                .appendingPathComponent("Contents/Resources")
                .appendingPathComponent(BundleResource.toolsDirectory)
                .appendingPathComponent(toolName)
        )

        // 去重並尋找第一個存在的路徑
        let uniqueCandidates = Array(NSOrderedSet(array: candidates).compactMap { $0 as? URL })
        for url in uniqueCandidates where FileManager.default.fileExists(atPath: url.path) {
            return url
        }

        // Debug：輸出所有嘗試過的路徑，方便定位
        if !uniqueCandidates.isEmpty {
            let paths = uniqueCandidates.map { $0.path }.joined(separator: ", ")
            print("⚠️ 無法找到工具 \(toolName)，檢查過的路徑：\(paths)")
        }
        return nil
    }

    // MARK: - UserDefaults Keys

    /// Bookmark 儲存 key
    static let lastDestinationBookmarkKey = "lastDestinationBookmark"

    /// 上次目的地路徑 key
    static let lastDestinationPathKey = "lastDestinationPath"

    /// 啟動檔案路徑 key
    static let launchFilePathKey = "launchFilePath"

    /// 外觀模式 key
    static let selectedAppearanceKey = "selectedAppearance"

    // MARK: - 輔助方法

    /// 判斷檔案是否為支援的壓縮檔
    /// - Parameter url: 檔案 URL
    /// - Returns: 是否為支援的格式
    static func isSupportedArchive(_ url: URL) -> Bool {
        let fileName = url.lastPathComponent.lowercased()

        // 檢查複合副檔名
        for compound in compoundExtensions {
            if fileName.hasSuffix(compound) {
                return true
            }
        }

        // 檢查單一副檔名
        let ext = url.pathExtension.lowercased()
        return supportedArchiveExtensions.contains(ext)
    }

    /// 判斷是否為多分片 RAR 檔案
    /// - Parameter url: 檔案 URL
    /// - Returns: 是否為多分片
    static func isMultipartRAR(_ url: URL) -> Bool {
        let fileName = url.lastPathComponent.lowercased()
        return fileName.range(of: multipartRARPattern, options: .regularExpression) != nil
    }

    /// 從檔名提取分片編號
    /// - Parameter url: 檔案 URL
    /// - Returns: 分片編號，如果不是分片檔案則返回 nil
    static func extractPartNumber(from url: URL) -> Int? {
        let fileName = url.lastPathComponent

        guard let regex = try? NSRegularExpression(pattern: partExtractPattern, options: []),
              let match = regex.firstMatch(in: fileName, options: [], range: NSRange(fileName.startIndex..., in: fileName)),
              let range = Range(match.range(at: 1), in: fileName) else {
            return nil
        }

        let numberString = String(fileName[range])
        return Int(numberString)
    }

    /// 根據檔案大小決定超時時間
    /// - Parameter fileSize: 檔案大小（位元組）
    /// - Returns: 超時時間（秒）
    static func timeout(for fileSize: Int64) -> TimeInterval {
        let megabytes = Double(fileSize) / 1_048_576.0

        if megabytes < 10 {
            return smallFileTimeout
        } else if megabytes < 1000 {
            return defaultTimeout
        } else {
            return largeFileTimeout
        }
    }
}
