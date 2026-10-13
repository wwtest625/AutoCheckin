import Foundation

enum PlatformType: String, Codable, CaseIterable, Sendable {
    case trae = "Trae CN"
    case workbuddy = "WorkBuddy"

    var iconName: String {
        switch self {
        case .trae: return "sparkles"
        case .workbuddy: return "cube.transparent.fill"
        }
    }

    /// 稳定账号 ID 的前缀。
    var idPrefix: String {
        switch self {
        case .trae: return "trae"
        case .workbuddy: return "wb"
        }
    }

    /// 日志与提示里用的简称。
    var shortName: String {
        switch self {
        case .trae: return "Trae"
        case .workbuddy: return "WorkBuddy"
        }
    }
}

enum CheckinStatus: String, Codable {
    case unknown = "未检测"
    case pending = "今日待签"
    case checking = "签到中..."
    case alreadyCheckedIn = "今日已签"
    case success = "签到成功"
    case failed = "签到失败"
    case expired = "已过期"
}

/// 内存中的账号模型。
///
/// 本类型**不再参与 JSON 持久化**（见 `AccountStorage.StoredAccount`），
/// 目的是让 `token` / `refreshToken` 没有任何被误写入磁盘的路径：
/// 凭证只存在内存与系统钥匙串中。
struct AccountItem: Identifiable, Sendable {
    var id: String
    var platform: PlatformType

    /// 稳定身份标识：Trae 的 userId / WorkBuddy 的 uid，不含展示用前缀。
    /// `id` 与钥匙串键名都由它派生，因此与「扫描到的顺序」无关。
    var rawId: String

    var name: String                // 真实用户名 / 昵称 (如 Aron-01, Ww^)
    var phone: String               // 脱敏手机号 (如 150******68)
    var uid: String                 // 展示用用户 ID (如 "UID: 123456")
    var avatarUrl: String           // 头像链接
    var region: String
    var token: String
    var refreshToken: String = ""   // 支持长期保活
    var deviceId: String
    var domain: String

    var status: CheckinStatus = .unknown
    var statusDetail: String = ""
    var credits: String = "--"
    var lastCheckinTime: Date?
    var isLoading: Bool = false

    // MARK: - 稳定身份

    /// 由平台与原始标识派生账号 ID。
    static func makeId(platform: PlatformType, rawId: String) -> String {
        "\(platform.idPrefix)-\(rawId)"
    }

    /// 从展示用 uid 字段（"UID: 123" / "UIN: abc..."）还原原始标识，用于兼容旧持久化数据。
    static func extractRawId(from uidText: String) -> String {
        uidText
            .replacingOccurrences(of: "UIN: ", with: "")
            .replacingOccurrences(of: "UID: ", with: "")
            .replacingOccurrences(of: "...", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 统一身份：rawId 缺失时从展示字段回填，随后一律重算 `id`。
    /// 旧版本按扫描顺序编号（trae-1 / wb-2）的数据，经此步骤升级为稳定 ID。
    mutating func normalizeIdentity() {
        if rawId.isEmpty {
            rawId = Self.extractRawId(from: uid)
        }
        guard !rawId.isEmpty else { return }
        id = Self.makeId(platform: platform, rawId: rawId)
    }

    /// 钥匙串条目键名。
    var credentialKey: String { "account/\(id)" }
}
