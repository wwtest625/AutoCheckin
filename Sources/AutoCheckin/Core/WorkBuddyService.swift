import Foundation

struct WorkBuddyService {
    static let apiBase = "https://copilot.tencent.com/v2/billing/meter"
    static let resourceApi = "https://copilot.tencent.com/billing/meter/get-user-resource-summary"
    
    // MARK: - Scan Local Accounts
    static func scanAccounts() -> ScanOutput {
        var output = ScanOutput()
        var seenUids = Set<String>()
        var seenUins = Set<String>()
        
        let authDir = NSString(string: "~/Library/Application Support/CodeBuddyExtension/Data/Public/auth").expandingTildeInPath
        let fm = FileManager.default
        
        guard fm.fileExists(atPath: authDir) else {
            output.notices.append(ScanNotice(.warning, "[WorkBuddy] 未找到凭证目录 \(authDir)，请确认已安装并登录 WorkBuddy 或 CodeBuddy 客户端"))
            return output
        }
        
        guard let files = try? fm.contentsOfDirectory(atPath: authDir) else {
            output.notices.append(ScanNotice(.error, "[WorkBuddy] 凭证目录存在但无法列出内容：\(authDir)"))
            return output
        }
        
        let candidates = files.filter { $0.hasSuffix(".info") }
        guard !candidates.isEmpty else {
            output.notices.append(ScanNotice(.warning, "[WorkBuddy] 凭证目录下没有 .info 登录态文件，客户端可能尚未登录"))
            return output
        }
        
        // 优先处理官方桌面版 workbuddy-desktop.info，其次才是插件端
        let sortedFiles = candidates.sorted { f1, f2 in
            if f1.contains("workbuddy-desktop") { return true }
            if f2.contains("workbuddy-desktop") { return false }
            return f1 < f2
        }
        
        for file in sortedFiles {
            let filePath = (authDir as NSString).appendingPathComponent(file)
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: filePath)),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                output.notices.append(ScanNotice(.error, "[WorkBuddy] \(file) 无法读取或 JSON 解析失败"))
                continue
            }
            guard let auth = json["auth"] as? [String: Any],
                  let accountDict = json["account"] as? [String: Any] else {
                output.notices.append(ScanNotice(.warning, "[WorkBuddy] \(file) 缺少 auth 或 account 字段，结构可能已变更"))
                continue
            }
            guard let uid = accountDict["uid"] as? String, !uid.isEmpty else {
                output.notices.append(ScanNotice(.warning, "[WorkBuddy] \(file) 缺少 account.uid，无法建立稳定账号标识"))
                continue
            }
            guard let tokenEnc = auth["accessToken"] else {
                output.notices.append(ScanNotice(.warning, "[WorkBuddy] \(file) 的 auth 中没有 accessToken"))
                continue
            }
            guard let token = try? CryptoUtils.decryptWbField(value: tokenEnc), !token.isEmpty else {
                output.notices.append(ScanNotice(.error, "[WorkBuddy] \(file) 凭证解密失败：加密格式可能已更新，需要适配 CryptoUtils.decryptWbField"))
                continue
            }
            
            let uin = "\(accountDict["uin"] ?? "")"
            
            // 按 uid 与 uin 强去重，避免同一个用户因多客户端（IDE插件+桌面端）重复显示
            if seenUids.contains(uid) || (!uin.isEmpty && seenUins.contains(uin)) {
                output.notices.append(ScanNotice(.info, "[WorkBuddy] \(file) 与已扫描账号重复（\(uin.isEmpty ? uid : uin)），跳过"))
                continue
            }
            
            seenUids.insert(uid)
            if !uin.isEmpty {
                seenUins.insert(uin)
            }
            
            let domain = (auth["domain"] as? String) ?? ""
            
            // 解密真实昵称与手机号（展示字段失败不影响账号可用性）
            var nickname = ""
            if let nickEnc = accountDict["nickname"] {
                if let value = try? CryptoUtils.decryptWbField(value: nickEnc) {
                    nickname = value
                } else {
                    output.notices.append(ScanNotice(.warning, "[WorkBuddy] \(file) 昵称解密失败，改用脱敏手机号或默认名称显示"))
                }
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
                output.notices.append(ScanNotice(.warning, "[WorkBuddy] 账号 \(displayName) 的登录态已于 \(formattedDate(expiresAt / 1000.0)) 过期，签到会被跳过"))
            }
            
            let item = AccountItem(
                id: AccountItem.makeId(platform: .workbuddy, rawId: uid),
                platform: .workbuddy,
                rawId: uid,
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
            output.accounts.append(item)
        }
        
        return output
    }
    
    private static func formattedDate(_ seconds: Double) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: Date(timeIntervalSince1970: seconds))
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
        // 客户端 5.8.x 起状态查询已切换到 checkin-activity-status；
        // 旧 checkin-status 返回全零死数据（active=false、未签到），会误判真实签到状态。
        guard let url = URL(string: "\(apiBase)/checkin-activity-status") else {
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
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw ApiError.httpFailure(response: response, data: data, context: "[\(account.name)] 签到状态查询")
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
        // 只信服务端字段：本地 lastCheckinTime 可能来自一次并未真正生效的签到
        // （活动未开启时签到接口照样返回成功），用它覆盖服务端状态会让假成功卡死一整天。
        let checkedIn = (d["today_checked_in"] as? Bool) ?? false
        
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
            
            if code == 0 || code == 10001 {
                // 接口说成功/已签到后，仍回查状态接口向服务端确认今日签到确实记录在案，
                // 防止接口语义再变化时出现"假成功"。
                if let status = try? await queryStatus(account: account) {
                    if status.checkedIn {
                        let credit = code == 0 ? (((json["data"] as? [String: Any])?["credit"] as? Int) ?? 0) : 0
                        return (true, credit, code == 0 ? "签到成功" : "今日已签到")
                    }
                    return (false, 0, "签到接口返回成功，但服务端未记录今日签到（签到活动可能未开启）")
                }
                return (false, 0, "签到接口返回成功，但状态回查失败，无法确认签到是否生效")
            } else {
                return (false, 0, msg)
            }
        }
        
        // 响应体不是预期 JSON：把状态码与片段抛出去，方便日志判断是被网关拦截还是格式变更
        throw ApiError.httpFailure(response: response, data: data, context: "[\(account.name)] 签到响应无法解析")
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
        
        // 兜底 1：扫描时记录的真实 uid（稳定、无前缀）
        if !account.rawId.isEmpty {
            return account.rawId
        }
        // 兜底 2：兼容旧持久化数据，从展示字段剥离前缀与省略号
        return AccountItem.extractRawId(from: account.uid)
    }
}
