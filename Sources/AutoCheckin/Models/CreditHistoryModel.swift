import Foundation

/// 每次拉取或签到时记录的一条原始积分快照（时序数据点）。
public struct CreditSnapshot: Codable, Sendable, Identifiable {
    public var id: UUID
    public var accountId: String
    public var dateString: String // "yyyy-MM-dd"
    public var timestamp: Date
    public var balance: Double

    public init(id: UUID = UUID(), accountId: String, dateString: String, timestamp: Date, balance: Double) {
        self.id = id
        self.accountId = accountId
        self.dateString = dateString
        self.timestamp = timestamp
        self.balance = balance
    }
}

/// 柱状图渲染所需的日粒度数据点。
public struct DailyCreditPoint: Identifiable, Sendable {
    public var id: String { "\(accountId)_\(dateString)" }
    public var accountId: String
    public var date: Date
    public var dateString: String     // "yyyy-MM-dd"
    public var displayDate: String    // "10/26"
    public var closingBalance: Double // 当日最终积分
    public var netDelta: Double       // 相对上一记录日的净增减 = closingBalance - previousBalance
    public var hasRecord: Bool        // 当天是否有实际打点记录
    public var daysSincePrevious: Int // 距离上一次有效打点的间隔天数（1 表示紧邻前一日，>1 表示跨多天断档）
    
    public var isConsecutive: Bool { daysSincePrevious <= 1 }
    
    public init(accountId: String, date: Date, dateString: String, displayDate: String, closingBalance: Double, netDelta: Double, hasRecord: Bool, daysSincePrevious: Int = 1) {
        self.accountId = accountId
        self.date = date
        self.dateString = dateString
        self.displayDate = displayDate
        self.closingBalance = closingBalance
        self.netDelta = netDelta
        self.hasRecord = hasRecord
        self.daysSincePrevious = daysSincePrevious
    }
}

/// 积分统计概览数据模型。
public struct CreditSummary: Sendable {
    public var currentTotal: Double
    public var todayDelta: Double
    public var fourteenDayDelta: Double
    public var todayDaysSincePrevious: Int
    public var points: [DailyCreditPoint]

    public init(currentTotal: Double = 0, todayDelta: Double = 0, fourteenDayDelta: Double = 0, todayDaysSincePrevious: Int = 1, points: [DailyCreditPoint] = []) {
        self.currentTotal = currentTotal
        self.todayDelta = todayDelta
        self.fourteenDayDelta = fourteenDayDelta
        self.todayDaysSincePrevious = todayDaysSincePrevious
        self.points = points
    }
}
