import Foundation
import ServiceManagement

/// 登录自启设置结果，携带可直接写进控制台的说明。
enum LoginItemOutcome {
    case enabled
    case disabled
    case needsApproval(reason: String)
    case failed(reason: String)
}

/// 基于 `SMAppService.mainApp` 的登录项管理（macOS 13+）。
///
/// 定时签到依赖进程常驻：机器重启后若没人手动打开 App，那一天就会漏签。
/// 注册登录项后，用户登录进桌面时 App 自动静默启动（Info.plist 里 LSUIElement 已为 true）。
///
/// 注意：登录项只能由「标准 .app 包」注册。用 `swift run` / `Scripts/run.sh` 直接跑的裸二进制
/// 没有 bundle 身份，`register()` 必然失败，这里会把原因说清楚而不是静默失效。
enum LoginItemService {

    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    /// 开启或关闭登录自启。
    static func setEnabled(_ enabled: Bool) -> LoginItemOutcome {
        let service = SMAppService.mainApp
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
        } catch {
            let description = (error as NSError).localizedDescription
            if isRunningAsPlainExecutable {
                return .failed(reason: "当前是从命令行直接运行的裸二进制，系统不允许它注册登录项。请改用打包好的 AutoCheckin.app（bash Scripts/bundle.sh 后 open AutoCheckin.app）")
            }
            return .failed(reason: "系统拒绝了登录项设置：\(description)")
        }

        guard enabled else { return .disabled }

        switch service.status {
        case .enabled:
            return .enabled
        case .requiresApproval:
            return .needsApproval(reason: "已登记，但需要你在「系统设置 → 通用 → 登录项与扩展」中手动勾选 AutoCheckin（当前状态：等待用户批准）")
        case .notFound:
            return .failed(reason: "系统找不到本 App 的注册信息，请从 /Applications 中启动已打包的 AutoCheckin.app")
        default:
            return .needsApproval(reason: "当前状态：\(describe(service.status))")
        }
    }

    /// 当前是否以「非 .app 包」方式运行（裸二进制 / swift run 调试）。
    private static var isRunningAsPlainExecutable: Bool {
        Bundle.main.bundleURL.pathExtension != "app"
    }

    static func describe(_ status: SMAppService.Status) -> String {
        switch status {
        case .notRegistered: return "未注册"
        case .enabled: return "已开启"
        case .requiresApproval: return "等待在系统设置中批准"
        case .notFound: return "未找到应用注册信息"
        @unknown default: return "未知状态"
        }
    }
}
