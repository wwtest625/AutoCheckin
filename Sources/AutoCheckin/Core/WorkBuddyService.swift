import Foundation

struct WorkBuddyService {
    static let apiBase = "https://copilot.tencent.com/v2/billing/meter"
    static let resourceApi = "https://copilot.tencent.com/billing/meter/get-user-resource-summary"
    
    // MARK: - Scan Local Accounts
    static func scanAccounts() -> [AccountItem] {
        var results: [AccountItem] = []
        var seenUids = Set<String>()
        var seenUins = Set<String>()
        
        let authDir = NSString(string: "~/Library/Application Support/CodeBuddyExtension/Data/Public/auth").expandingTildeInPath
        let fm = FileManager.default
        
        guard let files = try? fm.contentsOfDirectory(atPath: authDir) else {
            return []
        }
        
        // 优先处理官方桌面版 workbuddy-desktop.info，其次才是插件端
        let sortedFiles = files.sorted { f1, f2 in
            if f1.contains("workbuddy-desktop") { return true }
            if f2.contains("workbuddy-desktop") { return false }
            return f1 < f2
        }
        
        for file in sortedFiles where file.hasSuffix(".info") {
            let filePath = (authDir as NSString).appendingPathComponent(file)
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: filePath)),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let auth = json["auth"] as? [String: Any],
                  let accountDict = json["account"] as? [String: Any],
                  let uid = accountDict["uid"] as? String,
                  let tokenEnc = auth["accessToken"],
                  let token = try? CryptoUtils.decryptWbField(value: tokenEnc) else {
                continue
            }
            
            let uin = "\(accountDict["uin"] ?? "")"
            
            // 按 uid 与 uin 强去重，避免同一个用户因多客户端（IDE插件+桌面端）重复显示
            if seenUids.contains(uid) || (!uin.isEmpty && seenUins.contains(uin)) {
                continue
            }
            
            seenUids.insert(uid)
            if !uin.isEmpty {
                seenUins.insert(uin)
            }
            
            let domain = (auth["domain"] as? String) ?? ""
            
            // 解密真实昵称与手机号
            var nickname = ""
            if let nickEnc = accountDict["nickname"] {
                nickname = (try? CryptoUtils.decryptWbField(value: nickEnc)) ?? ""
            }
            var phone = ""
            if let phoneEnc = accountDict["phoneNumber"] {
                phone = (try? CryptoUtils.decryptWbField(value: phoneEnc)) ?? ""
            }
            
            let displayName = !nickname.isEmpty ? nickname : (!phone.isEmpty ? phone : "WorkBuddy 用户")
            
            // 检查过期时间
            let expiresAt = (auth["expiresAt"] as? Double) ?? 0
            var initialStatus: CheckinStatus = .unknown
            var initialDetail = ""
            if expiresAt > 0 && expiresAt / 1000.0 < Date().timeIntervalSince1970 {
                initialStatus = .expired
                initialDetail = "登录态已过期，请在客户端重新登录"
            }
            
            let item = AccountItem(
                id: "wb-\(results.count + 1)",
                platform: .workbuddy,
                name: displayName,
                phone: phone,
                uid: !uin.isEmpty ? "UIN: \(uin)" : "UID: \(uid.prefix(8))...",
                avatarUrl: "",
                region: "",
                token: token,
                deviceId: "",
                domain: domain,
                status: initialStatus,
                statusDetail: initialDetail
            )
            results.append(item)
        }
        
        return results
    }
    
    private static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) WorkBuddy/5.8.2 Chrome/120.0.0.0 Electron/28.2.0 Safari/537.36"
    
    // MARK: - Query Real Remaining Credits
    static func queryTotalCredits(account: AccountItem) async -> String? {
        guard let url = URL(string: resourceApi) else { return nil }
        let rawUid = getRawUid(for: account)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(account.token)", forHTTPHeaderField: "Authorization")
        request.setValue(rawUid, forHTTPHeaderField: "X-User-Id")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        if !account.domain.isEmpty {
            request.setValue(account.domain, forHTTPHeaderField: "X-Domain")
        }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = "{}".data(using: .utf8)
        
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataDict = json["data"] as? [String: Any],
              let packages = dataDict["Packages"] as? [[String: Any]] else {
            return nil
        }
        
        var totalRemain: Double = 0
        for p in packages {
            if let valStr = p["CycleRemainCapacity"] as? String, let val = Double(valStr) {
                totalRemain += val
            } else if let valNum = p["CycleRemainCapacity"] as? Double {
                totalRemain += valNum
            } else if let valInt = p["CycleRemainCapacity"] as? Int {
                totalRemain += Double(valInt)
            }
        }
        
        if totalRemain.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(totalRemain)) 积分"
        } else {
            return String(format: "%.1f 积分", totalRemain)
        }
    }
    
    // MARK: - API Calls
    static func queryStatus(account: AccountItem) async throws -> (checkedIn: Bool, totalCredits: String) {
        guard let url = URL(string: "\(apiBase)/checkin-status") else {
            throw URLError(.badURL)
        }
        
        let rawUid = getRawUid(for: account)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(account.token)", forHTTPHeaderField: "Authorization")
        request.setValue(rawUid, forHTTPHeaderField: "X-User-Id")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        if !account.domain.isEmpty {
            request.setValue(account.domain, forHTTPHeaderField: "X-Domain")
        }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = "{}".data(using: .utf8)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw URLError(.cannotParseResponse)
        }
        
        let code = json["code"] as? Int ?? -1
        guard code == 0 else {
            let msg = (json["msg"] as? String) ?? "查询失败"
            throw NSError(domain: "WorkBuddy", code: code, userInfo: [NSLocalizedDescriptionKey: msg])
        }
        
        let d = (json["data"] as? [String: Any]) ?? [:]
        var checkedIn = (d["today_checked_in"] as? Bool) ?? false
        if !checkedIn, let lastTime = account.lastCheckinTime {
            if Calendar.current.isDateInToday(lastTime) {
                checkedIn = true
            }
        }
        
        // 读取真实的可用总积分
        let realCredits = await queryTotalCredits(account: account)
        let displayCredits = realCredits ?? "\((d["total_credits"] as? Int) ?? 0) 积分"
        
        return (checkedIn, displayCredits)
    }
    
    static func claimCheckin(account: AccountItem) async throws -> (success: Bool, credit: Int, message: String) {
        guard let url = URL(string: "\(apiBase)/daily-checkin") else {
            throw URLError(.badURL)
        }
        
        let rawUid = getRawUid(for: account)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(account.token)", forHTTPHeaderField: "Authorization")
        request.setValue(rawUid, forHTTPHeaderField: "X-User-Id")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        if !account.domain.isEmpty {
            request.setValue(account.domain, forHTTPHeaderField: "X-Domain")
        }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = "{}".data(using: .utf8)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        // 腾讯云在重复签到时会返回 HTTP 400，但带有 JSON：{"code":10001, "msg":"今天已签到，请明天再来"}
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let code = json["code"] as? Int ?? -1
            let msg = (json["msg"] as? String) ?? "请求异常"
            
            if code == 0 {
                let credit = ((json["data"] as? [String: Any])?["credit"] as? Int) ?? 0
                return (true, credit, "签到成功")
            } else if code == 10001 {
                return (true, 0, "今日已签到")
            } else {
                return (false, 0, msg)
            }
        }
        
        guard let httpResp = response as? HTTPURLResponse, (200...299).contains(httpResp.statusCode) else {
            throw URLError(.badServerResponse)
        }
        
        return (false, 0, "未知异常")
    }
    
    private static func getRawUid(for account: AccountItem) -> String {
        // 优先从 JWT payload 解析 sub
        let parts = account.token.split(separator: ".")
        if parts.count >= 2 {
            var b64 = String(parts[1])
            while b64.count % 4 != 0 { b64 += "=" }
            b64 = b64.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
            if let d = Data(base64Encoded: b64),
               let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
               let sub = j["sub"] as? String, !sub.isEmpty {
                return sub
            }
        }
        
        // 兜底：从 account.uid 字段提取原始值（去掉 "UIN: "/"UID: " 前缀与省略号）
        let raw = account.uid
            .replacingOccurrences(of: "UIN: ", with: "")
            .replacingOccurrences(of: "UID: ", with: "")
            .replacingOccurrences(of: "...", with: "")
            .trimmingCharacters(in: .whitespaces)
        return raw
    }
}
