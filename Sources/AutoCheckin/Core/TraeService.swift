import Foundation

struct TraeService {
    static let apiBase = "https://api.trae.cn/trae/api/v2/ug/checkin_credits"
    static let usageApi = "https://api.trae.cn/trae/api/v2/pay/ide_user_ent_usage"
    static let authKey = "iCubeAuthInfo://icube.cloudide"
    
    // MARK: - Scan Local & Magpie Domestic Accounts
    static func scanAccounts() -> [AccountItem] {
        var results: [AccountItem] = []
        var seenTokens = Set<String>()
        var seenUserIds = Set<String>()
        
        // 1. 扫描本地 Trae CN 客户端目录
        let possibleDirs = [
            "~/Library/Application Support/Trae CN",
            "~/Library/Application Support/TRAE SOLO CN",
            "~/Library/Application Support/Trae"
        ]
        
        for dirStr in possibleDirs {
            let expandedDir = NSString(string: dirStr).expandingTildeInPath
            let storagePath = (expandedDir as NSString).appendingPathComponent("User/globalStorage/storage.json")
            
            guard FileManager.default.fileExists(atPath: storagePath),
                  let data = try? Data(contentsOf: URL(fileURLWithPath: storagePath)),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let authB64 = json[authKey] as? String,
                  let authInfo = try? CryptoUtils.decryptTraeAuth(b64Text: authB64),
                  let token = authInfo["token"] as? String,
                  !seenTokens.contains(token) else {
                continue
            }
            
            let userId = "\(authInfo["userId"] ?? "")"
            if !userId.isEmpty && seenUserIds.contains(userId) {
                continue
            }
            seenTokens.insert(token)
            if !userId.isEmpty {
                seenUserIds.insert(userId)
            }
            let region = ((authInfo["userRegion"] as? [String: Any])?["region"] as? String) ?? "CN"
            let deviceId = getDeviceId(baseDir: expandedDir)
            let refreshToken = (authInfo["refreshToken"] as? String) ?? ""
            
            // 提取账户信息
            let accountDict = authInfo["account"] as? [String: Any]
            let username = (accountDict?["username"] as? String) ?? ""
            let phone = (accountDict?["nonPlainTextMobile"] as? String) ?? ""
            let avatar = (accountDict?["avatar_url"] as? String) ?? ""
            let displayName = !username.isEmpty ? username : (!phone.isEmpty ? phone : "Trae CN 用户")
            
            let account = AccountItem(
                id: "trae-\(results.count + 1)",
                platform: .trae,
                name: displayName,
                phone: phone,
                uid: "UID: \(userId)",
                avatarUrl: avatar,
                region: region,
                token: token,
                refreshToken: refreshToken,
                deviceId: deviceId,
                domain: ""
            )
            results.append(account)
        }
        
        // 2. 扫描 Magpie 中保存的所有国内版 Trae CN 账号 (trae-cn, trae-cn#hash)
        let magpiePath = NSString(string: "~/.config/magpie/plugin-auth.json").expandingTildeInPath
        if let data = try? Data(contentsOf: URL(fileURLWithPath: magpiePath)),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for (key, val) in json {
                // 仅同步国内版 (trae-cn, trae-cn#*)，严格忽略海外版 trae-global
                if (key == "trae-cn" || key.hasPrefix("trae-cn#")),
                   let dict = val as? [String: Any],
                   let token = dict["access"] as? String,
                   let uid = dict["uid"] as? String,
                   !seenUserIds.contains(uid) {
                    
                    seenUserIds.insert(uid)
                    seenTokens.insert(token)
                    let accountId = dict["accountId"] as? String ?? "Trae CN 用户"
                    let magpieDeviceId = dict["deviceId"] as? String ?? ""
                    let localRealDeviceId = getDeviceId(baseDir: NSString(string: "~/Library/Application Support/Trae CN").expandingTildeInPath)
                    let deviceId = !localRealDeviceId.isEmpty ? localRealDeviceId : magpieDeviceId
                    let refresh = dict["refresh"] as? String ?? ""
                    
                    let account = AccountItem(
                        id: "trae-\(results.count + 1)",
                        platform: .trae,
                        name: accountId,
                        phone: "",
                        uid: "UID: \(uid)",
                        avatarUrl: "",
                        region: "CN",
                        token: token,
                        refreshToken: refresh,
                        deviceId: deviceId,
                        domain: ""
                    )
                    results.append(account)
                }
            }
        }
        
        return results
    }
    
    static func getDeviceId(baseDir: String) -> String {
        // 1. ahanet config
        let cfgPath = (baseDir as NSString).appendingPathComponent("ahanet/tt_net_config.config")
        if let content = try? String(contentsOfFile: cfgPath, encoding: .utf8),
           let match = content.range(of: #"device_id[^\w]*(\d+)"#, options: .regularExpression) {
            let digits = content[match].filter { $0.isNumber }
            if !digits.isEmpty { return String(digits) }
        }
        
        // 2. logs scan
        let logsDir = (baseDir as NSString).appendingPathComponent("logs")
        if let subdirs = try? FileManager.default.contentsOfDirectory(atPath: logsDir) {
            for sub in subdirs.sorted().reversed() {
                let logPath = (logsDir as NSString).appendingPathComponent("\(sub)/main.log")
                if let content = try? String(contentsOfFile: logPath, encoding: .utf8),
                   let match = content.range(of: #"\[ICDRS\].*?did:\s*(\d+)"#, options: .regularExpression) {
                    let digits = content[match].filter { $0.isNumber }
                    if !digits.isEmpty { return String(digits) }
                }
            }
        }
        
        return ""
    }
    
    private static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
    
    // MARK: - Query Real Remaining Credits
    static func queryTotalCredits(account: AccountItem) async -> String? {
        guard let url = URL(string: usageApi) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Cloud-IDE-JWT \(account.token)", forHTTPHeaderField: "Authorization")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !account.deviceId.isEmpty {
            request.setValue(account.deviceId, forHTTPHeaderField: "x-device-id")
        }
        if !account.region.isEmpty {
            request.setValue(account.region, forHTTPHeaderField: "X-User-Region")
        }
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["req_source": 1])
        
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        
        // 1. 优先读取 usage_summary (总额度 - 已消耗，兼容 Double 和 Int)
        if let summary = json["usage_summary"] as? [String: Any] {
            let total: Double = {
                if let v = summary["total_amount"] as? Double { return v }
                if let v = summary["total_amount"] as? Int { return Double(v) }
                if let s = summary["total_amount"] as? String, let v = Double(s) { return v }
                return 0
            }()
            let consumed: Double = {
                if let v = summary["consumed_amount"] as? Double { return v }
                if let v = summary["consumed_amount"] as? Int { return Double(v) }
                if let s = summary["consumed_amount"] as? String, let v = Double(s) { return v }
                return 0
            }()
            if total > 0 {
                let remain = max(0, total - consumed)
                if remain.truncatingRemainder(dividingBy: 1) == 0 {
                    return "\(Int(remain)) 积分"
                } else {
                    return String(format: "%.1f 积分", remain)
                }
            }
        }
        
        // 2. 兜底计算 user_entitlement_pack_list 中各有效包的剩余总额
        if let packs = json["user_entitlement_pack_list"] as? [[String: Any]] {
            var totalRemain: Double = 0
            for p in packs {
                let base = p["entitlement_base_info"] as? [String: Any]
                let quota = base?["quota"] as? [String: Any]
                let limit: Double = {
                    if let v = quota?["credits_limit"] as? Double { return v }
                    if let v = quota?["credits_limit"] as? Int { return Double(v) }
                    return 0
                }()
                let usage = p["usage"] as? [String: Any]
                let used: Double = {
                    if let v = usage?["credits_amount"] as? Double { return v }
                    if let v = usage?["credits_amount"] as? Int { return Double(v) }
                    if let v = usage?["credits_used"] as? Double { return v }
                    if let v = usage?["credits_used"] as? Int { return Double(v) }
                    return 0
                }()
                totalRemain += max(0, limit - used)
            }
            if totalRemain > 0 {
                if totalRemain.truncatingRemainder(dividingBy: 1) == 0 {
                    return "\(Int(totalRemain)) 积分"
                } else {
                    return String(format: "%.1f 积分", totalRemain)
                }
            }
        }
        
        return nil
    }
    
    // MARK: - API Calls
    static func queryStatus(account: AccountItem) async throws -> (checkedIn: Bool, credits: String) {
        guard let url = URL(string: "\(apiBase)/status") else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Cloud-IDE-JWT \(account.token)", forHTTPHeaderField: "Authorization")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !account.deviceId.isEmpty {
            request.setValue(account.deviceId, forHTTPHeaderField: "x-device-id")
        }
        if !account.region.isEmpty {
            request.setValue(account.region, forHTTPHeaderField: "X-User-Region")
        }
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["req_source": 1])
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        
        guard let rawJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw URLError(.cannotParseResponse)
        }
        
        let dict = (rawJson["data"] as? [String: Any]) ?? rawJson
        let checkedIn = (dict["checked_in"] as? Bool) ?? (dict["did_checked_in"] as? Bool) ?? false
        
        // 读取真实的可用总积分
        let realCredits = await queryTotalCredits(account: account)
        let displayCredits = realCredits ?? "\((dict["credits"] as? Int) ?? 0) 积分"
        
        return (checkedIn, displayCredits)
    }
    
    static func claimCheckin(account: AccountItem) async throws -> (success: Bool, credits: String, message: String) {
        guard let url = URL(string: "\(apiBase)/claim") else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Cloud-IDE-JWT \(account.token)", forHTTPHeaderField: "Authorization")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !account.deviceId.isEmpty {
            request.setValue(account.deviceId, forHTTPHeaderField: "x-device-id")
        }
        if !account.region.isEmpty {
            request.setValue(account.region, forHTTPHeaderField: "X-User-Region")
        }
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["req_source": 1])
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw URLError(.cannotParseResponse)
        }
        
        let code = json["code"] as? Int ?? -1
        let msg = (json["message"] as? String) ?? "未知返回"
        
        if code == 0 {
            // 签到成功后重新查询最新总积分
            if let status = try? await queryStatus(account: account) {
                return (true, status.credits, "签到成功")
            }
            return (true, "-- 积分", "签到成功")
        } else if code == 9095 {
            return (false, "", "设备限制: 本机今日已为其他账号签到(一机一日限一次)")
        } else if code == 9074 {
            return (false, "", "风控限制: 字节防作弊拦截(一机一日限一次)")
        } else {
            return (false, "", msg)
        }
    }
}
