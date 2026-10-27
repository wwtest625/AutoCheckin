import Foundation

/// 积分时序存储与聚合服务：
/// 负责记录每日积分快照、持久化至本地 JSON 文件 (0600 权限)，并聚合生成近 14 天的净增减数据。
final class CreditHistoryStorage: @unchecked Sendable {
    static let shared = CreditHistoryStorage()
    
    private let lock = NSLock()
    private let ioQueue = DispatchQueue(label: "com.autocheckin.credithistory.io", qos: .utility)
    
    private static let fileName = "credit_history.json"
    private static let maxRetentionDays = 90
    
    private static var storageFile: URL {
        let dir: URL
        if let override = ProcessInfo.processInfo.environment[AccountStorage.dataDirOverrideEnv], !override.isEmpty {
            dir = URL(fileURLWithPath: (override as NSString).expandingTildeInPath, isDirectory: true)
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            dir = appSupport.appendingPathComponent("AutoCheckin")
        }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(fileName)
    }
    
    private var cachedSnapshots: [CreditSnapshot]?
    private var hasCorruptedFileError: Bool = false
    
    private let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "zh_CN")
        f.timeZone = TimeZone.current
        return f
    }()
    
    private let displayDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM/dd"
        f.locale = Locale(identifier: "zh_CN")
        f.timeZone = TimeZone.current
        return f
    }()
    
    private init() {}
    
    // MARK: - 存储与加载 (带防御性备份与防覆盖保护)
    
    func loadSnapshots() -> [CreditSnapshot] {
        lock.lock()
        defer { lock.unlock() }
        
        if let cached = cachedSnapshots {
            return cached
        }
        
        let file = Self.storageFile
        let fm = FileManager.default
        
        // 1. 文件不存在：正常初始化空数据
        guard fm.fileExists(atPath: file.path) else {
            cachedSnapshots = []
            hasCorruptedFileError = false
            return []
        }
        
        // 2. 文件存在：尝试读取并解码
        do {
            let data = try Data(contentsOf: file)
            let list = try JSONDecoder().decode([CreditSnapshot].self, from: data)
            cachedSnapshots = list
            hasCorruptedFileError = false
            return list
        } catch {
            // 3. 读取或解码异常：绝不能当作空数据覆盖！备份原文件以供救回
            hasCorruptedFileError = true
            let timestamp = Int(Date().timeIntervalSince1970)
            let backupFile = file.deletingLastPathComponent().appendingPathComponent("credit_history.corrupted.\(timestamp).json")
            try? fm.copyItem(at: file, to: backupFile)
            NSLog("[AutoCheckin] ⚠️ credit_history.json 读取或解析失败: \(error.localizedDescription)。原文件已自动备份至: \(backupFile.path)")
            
            // 返回空列表供只读展示，但由于 hasCorruptedFileError = true，后续写入会被拒绝直到排查或确认
            return []
        }
    }
    
    /// 记录一条经过验证的真实积分快照
    func recordSnapshot(accountId: String, balance: Double, date: Date = Date()) {
        lock.lock()
        defer { lock.unlock() }
        
        // 如果之前文件读取失败，严禁以单条数据覆盖原文件
        if hasCorruptedFileError {
            NSLog("[AutoCheckin] ⚠️ 历史数据文件处于损坏保护状态，本次写入已拦截，以避免覆盖旧数据")
            return
        }
        
        var list = cachedSnapshots ?? {
            let file = Self.storageFile
            if FileManager.default.fileExists(atPath: file.path) {
                if let data = try? Data(contentsOf: file),
                   let decoded = try? JSONDecoder().decode([CreditSnapshot].self, from: data) {
                    return decoded
                } else {
                    hasCorruptedFileError = true
                    return []
                }
            }
            return []
        }()
        
        if hasCorruptedFileError { return }
        
        let dateStr = dayFormatter.string(from: date)
        
        // 同账号同天快照折叠优化：
        // 寻找今天同一账号的已有快照，如果数值没有变化，则无需增加新记录；
        // 如果数值发生变化（如签到后或使用后），更新当天快照为最新收盘点，避免频繁刷新产生海量冗余数据。
        if let lastIdx = list.lastIndex(where: { $0.accountId == accountId && $0.dateString == dateStr }) {
            if abs(list[lastIdx].balance - balance) < 0.0001 {
                // 数值相同且在当天，跳过
                return
            } else {
                // 同一天积分发生变动：更新该快照为最新值
                list[lastIdx].balance = balance
                list[lastIdx].timestamp = date
            }
        } else {
            // 当天首个有效打点
            let newSnapshot = CreditSnapshot(
                accountId: accountId,
                dateString: dateStr,
                timestamp: date,
                balance: balance
            )
            list.append(newSnapshot)
        }
        
        // 自动修剪超过 90 天的历史旧记录
        let calendar = Calendar.current
        if let cutoffDate = calendar.date(byAdding: .day, value: -Self.maxRetentionDays, to: date) {
            let cutoffStr = dayFormatter.string(from: cutoffDate)
            list.removeAll(where: { $0.dateString < cutoffStr })
        }
        
        cachedSnapshots = list
        
        // 移交后台异步串行队列持久化至磁盘，避免在 MainActor 产生磁盘 I/O 卡顿
        let toSave = list
        ioQueue.async {
            Self.saveSnapshotsToDisk(toSave)
        }
    }
    
    private static func saveSnapshotsToDisk(_ snapshots: [CreditSnapshot]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        guard let data = try? encoder.encode(snapshots) else { return }
        
        let file = storageFile
        let fm = FileManager.default
        let parentDir = file.deletingLastPathComponent()
        
        try? fm.createDirectory(at: parentDir, withIntermediateDirectories: true)
        
        // 0600 权限原子写入
        if !fm.fileExists(atPath: file.path) {
            fm.createFile(atPath: file.path, contents: data, attributes: [
                .posixPermissions: NSNumber(value: 0o600)
            ])
        } else {
            try? data.write(to: file, options: .atomic)
            try? fm.setAttributes([.posixPermissions: NSNumber(value: 0o600)], ofItemAtPath: file.path)
        }
    }
    
    // MARK: - 聚合近 N 天的时序数据
    
    /// 获取指定账号或全部账号合并后的近 N 天数据
    func getSummary(accountId: String?, allAccounts: [AccountItem], days: Int = 14) -> CreditSummary {
        let allSnapshots = loadSnapshots()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
        // 构造连续的近 N 天日期序列（从过去到今天）
        var dayDates: [Date] = []
        for i in (0..<days).reversed() {
            if let d = calendar.date(byAdding: .day, value: -i, to: today) {
                dayDates.append(d)
            }
        }
        
        if let targetId = accountId, !targetId.isEmpty {
            // 单账号计算
            return calculateSummaryForSingleAccount(
                accountId: targetId,
                snapshots: allSnapshots.filter { $0.accountId == targetId },
                dayDates: dayDates,
                fallbackItem: allAccounts.first(where: { $0.id == targetId })
            )
        } else {
            // 全部账号合并计算
            return calculateSummaryForAllAccounts(
                allAccounts: allAccounts,
                snapshots: allSnapshots,
                dayDates: dayDates
            )
        }
    }
    
    private func calculateSummaryForSingleAccount(
        accountId: String,
        snapshots: [CreditSnapshot],
        dayDates: [Date],
        fallbackItem: AccountItem?
    ) -> CreditSummary {
        let sortedSnapshots = snapshots.sorted { $0.timestamp < $1.timestamp }
        var points: [DailyCreditPoint] = []
        let calendar = Calendar.current
        
        // 寻找区间开始前的最近基准积分与对应日期
        var previousClosing: Double? = nil
        var previousDate: Date? = nil
        if let firstDate = dayDates.first {
            let firstDateStr = dayFormatter.string(from: firstDate)
            if let prior = sortedSnapshots.last(where: { $0.dateString < firstDateStr }) {
                previousClosing = prior.balance
                previousDate = prior.timestamp
            }
        }
        
        for date in dayDates {
            let dateStr = dayFormatter.string(from: date)
            let displayStr = displayDayFormatter.string(from: date)
            
            // 找出当天的所有快照
            let daySnapshots = sortedSnapshots.filter { $0.dateString == dateStr }
            
            if let lastOfDay = daySnapshots.last {
                let closing = lastOfDay.balance
                let delta = (previousClosing != nil) ? (closing - previousClosing!) : 0
                
                // 计算距离上一次有效记录的天数
                let daysGap: Int = {
                    guard let prevD = previousDate else { return 1 }
                    let startCurrent = calendar.startOfDay(for: date)
                    let startPrev = calendar.startOfDay(for: prevD)
                    let comps = calendar.dateComponents([.day], from: startPrev, to: startCurrent)
                    return max(1, comps.day ?? 1)
                }()
                
                points.append(DailyCreditPoint(
                    accountId: accountId,
                    date: date,
                    dateString: dateStr,
                    displayDate: displayStr,
                    closingBalance: closing,
                    netDelta: delta,
                    hasRecord: true,
                    daysSincePrevious: daysGap
                ))
                previousClosing = closing
                previousDate = date
            } else {
                // 当天没有记录：若为今天且内存里有经确认的实时积分，尝试采用
                let isToday = calendar.isDateInToday(date)
                if isToday, let fallback = fallbackItem, let num = fallback.numericCredits {
                    let delta = (previousClosing != nil) ? (num - previousClosing!) : 0
                    let daysGap: Int = {
                        guard let prevD = previousDate else { return 1 }
                        let startCurrent = calendar.startOfDay(for: date)
                        let startPrev = calendar.startOfDay(for: prevD)
                        let comps = calendar.dateComponents([.day], from: startPrev, to: startCurrent)
                        return max(1, comps.day ?? 1)
                    }()
                    
                    points.append(DailyCreditPoint(
                        accountId: accountId,
                        date: date,
                        dateString: dateStr,
                        displayDate: displayStr,
                        closingBalance: num,
                        netDelta: delta,
                        hasRecord: true,
                        daysSincePrevious: daysGap
                    ))
                    previousClosing = num
                    previousDate = date
                } else {
                    // 当天未打开应用或无记录：延续上一日积分，当日变动显式记为 0
                    let closing = previousClosing ?? 0
                    points.append(DailyCreditPoint(
                        accountId: accountId,
                        date: date,
                        dateString: dateStr,
                        displayDate: displayStr,
                        closingBalance: closing,
                        netDelta: 0,
                        hasRecord: false,
                        daysSincePrevious: 1
                    ))
                }
            }
        }
        
        let currentTotal = points.last?.closingBalance ?? (fallbackItem?.numericCredits ?? 0)
        let todayPoint = points.last
        let todayDelta = todayPoint?.netDelta ?? 0
        let todayDaysSincePrevious = todayPoint?.daysSincePrevious ?? 1
        let fourteenDayDelta = points.reduce(0.0) { $0 + $1.netDelta }
        
        return CreditSummary(
            currentTotal: currentTotal,
            todayDelta: todayDelta,
            fourteenDayDelta: fourteenDayDelta,
            todayDaysSincePrevious: todayDaysSincePrevious,
            points: points
        )
    }
    
    private func calculateSummaryForAllAccounts(
        allAccounts: [AccountItem],
        snapshots: [CreditSnapshot],
        dayDates: [Date]
    ) -> CreditSummary {
        guard !allAccounts.isEmpty else {
            return CreditSummary()
        }
        
        var accountPointsMap: [String: [DailyCreditPoint]] = [:]
        for acc in allAccounts {
            let accSnapshots = snapshots.filter { $0.accountId == acc.id }
            let summary = calculateSummaryForSingleAccount(
                accountId: acc.id,
                snapshots: accSnapshots,
                dayDates: dayDates,
                fallbackItem: acc
            )
            accountPointsMap[acc.id] = summary.points
        }
        
        var combinedPoints: [DailyCreditPoint] = []
        for (index, date) in dayDates.enumerated() {
            let dateStr = dayFormatter.string(from: date)
            let displayStr = displayDayFormatter.string(from: date)
            
            var dayClosingSum: Double = 0
            var dayDeltaSum: Double = 0
            var anyHasRecord = false
            var maxDaysGap = 1
            
            for acc in allAccounts {
                if let pts = accountPointsMap[acc.id], index < pts.count {
                    let pt = pts[index]
                    dayClosingSum += pt.closingBalance
                    dayDeltaSum += pt.netDelta
                    if pt.hasRecord {
                        anyHasRecord = true
                        maxDaysGap = max(maxDaysGap, pt.daysSincePrevious)
                    }
                }
            }
            
            combinedPoints.append(DailyCreditPoint(
                accountId: "all",
                date: date,
                dateString: dateStr,
                displayDate: displayStr,
                closingBalance: dayClosingSum,
                netDelta: dayDeltaSum,
                hasRecord: anyHasRecord,
                daysSincePrevious: maxDaysGap
            ))
        }
        
        let currentTotal = combinedPoints.last?.closingBalance ?? 0
        let todayPoint = combinedPoints.last
        let todayDelta = todayPoint?.netDelta ?? 0
        let todayDaysSincePrevious = todayPoint?.daysSincePrevious ?? 1
        let fourteenDayDelta = combinedPoints.reduce(0.0) { $0 + $1.netDelta }
        
        return CreditSummary(
            currentTotal: currentTotal,
            todayDelta: todayDelta,
            fourteenDayDelta: fourteenDayDelta,
            todayDaysSincePrevious: todayDaysSincePrevious,
            points: combinedPoints
        )
    }
}
