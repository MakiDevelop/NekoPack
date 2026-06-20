//
//  ExtractionModels.swift
//  NekoRAR
//
//  Created by Claude Code on 2025/10/23.
//

import Foundation

// MARK: - 解壓縮選項

/// 解壓縮選項配置
struct ExtractionOptions {
    /// 是否建立子資料夾（以壓縮檔名稱命名）
    var createSubfolder: Bool = true

    /// 檔案覆蓋模式
    var overwriteMode: OverwriteMode = .ask

    /// 解壓後是否刪除原始壓縮檔
    var deleteSourceAfterExtraction: Bool = false

    /// 是否保留檔案權限和時間戳
    var preservePermissions: Bool = true

    /// 是否解壓到與壓縮檔相同的資料夾
    var extractToSameFolder: Bool = true

    /// 預設選項
    static let `default` = ExtractionOptions()
}

/// 檔案覆蓋模式
enum OverwriteMode: String, CaseIterable {
    /// 詢問用戶
    case ask = "ask"
    /// 直接覆蓋
    case overwrite = "overwrite"
    /// 跳過已存在的檔案
    case skip = "skip"
    /// 自動重新命名
    case rename = "rename"

    var localizedName: String {
        switch self {
        case .ask:
            return NSLocalizedString("overwrite_ask", comment: "")
        case .overwrite:
            return NSLocalizedString("overwrite_overwrite", comment: "")
        case .skip:
            return NSLocalizedString("overwrite_skip", comment: "")
        case .rename:
            return NSLocalizedString("overwrite_rename", comment: "")
        }
    }
}

// MARK: - 解壓縮任務

/// 解壓縮任務狀態
enum ExtractionTaskState {
    case pending        // 等待中
    case extracting     // 解壓縮中
    case completed      // 已完成
    case failed         // 失敗
    case cancelled      // 已取消
}

/// 解壓縮任務
class ExtractionTask: ObservableObject {
    /// 任務 ID
    let id: UUID

    /// 壓縮檔 URL
    let archiveURL: URL

    /// 目的地 URL
    let destinationURL: URL

    /// 密碼（可選）
    var password: String?

    /// 解壓縮選項
    var options: ExtractionOptions

    /// 任務狀態
    @Published var state: ExtractionTaskState = .pending

    /// 進度（0.0 - 1.0）
    @Published var progress: Double = 0.0

    /// 狀態訊息
    @Published var statusMessage: String = ""

    /// 當前處理的檔案名稱
    @Published var currentFileName: String?

    /// 已解壓縮的檔案數量
    @Published var extractedFileCount: Int = 0

    /// 總檔案數量（如果已知）
    @Published var totalFileCount: Int?

    /// 錯誤（如果失敗）
    var error: ExtractionError?

    /// 當前執行的 Process（用於取消）
    var currentProcess: Process?

    /// 是否已被取消
    private(set) var isCancelled: Bool = false

    init(
        archiveURL: URL,
        destinationURL: URL,
        password: String? = nil,
        options: ExtractionOptions = .default
    ) {
        self.id = UUID()
        self.archiveURL = archiveURL
        self.destinationURL = destinationURL
        self.password = password
        self.options = options
    }

    /// 取消解壓縮
    func cancel() {
        guard !isCancelled else { return }

        isCancelled = true
        state = .cancelled
        currentProcess?.terminate()

        print("🛑 取消解壓縮任務：\(archiveURL.lastPathComponent)")
    }

    /// 清理部分解壓縮的檔案
    func cleanupPartialExtraction() {
        guard isCancelled else { return }

        // 如果建立了子資料夾，嘗試刪除
        if options.createSubfolder {
            let folderName = archiveURL.deletingPathExtension().lastPathComponent
            let extractedFolder = destinationURL.appendingPathComponent(folderName)

            if FileManager.default.fileExists(atPath: extractedFolder.path) {
                do {
                    try FileManager.default.removeItem(at: extractedFolder)
                    print("🧹 已清理部分解壓縮：\(extractedFolder.path)")
                } catch {
                    print("⚠️ 清理失敗：\(error.localizedDescription)")
                }
            }
        }
    }
}

// MARK: - 解壓縮結果

/// 解壓縮結果
struct ExtractionResult {
    /// 是否成功
    let success: Bool

    /// 壓縮檔 URL
    let archiveURL: URL

    /// 解壓縮到的資料夾
    let extractedFolder: URL?

    /// 解壓縮的檔案數量
    let fileCount: Int?

    /// 耗時（秒）
    let duration: TimeInterval

    /// 錯誤（如果失敗）
    let error: ExtractionError?

    /// 成功結果
    static func success(
        archiveURL: URL,
        extractedFolder: URL,
        fileCount: Int,
        duration: TimeInterval
    ) -> ExtractionResult {
        ExtractionResult(
            success: true,
            archiveURL: archiveURL,
            extractedFolder: extractedFolder,
            fileCount: fileCount,
            duration: duration,
            error: nil
        )
    }

    /// 失敗結果
    static func failure(
        archiveURL: URL,
        error: ExtractionError,
        duration: TimeInterval
    ) -> ExtractionResult {
        ExtractionResult(
            success: false,
            archiveURL: archiveURL,
            extractedFolder: nil,
            fileCount: nil,
            duration: duration,
            error: error
        )
    }

    /// 取消結果
    static func cancelled(
        archiveURL: URL,
        duration: TimeInterval
    ) -> ExtractionResult {
        ExtractionResult(
            success: false,
            archiveURL: archiveURL,
            extractedFolder: nil,
            fileCount: nil,
            duration: duration,
            error: .cancelled
        )
    }
}
