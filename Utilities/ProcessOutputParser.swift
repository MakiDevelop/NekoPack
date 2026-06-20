//
//  ProcessOutputParser.swift
//  NekoRAR
//
//  Created by Claude Code on 2025/10/23.
//

import Foundation

/// 解壓縮工具類型
enum ExtractionTool {
    case unar
    case unrar
    case sevenZip
    case tar
}

/// Process 輸出解析器 - 從輸出中提取進度資訊
class ProcessOutputParser {

    /// 從輸出中解析進度
    /// - Parameters:
    ///   - output: 工具的輸出文字
    ///   - tool: 使用的工具類型
    /// - Returns: 進度值（0.0 - 1.0），如果無法解析則返回 nil
    func parseProgress(from output: String, tool: ExtractionTool) -> Double? {
        switch tool {
        case .unar:
            return parseUnarProgress(output)
        case .unrar:
            return parseUnrarProgress(output)
        case .sevenZip:
            return parse7zProgress(output)
        case .tar:
            return nil  // tar 沒有進度輸出
        }
    }

    /// 從輸出中解析當前處理的檔案名稱
    /// - Parameters:
    ///   - output: 工具的輸出文字
    ///   - tool: 使用的工具類型
    /// - Returns: 檔案名稱，如果無法解析則返回 nil
    func parseCurrentFile(from output: String, tool: ExtractionTool) -> String? {
        switch tool {
        case .unar:
            return parseUnarCurrentFile(output)
        case .unrar:
            return parseUnrarCurrentFile(output)
        case .sevenZip:
            return parse7zCurrentFile(output)
        case .tar:
            return nil
        }
    }

    /// 從輸出中解析總檔案數量
    /// - Parameters:
    ///   - output: 工具的輸出文字
    ///   - tool: 使用的工具類型
    /// - Returns: 總檔案數量，如果無法解析則返回 nil
    func parseTotalFileCount(from output: String, tool: ExtractionTool) -> Int? {
        switch tool {
        case .unar:
            return parseUnarTotalFiles(output)
        case .sevenZip:
            return parse7zTotalFiles(output)
        default:
            return nil
        }
    }

    // MARK: - unar 解析

    /// 解析 unar 的進度
    /// unar 輸出格式：  movie.mkv  (50.2%)... OK.
    private func parseUnarProgress(_ output: String) -> Double? {
        // 尋找最後一個百分比
        let pattern = #"(\d+\.?\d*)%"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.matches(in: output, options: [], range: NSRange(output.startIndex..., in: output)).last,
              let range = Range(match.range(at: 1), in: output) else {
            return nil
        }

        let percentString = String(output[range])
        return Double(percentString).map { $0 / 100.0 }
    }

    /// 解析 unar 當前處理的檔案
    /// 格式：  movie.mkv  (50.2%)... 或   movie.mkv... OK.
    private func parseUnarCurrentFile(_ output: String) -> String? {
        let lines = output.split(separator: "\n")
        guard let lastLine = lines.last(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) else {
            return nil
        }

        // 提取檔案名稱（在百分比或 "..." 之前）
        let pattern = #"^\s*(.+?)\s+\(.*%\)|^\s*(.+?)\.\.\."#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(in: String(lastLine), options: [], range: NSRange(lastLine.startIndex..., in: lastLine)) else {
            return nil
        }

        // 嘗試第一個捕獲組（帶百分比）或第二個（不帶百分比）
        for i in 1...2 {
            if let range = Range(match.range(at: i), in: lastLine), !range.isEmpty {
                return String(lastLine[range]).trimmingCharacters(in: .whitespaces)
            }
        }

        return nil
    }

    /// 解析 unar 總檔案數量
    /// 不太可靠，unar 不一定會輸出
    private func parseUnarTotalFiles(_ output: String) -> Int? {
        // unar 通常不會顯示總數，只能從完成訊息推測
        return nil
    }

    // MARK: - unrar 解析

    /// 解析 unrar 的進度
    /// unrar 輸出格式：Extracting from archive.rar
    /// 沒有百分比，只能根據檔案數量估算
    private func parseUnrarProgress(_ output: String) -> Double? {
        // unrar 沒有進度百分比
        // 可以嘗試計算「Extracting」出現次數 vs 總數
        return nil
    }

    /// 解析 unrar 當前處理的檔案
    /// 格式：Extracting  movie.mkv        OK
    private func parseUnrarCurrentFile(_ output: String) -> String? {
        let pattern = #"Extracting\s+(.+?)\s+(OK|\.\.\.)"#
        let lines = output.split(separator: "\n")

        guard let lastLine = lines.last(where: { $0.contains("Extracting") }),
              let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(in: String(lastLine), options: [], range: NSRange(lastLine.startIndex..., in: lastLine)),
              let range = Range(match.range(at: 1), in: lastLine) else {
            return nil
        }

        return String(lastLine[range]).trimmingCharacters(in: .whitespaces)
    }

    // MARK: - 7za 解析

    /// 解析 7za 的進度
    /// 7za 輸出格式：  50% - movie.mkv
    private func parse7zProgress(_ output: String) -> Double? {
        let pattern = #"(\d+)%"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.matches(in: output, options: [], range: NSRange(output.startIndex..., in: output)).last,
              let range = Range(match.range(at: 1), in: output) else {
            return nil
        }

        let percentString = String(output[range])
        return Double(percentString).map { $0 / 100.0 }
    }

    /// 解析 7za 當前處理的檔案
    /// 格式：  50% - movie.mkv 或 - movie.mkv
    private func parse7zCurrentFile(_ output: String) -> String? {
        let lines = output.split(separator: "\n")
        guard let lastLine = lines.last(where: { $0.contains("-") && !$0.contains("Archive:") }) else {
            return nil
        }

        // 提取 " - " 後面的檔案名稱
        let components = lastLine.split(separator: "-", maxSplits: 1)
        guard components.count == 2 else {
            return nil
        }

        return String(components[1]).trimmingCharacters(in: .whitespaces)
    }

    /// 解析 7za 總檔案數量
    /// 7za 在開始時會顯示：Scanning the drive for archives:
    /// 然後列出檔案
    private func parse7zTotalFiles(_ output: String) -> Int? {
        // 計算有多少行包含 " - " 且不是 Archive 行
        let lines = output.split(separator: "\n")
        let fileLines = lines.filter { $0.contains("-") && !$0.contains("Archive:") }
        return fileLines.isEmpty ? nil : fileLines.count
    }
}

/// 進度追蹤助手 - 用於估算沒有真實進度的工具
class ProgressEstimator {
    private var startTime: Date
    private var lastUpdateTime: Date
    private var estimatedDuration: TimeInterval

    /// 檔案大小（位元組）
    private var fileSize: Int64?

    init(fileSize: Int64? = nil, estimatedDuration: TimeInterval = 60.0) {
        self.startTime = Date()
        self.lastUpdateTime = Date()
        self.fileSize = fileSize
        self.estimatedDuration = estimatedDuration
    }

    /// 取得估算的進度（基於時間）
    func estimatedProgress() -> Double {
        let elapsed = Date().timeIntervalSince(startTime)

        // 使用 sigmoid 函數讓進度更平滑
        // 永遠不會達到 100%，最多到 95%
        let rawProgress = elapsed / estimatedDuration
        let sigmoid = 1.0 / (1.0 + exp(-5.0 * (rawProgress - 0.5)))
        return min(sigmoid * 0.95, 0.95)
    }

    /// 更新估算時間（根據實際進度）
    func updateEstimate(actualProgress: Double) {
        guard actualProgress > 0 else { return }

        let elapsed = Date().timeIntervalSince(startTime)
        estimatedDuration = elapsed / actualProgress

        lastUpdateTime = Date()
    }

    /// 重置計時器
    func reset() {
        startTime = Date()
        lastUpdateTime = Date()
    }
}
