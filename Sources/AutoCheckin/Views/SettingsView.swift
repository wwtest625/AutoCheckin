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
                    
                    Text("💡 只要本程序保持运行或在后台菜单栏开启，到了指定时间点将自动静默触发签到。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Section("安全与凭证读取说明") {
                VStack(alignment: .leading, spacing: 8) {
                    Label("只读访问本地安装目录，绝不修改客户端任何文件", systemImage: "lock.shield.fill")
                    Label("解密仅在本地系统内存中进行，绝不上传到任何第三方", systemImage: "key.fill")
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
