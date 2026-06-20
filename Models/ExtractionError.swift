//
//  ExtractionError.swift
//  NekoRAR
//
//  Created by Claude Code on 2025/10/23.
//

import Foundation

/// 解壓縮過程中可能發生的錯誤類型
enum ExtractionError: LocalizedError {
    case destinationNotAccessible(path: String)
    case archiveNotFound(path: String)
    case archiveCorrupted(details: String)
    case passwordRequired
    case passwordIncorrect
    case insufficientSpace(required: Int64?, available: Int64?)
    case permissionDenied(path: String)
    case unsupportedFormat(extension: String)
    case multipartIncomplete(missingParts: [Int])
    case toolNotFound(tool: String)
    case extractionFailed(exitCode: Int32, output: String)
    case cancelled
    case unknown(message: String)

    /// 錯誤描述（本地化）
    var errorDescription: String? {
        switch self {
        case .destinationNotAccessible(let path):
            return String(format: NSLocalizedString("error_destination_not_accessible", comment: ""),
                         path)

        case .archiveNotFound(let path):
            return String(format: NSLocalizedString("error_archive_not_found", comment: ""),
                         path)

        case .archiveCorrupted:
            return NSLocalizedString("error_archive_corrupted", comment: "")

        case .passwordRequired:
            return NSLocalizedString("error_password_required", comment: "")

        case .passwordIncorrect:
            return NSLocalizedString("error_password_incorrect", comment: "")

        case .insufficientSpace(let required, let available):
            if let req = required, let avail = available {
                return String(format: NSLocalizedString("error_insufficient_space_detailed", comment: ""),
                            formatBytes(req), formatBytes(avail))
            } else {
                return NSLocalizedString("error_insufficient_space", comment: "")
            }

        case .permissionDenied(let path):
            return String(format: NSLocalizedString("error_permission_denied", comment: ""),
                         path)

        case .unsupportedFormat(let ext):
            return String(format: NSLocalizedString("error_unsupported_format", comment: ""),
                         ext)

        case .multipartIncomplete(let missingParts):
            let partsList = missingParts.map { String($0) }.joined(separator: ", ")
            return String(format: NSLocalizedString("error_multipart_incomplete", comment: ""),
                         partsList)

        case .toolNotFound(let tool):
            return String(format: NSLocalizedString("error_tool_not_found", comment: ""),
                         tool)

        case .extractionFailed(let exitCode, _):
            return String(format: NSLocalizedString("error_extraction_failed", comment: ""),
                         exitCode)

        case .cancelled:
            return NSLocalizedString("error_cancelled", comment: "")

        case .unknown(let message):
            return String(format: NSLocalizedString("error_unknown", comment: ""),
                         message)
        }
    }

    /// 恢復建議（本地化）
    var recoverySuggestion: String? {
        switch self {
        case .destinationNotAccessible:
            return NSLocalizedString("suggestion_destination_not_accessible", comment: "")

        case .archiveNotFound:
            return NSLocalizedString("suggestion_archive_not_found", comment: "")

        case .archiveCorrupted:
            return NSLocalizedString("suggestion_archive_corrupted", comment: "")

        case .passwordRequired, .passwordIncorrect:
            return NSLocalizedString("suggestion_password_incorrect", comment: "")

        case .insufficientSpace:
            return NSLocalizedString("suggestion_insufficient_space", comment: "")

        case .permissionDenied:
            return NSLocalizedString("suggestion_permission_denied", comment: "")

        case .unsupportedFormat:
            return NSLocalizedString("suggestion_unsupported_format", comment: "")

        case .multipartIncomplete:
            return NSLocalizedString("suggestion_multipart_incomplete", comment: "")

        case .toolNotFound:
            return NSLocalizedString("suggestion_tool_not_found", comment: "")

        case .extractionFailed:
            return NSLocalizedString("suggestion_extraction_failed", comment: "")

        case .cancelled:
            return nil

        case .unknown:
            return NSLocalizedString("suggestion_unknown", comment: "")
        }
    }

    /// 格式化位元組大小為可讀字串
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    /// 完整的錯誤訊息（包含描述和建議）
    var fullMessage: String {
        var message = errorDescription ?? NSLocalizedString("error_unknown_generic", comment: "")

        if let suggestion = recoverySuggestion {
            message += "\n\n💡 " + suggestion
        }

        return message
    }
}

/// 錯誤分析器 - 根據退出碼和輸出判斷錯誤類型
class ExtractionErrorAnalyzer {

    /// 分析解壓縮失敗的原因
    /// - Parameters:
    ///   - exitCode: 程序退出碼
    ///   - output: 標準輸出內容
    ///   - errorOutput: 錯誤輸出內容
    ///   - archiveURL: 壓縮檔 URL
    ///   - destinationURL: 目的地 URL
    /// - Returns: 具體的錯誤類型
    func analyze(
        exitCode: Int32,
        output: String,
        errorOutput: String,
        archiveURL: URL,
        destinationURL: URL
    ) -> ExtractionError {

        // 合併輸出用於關鍵字搜尋
        let combinedOutput = (output + "\n" + errorOutput).lowercased()

        // 1. 根據退出碼判斷（不同工具的退出碼意義不同）
        switch exitCode {
        case 0:
            // 成功，不應該呼叫此方法
            return .unknown(message: "Exit code 0 but treated as error")

        case 1:
            // 一般錯誤，需進一步分析
            break

        case 2:
            // 通常表示密碼錯誤或需要密碼
            if containsPasswordKeywords(combinedOutput) {
                return determinePasswordError(from: combinedOutput)
            }

        case 3:
            // 通常表示檔案損毀
            return .archiveCorrupted(details: errorOutput)

        case 4:
            // 通常表示磁碟空間不足
            return .insufficientSpace(required: nil, available: nil)

        default:
            break
        }

        // 2. 檢查密碼相關錯誤（多語言關鍵字）
        if containsPasswordKeywords(combinedOutput) {
            return determinePasswordError(from: combinedOutput)
        }

        // 3. 檢查檔案損毀（多語言關鍵字）
        if containsCorruptionKeywords(combinedOutput) {
            return .archiveCorrupted(details: errorOutput)
        }

        // 4. 檢查權限問題
        if containsPermissionKeywords(combinedOutput) {
            return .permissionDenied(path: destinationURL.path)
        }

        // 5. 檢查磁碟空間
        if containsSpaceKeywords(combinedOutput) {
            if let available = getAvailableSpace(at: destinationURL) {
                return .insufficientSpace(required: nil, available: available)
            }
            return .insufficientSpace(required: nil, available: nil)
        }

        // 6. 檢查檔案不存在
        if !FileManager.default.fileExists(atPath: archiveURL.path) {
            return .archiveNotFound(path: archiveURL.path)
        }

        // 7. 檢查目的地不可訪問
        if !FileManager.default.fileExists(atPath: destinationURL.path) {
            return .destinationNotAccessible(path: destinationURL.path)
        }

        // 8. 預設：一般解壓縮失敗
        return .extractionFailed(exitCode: exitCode, output: errorOutput)
    }

    // MARK: - 關鍵字檢測方法

    /// 檢查是否包含密碼相關關鍵字（多語言）
    private func containsPasswordKeywords(_ text: String) -> Bool {
        let keywords = [
            "password", "passwd", "pwd",           // 英文
            "密碼", "密码",                         // 中文
            "パスワード",                           // 日文
            "encrypted", "암호"                     // 其他
        ]
        return keywords.contains { text.contains($0) }
    }

    /// 判斷是需要密碼還是密碼錯誤
    private func determinePasswordError(from text: String) -> ExtractionError {
        let incorrectKeywords = [
            "wrong", "incorrect", "invalid",
            "錯誤", "错误", "不正確", "不正确",
            "間違", "失敗"
        ]

        if incorrectKeywords.contains(where: { text.contains($0) }) {
            return .passwordIncorrect
        }

        return .passwordRequired
    }

    /// 檢查檔案損毀關鍵字
    private func containsCorruptionKeywords(_ text: String) -> Bool {
        let keywords = [
            "corrupt", "damaged", "broken",
            "checksum", "crc", "crc32",
            "損毀", "损坏", "破損", "破损",
            "壊れ", "エラー"
        ]
        return keywords.contains { text.contains($0) }
    }

    /// 檢查權限問題關鍵字
    private func containsPermissionKeywords(_ text: String) -> Bool {
        let keywords = [
            "permission", "denied", "access",
            "権限", "拒否", "アクセス",
            "權限", "拒絕", "访问"
        ]
        return keywords.contains { text.contains($0) }
    }

    /// 檢查磁碟空間關鍵字
    private func containsSpaceKeywords(_ text: String) -> Bool {
        let keywords = [
            "space", "disk full", "no space",
            "容量", "空間不足", "空间不足",
            "ディスク", "容量不足"
        ]
        return keywords.contains { text.contains($0) }
    }

    // MARK: - 輔助方法

    /// 取得可用磁碟空間
    private func getAvailableSpace(at url: URL) -> Int64? {
        do {
            let values = try url.resourceValues(forKeys: [.volumeAvailableCapacityKey])
            return values.volumeAvailableCapacity.map { Int64($0) }
        } catch {
            return nil
        }
    }
}
