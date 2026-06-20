//
//  FileAccessManager.swift
//  NekoRAR
//
//  Created by Claude Code on 2025/11/22.
//

import Foundation
import AppKit

/// 檔案存取管理器
/// 負責處理安全作用域資源、Bookmark 和檔案權限
class FileAccessManager {

    // MARK: - Properties

    private var activeResources: Set<URL> = []
    private let fileManager = FileManager.default

    // MARK: - Bookmark Management

    /// 創建 Security-Scoped Bookmark
    /// - Parameter url: 要創建 bookmark 的 URL
    /// - Returns: Bookmark 資料
    /// - Throws: 如果創建失敗
    func createBookmark(for url: URL) throws -> Data {
        return try url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    /// 解析 Bookmark
    /// - Parameter bookmarkData: Bookmark 資料
    /// - Returns: 解析後的 URL
    /// - Throws: 如果解析失敗
    func resolveBookmark(_ bookmarkData: Data) throws -> URL {
        var isStale = false
        let url = try URL(
            resolvingBookmarkData: bookmarkData,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )

        if isStale {
            print("⚠️ Bookmark 已過期，需要重新創建")
            // 可以選擇重新創建 bookmark
        }

        return url
    }

    /// 儲存 Bookmark 到 UserDefaults
    /// - Parameters:
    ///   - bookmarkData: Bookmark 資料
    ///   - key: 儲存的 key
    func saveBookmark(_ bookmarkData: Data, forKey key: String) {
        UserDefaults.standard.set(bookmarkData, forKey: key)
    }

    /// 從 UserDefaults 載入 Bookmark
    /// - Parameter key: Bookmark 的 key
    /// - Returns: Bookmark 資料（如果存在）
    func loadBookmark(forKey key: String) -> Data? {
        return UserDefaults.standard.data(forKey: key)
    }

    /// 嘗試從 Bookmark 恢復目的地
    /// - Returns: 目的地 URL（如果成功）
    func restoreDestinationFromBookmark() -> URL? {
        guard let bookmarkData = loadBookmark(forKey: ExtractionConstants.lastDestinationBookmarkKey) else {
            return nil
        }

        do {
            let url = try resolveBookmark(bookmarkData)
            print("✅ 從 bookmark 恢復目的地：\(url.path)")
            return url
        } catch {
            print("⚠️ 無法從 bookmark 恢復目的地：\(error)")
            return nil
        }
    }

    // MARK: - Security-Scoped Resource Access

    /// 開始存取安全作用域資源
    /// - Parameter url: 要存取的 URL
    /// - Returns: 是否成功開始存取
    @discardableResult
    func startAccessing(_ url: URL) -> Bool {
        guard url.startAccessingSecurityScopedResource() else {
            print("❌ 無法存取安全作用域資源：\(url.path)")
            return false
        }

        activeResources.insert(url)
        print("✅ 開始存取：\(url.path)")
        return true
    }

    /// 停止存取安全作用域資源
    /// - Parameter url: 要停止存取的 URL
    func stopAccessing(_ url: URL) {
        if activeResources.contains(url) {
            url.stopAccessingSecurityScopedResource()
            activeResources.remove(url)
            print("✅ 停止存取：\(url.path)")
        }
    }

    /// 停止所有活動的資源存取
    func stopAllAccess() {
        for url in activeResources {
            url.stopAccessingSecurityScopedResource()
            print("✅ 停止存取：\(url.path)")
        }
        activeResources.removeAll()
    }

    /// 使用安全作用域資源執行操作
    /// - Parameters:
    ///   - url: 要存取的 URL
    ///   - operation: 要執行的操作
    /// - Returns: 操作結果
    /// - Throws: 操作拋出的錯誤
    func withSecureAccess<T>(
        to url: URL,
        operation: () throws -> T
    ) throws -> T {
        guard startAccessing(url) else {
            throw ExtractionError.permissionDenied(path: url.path)
        }

        defer {
            stopAccessing(url)
        }

        return try operation()
    }

    /// 異步使用安全作用域資源
    /// - Parameters:
    ///   - url: 要存取的 URL
    ///   - operation: 要執行的異步操作
    /// - Returns: 操作結果
    /// - Throws: 操作拋出的錯誤
    func withSecureAccess<T>(
        to url: URL,
        operation: () async throws -> T
    ) async throws -> T {
        guard startAccessing(url) else {
            throw ExtractionError.permissionDenied(path: url.path)
        }

        defer {
            stopAccessing(url)
        }

        return try await operation()
    }

    // MARK: - Validation

    /// 驗證 URL 是否可存取
    /// - Parameter url: 要驗證的 URL
    /// - Returns: 是否可存取
    func validateAccess(to url: URL) -> Bool {
        // 檢查檔案是否存在
        guard fileManager.fileExists(atPath: url.path) else {
            print("❌ 檔案不存在：\(url.path)")
            return false
        }

        // 檢查是否可讀
        guard fileManager.isReadableFile(atPath: url.path) else {
            print("❌ 檔案不可讀：\(url.path)")
            return false
        }

        return true
    }

    /// 驗證目的地是否可寫入
    /// - Parameter url: 目的地 URL
    /// - Returns: 是否可寫入
    func validateDestination(_ url: URL) -> Bool {
        // 如果目錄存在，檢查是否可寫
        if fileManager.fileExists(atPath: url.path) {
            guard fileManager.isWritableFile(atPath: url.path) else {
                print("❌ 目的地不可寫：\(url.path)")
                return false
            }
            return true
        }

        // 如果目錄不存在，檢查父目錄是否可寫
        let parentURL = url.deletingLastPathComponent()
        guard fileManager.fileExists(atPath: parentURL.path) else {
            print("❌ 父目錄不存在：\(parentURL.path)")
            return false
        }

        guard fileManager.isWritableFile(atPath: parentURL.path) else {
            print("❌ 父目錄不可寫：\(parentURL.path)")
            return false
        }

        return true
    }

    /// 檢查磁碟空間
    /// - Parameters:
    ///   - url: 要檢查的路徑
    ///   - requiredSpace: 需要的空間（位元組）
    /// - Returns: 是否有足夠空間
    /// - Throws: 如果無法取得磁碟資訊
    func checkDiskSpace(at url: URL, requiredSpace: Int64) throws -> Bool {
        let attributes = try fileManager.attributesOfFileSystem(forPath: url.path)

        guard let freeSpace = attributes[.systemFreeSize] as? Int64 else {
            throw ExtractionError.unknown(message: "無法取得可用空間")
        }

        print("💾 可用空間：\(ByteCountFormatter.string(fromByteCount: freeSpace, countStyle: .file))")
        print("💾 需要空間：\(ByteCountFormatter.string(fromByteCount: requiredSpace, countStyle: .file))")

        return freeSpace >= requiredSpace
    }

    // MARK: - File Selection

    /// 選擇檔案
    /// - Parameters:
    ///   - allowedTypes: 允許的檔案類型
    ///   - title: 對話框標題
    /// - Returns: 選擇的 URL（如果有）
    func selectFile(allowedTypes: [String], title: String = "選擇檔案") -> URL? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedFileTypes = allowedTypes

        guard panel.runModal() == .OK else {
            return nil
        }

        return panel.url
    }

    /// 選擇資料夾
    /// - Parameter title: 對話框標題
    /// - Returns: 選擇的 URL（如果有）
    func selectFolder(title: String = "選擇資料夾") -> URL? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK else {
            return nil
        }

        return panel.url
    }

    // MARK: - Path Utilities

    /// 取得安全的輸出路徑
    /// - Parameters:
    ///   - archiveURL: 壓縮檔 URL
    ///   - destinationURL: 目的地 URL
    /// - Returns: 安全的輸出路徑
    func getSafeOutputPath(for archiveURL: URL, in destinationURL: URL) -> URL {
        let archiveName = archiveURL.deletingPathExtension().lastPathComponent
        var outputPath = destinationURL.appendingPathComponent(archiveName)

        // 如果路徑已存在，添加數字後綴
        var counter = 1
        while fileManager.fileExists(atPath: outputPath.path) {
            let newName = "\(archiveName) (\(counter))"
            outputPath = destinationURL.appendingPathComponent(newName)
            counter += 1
        }

        return outputPath
    }

    /// 創建目錄（如果不存在）
    /// - Parameter url: 目錄 URL
    /// - Throws: 如果創建失敗
    func createDirectoryIfNeeded(at url: URL) throws {
        if !fileManager.fileExists(atPath: url.path) {
            try fileManager.createDirectory(
                at: url,
                withIntermediateDirectories: true,
                attributes: nil
            )
            print("✅ 創建目錄：\(url.path)")
        }
    }

    // MARK: - Cleanup

    /// 清理資源
    deinit {
        stopAllAccess()
    }
}

// MARK: - Convenience Extensions

extension FileAccessManager {

    /// 請求並驗證存取權限
    /// - Parameter url: 要存取的 URL
    /// - Throws: 如果無法存取
    func requestAndValidateAccess(to url: URL) throws {
        // 驗證檔案存在
        guard validateAccess(to: url) else {
            throw ExtractionError.archiveNotFound(path: url.path)
        }

        // 開始存取
        guard startAccessing(url) else {
            throw ExtractionError.permissionDenied(path: url.path)
        }
    }

    /// 準備目的地
    /// - Parameter url: 目的地 URL
    /// - Throws: 如果準備失敗
    func prepareDestination(_ url: URL) throws {
        // 驗證目的地
        guard validateDestination(url) else {
            throw ExtractionError.destinationNotAccessible(path: url.path)
        }

        // 創建目錄
        try createDirectoryIfNeeded(at: url)

        // 開始存取
        guard startAccessing(url) else {
            throw ExtractionError.permissionDenied(path: url.path)
        }
    }
}
