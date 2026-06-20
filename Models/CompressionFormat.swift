import Foundation

/// 壓縮格式
enum CompressionFormat: String, CaseIterable, Identifiable {
    case zip = "ZIP"
    case sevenZip = "7z"
    case tarGz = "tar.gz"
    case tarXz = "tar.xz"
    case tarZst = "tar.zst"

    var id: String { rawValue }

    var fileExtension: String {
        switch self {
        case .zip: return "zip"
        case .sevenZip: return "7z"
        case .tarGz: return "tar.gz"
        case .tarXz: return "tar.xz"
        case .tarZst: return "tar.zst"
        }
    }

    var displayName: String { rawValue }

    var toolName: String {
        switch self {
        case .zip, .sevenZip: return "7zz"
        case .tarGz, .tarXz, .tarZst: return "tar"
        }
    }

    /// 跨平台相容性等級
    var compatibility: Compatibility {
        switch self {
        case .zip: return .universal
        case .sevenZip: return .needsTool
        case .tarGz: return .linuxNative
        case .tarXz: return .linuxNative
        case .tarZst: return .modern
        }
    }

    /// 壓縮率（相對評級）
    var compressionLevel: CompressionLevel {
        switch self {
        case .zip: return .standard
        case .sevenZip: return .high
        case .tarGz: return .standard
        case .tarXz: return .high
        case .tarZst: return .high
        }
    }

    /// 給用戶的一句話說明
    var hint: String {
        switch self {
        case .zip: return "最通用，Windows/macOS/Linux 都能直接開"
        case .sevenZip: return "壓縮率最高，對方需安裝 7-Zip"
        case .tarGz: return "Linux/macOS 常用，Windows 需工具"
        case .tarXz: return "比 tar.gz 壓更小，Linux 常用"
        case .tarZst: return "速度快壓縮率高，較新的格式"
        }
    }

    /// 是否支援密碼保護
    var supportsPassword: Bool {
        switch self {
        case .zip, .sevenZip: return true
        case .tarGz, .tarXz, .tarZst: return false
        }
    }

    enum Compatibility: String {
        case universal = "通用"
        case needsTool = "需工具"
        case linuxNative = "Linux 原生"
        case modern = "較新"
    }

    enum CompressionLevel: String {
        case standard = "標準"
        case high = "高"
    }
}
