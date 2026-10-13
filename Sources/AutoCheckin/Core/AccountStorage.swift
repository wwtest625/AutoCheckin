import Foundation

struct AccountStorage {
    private static var storageFile: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("AutoCheckin")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("saved_accounts.json")
    }
    
    static func loadAccounts() -> [AccountItem] {
        guard let data = try? Data(contentsOf: storageFile),
              let list = try? JSONDecoder().decode([AccountItem].self, from: data) else {
            return []
        }
        return list
    }
    
    static func saveAccounts(_ accounts: [AccountItem]) {
        if let data = try? JSONEncoder().encode(accounts) {
            try? data.write(to: storageFile)
        }
    }
    
    /// 增量合并策略：比对 UID，若已存在则更新凭证与信息；若不存在则安全追加
    static func upsert(newAccounts: [AccountItem]) -> [AccountItem] {
        var current = loadAccounts()
        
        for newAcc in newAccounts {
            if let index = current.firstIndex(where: { $0.uid == newAcc.uid && $0.platform == newAcc.platform }) {
                // 更新凭证与数据，保留用户已有的名称或状态
                current[index].token = newAcc.token
                if !newAcc.refreshToken.isEmpty {
                    current[index].refreshToken = newAcc.refreshToken
                }
                if !newAcc.deviceId.isEmpty {
                    current[index].deviceId = newAcc.deviceId
                }
                if !newAcc.phone.isEmpty {
                    current[index].phone = newAcc.phone
                }
                if !newAcc.avatarUrl.isEmpty {
                    current[index].avatarUrl = newAcc.avatarUrl
                }
                current[index].name = newAcc.name
            } else {
                var toAdd = newAcc
                let existingIds = Set(current.map { $0.id })
                if existingIds.contains(toAdd.id) {
                    let prefix = toAdd.platform == .trae ? "trae" : "wb"
                    var count = current.count + 1
                    while existingIds.contains("\(prefix)-\(count)") {
                        count += 1
                    }
                    toAdd.id = "\(prefix)-\(count)"
                }
                current.append(toAdd)
            }
        }
        
        // 兜底修复任何历史可能重复的 ID
        var seen = Set<String>()
        for i in 0..<current.count {
            if seen.contains(current[i].id) {
                let prefix = current[i].platform == .trae ? "trae" : "wb"
                current[i].id = "\(prefix)-\(UUID().uuidString.prefix(6))"
            }
            seen.insert(current[i].id)
        }
        
        saveAccounts(current)
        return current
    }
    
    static func deleteAccount(id: String) -> [AccountItem] {
        var current = loadAccounts()
        current.removeAll(where: { $0.id == id })
        saveAccounts(current)
        return current
    }
}
