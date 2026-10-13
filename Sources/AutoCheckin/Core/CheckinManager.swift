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
        
        // 2. 启动定时器
        setupTimer()
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
            let traeList = TraeService.scanAccounts()
            let wbList = WorkBuddyService.scanAccounts()
            let freshFound = traeList + wbList
            
            // 合并入本地保险库（增量，不覆盖旧号）
            let merged = AccountStorage.upsert(newAccounts: freshFound)
            
            await MainActor.run {
                self.accounts = merged
                self.isScanning = false
                
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
            addLog("已删除账号: [\(acc.platform.rawValue)] \(acc.name)", level: .warning)
        }
        self.accounts = AccountStorage.deleteAccount(id: id)
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
        guard autoCheckinEnabled else { return }
        
        let now = Date()
        let cal = Calendar.current
        let hour = cal.component(.hour, from: now)
        let minute = cal.component(.minute, from: now)
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let todayStr = formatter.string(from: now)
        
        let isPastScheduledTime = (hour > autoCheckinHour) || (hour == autoCheckinHour && minute >= autoCheckinMinute)
        
        if isPastScheduledTime && lastRunDateStr != todayStr {
            lastRunDateStr = todayStr
            addLog("⏰ 触发每日定时签到任务 (\(todayStr) \(String(format: "%02d:%02d", hour, minute)))", level: .info)
            Task {
                await checkinAll()
            }
        }
    }
}
