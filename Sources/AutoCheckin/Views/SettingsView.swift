import SwiftUI

struct SettingsView: View {
    @Bindable var manager: CheckinManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                automationSection
                dataSection
                securitySection
            }
            .padding(24)
            .frame(maxWidth: 820)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(AppTheme.canvas)
    }

    private var automationSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionTitle("自动化", subtitle: "让它按你的节奏安静地工作")

            VStack(spacing: 0) {
                settingsRow(icon: "clock", tint: AppTheme.accent, title: "每日自动签到", description: "到达设定时间后自动处理所有待签账号") {
                    Toggle("", isOn: $manager.autoCheckinEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }

                if manager.autoCheckinEnabled {
                    Divider().padding(.leading, 50)
                    settingsRow(icon: "calendar.badge.clock", tint: AppTheme.accent, title: "执行时间", description: "应用保持运行时生效；当天自动执行不会重复") {
                        HStack(spacing: 6) {
                            Picker("小时", selection: $manager.autoCheckinHour) {
                                ForEach(0..<24) { hour in
                                    Text(String(format: "%02d", hour)).tag(hour)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 60)
                            Text(":")
                                .foregroundStyle(.secondary)
                            Picker("分钟", selection: $manager.autoCheckinMinute) {
                                ForEach([0, 5, 10, 15, 20, 30, 45], id: \.self) { minute in
                                    Text(String(format: "%02d", minute)).tag(minute)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 60)
                        }
                    }
                }

                Divider().padding(.leading, 50)
                settingsRow(
                    icon: "power",
                    tint: AppTheme.success,
                    title: "登录后自动启动",
                    description: LoginItemService.canRegister ? "重启 Mac 后自动回到菜单栏，避免漏签" : "命令行调试版不支持此功能，请使用打包好的 AutoCheckin.app"
                ) {
                    Toggle("", isOn: $manager.launchAtLogin)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .disabled(!LoginItemService.canRegister)
                }
            }
            .cardStyle(padding: 0)
        }
    }

    private var dataSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionTitle("本地数据", subtitle: "账号、凭证与忽略名单")

            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    Label("凭证存储位置", systemImage: "folder")
                        .font(.system(size: 12, weight: .medium))
                    Text(manager.credentialStorageDescription)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .padding(9)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 7))
                    Text("仅当前 macOS 用户可读写。删除该文件会清空本地账号数据，下次扫描可重新建立。")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .padding(16)

                Divider().padding(.leading, 50)
                settingsRow(icon: "person.crop.circle.badge.minus", tint: AppTheme.warning, title: "已忽略的账号", description: "恢复后重新扫描，即可再次加入账号列表") {
                    HStack(spacing: 10) {
                        Text("\(manager.ignoredCount) 个")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Button("恢复") { manager.restoreIgnoredAccounts() }
                            .controlSize(.small)
                            .disabled(manager.ignoredCount == 0)
                    }
                }
            }
            .cardStyle(padding: 0)
        }
    }

    private var securitySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionTitle("隐私与安全", subtitle: "数据留在本机，请求直达官方服务")

            HStack(spacing: 22) {
                securityItem(icon: "doc.text", title: "只读扫描", detail: "不修改客户端文件")
                securityItem(icon: "lock.shield", title: "本地解密", detail: "凭证不离开这台 Mac")
                securityItem(icon: "network", title: "官方接口", detail: "没有第三方中转")
            }
            .cardStyle(padding: 18)
        }
    }

    private func sectionTitle(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 14, weight: .semibold))
            Text(subtitle).font(.system(size: 10)).foregroundStyle(.secondary)
        }
        .padding(.bottom, 10)
    }

    private func settingsRow<Accessory: View>(
        icon: String,
        tint: Color,
        title: String,
        description: String,
        @ViewBuilder accessory: () -> Accessory
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.09), in: RoundedRectangle(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 12, weight: .medium))
                Text(description).font(.system(size: 10)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            accessory()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    private func securityItem(icon: String, title: String, detail: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(AppTheme.success)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 11, weight: .medium))
                Text(detail).font(.system(size: 9)).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
