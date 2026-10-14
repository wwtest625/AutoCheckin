import Foundation
import Observation

@MainActor
@Observable
final class CheckinManager {
    var accounts: [AccountItem] = []
    var logs: [LogMessage] = []
    var isCheckingAll: Bool = false
    var isScanning: Bool = false
    var selectedTab: Int = 0
    
    // 日志控制台状态
    var logFilterLevel: LogLevel? = nil
    var logSearchText: String = ""
    var logAutoScroll: Bool = true
    
    // 运行环境状态
    var ignoredCount: Int = 0
    var launchAtLogin: Bool = false {
        didSet {
            guard launchAtLogin != oldValue, !isApplyingLoginItem else { return }
            isApplyingLoginItem = true
            defer { isApplyingLoginItem = false }
            
            switch LoginItemService.setEnabled(launchAtLogin) {
            case .enabled:
                addLog("已开启登录自启：开机登录后菜单栏自动常驻，定时签到不会再漏", level: .success)
            case .disabled:
                addLog("已关闭登录自启：退出或重启电脑后需要手动打开本 App，定时任务才会继续生效", level: .info)
            case .needsApproval(let reason):
                addLog("登录自启：\(reason)", level: .warning)
            case .failed(let reason):
                addLog("登录自启设置失败：\(reason)", level: .error)
            }
            
            // 以系统真实状态回填，避免界面开关与实际不一致
            launchAtLogin = LoginItemService.isEnabled
        }
    }
    private var isApplyingLoginItem = false
    
    /// 凭证与账号信息当前存放的目录，供设置页如实展示。
    var credentialStorageDescription: String { AccountStorage.storageDirectory }

    // 偏好设置
    var autoCheckinEnabled: Bool {
        didSet {
            UserDefaults.standard.set(autoCheckinEnabled, forKey: "autoCheckinEnabled")
            if autoCheckinEnabled {
                addLog("已开启每日自动签到，定时时间为 \(String(format: "%02d:%02d", autoCheckinHour, autoCheckinMinute))", level: .info)
                checkScheduledTime()
            } else {
                addLog("已关闭每日自动签到", level: .warning)
            }
        }
    }
    
    var autoCheckinHour: Int {
        didSet {
            UserDefaults.standard.set(autoCheckinHour, forKey: "autoCheckinHour")
            if autoCheckinEnabled {
                checkScheduledTime()
            }
        }
    }
    
    var autoCheckinMinute: Int {
        didSet {
            UserDefaults.standard.set(autoCheckinMinute, forKey: "autoCheckinMinute")
            if autoCheckinEnabled {
                checkScheduledTime()
            }
        }
    }
    
    private var lastRunDateStr: String {
        get { UserDefaults.standard.string(forKey: "lastRunDateStr") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "lastRunDateStr") }
    }
    
    private var timer: Timer?
    
    init() {
        self.autoCheckinEnabled = UserDefaults.standard.bool(forKey: "autoCheckinEnabled")
        let h = UserDefaults.standard.integer(forKey: "autoCheckinHour")
        self.autoCheckinHour = (h == 0 && !UserDefaults.standard.bool(forKey: "hourSet")) ? 9 : h
        self.autoCheckinMinute = UserDefaults.standard.integer(forKey: "autoCheckinMinute")
        UserDefaults.standard.set(true, forKey: "hourSet")
        
        // 1. 先从本地持久化保险库加载已有账号
        self.accounts = AccountStorage.loadAccounts()
        self.ignoredCount = AccountStorage.ignoredAccountIds().count
        self.launchAtLogin = LoginItemService.isEnabled
        
        // 2. 启动定时器并进行首次时间比对与跨天检查
        setupTimer()
        checkScheduledTime()
    }
    
    func addLog(_ content: String, level: LogLevel = .info) {
        let msg = LogMessage(level: level, content: content)
        self.logs.append(msg)
        if self.logs.count > 500 {
            self.logs.removeFirst(self.logs.count - 500)
        }
    }
    
    // MARK: - Scan & Vault Upsert
    func scanAll() {
        isScanning = true
        addLog("正在扫描本地 Trae CN 与 WorkBuddy 国内版登录凭证...", level: .info)
        
        Task.detached(priority: .userInitiated) {
            // 文件 I/O 与 JSON 解析在后台线程执行，避免卡住主线程
            let traeScan = TraeService.scanAccounts()
            let wbScan = WorkBuddyService.scanAccounts()
            let freshFound = traeScan.accounts + wbScan.accounts
            
            // 合并入本地保险库（增量，不覆盖旧号）
            let merged = AccountStorage.upsert(newAccounts: freshFound)
            var finalList = merged.accounts
            
            // 「这次没扫到」有两种原因：登录态真的没了，或者扫描/解密本身失败了。
            // 只有前者成立才把账号标为过期，否则客户端一改加密格式就会误伤全部账号。
            let freshIds = Set(freshFound.map { $0.id })
            var lostAccounts: [AccountItem] = []
            for index in finalList.indices {
                let account = finalList[index]
                if freshIds.contains(account.id) || account.status == .expired { continue }
                let platformBlocked = account.platform == .trae ? traeScan.hasBlockingFailure : wbScan.hasBlockingFailure
                if platformBlocked { continue }
                
                finalList[index].status = .expired
                finalList[index].statusDetail = "本地已无该账号的登录态，请在客户端重新登录后再扫描"
                lostAccounts.append(account)
            }
            if !lostAccounts.isEmpty {
                AccountStorage.saveAccounts(finalList)
            }
            
            await MainActor.run {
                // 先播报过程诊断，再给结论，方便对照定位
                for notice in traeScan.notices + wbScan.notices + merged.notices {
                    self.addLog(notice.message, level: notice.level)
                }
                for account in lostAccounts {
                    self.addLog("[\(account.platform.rawValue) - \(account.name)] 本地登录态已不存在，已标记为过期", level: .warning)
                }
                
                self.accounts = finalList
                self.isScanning = false
                self.ignoredCount = AccountStorage.ignoredAccountIds().count
                
                if self.accounts.isEmpty {
                    self.addLog("未发现任何国内版登录态文件，请在 Trae CN 或 WorkBuddy 客户端中登录账号。", level: .warning)
                } else {
                    self.addLog("扫描完成！已同步国内账号总数: \(self.accounts.count) 个（Trae CN: \(self.accounts.filter { $0.platform == .trae }.count) 个，WorkBuddy: \(self.accounts.filter { $0.platform == .workbuddy }.count) 个）。", level: .success)
                    for acc in self.accounts {
                        let identifier = acc.phone.isEmpty ? acc.uid : "\(acc.phone) / \(acc.uid)"
                        self.addLog("国内账号已就绪: [\(acc.platform.rawValue)] \(acc.name) (\(identifier))", level: .info)
                    }
                    Task {
                        await self.refreshAllStatuses()
                    }
                }
            }
        }
    }
    
    // MARK: - Delete Account
    func deleteAccount(id: String) {
        if let acc = accounts.first(where: { $0.id == id }) {
            addLog("已删除账号: [\(acc.platform.rawValue)] \(acc.name)（已记入忽略名单，后续扫描不会再自动加回）", level: .warning)
        }
        self.accounts = AccountStorage.deleteAccount(id: id)
        self.ignoredCount = AccountStorage.ignoredAccountIds().count
    }
    
    /// 清空忽略名单，让此前手动删除过的账号在下次扫描时重新出现。
    func restoreIgnoredAccounts() {
        let count = AccountStorage.restoreIgnoredAccounts()
        ignoredCount = 0
        addLog(count > 0
            ? "已恢复 \(count) 个被忽略的账号，点击「刷新扫描」即可重新录入"
            : "当前没有需要恢复的账号", level: .info)
    }
    
    // MARK: - Query Status
    func refreshAllStatuses() async {
        addLog("正在查询所有国内版账号今日签到状态与剩余总积分...", level: .info)
        for i in 0..<accounts.count {
            await refreshSingleStatus(index: i)
        }
        // 持久化保存最新状态与积分
        AccountStorage.saveAccounts(accounts)
        addLog("全量状态与积分查询完毕。", level: .info)
    }
    
    private func refreshSingleStatus(index: Int) async {
        guard index < accounts.count else { return }
        let acc = accounts[index]
        if acc.status == .expired { return }
        
        // 凭证缺失时不要拿着空 token 去打接口，
        // 否则日志里只会看到一条含义不明的 401。
        guard !acc.token.isEmpty else {
            accounts[index].status = .expired
            accounts[index].statusDetail = "本地找不到该账号的登录凭证，请在客户端重新登录后再扫描"
            addLog("[\(acc.platform.rawValue) - \(acc.name)] 缺少登录凭证，已跳过状态查询", level: .error)
            return
        }
        
        accounts[index].isLoading = true
        
        do {
            switch acc.platform {
            case .trae:
                let (checkedIn, credits) = try await TraeService.queryStatus(account: acc)
                accounts[index].credits = credits
                if checkedIn {
                    accounts[index].status = .alreadyCheckedIn
                    accounts[index].statusDetail = "今日已签到"
                } else {
                    accounts[index].status = .pending
                    accounts[index].statusDetail = "今日待签到"
                }
                addLog("[\(acc.platform.rawValue) - \(acc.name)] 状态: \(checkedIn ? "今日已签" : "今日待签"), 剩余积分: \(credits)", level: .info)
            case .workbuddy:
                let (checkedIn, totalCredits) = try await WorkBuddyService.queryStatus(account: acc)
                accounts[index].credits = totalCredits
                if checkedIn {
                    accounts[index].status = .alreadyCheckedIn
                    accounts[index].statusDetail = "今日已签到"
                } else {
                    accounts[index].status = .pending
                    accounts[index].statusDetail = "今日待签到"
                }
                addLog("[\(acc.platform.rawValue) - \(acc.name)] 状态: \(checkedIn ? "今日已签" : "今日待签"), 剩余积分: \(totalCredits)", level: .info)
            }
        } catch {
            accounts[index].statusDetail = "查询出错: \(error.localizedDescription)"
            addLog("[\(acc.platform.rawValue) - \(acc.name)] 查询状态异常: \(error.localizedDescription)", level: .error)
        }
        
        accounts[index].isLoading = false
    }
    
    // MARK: - Checkin Single
    func checkinAccount(id: String) async {
        guard let index = accounts.firstIndex(where: { $0.id == id }) else { return }
        let acc = accounts[index]
        
        accounts[index].isLoading = true
        accounts[index].status = .checking
        addLog("[\(acc.platform.rawValue) - \(acc.name)] 开始执行签到...", level: .info)
        
        do {
            switch acc.platform {
            case .trae:
                let res = try await TraeService.claimCheckin(account: acc)
                if res.success {
                    accounts[index].status = .alreadyCheckedIn
                    accounts[index].statusDetail = "今日已签到"
                    if !res.credits.isEmpty {
                        accounts[index].credits = res.credits
                    }
                    accounts[index].lastCheckinTime = Date()
                    AccountStorage.saveAccounts(accounts)
                    addLog("[\(acc.platform.rawValue) - \(acc.name)] 签到成功！当前剩余积分: \(accounts[index].credits)", level: .success)
                } else {
                    accounts[index].status = .failed
                    accounts[index].statusDetail = res.message
                    addLog("[\(acc.platform.rawValue) - \(acc.name)] 签到失败: \(res.message)", level: .error)
                }
            case .workbuddy:
                let res = try await WorkBuddyService.claimCheckin(account: acc)
                if res.success {
                    accounts[index].status = .alreadyCheckedIn
                    accounts[index].statusDetail = res.message
                    accounts[index].lastCheckinTime = Date()
                    if let status = try? await WorkBuddyService.queryStatus(account: acc) {
                        accounts[index].credits = status.totalCredits
                    }
                    AccountStorage.saveAccounts(accounts)
                    addLog("[\(acc.platform.rawValue) - \(acc.name)] \(res.message)！当前剩余积分: \(accounts[index].credits)", level: .success)
                } else {
                    accounts[index].status = .failed
                    accounts[index].statusDetail = res.message
                    addLog("[\(acc.platform.rawValue) - \(acc.name)] 签到失败: \(res.message)", level: .error)
                }
            }
        } catch {
            accounts[index].status = .failed
            accounts[index].statusDetail = "网络异常: \(error.localizedDescription)"
            addLog("[\(acc.platform.rawValue) - \(acc.name)] 请求出错: \(error.localizedDescription)", level: .error)
        }
        
        accounts[index].isLoading = false
    }
    
    // MARK: - Checkin All
    func checkinAll() async {
        guard !isCheckingAll else { return }
        isCheckingAll = true
        addLog("============== 开始批量自动签到 ==============", level: .info)
        
        // 1. 签到前先向官方服务器拉取最新的真实签到状态，防止跨天内存状态残留
        addLog("正在同步所有账号今日最新签到状态...", level: .info)
        for i in 0..<accounts.count {
            await refreshSingleStatus(index: i)
        }
        
        // 2. 逐一执行未完成签到的账号
        for acc in accounts {
            if acc.status == .alreadyCheckedIn {
                addLog("[\(acc.platform.rawValue) - \(acc.name)] 今日已签到，跳过。", level: .info)
                continue
            }
            if acc.status == .expired {
                addLog("[\(acc.platform.rawValue) - \(acc.name)] 登录态已过期，跳过。", level: .warning)
                continue
            }
            await checkinAccount(id: acc.id)
            // 每次请求间隔 500ms，友好防频控
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        
        AccountStorage.saveAccounts(accounts)
        addLog("============== 批量签到全部完成 ==============", level: .success)
        isCheckingAll = false
    }
    
    // MARK: - Timer & Daily Auto
    private func setupTimer() {
        let t = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkScheduledTime()
            }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }
    
    private func checkScheduledTime() {
        let now = Date()
        let cal = Calendar.current
        let hour = cal.component(.hour, from: now)
        let minute = cal.component(.minute, from: now)
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let todayStr = formatter.string(from: now)
        
        // 跨天自愈：检测到进入新的一天，自动重置账号卡片上的已签到状态为「今日待签」
        let lastKnownDay = UserDefaults.standard.string(forKey: "currentWorkingDay") ?? ""
        if lastKnownDay != todayStr {
            UserDefaults.standard.set(todayStr, forKey: "currentWorkingDay")
            var hasReset = false
            for i in accounts.indices {
                if accounts[i].status == .alreadyCheckedIn || accounts[i].status == .success {
                    accounts[i].status = .pending
                    accounts[i].statusDetail = "今日待签到"
                    hasReset = true
                }
            }
            if hasReset {
                AccountStorage.saveAccounts(accounts)
                addLog("🌅 跨入新的一天 (\(todayStr))，已重置账号为今日待签状态", level: .info)
            }
        }
        
        guard autoCheckinEnabled else { return }
        
        let isPastScheduledTime = (hour > autoCheckinHour) || (hour == autoCheckinHour && minute >= autoCheckinMinute)
        
        // 只有到了指定时间，且今天尚未成功签到完毕，且当前没有在签到中
        if isPastScheduledTime && lastRunDateStr != todayStr && !isCheckingAll {
            addLog("⏰ 触发每日定时签到任务 (\(todayStr) \(String(format: "%02d:%02d", hour, minute)))", level: .info)
            Task {
                await checkinAll()
                
                // 检查是否仍有未签到的有效账号
                let pendingCount = self.accounts.filter { $0.status != .alreadyCheckedIn && $0.status != .expired }.count
                if pendingCount == 0 {
                    self.lastRunDateStr = todayStr
                    self.addLog("✅ 今日全部有效账号已签到完毕，锁定今日定时", level: .success)
                } else {
                    self.addLog("⚠️ 尚有 \(pendingCount) 个账号未完成签到，稍后将自动补偿重试", level: .warning)
                }
            }
        }
    }
}
