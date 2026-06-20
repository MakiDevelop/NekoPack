//
//  ArchiveType.swift
//  NekoRAR
//
//  Created by Claude Code on 2025/11/22.
//

import Foundation

/// 壓縮檔類型枚舉
enum ArchiveType: Equatable {
    case rar(isMultipart: Bool)
    case zip
    case sevenZip
    case tar
    case tarGz
    case tarBz2

    /// 工具名稱
    var toolName: String {
        switch self {
        case .rar(let isMultipart):
            return isMultipart ? "unrar" : "unrar"
        case .zip, .sevenZip:
            return "7zz"
        case .tar, .tarGz, .tarBz2:
            return "tar"
        }
    }

    /// 對應的解壓縮工具類型
    var extractionTool: ExtractionTool {
        switch self {
        case .rar(let isMultipart):
            return isMultipart ? .unrar : .unrar
        case .zip, .sevenZip:
            return .sevenZip
        case .tar, .tarGz, .tarBz2:
            return .tar
        }
    }

    /// 支援的副檔名
    var supportedExtensions: [String] {
        switch self {
        case .rar:
            return ["rar"]
        case .zip:
            return ["zip"]
        case .sevenZip:
            return ["7z"]
        case .tar:
            return ["tar"]
        case .tarGz:
            return ["tar.gz", "tgz"]
        case .tarBz2:
            return ["tar.bz2", "tbz"]
        }
    }

    /// 是否支援實時進度追蹤
    var supportsRealTimeProgress: Bool {
        switch self {
        case .rar(let isMultipart):
            // unar 支援進度，unrar 不支援百分比
            return !isMultipart
        case .zip, .sevenZip:
            return true
        case .tar, .tarGz, .tarBz2:
            return false
        }
    }

    /// 是否支援當前檔案顯示
    var supportsCurrentFile: Bool {
        switch self {
        case .rar, .zip, .sevenZip:
            return true
        case .tar, .tarGz, .tarBz2:
            return false
        }
    }

    /// 是否為多分片壓縮檔
    var isMultipart: Bool {
        switch self {
        case .rar(let isMultipart):
            return isMultipart
        default:
            return false
        }
    }

    /// 從 URL 偵測壓縮檔類型
    /// - Parameter url: 壓縮檔 URL
    /// - Returns: 偵測到的類型，如果無法識別則返回 nil
    static func detect(from url: URL) -> ArchiveType? {
        let fileName = url.lastPathComponent.lowercased()
        let pathExtension = url.pathExtension.lowercased()

        // 檢查複合副檔名（如 .tar.gz）
        if fileName.hasSuffix(".tar.gz") || fileName.hasSuffix(".tgz") {
            return .tarGz
        }

        if fileName.hasSuffix(".tar.bz2") || fileName.hasSuffix(".tbz") {
            return .tarBz2
        }

        // 檢查單一副檔名
        switch pathExtension {
        case "rar":
            // 需要進一步檢查是否為多分片
            return .rar(isMultipart: false) // 預設為單檔，之後會更新
        case "zip":
            return .zip
        case "7z":
            return .sevenZip
        case "tar":
            return .tar
        default:
            return nil
        }
    }

    /// 取得人類可讀的描述
    var description: String {
        switch self {
        case .rar(let isMultipart):
            return isMultipart ? "RAR (多分片)" : "RAR"
        case .zip:
            return "ZIP"
        case .sevenZip:
            return "7-Zip"
        case .tar:
            return "TAR"
        case .tarGz:
            return "TAR.GZ"
        case .tarBz2:
            return "TAR.BZ2"
        }
    }
}
