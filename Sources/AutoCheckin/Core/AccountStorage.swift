import Foundation

/// 本地账号「保险库」：负责账号信息与凭证的持久化、增量合并，以及删除后的忽略名单。
///
/// 凭证存放位置：`~/Library/Application Support/AutoCheckin/saved_accounts.json`，
/// 文件权限收紧为 0600（仅当前用户可读写）。这是刻意选择的简单方案——
/// 不引入钥匙串，避免为了有限的安全收益去维护签名身份、可用性探测与迁移校验这套复杂度。
/// 需要迁移或清理时，删掉这个文件即可，账号会在下次扫描时从客户端登录态重建。
enum AccountStorage {

    /// upsert 的产出：合并后的列表 + 过程中的诊断信息。
    struct UpsertResult {
        var accounts: [AccountItem] = []
        var notices: [ScanNotice] = []
    }

    /// 磁盘上的账号记录，与 `AccountItem` 字段一一对应。
    /// 单独分一层是为了让「内存模型」和「落盘格式」解耦，
    /// 以后调整存储结构不必动 `AccountItem` 的构造点。
    struct StoredAccount: Codable {
        var id: String
        var platform: PlatformType
        var rawId: String?
        var name: String
        var phone: String
        var uid: String
        var avatarUrl: String
        var region: String
        var deviceId: String
        var domain: String
        var status: CheckinStatus
        var statusDetail: String
        var credits: String
        var lastCheckinTime: Date?
        var token: String
        var refreshToken: String

        init(_ account: AccountItem) {
            id = account.id
            platform = account.platform
            rawId = account.rawId
            name = account.name
            phone = account.phone
            uid = account.uid
            avatarUrl = account.avatarUrl
            region = account.region
            deviceId = account.deviceId
            domain = account.domain
            status = account.status
            statusDetail = account.statusDetail
            credits = account.credits
            lastCheckinTime = account.lastCheckinTime
            token = account.token
            refreshToken = account.refreshToken
        }

        func toAccountItem() -> AccountItem {
            var item = AccountItem(
                id: id,
                platform: platform,
                rawId: rawId ?? "",
                name: name,
                phone: phone,
                uid: uid,
                avatarUrl: avatarUrl,
                region: region,
                token: token,
                refreshToken: refreshToken,
                deviceId: deviceId,
                domain: domain,
                status: status,
                statusDetail: statusDetail
            )
            item.credits = credits
            item.lastCheckinTime = lastCheckinTime
            // 旧数据的 id 是按扫描顺序生成的（trae-1 / wb-2），读入时统一升级为稳定 ID。
            item.normalizeIdentity()
            return item
        }
    }

    // MARK: - 文件位置

    /// 供设置页展示的持久化文件名。
    static var fileName: String { "saved_accounts.json" }

    /// 测试/调试用的数据目录覆盖。
    ///
    /// macOS 的 `applicationSupportDirectory` 走真实用户目录，改 `HOME` 环境变量**不生效**，
    /// 所以验证程序必须靠这个显式覆盖来隔离，否则会把真实账号文件当测试数据覆盖掉。
    static let dataDirOverrideEnv = "AUTOCHECKIN_DATA_DIR"

    private static var overrideDataDir: String? {
        let value = ProcessInfo.processInfo.environment[dataDirOverrideEnv]
        return (value?.isEmpty == false) ? value : nil
    }

    private static var storageFile: URL {
        let dir: URL
        if let override = overrideDataDir {
            dir = URL(fileURLWithPath: (override as NSString).expandingTildeInPath, isDirectory: true)
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            dir = appSupport.appendingPathComponent("AutoCheckin")
        }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(fileName)
    }

    /// 当前实际使用的数据目录，供日志与设置页展示。
    static var storageDirectory: String { storageFile.deletingLastPathComponent().path }

    // MARK: - 忽略名单（已删除的账号不再被扫描重新加回）

    private static let ignoredKey = "ignoredAccountIds"

    static func ignoredAccountIds() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: ignoredKey) ?? [])
    }

    static func addIgnored(id: String) {
        var list = UserDefaults.standard.stringArray(forKey: ignoredKey) ?? []
        guard !list.contains(id) else { return }
        list.append(id)
        UserDefaults.standard.set(list, forKey: ignoredKey)
    }

    /// 清空忽略名单，返回此前被忽略的账号数量。
    @discardableResult
    static func restoreIgnoredAccounts() -> Int {
        let count = ignoredAccountIds().count
        UserDefaults.standard.removeObject(forKey: ignoredKey)
        return count
    }

    // MARK: - Load / Save

    static func loadAccounts() -> [AccountItem] {
        guard let data = try? Data(contentsOf: storageFile),
              let list = try? JSONDecoder().decode([StoredAccount].self, from: data) else {
            return []
        }
        return list.map { $0.toAccountItem() }
    }

    static func saveAccounts(_ accounts: [AccountItem]) {
        guard let data = try? JSONEncoder().encode(accounts.map(StoredAccount.init)) else { return }
        try? data.write(to: storageFile, options: .atomic)
        // 凭证就存在这个文件里，收紧权限到仅当前用户可读写。
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: storageFile.path
        )
    }

    // MARK: - Upsert

    /// 增量合并：按稳定 ID 比对（兼容旧数据再兜底比 uid + 平台）；
    /// 已存在则刷新凭证与信息，不存在则追加；被用户删除过的账号跳过。
    static func upsert(newAccounts: [AccountItem]) -> UpsertResult {
        var result = UpsertResult()
        let ignored = ignoredAccountIds()
        var current = loadAccounts()

        for incoming in newAccounts {
            if ignored.contains(incoming.id) {
                result.notices.append(ScanNotice(.info, "[系统] 已忽略账号 \(incoming.name)（此前手动删除过，可在「定时设置」中恢复）"))
                continue
            }
            guard !incoming.id.isEmpty else { continue }

            let index = current.firstIndex(where: { $0.id == incoming.id })
                ?? (incoming.uid.isEmpty ? nil : current.firstIndex(where: { $0.uid == incoming.uid && $0.platform == incoming.platform }))

            if let index {
                let wasExpired = current[index].status == .expired
                current[index].token = incoming.token
                if !incoming.refreshToken.isEmpty { current[index].refreshToken = incoming.refreshToken }
                if !incoming.deviceId.isEmpty { current[index].deviceId = incoming.deviceId }
                if !incoming.phone.isEmpty { current[index].phone = incoming.phone }
                if !incoming.avatarUrl.isEmpty { current[index].avatarUrl = incoming.avatarUrl }
                if !incoming.name.isEmpty { current[index].name = incoming.name }
                if !incoming.region.isEmpty { current[index].region = incoming.region }
                if !incoming.domain.isEmpty { current[index].domain = incoming.domain }
                if !incoming.rawId.isEmpty { current[index].rawId = incoming.rawId }
                // 旧数据里 id 可能是位置编号，命中后统一改写成稳定 id。
                current[index].id = incoming.id
                // 重新扫到登录态，说明此前的「已过期」判定不再成立。
                if wasExpired && !incoming.token.isEmpty {
                    current[index].status = .unknown
                    current[index].statusDetail = ""
                }
            } else {
                current.append(incoming)
            }
        }

        // 兜底：合并后若仍有同 id 条目（同一账号被重复录入），只保留第一条。
        var deduped: [AccountItem] = []
        var kept = Set<String>()
        for original in current {
            var account = original
            if account.id.isEmpty {
                account.id = AccountItem.makeId(platform: account.platform, rawId: "unknown-\(deduped.count + 1)")
            }
            if kept.contains(account.id) { continue }
            kept.insert(account.id)
            deduped.append(account)
        }
        current = deduped

        saveAccounts(current)
        result.accounts = current
        return result
    }

    // MARK: - Delete

    /// 删除账号，并记入忽略名单。
    /// 否则下一次「刷新扫描」会从客户端登录态里把它原样加回来，表现为"删不掉"。
    static func deleteAccount(id: String) -> [AccountItem] {
        var current = loadAccounts()
        if let removed = current.first(where: { $0.id == id }) {
            addIgnored(id: removed.id)
        }
        current.removeAll(where: { $0.id == id })
        saveAccounts(current)
        return current
    }
}
