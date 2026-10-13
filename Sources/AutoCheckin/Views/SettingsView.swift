import SwiftUI

struct SettingsView: View {
    @Bindable var manager: CheckinManager
    
    var body: some View {
        Form {
            Section("每日定时自动签到") {
                Toggle("启用每日自动签到", isOn: $manager.autoCheckinEnabled)
                
                if manager.autoCheckinEnabled {
                    HStack {
                        Text("签到时间点")
                        Spacer()
                        Picker("小时", selection: $manager.autoCheckinHour) {
                            ForEach(0..<24) { h in
                                Text(String(format: "%02d 点", h)).tag(h)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 80)
                        
                        Picker("分钟", selection: $manager.autoCheckinMinute) {
                            ForEach([0, 5, 10, 15, 20, 30, 45], id: \.self) { m in
                                Text(String(format: "%02d 分", m)).tag(m)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 80)
                    }
                    
                    Text("💡 到点后需保持本程序在运行中才会静默触发。若当天已自动跑过一次，再改时间不会重复执行，需要手动点「一键全部签到」。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Section("开机与后台运行") {
                Toggle("开机后自动启动（登录自启）", isOn: $manager.launchAtLogin)
                
                Text("开启后每次登录 macOS，本程序会自动常驻菜单栏，定时签到不会因为电脑重启而漏掉。关闭则需自行打开。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Section("凭证与账号数据") {
                LabeledContent("数据文件位置", value: manager.credentialStorageDescription)
                
                Text("登录凭证（access token / refresh token）就保存在上面这个文件里，权限已限制为仅当前用户可读写。想彻底清空账号，直接删除该文件即可，下次扫描会从客户端登录态重新建立。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                HStack {
                    Text("已忽略的账号")
                    Spacer()
                    Text("\(manager.ignoredCount) 个")
                        .foregroundStyle(.secondary)
                    Button("恢复") {
                        manager.restoreIgnoredAccounts()
                    }
                    .controlSize(.small)
                    .disabled(manager.ignoredCount == 0)
                }
                
                Text("在账号卡片上删除的账号会进入忽略名单，避免下次扫描时又被自动加回来；恢复后重新扫描即可录入。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Section("安全与凭证读取说明") {
                VStack(alignment: .leading, spacing: 8) {
                    Label("只读访问本地安装目录，绝不修改客户端任何文件", systemImage: "lock.shield.fill")
                    Label("解密只在本地完成，凭证仅保存在你自己电脑的私有目录", systemImage: "key.fill")
                    Label("仅直接向 Trae CN (api.trae.cn) 与腾讯云官方接口发起请求", systemImage: "network")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(16)
    }
}
