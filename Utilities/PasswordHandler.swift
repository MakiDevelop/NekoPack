//
//  PasswordHandler.swift
//  NekoRAR
//
//  Created by Claude Code on 2025/11/22.
//

import Foundation

/// 密碼處理工具
class PasswordHandler {

    // MARK: - Public Methods

    /// 安全地為 process 設定密碼環境變數
    /// - Parameters:
    ///   - process: 要設定的 Process
    ///   - password: 密碼字串（可選）
    ///   - variableName: 環境變數名稱
    static func setPasswordEnvironment(
        _ process: Process,
        password: String?,
        variableName: String = ExtractionConstants.unrarPasswordEnvVar
    ) {
        var env = ExtractionConstants.defaultEnvironment

        // 只有在有密碼時才設定環境變數
        if let password = password, !password.isEmpty {
            env[variableName] = password
        }

        process.environment = env
    }

    /// 通過 stdin 安全地傳遞密碼給 process
    /// - Parameters:
    ///   - process: 要傳遞密碼的 Process
    ///   - password: 密碼字串（可選）
    /// - Returns: 用於寫入密碼的 Pipe，如果沒有密碼則返回 nil
    static func createPasswordPipe(for process: Process, password: String?) -> Pipe? {
        guard let password = password, !password.isEmpty else {
            return nil
        }

        let passwordPipe = Pipe()
        process.standardInput = passwordPipe

        // 在背景執行緒寫入密碼
        DispatchQueue.global(qos: .utility).async {
            if let passwordData = (password + "\n").data(using: .utf8) {
                passwordPipe.fileHandleForWriting.write(passwordData)
            }
            try? passwordPipe.fileHandleForWriting.close()
        }

        return passwordPipe
    }

    /// 為特定工具準備密碼參數
    /// - Parameters:
    ///   - tool: 解壓縮工具類型
    ///   - password: 密碼字串（可選）
    /// - Returns: 密碼相關的命令列參數
    static func passwordArguments(for tool: ExtractionTool, password: String?) -> [String] {
        switch tool {
        case .unar:
            // unar 必須使用參數傳遞密碼
            if let password = password, !password.isEmpty {
                return ["-p", password]
            } else {
                return []
            }

        case .unrar:
            // unrar 直接帶參數，無密碼則 -p-
            if let password = password, !password.isEmpty {
                return ["-p\(password)"]
            } else {
                return ["-p-"]
            }

        case .sevenZip:
            // 7za 使用 stdin，返回 -p 參數
            if let password = password, !password.isEmpty {
                return ["-p"]
            } else {
                return []
            }

        case .tar:
            // tar 不支援密碼
            return []
        }
    }

    /// 設定 Process 的密碼處理
    /// - Parameters:
    ///   - process: Process 實例
    ///   - tool: 解壓縮工具類型
    ///   - password: 密碼字串（可選）
    /// - Returns: 密碼 Pipe（如果使用 stdin 傳遞）
    @discardableResult
    static func configurePassword(
        for process: Process,
        tool: ExtractionTool,
        password: String?
    ) -> Pipe? {
        switch tool {
        case .unar:
            // unar 使用參數，不需要特殊設定
            return nil

        case .unrar:
            // unrar 已透過參數帶密碼，僅保持預設環境
            process.environment = ExtractionConstants.defaultEnvironment
            return nil

        case .sevenZip:
            // 7za 使用 stdin
            return createPasswordPipe(for: process, password: password)

        case .tar:
            // tar 不支援密碼
            return nil
        }
    }

    /// 清理密碼相關資源
    /// - Parameter pipe: 密碼 Pipe（可選）
    static func cleanup(_ pipe: Pipe?) {
        guard let pipe = pipe else { return }

        // 確保 pipe 已關閉
        try? pipe.fileHandleForWriting.close()
    }

    // MARK: - Validation

    /// 驗證密碼是否有效
    /// - Parameter password: 密碼字串
    /// - Returns: 是否為有效密碼
    static func isValid(_ password: String?) -> Bool {
        guard let password = password else { return false }
        return !password.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// 取得安全的密碼顯示文字（用於日誌）
    /// - Parameter password: 密碼字串（可選）
    /// - Returns: 安全的顯示文字
    static func safeDisplay(_ password: String?) -> String {
        if isValid(password) {
            return "[密碼已設定]"
        } else {
            return "[無密碼]"
        }
    }

    // MARK: - Tool-specific Helpers

    /// 為 7za 準備參數（使用 stdin）
    /// - Parameter password: 密碼字串（可選）
    /// - Returns: 參數陣列和 Pipe
    static func prepare7zPassword(_ password: String?) -> (arguments: [String], pipe: Pipe?) {
        if isValid(password) {
            return (arguments: ["-p"], pipe: nil) // pipe 會由外部設定
        } else {
            return (arguments: [], pipe: nil)
        }
    }

    /// 為 unrar 準備參數（使用環境變數）
    /// - Parameter password: 密碼字串（可選）
    /// - Returns: 參數陣列
    static func prepareUnrarPassword(_ password: String?) -> [String] {
        if let password = password, !password.isEmpty {
            return ["-p\(password)"]
        } else {
            return ["-p-"]
        }
    }

    /// 為 unar 準備參數（使用命令列參數）
    /// - Parameter password: 密碼字串（可選）
    /// - Returns: 參數陣列
    static func prepareUnarPassword(_ password: String?) -> [String] {
        if let password = password, !password.isEmpty {
            return ["-p", password]
        } else {
            return []
        }
    }
}

// MARK: - Password Security Extensions

extension PasswordHandler {

    /// 密碼安全等級
    enum SecurityLevel {
        case high       // 使用 stdin 或環境變數
        case medium     // 使用命令列參數但不記錄
        case low        // 使用命令列參數且可能被記錄

        var description: String {
            switch self {
            case .high:
                return "高（stdin/環境變數）"
            case .medium:
                return "中（命令列參數，不記錄）"
            case .low:
                return "低（命令列參數）"
            }
        }
    }

    /// 取得特定工具的安全等級
    /// - Parameter tool: 解壓縮工具
    /// - Returns: 安全等級
    static func securityLevel(for tool: ExtractionTool) -> SecurityLevel {
        switch tool {
        case .sevenZip:
            return .high // 使用 stdin
        case .unrar:
            return .high // 使用環境變數
        case .unar:
            return .medium // 使用參數但不記錄
        case .tar:
            return .high // 不支援密碼
        }
    }
}
