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
