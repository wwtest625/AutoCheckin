import Foundation
import CryptoKit

struct TraeService {
    static let apiBase = "https://api.trae.cn/trae/api/v2/ug/checkin_credits"
    static let usageApi = "https://api.trae.cn/trae/api/v2/pay/ide_user_ent_usage"
    static let authKey = "iCubeAuthInfo://icube.cloudide"
    
    // MARK: - Scan Local & Magpie Domestic Accounts
    static func scanAccounts() -> ScanOutput {
        var output = ScanOutput()
        var seenTokens = Set<String>()
        var seenUserIds = Set<String>()
        var scannedDirs = 0

        // 1. 扫描本地 Trae CN 客户端目录
        let possibleDirs = [
            "~/Library/Application Support/Trae CN",
            "~/Library/Application Support/TRAE SOLO CN",
            "~/Library/Application Support/Trae"
        ]
        
        for dirStr in possibleDirs {
            let expandedDir = NSString(string: dirStr).expandingTildeInPath
            let storagePath = (expandedDir as NSString).appendingPathComponent("User/globalStorage/storage.json")
            
            // 目录/文件不存在属正常情况（用户没装这个客户端），留到末尾汇总提示。
            guard FileManager.default.fileExists(atPath: storagePath) else { continue }
            scannedDirs += 1
            
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: storagePath)),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                output.notices.append(ScanNotice(.error, "[Trae] 登录态文件无法读取或 JSON 解析失败：\(storagePath)"))
                continue
            }
            
            guard let authB64 = json[authKey] as? String, !authB64.isEmpty else {
                output.notices.append(ScanNotice(.warning, "[Trae] \(dirStr) 的 storage.json 里没有登录态字段「\(authKey)」，客户端可能未登录或已更换存储键名"))
                continue
            }
            
            guard let authInfo = try? CryptoUtils.decryptTraeAuth(b64Text: authB64) else {
                output.notices.append(ScanNotice(.error, "[Trae] \(dirStr) 登录态解密失败：Trae 的凭证加密格式可能已更新，需要适配 CryptoUtils.decryptTraeAuth"))
                continue
            }
            
            guard let token = authInfo["token"] as? String, !token.isEmpty else {
                output.notices.append(ScanNotice(.error, "[Trae] \(dirStr) 登录态解密成功但其中没有 token，返回结构已变化"))
                continue
            }
            
            let userId = "\(authInfo["userId"] ?? "")"
            if userId.isEmpty {
                output.notices.append(ScanNotice(.warning, "[Trae] \(dirStr) 的登录态缺少 userId，无法建立稳定账号标识"))
            }
            if seenTokens.contains(token) {
                output.notices.append(ScanNotice(.info, "[Trae] \(dirStr) 与已扫描的账号凭证相同，跳过"))
                continue
            }
            if !userId.isEmpty && seenUserIds.contains(userId) {
                output.notices.append(ScanNotice(.info, "[Trae] \(dirStr) 是重复登录的同一账号（UID: \(userId)），跳过"))
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
            
            // 稳定 ID：优先 userId，缺失时用凭证指纹兜底，保证与扫描顺序无关。
            let rawId = !userId.isEmpty ? userId : "t-\(stableHash(of: token))"
            let account = AccountItem(
                id: AccountItem.makeId(platform: .trae, rawId: rawId),
                platform: .trae,
                rawId: rawId,
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
            output.accounts.append(account)
        }
        
        if scannedDirs == 0 {
            output.notices.append(ScanNotice(.warning, "[Trae] 未找到任何 Trae CN 客户端数据目录（已检查：\(possibleDirs.joined(separator: "、"))）"))
        }
        
        // 2. 扫描 Magpie 中保存的所有国内版 Trae CN 账号 (trae-cn, trae-cn#hash)
        let magpiePath = NSString(string: "~/.config/magpie/plugin-auth.json").expandingTildeInPath
        if FileManager.default.fileExists(atPath: magpiePath) {
            if let data = try? Data(contentsOf: URL(fileURLWithPath: magpiePath)),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                var magpieHit = 0
                for (key, val) in json.sorted(by: { $0.key < $1.key }) {
                    // 仅同步国内版 (trae-cn, trae-cn#*)，严格忽略海外版 trae-global
                    guard key == "trae-cn" || key.hasPrefix("trae-cn#") else { continue }
                    guard let dict = val as? [String: Any] else {
                        output.notices.append(ScanNotice(.warning, "[Trae] Magpie 条目「\(key)」结构异常，已跳过"))
                        continue
                    }
                    guard let token = dict["access"] as? String, !token.isEmpty,
                          let uid = dict["uid"] as? String, !uid.isEmpty else {
                        output.notices.append(ScanNotice(.warning, "[Trae] Magpie 条目「\(key)」缺少 access 或 uid，已跳过"))
                        continue
                    }
                    if seenUserIds.contains(uid) {
                        output.notices.append(ScanNotice(.info, "[Trae] Magpie 条目「\(key)」与客户端账号重复（UID: \(uid)），跳过"))
                        continue
                    }
                    
                    seenUserIds.insert(uid)
                    seenTokens.insert(token)
                    magpieHit += 1
                    let accountId = dict["accountId"] as? String ?? "Trae CN 用户"
                    let magpieDeviceId = dict["deviceId"] as? String ?? ""
                    let localRealDeviceId = getDeviceId(baseDir: NSString(string: "~/Library/Application Support/Trae CN").expandingTildeInPath)
                    let deviceId = !localRealDeviceId.isEmpty ? localRealDeviceId : magpieDeviceId
                    let refresh = dict["refresh"] as? String ?? ""
                    
                    if deviceId.isEmpty {
                        output.notices.append(ScanNotice(.info, "[Trae] 未能从本地文件取到 Magpie 账号「\(accountId)」的 device id，签到可能触发设备风控（一机一日限一次）"))
                    }
                    
                    let account = AccountItem(
                        id: AccountItem.makeId(platform: .trae, rawId: uid),
                        platform: .trae,
                        rawId: uid,
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
                    output.accounts.append(account)
                }
                if magpieHit == 0 {
                    output.notices.append(ScanNotice(.info, "[Trae] Magpie 账号库中没有国内版（trae-cn）条目"))
                }
            } else {
                output.notices.append(ScanNotice(.warning, "[Trae] Magpie 账号库无法解析：\(magpiePath)"))
            }
        }
        
        return output
    }
    
    /// 用凭证生成短指纹，作为 userId 缺失时的稳定兜底标识。
    private static func stableHash(of text: String) -> String {
        let digest = SHA256.hash(data: Data(text.utf8))
        return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
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
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw ApiError.httpFailure(response: response, data: data, context: "[\(account.name)] 签到状态查询")
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
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw ApiError.httpFailure(response: response, data: data, context: "[\(account.name)] 签到请求")
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
