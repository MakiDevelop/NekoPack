//
//  ArchiveDetector.swift
//  NekoRAR
//
//  Created by Claude Code on 2025/11/22.
//

import Foundation

/// 壓縮檔偵測器
class ArchiveDetector {

    // MARK: - Public Methods

    /// 偵測壓縮檔類型
    /// - Parameter url: 壓縮檔 URL
    /// - Returns: 偵測到的類型，如果無法識別則返回 nil
    func detectType(of url: URL) -> ArchiveType? {
        guard var type = ArchiveType.detect(from: url) else {
            return nil
        }

        // 如果是 RAR，檢查是否為多分片
        if case .rar = type {
            let isMultipart = self.isMultipart(url)
            type = .rar(isMultipart: isMultipart)
        }

        return type
    }

    /// 判斷是否為多分片檔案
    /// - Parameter url: 壓縮檔 URL
    /// - Returns: 是否為多分片
    func isMultipart(_ url: URL) -> Bool {
        return ExtractionConstants.isMultipartRAR(url)
    }

    /// 找出所有相關的分片檔案
    /// - Parameter url: 任一分片檔案的 URL
    /// - Returns: 所有分片檔案的 URL 陣列（已排序）
    func findAllParts(of url: URL) -> [URL] {
        // 只處理 RAR 多分片檔案
        guard ExtractionConstants.isMultipartRAR(url) else {
            return [url]
        }

        let folder = url.deletingLastPathComponent()
        let fileName = url.lastPathComponent.lowercased()

        // 提取基礎檔名（移除 .partXX.rar）
        let basePrefix = fileName.replacingOccurrences(
            of: ExtractionConstants.partNumberPattern,
            with: "",
            options: .regularExpression
        )

        do {
            // 掃描資料夾中所有相關分片
            let files = try FileManager.default.contentsOfDirectory(atPath: folder.path)
                .filter { file in
                    let lowerFile = file.lowercased()
                    return lowerFile.hasPrefix(basePrefix) && lowerFile.hasSuffix(".rar")
                }
                .sorted()
                .map { folder.appendingPathComponent($0) }

            return files
        } catch {
            print("⚠️ 無法掃描分片檔案：\(error)")
            return [url]
        }
    }

    /// 驗證壓縮檔
    /// - Parameter url: 壓縮檔 URL
    /// - Throws: ExtractionError 如果驗證失敗
    func validateArchive(_ url: URL) throws {
        // 1. 檢查檔案是否存在
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ExtractionError.archiveNotFound(path: url.path)
        }

        // 2. 檢查是否為支援的格式
        guard detectType(of: url) != nil else {
            throw ExtractionError.unsupportedFormat(extension: url.pathExtension)
        }

        // 3. 檢查檔案大小
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            if let fileSize = attributes[.size] as? Int64 {
                guard fileSize >= ExtractionConstants.minimumFileSize else {
                    throw ExtractionError.archiveCorrupted(details: "檔案大小為 0")
                }
            }
        } catch let error as ExtractionError {
            throw error
        } catch {
            throw ExtractionError.unknown(message: "無法讀取檔案屬性：\(error.localizedDescription)")
        }

        // 4. 如果是多分片，檢查所有分片是否存在
        if isMultipart(url) {
            try validateMultipartArchive(url)
        }
    }

    /// 驗證多分片壓縮檔
    /// - Parameter url: 任一分片檔案的 URL
    /// - Throws: ExtractionError 如果驗證失敗
    func validateMultipartArchive(_ url: URL) throws {
        let allParts = findAllParts(of: url)

        // 提取所有分片編號
        let partNumbers = allParts.compactMap { fileURL in
            ExtractionConstants.extractPartNumber(from: fileURL)
        }

        // 檢查是否包含第一片
        guard partNumbers.contains(1) else {
            throw ExtractionError.multipartIncomplete(missingParts: [1])
        }

        // 檢查分片是否連續
        let missingParts = findMissingParts(in: partNumbers)
        if !missingParts.isEmpty {
            throw ExtractionError.multipartIncomplete(missingParts: missingParts)
        }
    }

    /// 取得第一片的 URL
    /// - Parameter url: 任一分片檔案的 URL
    /// - Returns: 第一片的 URL，如果不是多分片則返回原 URL
    func getFirstPart(of url: URL) -> URL {
        guard isMultipart(url) else {
            return url
        }

        let allParts = findAllParts(of: url)

        // 找到 part1, part01, 或 part001
        let firstPart = allParts.first { partURL in
            let fileName = partURL.lastPathComponent.lowercased()
            return fileName.contains("part1.rar") ||
                   fileName.contains("part01.rar") ||
                   fileName.contains("part001.rar")
        }

        return firstPart ?? url
    }

    /// 判斷檔案是否為第一片
    /// - Parameter url: 壓縮檔 URL
    /// - Returns: 是否為第一片（或非多分片檔案）
    func isFirstPart(_ url: URL) -> Bool {
        guard isMultipart(url) else {
            return true
        }

        let partNumber = ExtractionConstants.extractPartNumber(from: url)
        return partNumber == 1
    }

    // MARK: - Private Helpers

    /// 找出缺失的分片編號
    /// - Parameter partNumbers: 已存在的分片編號陣列
    /// - Returns: 缺失的分片編號陣列
    private func findMissingParts(in partNumbers: [Int]) -> [Int] {
        guard !partNumbers.isEmpty else { return [] }

        let sorted = partNumbers.sorted()
        let maxPart = sorted.last ?? 0

        var missing: [Int] = []
        for i in 1...maxPart {
            if !sorted.contains(i) {
                missing.append(i)
            }
        }

        return missing
    }

    /// 掃描資料夾中的所有壓縮檔
    /// - Parameters:
    ///   - folderURL: 資料夾 URL
    ///   - skipNonFirstParts: 是否跳過多分片檔案的非第一片
    /// - Returns: 壓縮檔 URL 陣列
    func scanArchives(in folderURL: URL, skipNonFirstParts: Bool = true) -> [URL] {
        do {
            let files = try FileManager.default.contentsOfDirectory(atPath: folderURL.path)

            var archives: [URL] = []

            for file in files {
                let fileURL = folderURL.appendingPathComponent(file)

                // 檢查是否為支援的格式
                guard ExtractionConstants.isSupportedArchive(fileURL) else {
                    continue
                }

                // 如果需要跳過非第一片
                if skipNonFirstParts && isMultipart(fileURL) && !isFirstPart(fileURL) {
                    continue
                }

                archives.append(fileURL)
            }

            return archives.sorted { $0.lastPathComponent < $1.lastPathComponent }
        } catch {
            print("⚠️ 無法掃描資料夾：\(error)")
            return []
        }
    }

    /// 取得壓縮檔的資訊
    /// - Parameter url: 壓縮檔 URL
    /// - Returns: 壓縮檔資訊
    func getArchiveInfo(_ url: URL) -> ArchiveInfo? {
        guard let type = detectType(of: url) else {
            return nil
        }

        var fileSize: Int64 = 0
        if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
           let size = attributes[.size] as? Int64 {
            fileSize = size
        }

        let isMultipart = self.isMultipart(url)
        let allParts = isMultipart ? findAllParts(of: url) : [url]

        return ArchiveInfo(
            url: url,
            type: type,
            fileSize: fileSize,
            isMultipart: isMultipart,
            allParts: allParts
        )
    }
}

// MARK: - ArchiveInfo

/// 壓縮檔資訊
struct ArchiveInfo {
    let url: URL
    let type: ArchiveType
    let fileSize: Int64
    let isMultipart: Bool
    let allParts: [URL]

    var fileName: String {
        url.lastPathComponent
    }

    var totalParts: Int {
        allParts.count
    }

    var totalSize: Int64 {
        allParts.reduce(0) { total, partURL in
            if let attributes = try? FileManager.default.attributesOfItem(atPath: partURL.path),
               let size = attributes[.size] as? Int64 {
                return total + size
            }
            return total
        }
    }

    var description: String {
        if isMultipart {
            return "\(fileName) (\(type.description), \(totalParts) 片, \(formatBytes(totalSize)))"
        } else {
            return "\(fileName) (\(type.description), \(formatBytes(fileSize)))"
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
