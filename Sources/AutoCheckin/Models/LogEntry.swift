import Foundation

enum LogLevel {
    case info
    case success
    case warning
    case error
    
    var colorName: String {
        switch self {
        case .info: return "blue"
        case .success: return "green"
        case .warning: return "orange"
        case .error: return "red"
        }
    }
}

struct LogMessage: Identifiable {
    let id = UUID()
    let timestamp: Date = Date()
    let level: LogLevel
    let content: String
    
    var formattedTime: String {
        LogMessage.timeFormatter.string(from: timestamp)
    }
    
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()
}
