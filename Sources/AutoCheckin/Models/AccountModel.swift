import Foundation

enum PlatformType: String, Codable, CaseIterable {
    case trae = "Trae CN"
    case workbuddy = "WorkBuddy"
    
    var iconName: String {
        switch self {
        case .trae: return "sparkles"
        case .workbuddy: return "cube.transparent.fill"
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

struct AccountItem: Identifiable, Codable {
    var id: String
    var platform: PlatformType
    var name: String                // 真实用户名 / 昵称 (如 Aron-01, Ww^)
    var phone: String               // 脱敏手机号 (如 150******68)
    var uid: String                 // 用户 ID / UIN
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
    
    enum CodingKeys: String, CodingKey {
        case id, platform, name, phone, uid, avatarUrl, region, token, refreshToken, deviceId, domain, status, statusDetail, credits, lastCheckinTime
    }
}
