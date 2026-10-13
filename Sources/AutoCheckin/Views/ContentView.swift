import SwiftUI

struct ContentView: View {
    @Bindable var manager: CheckinManager
    
    var body: some View {
        VStack(spacing: 0) {
            // Top Navigation & Stats Bar
            headerBar
            
            Divider()
            
            // Segmented Picker
            HStack {
                Picker("视图切换", selection: $manager.selectedTab) {
                    Text("账号列表 (\(manager.accounts.count))").tag(0)
                    Text("运行日志 (\(manager.logs.count))").tag(1)
                    Text("定时设置").tag(2)
                }
                .pickerStyle(.segmented)
                .frame(width: 380)
                
                Spacer()
                
                // Quick status summary
                let doneCount = manager.accounts.filter { $0.status == .alreadyCheckedIn || $0.status == .success }.count
                Text("今日完成: \(doneCount)/\(manager.accounts.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color(nsColor: .windowBackgroundColor))
            
            Divider()
            
            // Content according to selected tab
            Group {
                switch manager.selectedTab {
                case 0:
                    accountsListView
                case 1:
                    LogConsoleView(logs: manager.logs) {
                        manager.logs.removeAll()
                    }
                    .padding(16)
                case 2:
                    SettingsView(manager: manager)
                default:
                    EmptyView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            Divider()
            
            // Bottom Status Bar
            footerBar
        }
    }
    
    private var headerBar: some View {
        HStack {
            // Logo & Title
            HStack(spacing: 12) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("自动签到助手")
                        .font(.headline)
                    Text("Trae CN & WorkBuddy 每日积分自动领取")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            // Actions
            HStack(spacing: 10) {
                Button {
                    manager.scanAll()
                } label: {
                    if manager.isScanning {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("刷新扫描", systemImage: "arrow.clockwise")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(manager.isScanning || manager.isCheckingAll)
                
                Button {
                    Task {
                        await manager.checkinAll()
                    }
                } label: {
                    if manager.isCheckingAll {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("签到中...")
                        }
                    } else {
                        Label("一键全部签到", systemImage: "sparkles")
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .disabled(manager.accounts.isEmpty || manager.isCheckingAll)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Color(nsColor: .controlBackgroundColor))
    }
    
    private var accountsListView: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if manager.accounts.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "person.crop.circle.badge.questionmark")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        
                        Text("未找到已登录的 Trae CN 或 WorkBuddy 账号")
                            .font(.headline)
                        
                        Text("请先打开 Trae CN 或 WorkBuddy 客户端并登录，随后点击上方「刷新扫描」按钮。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 400)
                        
                        Button("立刻重新扫描") {
                            manager.scanAll()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(50)
                } else {
                    ForEach(manager.accounts) { acc in
                        AccountCardView(account: acc) {
                            Task {
                                await manager.checkinAccount(id: acc.id)
                            }
                        }
                        .contextMenu {
                            Button(role: .destructive) {
                                manager.deleteAccount(id: acc.id)
                            } label: {
                                Label("删除此账号", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
    }
    
    private var footerBar: some View {
        HStack {
            if manager.autoCheckinEnabled {
                HStack(spacing: 6) {
                    Image(systemName: "clock.badge.checkmark")
                        .foregroundStyle(.green)
                    Text("每日 \(String(format: "%02d:%02d", manager.autoCheckinHour, manager.autoCheckinMinute)) 自动执行")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "clock")
                        .foregroundStyle(.secondary)
                    Text("定时签到未开启")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            Text("安全说明：本地内存解密，凭证绝不上报")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
