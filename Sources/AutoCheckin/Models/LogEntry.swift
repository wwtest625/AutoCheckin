import Foundation
import SwiftUI

enum LogLevel: String, CaseIterable, Identifiable {
    case info = "信息"
    case success = "成功"
    case warning = "警告"
    case error = "错误"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .info: return "info.circle.fill"
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        }
    }

    var color: Color {
        switch self {
        case .info: return .blue
        case .success: return .green
        case .warning: return .orange
        case .error: return .red
        }
    }
}

/// 扫描过程中的诊断信息：目录不存在、字段缺失、解密失败等每种落空原因都要说话，
/// 否则客户端改了存储格式时用户只会看到「一个账号都没扫到」，无从判断原因。
struct ScanNotice: Sendable {
    let level: LogLevel
    let message: String

    init(_ level: LogLevel, _ message: String) {
        self.level = level
        self.message = message
    }
}

/// 单个平台的扫描产出。
struct ScanOutput: Sendable {
    var accounts: [AccountItem] = []
    var notices: [ScanNotice] = []

    /// 是否存在「格式/解密」级别的硬故障；有则说明本次没扫到不代表登录态消失了。
    var hasBlockingFailure: Bool {
        notices.contains { $0.level == .error }
    }
}

struct LogMessage: Identifiable {
    let id = UUID()
    let timestamp: Date = Date()
    let level: LogLevel
    let content: String
    
    // 智能提取出的业务标签（例如 "Trae CN - 用户名"、"定时任务" 等）
    let tag: String?
    // 去除中括号标签后的清晰正文
    let cleanMessage: String
    
    init(level: LogLevel, content: String) {
        self.level = level
        self.content = content
        
        // 智能解析形如 "[Trae CN - 用户] 签到成功" 的日志头
        if content.hasPrefix("["), let closingIndex = content.firstIndex(of: "]") {
            let extracted = String(content[content.index(after: content.startIndex)..<closingIndex])
            let rest = content[content.index(after: closingIndex)...].trimmingCharacters(in: .whitespaces)
            self.tag = extracted
            self.cleanMessage = rest.isEmpty ? content : rest
        } else if content.hasPrefix("⏰") {
            self.tag = "定时任务"
            self.cleanMessage = content.replacingOccurrences(of: "⏰", with: "").trimmingCharacters(in: .whitespaces)
        } else if content.contains("扫描") {
            self.tag = "系统扫描"
            self.cleanMessage = content
        } else if content.contains("批量") {
            self.tag = "批量操作"
            self.cleanMessage = content.replacingOccurrences(of: "=", with: "").trimmingCharacters(in: .whitespaces)
        } else {
            self.tag = nil
            self.cleanMessage = content
        }
    }
    
    var formattedTime: String {
        LogMessage.timeFormatter.string(from: timestamp)
    }
    
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()
}
